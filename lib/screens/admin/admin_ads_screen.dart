import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/partner_ad_model.dart';
import '../../providers/admin_provider.dart';
import '../../services/firestore_service.dart';
import '../../services/storage_service.dart';
import '../../widgets/top_app_bar.dart';
import 'admin_gate.dart';
import 'admin_widgets.dart';

/// Pushes Manage Ads, carrying the shell's [AdminProvider] into the route.
void openAdminAds(BuildContext context) {
  final admin = context.read<AdminProvider>();
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ChangeNotifierProvider.value(
        value: admin,
        child: const AdminAdsScreen(),
      ),
    ),
  );
}

/// Partner banner ads CRUD (Step 6). Display-only banners on Home.
class AdminAdsScreen extends StatelessWidget {
  const AdminAdsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ads = context.watch<AdminProvider>().partnerAds;
    return AdminGate(
      child: Scaffold(
        backgroundColor: AppColors.paper,
        appBar: const TopAppBar(title: 'Manage Ads'),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: AppColors.coral,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add),
          label: const Text('New Ad'),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const _AdEditor()),
          ),
        ),
        body: ads.isEmpty
            ? const Center(
                child: Text(
                  'No ads yet.',
                  style: TextStyle(color: AppColors.gray),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                itemCount: ads.length,
                itemBuilder: (context, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _AdCard(ad: ads[i]),
                ),
              ),
      ),
    );
  }
}

class _AdCard extends StatelessWidget {
  const _AdCard({required this.ad});

  final PartnerAdModel ad;

  @override
  Widget build(BuildContext context) {
    return AdminCard(
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 72,
              height: 48,
              child: ad.imageUrl.isEmpty
                  ? Container(
                      color: AppColors.cream,
                      child: const Icon(
                        Icons.image_outlined,
                        color: AppColors.gray,
                      ),
                    )
                  : CachedNetworkImage(
                      imageUrl: ad.imageUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => const Icon(
                        Icons.broken_image_outlined,
                        color: AppColors.gray,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ad.title.isEmpty ? 'Untitled' : ad.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  '${ad.startsAt == null ? '—' : AppUtils.formatDate(ad.startsAt)} → '
                  '${ad.endsAt == null ? '—' : AppUtils.formatDate(ad.endsAt)} · '
                  '${AppUtils.formatCurrency(ad.pricePaid)} paid',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.gray,
                  ),
                ),
                const SizedBox(height: 2),
                SoftPill(
                  ad.isLive ? 'Live' : 'Inactive',
                  color: ad.isLive ? AppColors.green : AppColors.gray,
                  dot: ad.isLive,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined, color: AppColors.teal),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => _AdEditor(existing: ad)),
            ),
          ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline, color: AppColors.red),
            onPressed: () => _delete(context, ad),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(BuildContext context, PartnerAdModel ad) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Delete this ad?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.of(d).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await FirestoreService().deletePartnerAd(ad.adId);
    } catch (e) {
      debugPrint('deleteAd: $e');
    }
  }
}

class _AdEditor extends StatefulWidget {
  const _AdEditor({this.existing});

  final PartnerAdModel? existing;

  @override
  State<_AdEditor> createState() => _AdEditorState();
}

