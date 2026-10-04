import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';
import '../../services/storage_service.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/top_app_bar.dart';

/// Edits the public profile fields of `users/{uid}` (Phase 3.11).
/// Sensitive data lives in `private/details` — never edited here.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _provinceCtrl = TextEditingController();
  File? _photo;
  bool _busy = false;
  bool _loaded = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _cityCtrl.dispose();
    _provinceCtrl.dispose();
    super.dispose();
  }

  void _fill(UserModel profile) {
    if (_loaded) return;
    _loaded = true;
    _nameCtrl.text = profile.name;
    _cityCtrl.text = profile.address.city;
    _provinceCtrl.text = profile.address.province;
  }

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
    );
    if (picked != null && mounted) {
      setState(() => _photo = File(picked.path));
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final auth = context.read<AuthProvider>();
    final uid = auth.firebaseUser?.uid ?? '';
    if (uid.isEmpty) return;
    setState(() => _busy = true);
    try {
      var photoUrl = auth.profile?.photoUrl ?? '';
      if (_photo != null) {
        photoUrl = await StorageService().uploadAvatar(_photo!, uid);
      }
      await FirestoreService().updateUserProfile(uid, {
        'name': _nameCtrl.text.trim(),
        'photoUrl': photoUrl,
        'address': {
          ...(auth.profile?.address.toMap() ?? const {}),
          'city': _cityCtrl.text.trim(),
          'province': _provinceCtrl.text.trim(),
        },
      });
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      debugPrint('editProfile: $e');
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
    final profile = context.watch<AuthProvider>().profile;
    if (profile == null) {
      return const Scaffold(
        backgroundColor: AppColors.cream,
        body: Center(child: Text('Profile not loaded.')),
      );
    }
    _fill(profile);
    final photo = _photo != null
        ? FileImage(_photo!)
        : (profile.photoUrl.isNotEmpty
            ? NetworkImage(profile.photoUrl)
            : null);

    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: const TopAppBar(title: 'Edit Profile'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: GestureDetector(
                  onTap: _busy ? null : _pickPhoto,
                  child: CircleAvatar(
                    radius: 46,
                    backgroundColor: AppColors.mist,
                    backgroundImage: photo as ImageProvider?,
                    child: photo == null
                        ? const Icon(
                            Icons.add_a_photo_outlined,
                            size: 30,
                            color: AppColors.gray,
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _nameCtrl,
                textInputAction: TextInputAction.next,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                decoration: const InputDecoration(labelText: 'Display name'),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _cityCtrl,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'City'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _provinceCtrl,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(labelText: 'Province'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              PrimaryButton(
                label: 'Save',
                loading: _busy,
                onPressed: _busy ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
