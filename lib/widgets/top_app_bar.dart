import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/theme.dart';

/// The SwidShop top app bar used on every screen.
///
/// * 56px tall, cream background
/// * back arrow **or** logo on the left
/// * title centered-left
/// * optional search / bell / avatar actions on the right
class TopAppBar extends StatelessWidget implements PreferredSizeWidget {
  const TopAppBar({
    super.key,
    this.title,
    this.showLogo = false,
    this.showBack = true,
    this.onBack,
    this.onSearch,
    this.onBell,
    this.onAvatar,
    this.avatarUrl,
    this.onLogout,
    this.notificationCount = 0,
    this.bottom,
    this.extraActions = const [],
  });

  final String? title;
  final bool showLogo;
  final bool showBack;
  final VoidCallback? onBack;
  final VoidCallback? onSearch;
  final VoidCallback? onBell;
  final VoidCallback? onAvatar;
  final String? avatarUrl;
  final VoidCallback? onLogout;
  final int notificationCount;
  final PreferredSizeWidget? bottom;

  /// Extra action buttons shown on the right, before search / bell / avatar.
  /// Everything here is a plain ink icon — the user avatar stays the only
  /// circled element (photos are circles everywhere in the app).
  final List<Widget> extraActions;

  @override
  Size get preferredSize =>
      Size.fromHeight(AppTheme.appBarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.cream,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: AppTheme.appBarHeight,
      leading: _leading(context),
      leadingWidth: showLogo ? 132 : 56,
      titleSpacing: showLogo ? 0 : 8,
      centerTitle: false,
      title: title == null
          ? null
          : Text(
              title!,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 18,
                color: AppColors.ink,
              ),
            ),
      actions: _actions(context),
      bottom: bottom,
    );
  }

  Widget? _leading(BuildContext context) {
    if (showLogo) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Image.asset(
            'assets/images/${AppConstants.appName.toLowerCase()}_logo.png',
            height: 32,
            errorBuilder: (context, error, stack) => const Text(
              AppConstants.appName,
              style: TextStyle(
                color: AppColors.coral,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
          ),
        ),
      );
    }
    if (!showBack) return const SizedBox.shrink();
    return IconButton(
      icon: const Icon(Icons.arrow_back, color: AppColors.ink),
      onPressed: onBack ?? () => Navigator.of(context).maybePop(),
    );
  }

  List<Widget> _actions(BuildContext context) {
    final widgets = <Widget>[...extraActions];
    if (onSearch != null) {
      widgets.add(
        IconButton(
          icon: const Icon(Icons.search, color: AppColors.ink),
          onPressed: onSearch,
        ),
      );
    }
    if (onBell != null) {
      widgets.add(
        Stack(
          alignment: Alignment.topRight,
          children: [
            IconButton(
              icon: const Icon(Icons.notifications_none, color: AppColors.ink),
              onPressed: onBell,
            ),
            if (notificationCount > 0)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: AppColors.red,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    notificationCount > 9 ? '9+' : '$notificationCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }
    if (onAvatar != null) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(right: 12, left: 4),
          child: GestureDetector(
            onTap: onAvatar,
            child: CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.coral,
              backgroundImage:
                  (avatarUrl != null && avatarUrl!.isNotEmpty)
                      ? NetworkImage(avatarUrl!)
                      : null,
              child: (avatarUrl == null || avatarUrl!.isEmpty)
                  ? const Icon(Icons.person, size: 18, color: Colors.white)
                  : null,
            ),
          ),
        ),
      );
    }
    if (onLogout != null) {
      widgets.add(
        IconButton(
          icon: const Icon(Icons.logout, color: AppColors.ink),
          tooltip: 'Sign out',
          onPressed: onLogout,
        ),
      );
    }
    return widgets;
  }
}