class _AdEditorState extends State<_AdEditor> {
  final _formKey = GlobalKey<FormState>();
  late final _titleCtrl =
      TextEditingController(text: widget.existing?.title ?? '');
  late final _linkCtrl =
      TextEditingController(text: widget.existing?.link ?? '');
  late final _priceCtrl = TextEditingController(
    text: widget.existing == null
        ? ''
        : widget.existing!.pricePaid.toStringAsFixed(0),
  );
  DateTime? _startsAt = DateTime.now();
  DateTime? _endsAt;
  String _imageUrl = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _imageUrl = widget.existing?.imageUrl ?? '';
    _startsAt = widget.existing?.startsAt ?? DateTime.now();
    _endsAt = widget.existing?.endsAt ??
        DateTime.now().add(const Duration(days: 7));
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _linkCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool start) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (start ? _startsAt : _endsAt) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked != null && mounted) {
      setState(() {
        if (start) {
          _startsAt = picked; // runs from the start of that day
        } else {
          // ...through the END of the chosen end day.
          _endsAt = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
        }
      });
    }
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
    );
    if (picked == null || !mounted) return;
    setState(() => _busy = true);
    try {
      // Ads reuse the listings upload pipeline (Cloudinary only).
      final url = await StorageService().uploadImage(
        File(picked.path),
        folder: AppConstants.listingsFolder('ads'),
      );
      if (mounted) setState(() => _imageUrl = url);
    } catch (e) {
      debugPrint('adImage: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Image upload failed. Try again.'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    String? problem;
    if (_imageUrl.isEmpty) {
      problem = 'Add a banner image.';
    } else if (_startsAt == null || _endsAt == null) {
      problem = 'Pick a start and an end date.';
    } else if (!_endsAt!.isAfter(_startsAt!)) {
      problem = 'The end date must be after the start date.';
    }
    if (problem != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(problem), backgroundColor: AppColors.red),
      );
      return;
    }
    // Live again whenever the window is (still) open — the hourly expiry
    // only switches ads off, so an extended ad must be switched back on.
    final active = _endsAt!.isAfter(DateTime.now());
    setState(() => _busy = true);
    try {
      final svc = FirestoreService();
      if (widget.existing == null) {
        await svc.createPartnerAd(PartnerAdModel(
          adId: '',
          title: _titleCtrl.text.trim(),
          imageUrl: _imageUrl,
          link: _linkCtrl.text.trim(),
          startsAt: _startsAt,
          endsAt: _endsAt,
          pricePaid: double.tryParse(_priceCtrl.text.trim()) ?? 0,
          active: active,
        ));
      } else {
        await svc.updatePartnerAd(widget.existing!.adId, {
          'title': _titleCtrl.text.trim(),
          'imageUrl': _imageUrl,
          'link': _linkCtrl.text.trim(),
          'startsAt': _startsAt == null
              ? null
              : Timestamp.fromDate(_startsAt!),
          'endsAt':
              _endsAt == null ? null : Timestamp.fromDate(_endsAt!),
          'pricePaid': double.tryParse(_priceCtrl.text.trim()) ?? 0,
          'active': active,
        });
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      debugPrint('saveAd: $e');
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save. Try again.'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: TopAppBar(
        title: widget.existing == null ? 'New Ad' : 'Edit Ad',
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GestureDetector(
                onTap: _busy ? null : _pickImage,
                child: Container(
                  height: 140,
                  decoration: BoxDecoration(
                    color: AppColors.cream,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.line),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _imageUrl.isEmpty
                      ? const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.add_photo_alternate_outlined,
                              color: AppColors.gray,
                              size: 32,
                            ),
                            SizedBox(height: 6),
                            Text(
                              'Banner image (Cloudinary)',
                              style: TextStyle(color: AppColors.gray),
                            ),
                          ],
                        )
                      : CachedNetworkImage(
                          imageUrl: _imageUrl,
                          fit: BoxFit.cover,
                        ),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _titleCtrl,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Title required' : null,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _linkCtrl,
                decoration: const InputDecoration(
                  labelText: 'Link (display text only)',
                  hintText: 'e.g. swid.shop/partner-sale',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _priceCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (v) {
                  final n = double.tryParse((v ?? '').trim());
                  return n == null || n < 0 ? 'Enter the amount paid' : null;
                },
                decoration: const InputDecoration(
                  labelText: 'Price paid (₱)',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pickDate(true),
                      child: Text(
                        _startsAt == null
                            ? 'Start date'
                            : AppUtils.formatDate(_startsAt),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pickDate(false),
                      child: Text(
                        _endsAt == null
                            ? 'End date'
                            : AppUtils.formatDate(_endsAt),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.coral,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(widget.existing == null ? 'Create Ad' : 'Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
