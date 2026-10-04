import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/listing_model.dart';
import '../../models/report_model.dart';
import '../../models/transaction_model.dart';
import '../../models/user_model.dart';

/// Shared building blocks for the admin screens (cards, pills, avatars,
/// filter rows). Brand palette only — selected state uses coralDeep.

/// White rounded card used across the admin side.
class AdminCard extends StatelessWidget {
  const AdminCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color = AppColors.surface,
    this.radius = 22,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
    );
    return Material(
      color: color,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Small rounded label. [dot] adds a leading status dot.
class SoftPill extends StatelessWidget {
  const SoftPill(
    this.label, {
    super.key,
    required this.color,
    this.icon,
    this.dot = false,
    this.solid = false,
    this.fontSize = 11.5,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final bool dot;

  /// Solid fill with white text instead of a tinted background.
  final bool solid;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final fg = solid ? Colors.white : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: solid ? color : color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
          ],
          if (icon != null) ...[
            Icon(icon, size: fontSize + 2, color: fg),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontSize: fontSize,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One option in a [PillRow].
class PillOption<T> {
  const PillOption(this.value, this.label, {this.icon});

  final T value;
  final String label;
  final IconData? icon;
}

/// Horizontally scrolling single-select pills (filters, tabs, sort).
class PillRow<T> extends StatelessWidget {
  const PillRow({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
    this.compact = false,
  });

  final List<PillOption<T>> options;
  final T selected;
  final ValueChanged<T> onSelected;
  final EdgeInsetsGeometry padding;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: compact ? 34 : 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final o = options[i];
          final on = o.value == selected;
          return Material(
            color: on ? AppColors.coralDeep : AppColors.surface,
            shape: StadiumBorder(
              side: BorderSide(
                color: on ? AppColors.coralDeep : AppColors.line,
              ),
            ),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () => onSelected(o.value),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (o.icon != null) ...[
                      Icon(
                        o.icon,
                        size: 16,
                        color: on ? Colors.white : AppColors.ink,
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      o.label,
                      style: TextStyle(
                        fontSize: compact ? 12.5 : 13.5,
                        fontWeight: FontWeight.w700,
                        color: on ? Colors.white : AppColors.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Rounded white search field with an optional trailing widget.
class AdminSearchField extends StatelessWidget {
  const AdminSearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          const Icon(Icons.search, color: AppColors.gray),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: hint,
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) => controller.text.isEmpty
                ? const SizedBox(width: 16)
                : IconButton(
                    icon: const Icon(Icons.cancel_outlined),
                    color: AppColors.gray,
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Circular user photo (or initials) with an optional status dot.
class AdminAvatar extends StatelessWidget {
  const AdminAvatar({
    super.key,
    required this.user,
    this.size = 56,
    this.showStatus = true,
  });

  final UserModel? user;
  final double size;
  final bool showStatus;

  @override
  Widget build(BuildContext context) {
    final u = user;
    final photo = u?.photoUrl ?? '';
    final initials = _initials(u?.name.isNotEmpty == true ? u!.name : u?.email);
    final status = u == null ? null : accountStatusColor(u.accountStatus);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: u?.role == UserRole.admin
                  ? AppColors.coral.withValues(alpha: 0.14)
                  : AppColors.mist,
              shape: BoxShape.circle,
            ),
            clipBehavior: Clip.antiAlias,
            alignment: Alignment.center,
            child: photo.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: photo,
                    width: size,
                    height: size,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) => _initialsText(initials),
                  )
                : u?.role == UserRole.admin
                ? Icon(
                    Icons.shield_outlined,
                    color: AppColors.coralDeep,
                    size: size * 0.45,
                  )
                : _initialsText(initials),
          ),
          if (showStatus && status != null)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: size * 0.28,
                height: size * 0.28,
                decoration: BoxDecoration(
                  color: status,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.surface, width: 2.5),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _initialsText(String initials) => Text(
    initials,
    style: TextStyle(
      fontSize: size * 0.34,
      fontWeight: FontWeight.w800,
      color: AppColors.ink,
    ),
  );

  static String _initials(String? name) {
    final parts = (name ?? '')
        .trim()
        .split(RegExp(r'[\s@._]+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
}

/// Uppercase small caption above a value ("FLAGGED QUEUE").
class CapsLabel extends StatelessWidget {
  const CapsLabel(this.text, {super.key, this.color = AppColors.gray});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: TextStyle(
      fontSize: 10.5,
      letterSpacing: 0.8,
      fontWeight: FontWeight.w700,
      color: color,
    ),
  );
}

/// Thumbnail with an optional id tag in the bottom-left corner.
class TaggedThumb extends StatelessWidget {
  const TaggedThumb({
    super.key,
    required this.url,
    this.tag,
    this.width = 96,
    this.height = 96,
    this.radius = 14,
  });

  final String url;
  final String? tag;
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: AppColors.mist,
      alignment: Alignment.center,
      child: const Icon(Icons.checkroom_outlined, color: AppColors.gray),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (url.isEmpty)
              placeholder
            else
              CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (_, _) => placeholder,
                errorWidget: (_, _, _) => placeholder,
              ),
            if (tag != null)
              Positioned(
                left: 6,
                bottom: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    tag!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// --- Labels & colours -------------------------------------------------------

Color accountStatusColor(AccountStatus s) => switch (s) {
  AccountStatus.active => AppColors.green,
  AccountStatus.suspended => AppColors.amber,
  AccountStatus.banned => AppColors.red,
};

String roleLabel(UserRole r) => switch (r) {
  UserRole.customer => 'Customer',
  UserRole.seller => 'Seller',
  UserRole.both => 'Buyer & Seller',
  UserRole.admin => 'Admin',
};

Color typeColor(ListingType t) => switch (t) {
  ListingType.buyNow => AppColors.coral,
  ListingType.bid => AppColors.amber,
  ListingType.swap => AppColors.teal,
};

String typeLabel(ListingType t) => switch (t) {
  ListingType.buyNow => 'Buy Now',
  ListingType.bid => 'Bidding',
  ListingType.swap => 'Swap',
};

IconData typeIcon(ListingType t) => switch (t) {
  ListingType.buyNow => Icons.shopping_bag_outlined,
  ListingType.bid => Icons.gavel,
  ListingType.swap => Icons.swap_horiz,
};

String reportStatusLabel(ReportStatus s) => switch (s) {
  ReportStatus.pending => 'Pending',
  ReportStatus.dismissed => 'Dismissed',
  ReportStatus.warned => 'Warned',
  ReportStatus.suspended => 'Suspended',
  ReportStatus.removed => 'Removed',
};

Color reportStatusColor(ReportStatus s) => switch (s) {
  ReportStatus.pending => AppColors.amber,
  ReportStatus.dismissed => AppColors.gray,
  ReportStatus.warned => AppColors.coral,
  ReportStatus.suspended => AppColors.red,
  ReportStatus.removed => AppColors.red,
};

Color txnStatusColor(TransactionStatus s) => switch (s) {
  TransactionStatus.pending => AppColors.amber,
  TransactionStatus.ongoing => AppColors.teal,
  TransactionStatus.completed => AppColors.green,
  TransactionStatus.cancelled => AppColors.gray,
  TransactionStatus.disputed => AppColors.red,
};

String txnStatusLabel(TransactionStatus s) => switch (s) {
  TransactionStatus.pending => 'Pending',
  TransactionStatus.ongoing => 'In progress',
  TransactionStatus.completed => 'Completed',
  TransactionStatus.cancelled => 'Cancelled',
  TransactionStatus.disputed => 'Disputed',
};

// --- Dialog helpers -----------------------------------------------------------

/// Yes/no confirmation; returns true only on confirm.
Future<bool> confirmAdminAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = true,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(d).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: destructive ? AppColors.red : AppColors.teal,
          ),
          onPressed: () => Navigator.of(d).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok == true;
}

void showAdminError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), backgroundColor: AppColors.red),
  );
}
