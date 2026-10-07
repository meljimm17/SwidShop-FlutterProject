import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/category_model.dart';
import '../../providers/admin_provider.dart';
import 'admin_widgets.dart';

/// Icon choices for categories, stored as `iconName` keys.
const Map<String, IconData> categoryIcons = {
  'tshirt': Icons.checkroom_outlined,
  'jacket': Icons.dry_cleaning_outlined,
  'denim': Icons.straighten,
  'knit': Icons.texture,
  'shoes': Icons.hiking,
  'cap': Icons.sports_baseball_outlined,
  'bag': Icons.shopping_bag_outlined,
  'jewelry': Icons.diamond_outlined,
  'archive': Icons.auto_awesome_outlined,
  'upcycle': Icons.recycling,
  'band': Icons.graphic_eq,
  'vinyl': Icons.album_outlined,
  'kids': Icons.child_care_outlined,
  'sports': Icons.sports_basketball_outlined,
  'other': Icons.category_outlined,
};

/// Best icon for a category: its saved key, else a guess from the name.
IconData categoryIcon(CategoryModel c) {
  final saved = categoryIcons[c.iconName];
  if (saved != null) return saved;
  final n = c.name.toLowerCase();
  for (final (word, key) in [
    ('tee', 'tshirt'),
    ('shirt', 'tshirt'),
    ('top', 'tshirt'),
    ('jacket', 'jacket'),
    ('outer', 'jacket'),
    ('coat', 'jacket'),
    ('denim', 'denim'),
    ('jean', 'denim'),
    ('pant', 'denim'),
    ('sweater', 'knit'),
    ('knit', 'knit'),
    ('shoe', 'shoes'),
    ('foot', 'shoes'),
    ('sneaker', 'shoes'),
    ('boot', 'shoes'),
    ('cap', 'cap'),
    ('hat', 'cap'),
    ('bag', 'bag'),
    ('jewel', 'jewelry'),
    ('silver', 'jewelry'),
    ('access', 'jewelry'),
    ('archive', 'archive'),
    ('vintage', 'archive'),
    ('rework', 'upcycle'),
    ('upcycl', 'upcycle'),
    ('band', 'band'),
    ('vinyl', 'vinyl'),
    ('book', 'vinyl'),
    ('kid', 'kids'),
    ('sport', 'sports'),
  ]) {
    if (n.contains(word)) return categoryIcons[key]!;
  }
  return categoryIcons['other']!;
}

enum _Sort { custom, volume, az }

/// Categories: CRUD, live listing counts and drag-to-reorder (Phase 4.5).
///
/// Home, Search and Post Listing all read `categories`, so edits land
/// everywhere instantly. Deleting a category in use first moves its
/// listings to "Uncategorized".
class AdminCategoriesScreen extends StatefulWidget {
  const AdminCategoriesScreen({super.key});

  @override
  State<AdminCategoriesScreen> createState() => _AdminCategoriesScreenState();
}

