import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/widgets/universal/app_logo.dart';
import '../../../../core/widgets/universal/hoverable.dart';
import '../../../../core/widgets/universal/theme_toggle_button.dart';

import '../../../../data/models/user_deletion_status.dart';

enum DesktopNavTab { overview, fileStudio, clipboard, devices }

/// Polished Desktop Sidebar Navigation Rail with tactile micro-interactions,
/// spring indicators, and borderless surface elevation.
class DesktopSidebar extends StatelessWidget {
  final DesktopNavTab currentTab;
  final ValueChanged<DesktopNavTab> onTabChanged;
  final String? userEmail;
  final bool isServerLive;
  final bool isRefreshing;
  final VoidCallback onRefresh;
  final VoidCallback onSignOut;
  final UserDeletionStatus? deletionStatus;
  final VoidCallback? onDeleteAccount;
  final VoidCallback? onUndeleteAccount;

  const DesktopSidebar({
    super.key,
    required this.currentTab,
    required this.onTabChanged,
    this.userEmail,
    required this.isServerLive,
    required this.isRefreshing,
    required this.onRefresh,
    required this.onSignOut,
    this.deletionStatus,
    this.onDeleteAccount,
    this.onUndeleteAccount,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      width: 264,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(right: BorderSide(color: colors.cardBorder, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // App Brand & Logo Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            child: Row(
              children: [
                const AppLogo(
                  size: 38,
                  borderRadius: 12,
                  showGlow: false,
                  isAnimated: false,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        AppStrings.appName,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                          fontSize: 18,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isServerLive
                                  ? colors.success
                                  : colors.textMuted,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              isServerLive
                                  ? 'Live & Connected'
                                  : 'Standby Mode',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: isServerLive
                                    ? colors.success
                                    : colors.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // User Profile Pill (if logged in)
          if (userEmail != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: colors.cardSurface,
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  border: Border.all(color: colors.cardBorder),
                  boxShadow: colors.cardShadow,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: colors.tint(colors.primaryLight),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          userEmail!.isNotEmpty
                              ? userEmail![0].toUpperCase()
                              : 'U',
                          style: TextStyle(
                            color: colors.primaryLight,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            userEmail!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: colors.textPrimary,
                            ),
                          ),
                          Text(
                            'Signed in',
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _buildAccountMenu(context),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Text(
              'WORKSPACES',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.1,
                color: colors.textMuted,
              ),
            ),
          ),

          // Navigation Links
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              children: [
                _buildNavItem(
                  context,
                  tab: DesktopNavTab.overview,
                  icon: Icons.dashboard_outlined,
                  activeIcon: Icons.dashboard_rounded,
                  label: 'Dashboard & Server',
                  accentColor: colors.primaryLight,
                ),
                _buildNavItem(
                  context,
                  tab: DesktopNavTab.fileStudio,
                  icon: Icons.folder_open_outlined,
                  activeIcon: Icons.folder_rounded,
                  label: 'File Transfer Studio',
                  accentColor: colors.primaryLight,
                ),
                _buildNavItem(
                  context,
                  tab: DesktopNavTab.clipboard,
                  icon: Icons.content_paste_outlined,
                  activeIcon: Icons.content_paste_rounded,
                  label: 'Clipboard Stream',
                  accentColor: colors.primaryLight,
                ),
                _buildNavItem(
                  context,
                  tab: DesktopNavTab.devices,
                  icon: Icons.devices_outlined,
                  activeIcon: Icons.devices_rounded,
                  label: 'Devices & Security',
                  accentColor: colors.primaryLight,
                ),
              ],
            ),
          ),

          // Bottom Action Bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: colors.cardBorder, width: 1),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const ThemeToggleButton(),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Hoverable(
                        onTap: isRefreshing ? null : onRefresh,
                        borderRadius: BorderRadius.circular(10),
                        builder: (context, isHovered) {
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            curve: Curves.easeOutCubic,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: isHovered
                                  ? colors.surfaceSubtle
                                  : colors.cardSurface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isHovered
                                    ? colors.primary.withValues(alpha: 0.3)
                                    : colors.cardBorder,
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (isRefreshing)
                                  const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                else
                                  Icon(
                                    Icons.refresh_rounded,
                                    size: 16,
                                    color: isHovered
                                        ? colors.primaryLight
                                        : colors.textSecondary,
                                  ),
                                const SizedBox(width: 6),
                                Text(
                                  'Sync',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: isHovered
                                        ? colors.textPrimary
                                        : colors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
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

  Widget _buildAccountMenu(BuildContext context) {
    final colors = context.colors;
    final pending = deletionStatus?.isDeleteRequested == true;

    PopupMenuItem<String> item(String value, IconData icon, String label, Color color) {
      return PopupMenuItem<String>(
        value: value,
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 12),
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: color)),
          ],
        ),
      );
    }

    return PopupMenuButton<String>(
      tooltip: 'Account',
      padding: EdgeInsets.zero,
      icon: Icon(Icons.more_horiz_rounded, size: 18, color: colors.textMuted),
      onSelected: (value) {
        switch (value) {
          case 'undelete':
            onUndeleteAccount?.call();
          case 'delete':
            onDeleteAccount?.call();
          case 'signout':
            onSignOut();
        }
      },
      itemBuilder: (context) => [
        if (pending)
          item('undelete', Icons.restore_rounded, 'Undelete account', colors.success)
        else
          item('delete', Icons.delete_outline_rounded, 'Delete account', colors.textSecondary),
        item('signout', Icons.logout_rounded, AppStrings.signOut, colors.error),
      ],
    );
  }

  Widget _buildNavItem(
    BuildContext context, {
    required DesktopNavTab tab,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required Color accentColor,
  }) {
    final isSelected = currentTab == tab;
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Hoverable(
        onTap: () => onTabChanged(tab),
        borderRadius: BorderRadius.circular(AppRadii.md),
        builder: (context, isHovered) {
          final effectiveBgColor = isSelected
              ? colors.cardSurface
              : (isHovered
                    ? colors.cardSurface.withValues(alpha: 0.6)
                    : Colors.transparent);

          return AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: effectiveBgColor,
              borderRadius: BorderRadius.circular(AppRadii.md),
              border: Border.all(
                color: isSelected ? colors.cardBorder : Colors.transparent,
              ),
              boxShadow: isSelected ? colors.cardShadow : null,
            ),
            child: Row(
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  child: Icon(
                    isSelected ? activeIcon : icon,
                    key: ValueKey<bool>(isSelected),
                    size: 19,
                    color: isSelected
                        ? accentColor
                        : (isHovered ? colors.textPrimary : colors.textMuted),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : (isHovered ? FontWeight.w600 : FontWeight.w500),
                      color: isSelected
                          ? colors.textPrimary
                          : (isHovered
                                ? colors.textPrimary
                                : colors.textSecondary),
                    ),
                  ),
                ),
                if (isSelected)
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accentColor,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
