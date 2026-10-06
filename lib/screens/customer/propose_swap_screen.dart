import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/listing_model.dart';
import '../../models/notification_model.dart';
import '../../models/swap_offer_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';
import '../../services/storage_service.dart';
import '../../widgets/app_card_wrapper.dart';
import '../../widgets/listing_widgets.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/top_app_bar.dart';
import '../../widgets/type_badge.dart';

/// What the offerer gives in a swap.
enum _OfferSource { photos, listing }

/// Proposes a swap for a listing (Phase 3.7). The offered item is EITHER
/// shown with photos straight from the phone (no listing needed — works for
/// any account) OR one of the offerer's active listings (seller accounts).
class ProposeSwapScreen extends StatefulWidget {
  const ProposeSwapScreen({super.key, required this.listingId});

  final String listingId;

  @override
  State<ProposeSwapScreen> createState() => _ProposeSwapScreenState();
}

class _ProposeSwapScreenState extends State<ProposeSwapScreen> {
  final _firestore = FirestoreService();
  final _messageCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  late final Stream<ListingModel?> _target = _firestore.streamListing(
    widget.listingId,
  );

  _OfferSource _source = _OfferSource.listing;
  String? _offeredItemId;

  /// Photos picked on this device, in order.
  final List<File> _photos = [];

  /// Already-uploaded photos (by local path) so a retry never re-uploads.
  final Map<String, String> _uploaded = {};

  /// Offer id reserved on first upload (photos live in `listings/swap-{id}`).
  String? _offerId;
  bool _busy = false;
  String? _progress;

  @override
  void dispose() {
    _messageCtrl.dispose();
    _titleCtrl.dispose();
    super.dispose();
  }

  _OfferSource _sourceFor(bool canSell) =>
      canSell ? _source : _OfferSource.photos;

  bool _readyFor(_OfferSource source) => switch (source) {
    _OfferSource.photos =>
      _photos.isNotEmpty && _titleCtrl.text.trim().isNotEmpty,
    _OfferSource.listing => _offeredItemId != null,
  };