class _AdminCategoriesScreenState extends State<AdminCategoriesScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  _Sort _sort = _Sort.custom;

  /// Optimistic order after a drag, until the stream catches up.
  List<String>? _pendingOrder;

  /// Created once so rebuilds don't re-subscribe.
  Stream<List<CategoryModel>>? _categories;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _addOrEdit(
    List<CategoryModel> all, {
    CategoryModel? existing,
  }) async {
    final fs = context.read<AdminProvider>().firestore;
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    var icon = existing == null
        ? 'other'
        : (categoryIcons.containsKey(existing.iconName)
              ? existing.iconName
              : categoryIcons.entries
                    .firstWhere(
                      (e) => e.value == categoryIcon(existing),
                      orElse: () => categoryIcons.entries.last,
                    )
                    .key);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setDialog) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(existing == null ? 'Add Category' : 'Edit Category'),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  autofocus: existing == null,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 16),
                const CapsLabel('Icon'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final e in categoryIcons.entries)
                      InkWell(
                        onTap: () => setDialog(() => icon = e.key),
                        customBorder: const CircleBorder(),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: icon == e.key
                                ? AppColors.coralDeep
                                : AppColors.mist,
                          ),
                          child: Icon(
                            e.value,
                            size: 20,
                            color: icon == e.key ? Colors.white : AppColors.ink,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(d).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.coralDeep,
              ),
              onPressed: () => Navigator.of(d).pop(true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    final name = nameCtrl.text.trim();
    nameCtrl.dispose();
    if (ok != true || name.isEmpty) return;
    final clash = all.any(
      (c) =>
          c.categoryId != existing?.categoryId &&
          c.name.toLowerCase() == name.toLowerCase(),
    );
    if (clash) {
      if (mounted) showAdminError(context, '"$name" already exists.');
      return;
    }
    try {
      if (existing == null) {
        final next = all.fold<int>(
          -1,
          (m, c) => c.sortOrder > m ? c.sortOrder : m,
        );
        final auditSaved = await fs.createCategory(
          CategoryModel(
            categoryId: '',
            name: name,
            iconName: icon,
            sortOrder: next + 1,
          ),
        );
        if (!auditSaved && mounted) {
          showAdminError(
            context,
            'Category added, but its audit record could not be saved.',
          );
        }
      } else {
        await fs.updateCategory(existing.categoryId, {
          'name': name,
          'iconName': icon,
        });
        if (name != existing.name) {
          // Keep listings attached to the renamed category.
          await _renameListings(existing.name, name);
        }
      }
    } catch (e) {
      debugPrint('saveCategory: $e');
      if (mounted) {
        final message = switch (e) {
          FirebaseException(code: 'permission-denied') =>
            'You do not have permission to add categories.',
          FirebaseException(code: 'unavailable') =>
            'Could not connect. Check your internet and try again.',
          StateError(:final message) => message.toString(),
          FirebaseException(:final message) when message != null => message,
          _ => 'Could not save category. Try again.',
        };
        showAdminError(context, message);
      }
    }
  }

  Future<void> _renameListings(String from, String to) async {
    final a = context.read<AdminProvider>();
    final affected = a.listings.where((l) => l.category == from);
    await Future.wait(
      affected.map(
        (l) => a.firestore.updateListing(l.listingId, {
          'category': to,
        }, auditAdminAction: true),
      ),
    );
  }

  Future<void> _delete(CategoryModel c, int inUse) async {
    final ok = await confirmAdminAction(
      context,
      title: 'Delete "${c.name}"?',
      message: inUse == 0
          ? 'No listings use it. This cannot be undone.'
          : '$inUse listing${inUse == 1 ? '' : 's'} use${inUse == 1 ? 's' : ''} '
                'it — they will be moved to "Uncategorized".',
      confirmLabel: 'Delete',
    );
    if (!ok || !mounted) return;
    final fs = context.read<AdminProvider>().firestore;
    try {
      if (inUse > 0) await fs.reassignCategoryListings(c.name);
      await fs.deleteCategory(c.categoryId);
    } catch (e) {
      debugPrint('deleteCategory: $e');
      if (mounted) showAdminError(context, 'Could not delete. Try again.');
    }
  }

  Future<void> _reorder(List<CategoryModel> ordered, int from, int to) async {
    final ids = ordered.map((c) => c.categoryId).toList();
    final moved = ids.removeAt(from);
    ids.insert(to, moved);
    setState(() => _pendingOrder = ids);
    try {
      await context.read<AdminProvider>().firestore.reorderCategories(ids);
    } catch (e) {
      debugPrint('reorderCategories: $e');
      if (mounted) {
        setState(() => _pendingOrder = null);
        showAdminError(context, 'Could not save the new order.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = context.watch<AdminProvider>();
    final counts = <String, int>{};
    for (final l in a.listings) {
      if (l.category.isEmpty) continue;
      counts[l.category] = (counts[l.category] ?? 0) + 1;
    }

    return StreamBuilder<List<CategoryModel>>(
      stream: _categories ??= a.firestore.streamCategories(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        var cats = snap.data!.toList()
          ..sort((x, y) => x.sortOrder.compareTo(y.sortOrder));
        final pending = _pendingOrder;
        if (pending != null) {
          final streamIds = cats.map((c) => c.categoryId).toList();
          if (streamIds.join() == pending.join()) {
            _pendingOrder = null; // stream caught up
          } else if (pending.length == cats.length) {
            final byId = {for (final c in cats) c.categoryId: c};
            if (pending.every(byId.containsKey)) {
              cats = [for (final id in pending) byId[id]!];
            }
          }
        }
        final all = cats;
        switch (_sort) {
          case _Sort.volume:
            cats = cats.toList()
              ..sort(
                (x, y) => (counts[y.name] ?? 0).compareTo(counts[x.name] ?? 0),
              );
          case _Sort.az:
            cats = cats.toList()
              ..sort(
                (x, y) => x.name.toLowerCase().compareTo(y.name.toLowerCase()),
              );
          case _Sort.custom:
            break;
        }
        if (_query.isNotEmpty) {
          cats = cats
              .where((c) => c.name.toLowerCase().contains(_query))
              .toList();
        }
        final canDrag = _sort == _Sort.custom && _query.isEmpty;
        final topCount = counts.values.fold<int>(0, (m, v) => v > m ? v : m);

        return Stack(
          children: [
            ReorderableListView.builder(
              buildDefaultDragHandles: false,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
              header: _header(all.length, canDrag),
              itemCount: cats.length,
              onReorderItem: (from, to) {
                if (canDrag) _reorder(cats, from, to);
              },
              proxyDecorator: (child, _, _) =>
                  Material(color: Colors.transparent, child: child),
              itemBuilder: (context, i) {
                final c = cats[i];
                final n = counts[c.name] ?? 0;
                return Padding(
                  key: ValueKey(c.categoryId),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _row(
                    c,
                    index: i,
                    count: n,
                    top: n > 0 && n == topCount,
                    canDrag: canDrag,
                    all: all,
                  ),
                );
              },
            ),
            Positioned(
              right: 20,
              bottom: 20,
              child: FloatingActionButton(
                heroTag: 'admin-add-category',
                tooltip: 'Add category',
                backgroundColor: AppColors.coralDeep,
                foregroundColor: Colors.white,
                shape: const CircleBorder(),
                onPressed: () => _addOrEdit(all),
                child: const Icon(Icons.add, size: 30),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _header(int total, bool canDrag) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminCard(
          color: AppColors.mist,
          radius: 22,
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.account_tree_outlined,
                    size: 18,
                    color: AppColors.teal,
                  ),
                  SizedBox(width: 6),
                  CapsLabel('Category Directory', color: AppColors.teal),
                ],
              ),
              const SizedBox(height: 8),
              const Text.rich(
                TextSpan(
                  text: 'Global list that feeds ',
                  children: [
                    TextSpan(
                      text: 'Home',
                      style: TextStyle(color: AppColors.coralDeep),
                    ),
                    TextSpan(text: ', '),
                    TextSpan(
                      text: 'Search & Filters',
                      style: TextStyle(color: AppColors.coralDeep),
                    ),
                    TextSpan(text: ' and '),
                    TextSpan(
                      text: 'Post New Listing',
                      style: TextStyle(color: AppColors.coralDeep),
                    ),
                    TextSpan(text: ' across SwidShop.'),
                  ],
                ),
                style: TextStyle(fontSize: 15.5, height: 1.4),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: AppColors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'Changes go live instantly',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  Text(
                    '$total categor${total == 1 ? 'y' : 'ies'}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        AdminSearchField(
          controller: _searchCtrl,
          hint: 'Filter categories ($total)…',
          onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const CapsLabel('Sort:'),
            const SizedBox(width: 8),
            Expanded(
              child: PillRow<_Sort>(
                compact: true,
                padding: EdgeInsets.zero,
                selected: _sort,
                onSelected: (s) => setState(() => _sort = s),
                options: const [
                  PillOption(_Sort.custom, 'Custom Order'),
                  PillOption(_Sort.volume, 'High Volume'),
                  PillOption(_Sort.az, 'A–Z'),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(
              Icons.drag_indicator,
              size: 16,
              color: canDrag ? AppColors.coralDeep : AppColors.gray,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                canDrag
                    ? 'Drag the handle to set display order'
                    : 'Switch to Custom Order (no filter) to reorder',
                style: const TextStyle(fontSize: 12, color: AppColors.gray),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _row(
    CategoryModel c, {
    required int index,
    required int count,
    required bool top,
    required bool canDrag,
    required List<CategoryModel> all,
  }) {
    final palette = [AppColors.coral, AppColors.teal, AppColors.amber];
    final tint = palette[index % palette.length];
    return AdminCard(
      radius: 22,
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 12),
      child: Row(
        children: [
          if (canDrag)
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Icon(Icons.drag_indicator, color: AppColors.gray),
              ),
            )
          else
            const SizedBox(width: 12),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(categoryIcon(c), color: tint, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    SoftPill(
                      '$count listing${count == 1 ? '' : 's'}',
                      color: AppColors.gray,
                      fontSize: 11,
                    ),
                    if (top)
                      const SoftPill(
                        'Most listings',
                        color: AppColors.teal,
                        icon: Icons.trending_up,
                        fontSize: 11,
                      ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined, color: AppColors.teal),
            onPressed: () => _addOrEdit(all, existing: c),
          ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline, color: AppColors.red),
            onPressed: () => _delete(c, count),
          ),
        ],
      ),
    );
  }
}
