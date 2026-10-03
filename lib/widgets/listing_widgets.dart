import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/listing_model.dart';
import '../models/transaction_model.dart';
import '../models/user_model.dart';
import '../services/firestore_service.dart';

/// Rounded square listing photo with a neutral placeholder.
class ListingThumb extends StatelessWidget {
  const ListingThumb({super.key, this.url, this.size = 64, this.radius = 12});

  final String? url;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: size,
      height: size,
      color: AppColors.mist,
      child: Icon(
        Icons.image_outlined,
        color: AppColors.gray,
        size: size * 0.4,
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: (url == null || url!.isEmpty)
          ? placeholder
          : CachedNetworkImage(
              imageUrl: url!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              placeholder: (_, _) => placeholder,
              errorWidget: (_, _, _) => placeholder,
            ),
    );
  }
}

/// Small rounded status label.
class StatusPill extends StatelessWidget {
  const StatusPill(this.label, {super.key, required this.color});

  final String label;
  final Color color;

  factory StatusPill.listing(ListingStatus status, {Key? key}) {
    return switch (status) {
      ListingStatus.active =>
        StatusPill('Active', color: AppColors.green, key: key),
      ListingStatus.sold => StatusPill('Sold', color: AppColors.coral, key: key),
      ListingStatus.expired =>
        StatusPill('Expired', color: AppColors.gray, key: key),
      ListingStatus.removed =>
        StatusPill('Delisted', color: AppColors.gray, key: key),
    };
  }

  factory StatusPill.transaction(TransactionStatus status, {Key? key}) {
    return switch (status) {
      TransactionStatus.pending =>
        StatusPill('Pending', color: AppColors.amber, key: key),
      TransactionStatus.ongoing =>
        StatusPill('In progress', color: AppColors.teal, key: key),
      TransactionStatus.completed =>
        StatusPill('Completed', color: AppColors.green, key: key),
      TransactionStatus.cancelled =>
        StatusPill('Cancelled', color: AppColors.gray, key: key),
      TransactionStatus.disputed =>
        StatusPill('Disputed', color: AppColors.red, key: key),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Resolves a user id to their profile once (cached) and builds with it.
class UserLookup extends StatelessWidget {
  const UserLookup({super.key, required this.uid, required this.builder});

  final String uid;
  final Widget Function(BuildContext context, UserModel? user) builder;

  @override
  Widget build(BuildContext context) {
    if (uid.isEmpty) return builder(context, null);
    return FutureBuilder<UserModel?>(
      future: FirestoreService().getUserCached(uid),
      builder: (context, snap) => builder(context, snap.data),
    );
  }
}

/// A user's display name, falling back to "SwidShop user".
class UserNameText extends StatelessWidget {
  const UserNameText(this.uid, {super.key, this.style});

  final String uid;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return UserLookup(
      uid: uid,
      builder: (context, user) => Text(
        (user?.name.isNotEmpty ?? false) ? user!.name : 'SwidShop user',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
  }
}

/// Centered icon + title + message for empty lists.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AppColors.mist,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.gray, size: 30),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.4,
                  color: AppColors.gray,
                ),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

/// White rounded card with a hairline border (flat, no shadow).
class OutlineCard extends StatelessWidget {
  const OutlineCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            border: Border.all(color: AppColors.line),
          ),
          child: child,
        ),
      ),
    );
  }
}
