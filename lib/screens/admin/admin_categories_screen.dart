import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/category_model.dart';
import '../../models/listing_model.dart';
import '../../services/firestore_service.dart';
import '../../widgets/app_card_wrapper.dart';
import '../../widgets/top_app_bar.dart';
import 'admin_gate.dart';

/// Category CRUD + reorder (Phase 4.5).
///
/// Home, Search and Post Listing all read `categories`, so edits land
/// everywhere instantly. Deleting a category in use first reassigns its
/// listings to "Uncategorized" (counted live, confirmed in a dialog).
class AdminCategoriesScreen extends StatefulWidget {
  const AdminCategoriesScreen({super.key});

  @override
  State<AdminCategoriesScreen> createState() => _AdminCategoriesScreenState();
}

class _AdminCategoriesScreenState extends State<AdminCategoriesScreen> {
  final _firestore = FirestoreService();

  /// Custom = sortOrder; Volume = live listing counts desc; A–Z = by name.
  String _sort = 'Custom';

  Future<void> _addOrEdit(
      {CategoryModel? existing, required int nextOrder}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final iconCtrl = TextEditingController(text: existing?.iconName ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(existing == null ? 'Add Category' : 'Edit Category'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: iconCtrl,
              decoration: const InputDecoration(
                labelText: 'Icon name (optional)',
                hintText: 'e.g. checkroom',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(d).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;
    try {
      if (existing == null) {
        await _firestore.seedCategories([
          CategoryModel(
            categoryId: '',
            name: name,
            iconName: iconCtrl.text.trim(),
            sortOrder: nextOrder,
          ),
        ]);
      } else {
        await _firestore.updateCategory(existing.categoryId, {
          'name': name,
          'iconName': iconCtrl.text.trim(),
        });
      }
    } catch (e) {
      debugPrint('saveCategory: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save. Try again.'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    }
  }

  Future<void> _delete(CategoryModel category, int inUse) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Delete "${category.name}"?'),
        content: Text(
          inUse == 0
              ? 'No listings use it. This cannot be undone.'
              : '$inUse listing${inUse == 1 ? '' : 's'} use${inUse == 1 ? 's' : ''} it — they will be moved to "Uncategorized".',
        ),
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
      if (inUse > 0) {
        await _firestore.reassignCategoryListings(category.name);
      }
      await _firestore.deleteCategory(category.categoryId);
    } catch (e) {
      debugPrint('deleteCategory: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not delete. Try again.'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    }
  }

  /// Swaps sortOrder with the neighbor above/below (live-stream safe).
  Future<void> _move(
    List<CategoryModel> ordered,
    int index,
    int delta,
  ) async {
    final other = index + delta;
    if (other < 0 || other >= ordered.length) return;
    final a = ordered[index];
    final b = ordered[other];
    try {
      await Future.wait([
        _firestore.updateCategory(a.categoryId, {'sortOrder': b.sortOrder}),
        _firestore.updateCategory(b.categoryId, {'sortOrder': a.sortOrder}),
      ]);
    } catch (e) {
      debugPrint('reorderCategory: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminGate(
      child: Scaffold(
        backgroundColor: AppColors.cream,
        appBar: const TopAppBar(title: 'Manage Categories'),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: AppColors.coral,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add),
          label: const Text('Add Category'),
          onPressed: () async {
            final cats = await _firestore.streamCategories().first;
            var maxOrder = 0;
            for (final c in cats) {
              if (c.sortOrder > maxOrder) maxOrder = c.sortOrder;
            }
            if (mounted) {
              await _addOrEdit(nextOrder: maxOrder + 1);
            }
          },
        ),
        body: StreamBuilder<List<ListingModel>>(
          stream: _firestore.streamAllListings(),
          builder: (context, listingSnap) {
            final listings = listingSnap.data ?? const <ListingModel>[];
            final counts = <String, int>{};
            for (final l in listings) {
              if (l.category.isEmpty) continue;
              counts[l.category] = (counts[l.category] ?? 0) + 1;
            }
            return StreamBuilder<List<CategoryModel>>(
              stream: _firestore.streamCategories(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final base = (snap.data ?? const <CategoryModel>[]).toList()
                  ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
                final ordered = _sorted(base, counts);
                if (ordered.isEmpty) {
                  return const Center(
                    child: Text(
                      'No categories yet.',
                      style: TextStyle(color: AppColors.gray),
                    ),
                  );
                }
                return Column(
                  children: [
                    _sortPills(),
                    Expanded(
                      child: ListView.builder(
                        padding:
                            const EdgeInsets.fromLTRB(16, 8, 16, 96),
                        itemCount: ordered.length,
                        itemBuilder: (context, i) => _row(
                          ordered[i],
                          index: i,
                          last: ordered.length - 1,
                          ordered: ordered,
                          inUse: counts[ordered[i].name] ?? 0,
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _row(
    CategoryModel c, {
    required int index,
    required int last,
    required List<CategoryModel> ordered,
    required int inUse,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCardWrapper(
        child: Row(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () => _move(ordered, index, -1),
                  child: Icon(
                    Icons.arrow_drop_up,
                    color: index == 0 ? AppColors.line : AppColors.gray,
                  ),
                ),
                GestureDetector(
                  onTap: () => _move(ordered, index, 1),
                  child: Icon(
                    Icons.arrow_drop_down,
                    color:
                        index == last ? AppColors.line : AppColors.gray,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '$inUse listings',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.gray,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(
                Icons.edit_outlined,
                color: AppColors.teal,
              ),
              onPressed: () => _addOrEdit(
                existing: c,
                nextOrder: c.sortOrder,
              ),
            ),
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(
                Icons.delete_outline,
                color: AppColors.red,
              ),
              onPressed: () => _delete(c, inUse),
            ),
          ],
        ),
      ),
    );
  }

  /// Mockup SORT pills: Custom order, High Volume, A–Z (all client-side).
  Widget _sortPills() {
    Widget pill(String label) {
      final selected = _sort == label;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          showCheckmark: false,
          onSelected: (_) => setState(() => _sort = label),
          selectedColor: AppColors.teal,
          labelStyle: TextStyle(
            color: selected ? Colors.white : AppColors.ink,
            fontWeight: FontWeight.w600,
          ),
          backgroundColor: AppColors.surface,
          side: BorderSide(
            color: selected ? AppColors.teal : AppColors.line,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      );
    }

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        children: [
          pill('Custom'),
          pill('High Volume'),
          pill('A–Z'),
        ],
      ),
    );
  }

  List<CategoryModel> _sorted(
    List<CategoryModel> cats,
    Map<String, int> counts,
  ) {
    final ordered = List<CategoryModel>.of(cats);
    switch (_sort) {
      case 'High Volume':
        ordered.sort(
          (a, b) => (counts[b.name] ?? 0).compareTo(counts[a.name] ?? 0),
        );
      case 'A–Z':
        ordered.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      default:
        break; // already sortOrder
    }
    return ordered;
  }
}
