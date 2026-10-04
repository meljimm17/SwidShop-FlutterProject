import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/category_model.dart';
import '../../models/listing_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';
import '../../services/storage_service.dart';
import '../../widgets/auth_widgets.dart';

/// Create (or edit, via [existing]) a Bid, Swap or Buy Now listing.
///
/// Photos are compressed on-device (JPEG 80%, longest edge 1600px), uploaded
/// to Cloudinary `listings/{listingId}` with per-photo progress, and only
/// the returned secure_urls are stored. Only fields for the chosen intent
/// are saved; the others are written as null.
class PostListingScreen extends StatefulWidget {
  const PostListingScreen({super.key, this.existing});

  final ListingModel? existing;

  @override
  State<PostListingScreen> createState() => _PostListingScreenState();
}

/// Fallback when the `categories` collection hasn't been seeded yet.
const List<String> kDefaultCategories = [
  'Tops',
  'Bottoms',
  'Dresses',
  'Outerwear & Jackets',
  'Shoes',
  'Bags',
  'Accessories',
  'Others',
];

/// Shared condition choices ([ListingModel.conditions]) plus Distressed.
const List<String> kConditions = [
  ...ListingModel.conditions,
  'Distressed',
];

/// Auction lengths in days (1 = 24h).
const List<int> kAuctionDays = [1, 3, 5, 7];
const List<double> kBidSteps = [50, 100, 250];
const int kMaxPhotos = 8;

class _PhotoSlot {
  _PhotoSlot.file(this.file) : url = null;
  _PhotoSlot.url(this.url) : file = null;

  final File? file;
  String? url;
  double? progress; // null = idle, 0..1 = uploading
  bool failed = false;

  bool get uploaded => url != null;
}

