import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/system_announcement.dart';
import '../../providers/admin_provider.dart';
import '../../services/firestore_service.dart';

class SuperadminSettingsScreen extends StatefulWidget {
  const SuperadminSettingsScreen({super.key});

  @override
  State<SuperadminSettingsScreen> createState() =>
      _SuperadminSettingsScreenState();
}

class _SuperadminSettingsScreenState extends State<SuperadminSettingsScreen> {
  final _message = TextEditingController();
  bool _enabled = false;
  bool _loaded = false;
  bool _saving = false;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  void _load(SystemAnnouncement announcement) {
    if (_loaded) return;
    _loaded = true;
    _enabled = announcement.enabled;
    _message.text = announcement.message;
  }

  @override
  Widget build(BuildContext context) {
    final fs = context.read<AdminProvider>().firestore;
    return StreamBuilder<SystemAnnouncement>(
      stream: fs.streamSystemAnnouncement(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Could not load system settings.'));
        }
        final announcement = snapshot.data;
        if (announcement == null) {
          return const Center(child: CircularProgressIndicator());
        }
        _load(announcement);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            const Text(
              'System settings',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text(
              'Publish a short public notice on the customer Home screen. '
              'Do not enter passwords, private data, or security settings.',
              style: TextStyle(color: AppColors.gray),
            ),
            const SizedBox(height: 18),
            Card(
              color: AppColors.surface,
              child: SwitchListTile(
                value: _enabled,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _enabled = value),
                title: const Text(
                  'Show announcement',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _message,
              maxLength: 160,
              maxLines: 3,
              enabled: !_saving,
              decoration: const InputDecoration(
                labelText: 'Announcement text',
                hintText: 'Write a brief message for customers',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
                filled: true,
                fillColor: AppColors.surface,
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _saving ? null : () => _save(fs),
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Saving…' : 'Save settings'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Changes are applied to Home immediately after saving.',
              style: TextStyle(color: AppColors.gray, fontSize: 12),
            ),
          ],
        );
      },
    );
  }

  Future<void> _save(FirestoreService fs) async {
    setState(() => _saving = true);
    try {
      await fs.saveSystemAnnouncement(
        enabled: _enabled,
        message: _message.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('System settings saved.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not save settings: $error'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