  Future<void> _addPhotos() async {
    final room = AppConstants.maxSwapOfferPhotos - _photos.length;
    if (room <= 0) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.of(sheet).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text('Choose from gallery (up to $room)'),
              onTap: () => Navigator.of(sheet).pop(ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    final picker = ImagePicker();
    List<XFile> picked;
    try {
      if (source == ImageSource.camera) {
        final one = await picker.pickImage(source: ImageSource.camera);
        picked = one == null ? const [] : [one];
      } else if (room == 1) {
        final one = await picker.pickImage(source: ImageSource.gallery);
        picked = one == null ? const [] : [one];
      } else {
        picked = await picker.pickMultiImage(limit: room);
      }
    } catch (e) {
      debugPrint('pickSwapPhotos: $e');
      return;
    }
    if (!mounted || picked.isEmpty) return;
    setState(() {
      _photos.addAll(picked.take(room).map((x) => File(x.path)));
    });
  }

  /// Uploads the not-yet-uploaded photos; returns all URLs in order.
  Future<List<String>> _uploadPhotos(String offerId) async {
    final storage = StorageService();
    final urls = <String>[];
    for (var i = 0; i < _photos.length; i++) {
      final f = _photos[i];
      final done = _uploaded[f.path];
      if (done != null) {
        urls.add(done);
        continue;
      }
      if (mounted) {
        setState(
          () => _progress = 'Uploading photo ${i + 1} of ${_photos.length}…',
        );
      }
      final small = await StorageService.compressForUpload(f);
      final url = await storage.uploadImage(
        small,
        folder: AppConstants.swapOfferFolder(offerId),
      );
      _uploaded[f.path] = url;
      urls.add(url);
    }
    return urls;
  }

  Future<void> _propose(ListingModel target) async {
    final uid = context.read<AuthProvider>().firebaseUser?.uid ?? '';
    final source = _sourceFor(
      context.read<AuthProvider>().profile?.role.canSell ?? false,
    );
    if (uid.isEmpty || !_readyFor(source) || _busy) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      final offerId = _offerId ??= _firestore.newSwapOfferId();
      final SwapOfferModel offer;
      if (source == _OfferSource.photos) {
        final urls = await _uploadPhotos(offerId);
        if (mounted) setState(() => _progress = 'Sending offer…');
        offer = SwapOfferModel(
          offerId: offerId,
          listingId: target.listingId,
          offeredById: uid,
          offeredTitle: _titleCtrl.text.trim(),
          offeredImages: urls,
          message: _messageCtrl.text.trim(),
        );
      } else {
        offer = SwapOfferModel(
          offerId: offerId,
          listingId: target.listingId,
          offeredById: uid,
          offeredItemId: _offeredItemId!,
          message: _messageCtrl.text.trim(),
        );
      }
      await _firestore.createSwapOffer(offer);
      if (target.sellerId.isNotEmpty) {
        try {
          await _firestore.addNotification(
            target.sellerId,
            NotificationModel(
              type: NotificationType.swapOffer,
              message: offer.isPhotoOffer
                  ? 'New swap offer on "${target.title}": '
                        '${offer.offeredTitle} (photos).'
                  : 'New swap offer on "${target.title}".',
              relatedId: 'offer:$offerId',
            ),
          );
        } catch (e) {
          debugPrint('notifySwapOffer: $e');
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Swap proposed — the seller has been notified.'),
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      debugPrint('proposeSwap: $e');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _progress = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is StateError
                ? e.message
                : e is StorageException
                ? 'Photo upload failed: ${e.message}'
                : 'Could not propose. Try again.',
          ),
          backgroundColor: AppColors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = context.read<AuthProvider>().firebaseUser?.uid ?? '';
    final canSell = context.select<AuthProvider, bool>(
      (a) => a.profile?.role.canSell ?? false,
    );
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: const TopAppBar(title: 'Propose Swap'),
      body: StreamBuilder<ListingModel?>(
        stream: _target,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final target = snap.data;
          if (target == null) {
            return const Center(child: Text('Listing not found'));
          }
          final source = _sourceFor(canSell);
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _label('You want'),
              const SizedBox(height: 8),
              _targetCard(target),
              const SizedBox(height: 20),
              if (target.sellerId == uid)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'This is your listing — you cannot swap with yourself.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.gray),
                    ),
                  ),
                )
              else ...[
                _label('You offer'),
                const SizedBox(height: 8),
                if (canSell) ...[
                  SegmentedButton<_OfferSource>(
                    segments: const [
                      ButtonSegment(
                        value: _OfferSource.photos,
                        icon: Icon(Icons.photo_camera_outlined, size: 18),
                        label: Text('Photos'),
                      ),
                      ButtonSegment(
                        value: _OfferSource.listing,
                        icon: Icon(Icons.storefront_outlined, size: 18),
                        label: Text('My listing'),
                      ),
                    ],
                    selected: {_source},
                    showSelectedIcon: false,
                    onSelectionChanged: _busy
                        ? null
                        : (v) => setState(() => _source = v.first),
                  ),
                  const SizedBox(height: 12),
                ],
                if (source == _OfferSource.photos)
                  _photoOffer()
                else
                  _listingOffer(uid, target),
                const SizedBox(height: 16),
                TextField(
                  controller: _messageCtrl,
                  enabled: !_busy,
                  minLines: 2,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Message to seller (optional)',
                    hintText: 'e.g. size, condition, meet-up only…',
                  ),
                ),
                if (_progress != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _progress!,
                          style: const TextStyle(color: AppColors.gray),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 20),
                PrimaryButton(
                  label: 'Propose Swap',
                  icon: Icons.swap_horiz,
                  loading: _busy,
                  onPressed: (_busy || !_readyFor(source))
                      ? null
                      : () => _propose(target),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _label(String text) => Text(
    text,
    style: const TextStyle(
      fontWeight: FontWeight.w700,
      color: AppColors.gray,
      fontSize: 13,
    ),
  );

  /// Item shown with photos from this phone — no listing needed.
  Widget _photoOffer() {
    const max = AppConstants.maxSwapOfferPhotos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _titleCtrl,
          enabled: !_busy,
          maxLength: 80,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'What are you offering?',
            hintText: 'e.g. Uniqlo linen shirt, size M',
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Photos (${_photos.length}/$max) — show the front, back and any flaws.',
          style: const TextStyle(fontSize: 12.5, color: AppColors.gray),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 92,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (var i = 0; i < _photos.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          _photos[i],
                          width: 92,
                          height: 92,
                          fit: BoxFit.cover,
                          cacheWidth: 276,
                        ),
                      ),
                      if (!_busy)
                        Positioned(
                          right: 2,
                          top: 2,
                          child: InkWell(
                            onTap: () => setState(() {
                              _uploaded.remove(_photos[i].path);
                              _photos.removeAt(i);
                            }),
                            child: Container(
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              padding: const EdgeInsets.all(3),
                              child: const Icon(
                                Icons.close,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              if (_photos.length < max)
                InkWell(
                  onTap: _busy ? null : _addPhotos,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 92,
                    height: 92,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add_a_photo_outlined,
                          color: AppColors.coral,
                        ),
                        SizedBox(height: 4),
                        Text('Add photo', style: TextStyle(fontSize: 11.5)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// One of the offerer's active listings (seller accounts).
  Widget _listingOffer(String uid, ListingModel target) {
    return StreamBuilder<List<ListingModel>>(
      stream: _firestore.streamSellerListings(uid),
      builder: (context, mineSnap) {
        if (mineSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final mine = (mineSnap.data ?? const <ListingModel>[])
            .where(
              (l) =>
                  l.status == ListingStatus.active &&
                  l.listingId != target.listingId,
            )
            .toList();
        if (mine.isEmpty) {
          return const Text(
            'You have no other active listings. Use "Photos" to offer an '
            'item straight from your phone instead.',
            style: TextStyle(color: AppColors.gray, height: 1.45),
          );
        }
        return Column(children: [for (final m in mine) _offerTile(m)]);
      },
    );
  }

  Widget _targetCard(ListingModel target) {
    return AppCardWrapper(
      child: Row(
        children: [
          ListingThumb(
            url: target.images.isNotEmpty ? target.images.first : '',
            size: 64,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  target.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    TypeBadge(target.type),
                    const SizedBox(width: 8),
                    if (!target.swapOnly && target.price != null)
                      Text(
                        AppUtils.formatCurrency(target.price),
                        style: const TextStyle(
                          color: AppColors.coral,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    else
                      const Text(
                        'Trade only',
                        style: TextStyle(
                          color: AppColors.teal,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _offerTile(ListingModel m) {
    final selected = _offeredItemId == m.listingId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCardWrapper(
        onTap: _busy
            ? null
            : () => setState(() => _offeredItemId = m.listingId),
        child: Row(
          children: [
            ListingThumb(
              url: m.images.isNotEmpty ? m.images.first : '',
              size: 56,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  TypeBadge(m.type),
                ],
              ),
            ),
            Icon(
              selected ? Icons.check_circle : Icons.radio_button_unchecked,
              color: selected ? AppColors.teal : AppColors.gray,
            ),
          ],
        ),
      ),
    );
  }
}