class _PostListingScreenState extends State<PostListingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firestore = FirestoreService();
  final _storage = StorageService();

  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _sizeCtrl = TextEditingController();
  final _fabricCtrl = TextEditingController();
  final _brandCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _startBidCtrl = TextEditingController();
  final _reserveCtrl = TextEditingController();
  final _wantsCtrl = TextEditingController();
  final _swapPriceCtrl = TextEditingController();
  final _meetupCtrl = TextEditingController();

  late final Stream<List<CategoryModel>> _categories = _firestore
      .streamCategories();

  final List<_PhotoSlot> _photos = [];
  ListingType _type = ListingType.bid;
  String? _category;
  String? _condition;
  double _bidStep = 100;
  List<double> _bidSteps = [...kBidSteps];
  int _auctionDays = 3;
  bool _durationTouched = false;
  bool _reserveOn = false;
  bool _swapOnly = true;
  final Set<String> _delivery = {};
  bool _busy = false;
  bool _showPhotoError = false;
  bool _showDeliveryError = false;

  bool get _editing => widget.existing != null;

  static Color colorFor(ListingType t) => switch (t) {
    ListingType.buyNow => AppColors.coral,
    ListingType.bid => AppColors.amber,
    ListingType.swap => AppColors.teal,
  };

  @override
  void initState() {
    super.initState();
    final l = widget.existing;
    if (l == null) return;
    _titleCtrl.text = l.title;
    _descCtrl.text = l.description;
    _sizeCtrl.text = l.size;
    _fabricCtrl.text = l.fabric;
    _brandCtrl.text = l.brand;
    _meetupCtrl.text = l.meetupSpot;
    _delivery.addAll(l.deliveryOptions);
    _type = l.type;
    _category = l.category.isEmpty ? null : l.category;
    _condition = kConditions.contains(l.condition) ? l.condition : null;
    _photos.addAll(l.images.map(_PhotoSlot.url));
    String num(double? v) => v == null ? '' : _trim(v);
    switch (l.type) {
      case ListingType.buyNow:
        _priceCtrl.text = num(l.price);
      case ListingType.bid:
        _startBidCtrl.text = num(l.startingBid);
        if (l.minIncrement != null) {
          _bidStep = l.minIncrement!;
          if (!_bidSteps.contains(_bidStep)) {
            _bidSteps = [..._bidSteps, _bidStep]..sort();
          }
        }
        if (l.reservePrice != null) {
          _reserveOn = true;
          _reserveCtrl.text = num(l.reservePrice);
        }
      case ListingType.swap:
        _wantsCtrl.text = l.swapWants;
        _swapOnly = l.swapOnly;
        _swapPriceCtrl.text = num(l.price);
    }
  }

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  void dispose() {
    for (final c in [
      _titleCtrl,
      _descCtrl,
      _sizeCtrl,
      _fabricCtrl,
      _brandCtrl,
      _priceCtrl,
      _startBidCtrl,
      _reserveCtrl,
      _wantsCtrl,
      _swapPriceCtrl,
      _meetupCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Photos
  // ---------------------------------------------------------------------------

  Future<void> _addPhotos() async {
    final remaining = kMaxPhotos - _photos.length;
    if (remaining <= 0) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text('Choose from gallery (up to $remaining)'),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null) return;

    final picker = ImagePicker();
    final List<XFile> picked;
    if (source == ImageSource.camera) {
      final one = await picker.pickImage(source: ImageSource.camera);
      picked = one == null ? const [] : [one];
    } else {
      picked = remaining == 1
          ? [?await picker.pickImage(source: ImageSource.gallery)]
          : await picker.pickMultiImage(limit: remaining);
    }
    if (!mounted || picked.isEmpty) return;
    setState(() {
      _photos.addAll(
        picked.take(remaining).map((x) => _PhotoSlot.file(File(x.path))),
      );
      _showPhotoError = false;
    });
  }

  Future<void> _photoOptions(_PhotoSlot slot) async {
    if (_busy) return;
    final isCover = _photos.indexOf(slot) == 0;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isCover)
              ListTile(
                leading: const Icon(Icons.star_outline_rounded),
                title: const Text('Make cover photo'),
                onTap: () => Navigator.of(sheetContext).pop('cover'),
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.red),
              title: const Text(
                'Remove photo',
                style: TextStyle(color: AppColors.red),
              ),
              onTap: () => Navigator.of(sheetContext).pop('remove'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    setState(() {
      if (action == 'cover') {
        _photos
          ..remove(slot)
          ..insert(0, slot);
      } else {
        _photos.remove(slot);
      }
    });
  }

  /// Compresses and uploads every photo that has no URL yet.
  Future<void> _uploadPending(String listingId) async {
    for (final slot in _photos) {
      if (slot.uploaded || slot.file == null) continue;
      setState(() {
        slot.progress = 0;
        slot.failed = false;
      });
      try {
        final compressed = await StorageService.compressForUpload(slot.file!);
        slot.url = await _storage.uploadListingImage(
          compressed,
          listingId,
          onProgress: (p) {
            if (mounted) setState(() => slot.progress = p);
          },
        );
      } catch (_) {
        if (mounted) setState(() => slot.failed = true);
        rethrow;
      } finally {
        if (mounted) setState(() => slot.progress = null);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Submit
  // ---------------------------------------------------------------------------

  double? _num(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(',', '').trim());

  String get _submitLabel {
    if (_editing) return 'Save changes';
    return switch (_type) {
      ListingType.bid =>
        'Publish ${_auctionDays == 1 ? '24-Hour' : '$_auctionDays-Day'} Auction',
      ListingType.swap => 'Publish Swap Listing',
      ListingType.buyNow => 'Publish Buy Now Listing',
    };
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final formOk = _formKey.currentState?.validate() ?? false;
    setState(() {
      _showPhotoError = _photos.isEmpty;
      _showDeliveryError = _delivery.isEmpty;
    });
    if (!formOk || _photos.isEmpty || _delivery.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please complete the highlighted fields.'),
        ),
      );
      return;
    }

    final uid = context.read<AuthProvider>().firebaseUser?.uid;
    if (uid == null) return;

    setState(() => _busy = true);
    try {
      final existing = widget.existing;
      final listingId = existing?.listingId ?? _firestore.newListingId();
      await _uploadPending(listingId);
      final images = _photos.map((s) => s.url!).toList();

      final isBid = _type == ListingType.bid;
      DateTime? auctionEndAt;
      if (isBid) {
        final keepOld =
            existing?.type == ListingType.bid &&
            existing?.auctionEndAt != null &&
            !_durationTouched;
        auctionEndAt = keepOld
            ? existing!.auctionEndAt
            : DateTime.now().add(Duration(days: _auctionDays));
      }

      final listing = ListingModel(
        listingId: listingId,
        sellerId: uid,
        title: _titleCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        category: _category ?? '',
        condition: _condition ?? '',
        size: _sizeCtrl.text.trim(),
        fabric: _fabricCtrl.text.trim(),
        brand: _brandCtrl.text.trim(),
        deliveryOptions: DeliveryOption.values
            .map((o) => o.value)
            .where(_delivery.contains)
            .toList(),
        meetupSpot: _delivery.contains(DeliveryOption.meetup.value)
            ? _meetupCtrl.text.trim()
            : '',
        images: images,
        type: _type,
        price: switch (_type) {
          ListingType.buyNow => _num(_priceCtrl),
          ListingType.swap => _swapOnly ? null : _num(_swapPriceCtrl),
          ListingType.bid => null,
        },
        startingBid: isBid ? _num(_startBidCtrl) : null,
        minIncrement: isBid ? _bidStep : null,
        auctionEndAt: auctionEndAt,
        reservePrice: isBid && _reserveOn ? _num(_reserveCtrl) : null,
        swapOpen: _type == ListingType.swap,
        swapWants: _type == ListingType.swap ? _wantsCtrl.text.trim() : '',
        swapOnly: _type == ListingType.swap ? _swapOnly : true,
        status: ListingStatus.active,
      );

      if (existing == null) {
        await _firestore.createListing(listing);
      } else {
        // Keep server-managed fields.
        final data = listing.toMap()
          ..remove('createdAt')
          ..remove('currentHighestBid')
          ..remove('bidCount')
          ..remove('highestBidderId')
          ..remove('status');
        await _firestore.updateListing(listingId, data);
      }

      if (!mounted) return;
      await showSuccessPopup(
        context,
        title: _editing ? 'Listing updated' : 'Listing posted',
        message: _editing
            ? 'Your changes are live.'
            : 'Buyers can now find it in the ${_typeLabel(_type)} feed.',
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      final msg = e is StorageException
          ? 'Photo upload failed: ${e.message}'
          : 'Could not save listing. Please try again.';
      debugPrint('PostListing: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppColors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _typeLabel(ListingType t) => switch (t) {
    ListingType.buyNow => 'Buy Now',
    ListingType.bid => 'Bidding',
    ListingType.swap => 'Swap',
  };

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        backgroundColor: AppColors.cream,
        appBar: AppBar(
          backgroundColor: AppColors.cream,
          title: Text(_editing ? 'Edit Listing' : 'Post New Listing'),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    children: [
                      _photosSection(),
                      const SizedBox(height: 28),
                      const _H('Listing Intent'),
                      _intentPills(),
                      const SizedBox(height: 14),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 220),
                        alignment: Alignment.topCenter,
                        child: _intentCard(),
                      ),
                      const SizedBox(height: 28),
                      const _H('Listing Title'),
                      TextFormField(
                        controller: _titleCtrl,
                        textCapitalization: TextCapitalization.sentences,
                        maxLength: 80,
                        validator: (v) => Validators.required(v, 'Title'),
                        decoration: const InputDecoration(
                          hintText: 'e.g. Vintage 90s Carhartt Detroit Jacket',
                          counterText: '',
                        ),
                      ),
                      const SizedBox(height: 24),
                      const _H('Category'),
                      _categoryField(),
                      const SizedBox(height: 24),
                      const _H('Garment Specs & Condition'),
                      _specsGrid(),
                      const SizedBox(height: 24),
                      const _H('Honest Flaws & Measurements'),
                      TextFormField(
                        controller: _descCtrl,
                        textCapitalization: TextCapitalization.sentences,
                        minLines: 4,
                        maxLines: 8,
                        maxLength: 1000,
                        validator: (v) => Validators.required(v, 'Description'),
                        decoration: const InputDecoration(
                          hintText:
                              'Pit-to-pit and length, fading, stains, '
                              'repairs, smell, how it fits…',
                        ),
                      ),
                      const SizedBox(height: 16),
                      _deliveryCard(),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                decoration: const BoxDecoration(
                  color: AppColors.cream,
                  border: Border(top: BorderSide(color: AppColors.line)),
                ),
                child: SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton(
                    onPressed: _busy ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.coralDeep,
                      disabledBackgroundColor: AppColors.coralDeep.withValues(
                        alpha: 0.6,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white,
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _submitLabel,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.arrow_forward_rounded, size: 20),
                            ],
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Photos ---------------------------------------------------------------

  Widget _photosSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Photos & Garment Tags',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
              ),
            ),
            Text(
              '${_photos.length} / $kMaxPhotos added',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.coralDeep,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          _showPhotoError
              ? 'Add at least one photo.'
              : 'Include collar tags, care labels, and clear flaw close-ups.',
          style: TextStyle(
            fontSize: 13,
            color: _showPhotoError ? AppColors.red : AppColors.gray,
          ),
        ),
        const SizedBox(height: 12),
        if (_photos.isEmpty)
          _AddTile(
            height: 170,
            error: _showPhotoError,
            label: 'Add photos',
            onTap: _busy ? null : _addPhotos,
          )
        else
          LayoutBuilder(builder: (context, c) => _photoLayout(c.maxWidth)),
        if (_photos.isNotEmpty && _photos.length < kMaxPhotos) ...[
          const SizedBox(height: 10),
          Material(
            color: AppColors.mist.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              onTap: _busy ? null : _addPhotos,
              borderRadius: BorderRadius.circular(999),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.add_photo_alternate_outlined, size: 19),
                    const SizedBox(width: 8),
                    Text(
                      'Add more angles or tag close-ups '
                      '(+${kMaxPhotos - _photos.length})',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Cover spans 2×2 cells on the left; next four fill a 2×2 block on the
  /// right; any further photos continue in rows of four.
  Widget _photoLayout(double width) {
    const gap = 8.0;
    final cell = (width - gap * 3) / 4;
    final big = cell * 2 + gap;
    Widget small(int i) => SizedBox(
      width: cell,
      height: cell,
      child: i < _photos.length
          ? _PhotoTile(slot: _photos[i], onTap: () => _photoOptions(_photos[i]))
          : null,
    );

    final rest = _photos.length > 5 ? _photos.sublist(5) : const <_PhotoSlot>[];
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: big,
              height: big,
              child: _PhotoTile(
                slot: _photos.first,
                isCover: true,
                onTap: () => _photoOptions(_photos.first),
              ),
            ),
            const SizedBox(width: gap),
            Column(
              children: [
                Row(
                  children: [
                    small(1),
                    const SizedBox(width: gap),
                    small(2),
                  ],
                ),
                const SizedBox(height: gap),
                Row(
                  children: [
                    small(3),
                    const SizedBox(width: gap),
                    small(4),
                  ],
                ),
              ],
            ),
          ],
        ),
        if (rest.isNotEmpty) ...[
          const SizedBox(height: gap),
          Row(
            children: [
              for (var i = 0; i < 4; i++) ...[
                if (i > 0) const SizedBox(width: gap),
                small(5 + i),
              ],
            ],
          ),
        ],
      ],
    );
  }

  // --- Intent ---------------------------------------------------------------

  Widget _intentPills() {
    Widget pill(ListingType t, IconData icon, String label) {
      final selected = _type == t;
      final color = colorFor(t);
      return Expanded(
        child: GestureDetector(
          onTap: _busy ? null : () => setState(() => _type = t),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              color: selected ? color : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected ? Colors.white : AppColors.ink,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.mist.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          pill(ListingType.bid, Icons.gavel_rounded, 'Bid'),
          pill(ListingType.swap, Icons.sync_alt_rounded, 'Swap'),
          pill(ListingType.buyNow, Icons.bolt_rounded, 'Buy Now'),
        ],
      ),
    );
  }

  Widget _intentCard() {
    final color = colorFor(_type);
    final (IconData icon, String title, String subtitle) = switch (_type) {
      ListingType.bid => (
        Icons.gavel_rounded,
        'Auction settings',
        'The highest bid when the timer ends wins.',
      ),
      ListingType.swap => (
        Icons.sync_alt_rounded,
        'Swap details',
        'Tell swappers what you’re hunting for.',
      ),
      ListingType.buyNow => (
        Icons.bolt_rounded,
        'Buy Now price',
        'First buyer to confirm gets it.',
      ),
    };

    return Container(
      key: ValueKey(_type),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: color.withValues(alpha: 0.14),
                child: Icon(icon, size: 20, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.gray,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ...switch (_type) {
            ListingType.bid => _bidFields(),
            ListingType.swap => _swapFields(),
            ListingType.buyNow => [
              const _Label('Fixed Price'),
              _BigMoneyField(controller: _priceCtrl, label: 'Price'),
            ],
          },
        ],
      ),
    );
  }

  List<Widget> _bidFields() {
    Widget choice(
      String label,
      bool selected,
      VoidCallback onTap, {
      Color? selectedColor,
      Color? selectedText,
    }) {
      return Expanded(
        child: GestureDetector(
          onTap: _busy ? null : onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected
                  ? (selectedColor ?? AppColors.coralDeep)
                  : AppColors.cream,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected
                    ? (selectedText ?? Colors.white)
                    : AppColors.ink,
              ),
            ),
          ),
        ),
      );
    }

    return [
      const _Label('Starting Price'),
      _BigMoneyField(controller: _startBidCtrl, label: 'Starting price'),
      const SizedBox(height: 18),
      const _Label('Minimum Bid Step'),
      Row(
        children: [
          for (var i = 0; i < _bidSteps.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            choice(
              '+₱${_trim(_bidSteps[i])}${_bidSteps[i] == 100 ? ' (default)' : ''}',
              _bidStep == _bidSteps[i],
              () => setState(() => _bidStep = _bidSteps[i]),
              selectedColor: AppColors.teal.withValues(alpha: 0.18),
              selectedText: AppColors.teal,
            ),
          ],
        ],
      ),
      const SizedBox(height: 18),
      _Label(
        'Auction Lifespan',
        trailing:
            _editing &&
                widget.existing?.auctionEndAt != null &&
                !_durationTouched
            ? 'Ends ${AppUtils.formatDateTime(widget.existing!.auctionEndAt)}'
            : null,
      ),
      Row(
        children: [
          for (var i = 0; i < kAuctionDays.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            choice(
              kAuctionDays[i] == 1 ? '24h' : '${kAuctionDays[i]} Days',
              _auctionDays == kAuctionDays[i],
              () => setState(() {
                _auctionDays = kAuctionDays[i];
                _durationTouched = true;
              }),
            ),
          ],
        ],
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hidden Reserve Price',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                Text(
                  'Won’t sell below this secret amount',
                  style: TextStyle(fontSize: 12.5, color: AppColors.gray),
                ),
              ],
            ),
          ),
          Switch(
            value: _reserveOn,
            onChanged: _busy ? null : (v) => setState(() => _reserveOn = v),
            activeThumbColor: Colors.white,
            activeTrackColor: AppColors.teal,
          ),
        ],
      ),
      if (_reserveOn) ...[
        const SizedBox(height: 8),
        TextFormField(
          controller: _reserveCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          validator: (v) {
            final err = Validators.positiveNumber(v, 'Reserve');
            if (err != null) return err;
            final start = _num(_startBidCtrl);
            if (start != null && _num(_reserveCtrl)! < start) {
              return 'Reserve must be at least the starting price';
            }
            return null;
          },
          decoration: InputDecoration(
            labelText: 'Reserve threshold',
            prefixIcon: const Icon(Icons.lock_outline),
            prefixText: '₱ ',
            fillColor: AppColors.cream,
            suffixIcon: Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Center(
                widthFactor: 1,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.teal.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Hidden',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.teal,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Bidders only see whether the reserve is met. If the top bid is '
          'below it when time runs out, the item doesn’t sell.',
          style: TextStyle(fontSize: 12, height: 1.4, color: AppColors.gray),
        ),
      ],
    ];
  }

  List<Widget> _swapFields() => [
    const _Label('What do you want in return?'),
    TextFormField(
      controller: _wantsCtrl,
      textCapitalization: TextCapitalization.sentences,
      maxLength: 120,
      validator: (v) => Validators.required(v, 'This'),
      decoration: const InputDecoration(
        hintText: 'e.g. Undercover or Issey pieces, size M',
        counterText: '',
        fillColor: AppColors.cream,
      ),
    ),
    const SizedBox(height: 8),
    Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Swap only',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              Text(
                _swapOnly
                    ? 'Only trades are accepted.'
                    : 'Buyers can also pay cash instead.',
                style: const TextStyle(fontSize: 12.5, color: AppColors.gray),
              ),
            ],
          ),
        ),
        Switch(
          value: _swapOnly,
          onChanged: _busy ? null : (v) => setState(() => _swapOnly = v),
          activeThumbColor: Colors.white,
          activeTrackColor: AppColors.teal,
        ),
      ],
    ),
    if (!_swapOnly) ...[
      const SizedBox(height: 12),
      const _Label('Cash price'),
      _BigMoneyField(controller: _swapPriceCtrl, label: 'Cash price'),
    ],
  ];

  // --- Details --------------------------------------------------------------

  Widget _categoryField() {
    return StreamBuilder<List<CategoryModel>>(
      stream: _categories,
      builder: (context, snap) {
        final names = (snap.data ?? const <CategoryModel>[])
            .map((c) => c.name)
            .where((n) => n.isNotEmpty)
            .toList();
        final options = names.isEmpty ? [...kDefaultCategories] : names;
        if (_category != null && !options.contains(_category)) {
          options.add(_category!);
        }
        return DropdownButtonFormField<String>(
          initialValue: _category,
          isExpanded: true,
          hint: const Text('Select a category'),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.checkroom_rounded, color: AppColors.coral),
          ),
          items: [
            for (final o in options) DropdownMenuItem(value: o, child: Text(o)),
          ],
          validator: (v) => v == null ? 'Pick a category' : null,
          onChanged: _busy ? null : (v) => setState(() => _category = v),
        );
      },
    );
  }

  Widget _specsGrid() {
    Widget box(String label, IconData icon, Widget field) => Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: AppColors.gray,
                  ),
                ),
              ),
              Icon(icon, size: 16, color: AppColors.coral),
            ],
          ),
          field,
        ],
      ),
    );

    const bare = InputDecoration(
      isDense: true,
      filled: false,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      focusedErrorBorder: InputBorder.none,
      contentPadding: EdgeInsets.symmetric(vertical: 8),
    );

    Widget text(TextEditingController c, String hint) => TextFormField(
      controller: c,
      textCapitalization: TextCapitalization.words,
      style: const TextStyle(fontWeight: FontWeight.w600),
      decoration: bare.copyWith(hintText: hint),
    );

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: box(
                'CONDITION',
                Icons.verified_outlined,
                DropdownButtonFormField<String>(
                  initialValue: _condition,
                  isExpanded: true,
                  isDense: true,
                  hint: const Text('Select'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                  decoration: bare,
                  items: [
                    for (final c in kConditions)
                      DropdownMenuItem(value: c, child: Text(c)),
                  ],
                  validator: (v) => v == null ? 'Required' : null,
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _condition = v),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: box(
                'SIZE / FIT',
                Icons.straighten_rounded,
                text(_sizeCtrl, 'M (boxy 24×26)'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: box(
                'FABRIC',
                Icons.texture_rounded,
                text(_fabricCtrl, 'Duck canvas'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: box(
                'BRAND',
                Icons.sell_outlined,
                text(_brandCtrl, 'Carhartt'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _deliveryCard() {
    final meetup = _delivery.contains(DeliveryOption.meetup.value);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: _showDeliveryError ? Border.all(color: AppColors.red) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Meetup & Courier',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          Text(
            _showDeliveryError
                ? 'Pick at least one way to hand it over.'
                : 'How can buyers get the item?',
            style: TextStyle(
              fontSize: 12.5,
              color: _showDeliveryError ? AppColors.red : AppColors.gray,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final o in DeliveryOption.values)
                FilterChip(
                  label: Text(o.label),
                  selected: _delivery.contains(o.value),
                  showCheckmark: true,
                  checkmarkColor: AppColors.teal,
                  onSelected: _busy
                      ? null
                      : (on) => setState(() {
                          on
                              ? _delivery.add(o.value)
                              : _delivery.remove(o.value);
                          _showDeliveryError = false;
                        }),
                  labelStyle: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _delivery.contains(o.value)
                        ? AppColors.teal
                        : AppColors.ink,
                  ),
                  selectedColor: AppColors.teal.withValues(alpha: 0.12),
                  backgroundColor: AppColors.cream,
                  side: BorderSide(
                    color: _delivery.contains(o.value)
                        ? AppColors.teal
                        : AppColors.line,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
            ],
          ),
          if (meetup) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _meetupCtrl,
              textCapitalization: TextCapitalization.words,
              validator: (v) =>
                  meetup ? Validators.required(v, 'Meet-up spot') : null,
              decoration: const InputDecoration(
                hintText: 'e.g. MRT Guadalupe or BGC High Street',
                prefixIcon: Icon(Icons.place_outlined),
                fillColor: AppColors.cream,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Pieces
// -----------------------------------------------------------------------------

class _H extends StatelessWidget {
  const _H(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
    ),
  );
}

class _Label extends StatelessWidget {
  const _Label(this.text, {this.trailing});

  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF55534E),
            ),
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: const TextStyle(fontSize: 12, color: AppColors.gray),
          ),
      ],
    ),
  );
}

class _BigMoneyField extends StatelessWidget {
  const _BigMoneyField({required this.controller, required this.label});

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
      validator: (v) => Validators.positiveNumber(v, label),
      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
      decoration: const InputDecoration(
        hintText: '0',
        fillColor: AppColors.cream,
        prefixIcon: Padding(
          padding: EdgeInsets.only(left: 16, right: 6),
          child: Text(
            '₱',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppColors.coralDeep,
            ),
          ),
        ),
        prefixIconConstraints: BoxConstraints(minWidth: 0, minHeight: 0),
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    required this.slot,
    required this.onTap,
    this.isCover = false,
  });

  final _PhotoSlot slot;
  final VoidCallback onTap;
  final bool isCover;

  @override
  Widget build(BuildContext context) {
    final Widget image = slot.file != null
        ? Image.file(slot.file!, fit: BoxFit.cover)
        : CachedNetworkImage(imageUrl: slot.url!, fit: BoxFit.cover);
    final progress = slot.progress;

    return GestureDetector(
      onTap: progress == null ? onTap : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(isCover ? 18 : 12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            image,
            if (progress != null)
              Container(
                color: Colors.black.withValues(alpha: 0.45),
                alignment: Alignment.center,
                child: SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(
                    value: progress == 0 ? null : progress,
                    strokeWidth: 3,
                    color: Colors.white,
                    backgroundColor: Colors.white24,
                  ),
                ),
              ),
            if (slot.failed)
              Container(
                color: AppColors.red.withValues(alpha: 0.55),
                alignment: Alignment.center,
                child: const Icon(Icons.error_outline, color: Colors.white),
              ),
            if (isCover) ...[
              Positioned(
                left: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.coralDeep,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'COVER',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ),
              if (progress == null)
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 10,
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: Colors.black38,
                        child: Icon(
                          Icons.photo_camera_outlined,
                          size: 17,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Tap to edit',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          shadows: [Shadow(blurRadius: 6)],
                        ),
                      ),
                    ],
                  ),
                ),
            ] else if (progress == null)
              Positioned(
                right: 5,
                top: 5,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    color: Colors.black45,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.more_horiz,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({
    required this.height,
    required this.error,
    required this.label,
    required this.onTap,
  });

  final double height;
  final bool error;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: error ? AppColors.red : AppColors.line,
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: AppColors.coral.withValues(alpha: 0.12),
                child: const Icon(
                  Icons.add_a_photo_outlined,
                  color: AppColors.coralDeep,
                ),
              ),
              const SizedBox(height: 10),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
              const Text(
                'Up to 8 photos · first one is the cover',
                style: TextStyle(fontSize: 12, color: AppColors.gray),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
