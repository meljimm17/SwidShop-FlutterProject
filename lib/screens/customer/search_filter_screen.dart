import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/category_model.dart';
import '../../models/listing_model.dart';
import '../../providers/listing_provider.dart';
import '../../services/firestore_service.dart';
import '../../widgets/top_app_bar.dart';
import 'home_screen.dart' show ListingCard;

/// Search + filters (Phase 3.2).
///
/// One equality-only feed from [ListingProvider]; every filter, the result
/// count and the pages are computed client-side (no indexes deployed).
/// Optional [sellerId]/[sellerName] scopes the view to one stall
/// ("Visit Stall").
class SearchFilterScreen extends StatefulWidget {
  const SearchFilterScreen({
    super.key,
    this.sellerId,
    this.sellerName,
    this.initialType,
  });

  final String? sellerId;
  final String? sellerName;

  /// Type chip preselected on open (from Home quick-access). Cleared with
  /// everything else when the screen is closed.
  final ListingType? initialType;

  @override
  State<SearchFilterScreen> createState() => _SearchFilterScreenState();
}

class _SearchFilterScreenState extends State<SearchFilterScreen> {
  final _searchCtrl = TextEditingController();
  final _minCtrl = TextEditingController();
  final _maxCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final provider = context.read<ListingProvider>();
    if (widget.sellerId != null) {
      provider.setSeller(widget.sellerId);
    }
    if (widget.initialType != null) {
      provider.setType(widget.initialType);
    }
    _searchCtrl.text = provider.query;
    _searchCtrl.addListener(() => provider.setQuery(_searchCtrl.text));
  }

  @override
  void dispose() {
    // Search owns its filter state: leave nothing behind for Home.
    final provider = context.read<ListingProvider>();
    provider.setType(null);
    provider.setQuery('');
    provider.clearFilters();
    _searchCtrl.dispose();
    _minCtrl.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  void _openSheet() {
    final provider = context.read<ListingProvider>();
    _minCtrl.text = provider.minPrice?.toStringAsFixed(0) ?? '';
    _maxCtrl.text = provider.maxPrice?.toStringAsFixed(0) ?? '';
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => _FilterSheet(
        initialCategory: provider.category,
        initialCondition: provider.condition,
        minCtrl: _minCtrl,
        maxCtrl: _maxCtrl,
        onApply: (category, condition) {
          final min = double.tryParse(_minCtrl.text.trim());
          final max = double.tryParse(_maxCtrl.text.trim());
          provider.setCategory(category);
          provider.setCondition(condition);
          provider.setPriceRange(min, max);
        },
        onClear: provider.clearFilters,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ListingProvider>();
    final matches = provider.listings;
    final visible = provider.visibleListings;

    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: TopAppBar(
        title: widget.sellerName ?? 'Search',
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _searchCtrl,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search title or description',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => _searchCtrl.clear(),
                      ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${matches.length} result${matches.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                      color: AppColors.gray,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (provider.hasActiveFilters)
                  TextButton(
                    onPressed: provider.clearFilters,
                    child: const Text('Clear filters'),
                  ),
                FilledButton.tonal(
                  onPressed: _openSheet,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.surface,
                    foregroundColor: AppColors.ink,
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.tune, size: 18),
                      SizedBox(width: 6),
                      Text('Filters'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _typeChips(provider),
          Expanded(
            child: matches.isEmpty
                ? const Center(
                    child: Text(
                      'No matches — try clearing filters.',
                      style: TextStyle(color: AppColors.gray),
                    ),
                  )
                : _pagedGrid(provider, visible),
          ),
        ],
      ),
    );
  }

  Widget _typeChips(ListingProvider provider) {
    Widget chip(String label, ListingType? type) {
      final selected = provider.type == type;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          showCheckmark: false,
          onSelected: (_) => provider.setType(
            selected ? null : type,
          ),
          selectedColor: AppColors.coral,
          labelStyle: TextStyle(
            color: selected ? Colors.white : AppColors.ink,
            fontWeight: FontWeight.w600,
          ),
          backgroundColor: AppColors.surface,
          side: BorderSide(
            color: selected ? AppColors.coral : AppColors.line,
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
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          chip('All', null),
          chip('Buy Now', ListingType.buyNow),
          chip('Bidding', ListingType.bid),
          chip('Swap', ListingType.swap),
        ],
      ),
    );
  }

  Widget _pagedGrid(ListingProvider provider, List items) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.68,
      ),
      itemCount: visibleCount(provider, items),
      itemBuilder: (context, i) {
        if (i >= items.length) {
          // Bottom spinner tile: reveal the next page once laid out.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            provider.showMore();
          });
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          );
        }
        return ListingCard(listing: items[i]);
      },
    );
  }

  int visibleCount(ListingProvider provider, List items) =>
      provider.hasMore ? items.length + 1 : items.length;
}

/// Bottom-sheet editor for category / condition / price range.
class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.initialCategory,
    required this.initialCondition,
    required this.minCtrl,
    required this.maxCtrl,
    required this.onApply,
    required this.onClear,
  });

  final String? initialCategory;
  final String? initialCondition;
  final TextEditingController minCtrl;
  final TextEditingController maxCtrl;
  final void Function(String? category, String? condition) onApply;
  final VoidCallback onClear;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  String? _category;
  String? _condition;

  @override
  void initState() {
    super.initState();
    _category = widget.initialCategory;
    _condition = widget.initialCondition;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Center(
              child: SizedBox(
                width: 40,
                height: 4,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.line,
                    borderRadius: BorderRadius.all(Radius.circular(999)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Filters',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            const Text(
              'Category',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            StreamBuilder<List<CategoryModel>>(
              stream: FirestoreService().streamCategories(),
              builder: (context, snap) {
                final cats = snap.data ?? const <CategoryModel>[];
                if (cats.isEmpty) {
                  return const Text(
                    'No categories yet.',
                    style: TextStyle(color: AppColors.gray),
                  );
                }
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _pick('All', _category == null, () {
                      setState(() => _category = null);
                    }),
                    for (final c in cats)
                      _pick(c.name, _category == c.name, () {
                        setState(() => _category = c.name);
                      }),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            const Text(
              'Condition',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _pick('Any', _condition == null, () {
                  setState(() => _condition = null);
                }),
                for (final c in ListingModel.conditions)
                  _pick(c, _condition == c, () {
                    setState(() => _condition = c);
                  }),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Price range (₱)',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: widget.minCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: 'Min'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: widget.maxCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: 'Max'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Applies to fixed prices and current bids.',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.gray,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      widget.onClear();
                      Navigator.of(context).pop();
                    },
                    child: const Text('Clear'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      widget.onApply(_category, _condition);
                      Navigator.of(context).pop();
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.coral,
                    ),
                    child: const Text('Apply'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _pick(String label, bool selected, VoidCallback onTap) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => onTap(),
      selectedColor: AppColors.teal,
      labelStyle: TextStyle(
        color: selected ? Colors.white : AppColors.ink,
        fontWeight: FontWeight.w600,
      ),
      backgroundColor: AppColors.cream,
      side: BorderSide(color: selected ? AppColors.teal : AppColors.line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    );
  }
}
