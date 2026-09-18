import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/widgets/universal/app_logo.dart';
import '../../../../core/widgets/universal/bounceable.dart';
import '../../../../core/widgets/universal/hoverable.dart';
import '../../../../core/widgets/universal/theme_toggle_button.dart';

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

  const DesktopSidebar({
    super.key,
    required this.currentTab,
    required this.onTabChanged,
    this.userEmail,
    required this.isServerLive,
    required this.isRefreshing,
    required this.onRefresh,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: colors.cardSurface,
        border: Border(right: BorderSide(color: colors.cardBorder, width: 0.8)),
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
                  showGlow: true,
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
                                  ? AppColors.success
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
                                    ? AppColors.success
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
                  color: colors.surfaceSubtle,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(8),
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
                            'Authenticated User',
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
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
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
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
                  label: 'Overview',
                  accentColor: colors.primary,
                ),
                _buildNavItem(
                  context,
                  tab: DesktopNavTab.fileStudio,
                  icon: Icons.folder_open_outlined,
                  activeIcon: Icons.folder_rounded,
                  label: 'Files',
                  accentColor: colors.accentPurple,
                ),
                _buildNavItem(
                  context,
                  tab: DesktopNavTab.clipboard,
                  icon: Icons.content_paste_outlined,
                  activeIcon: Icons.content_paste_rounded,
                  label: 'Clipboard',
                  accentColor: colors.secondary,
                ),
                _buildNavItem(
                  context,
                  tab: DesktopNavTab.devices,
                  icon: Icons.devices_outlined,
                  activeIcon: Icons.devices_rounded,
                  label: 'Devices',
                  accentColor: colors.accentWarm,
                ),
              ],
            ),
          ),

          // Bottom Action Bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surfaceSubtle.withValues(alpha: 0.5),
              border: Border(
                top: BorderSide(color: colors.cardBorder, width: 0.8),
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
                                width: 0.8,
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
                const SizedBox(height: 10),
                Bounceable(
                  onTap: onSignOut,
                  scaleFactor: 0.98,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.logout_rounded,
                          size: 15,
                          color: AppColors.error,
                        ),
                        SizedBox(width: 8),
                        Text(
                          AppStrings.signOut,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.error,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
        borderRadius: BorderRadius.circular(10),
        builder: (context, isHovered) {
          final effectiveBgColor = isSelected
              ? (isHovered
                    ? accentColor.withValues(alpha: 0.16)
                    : accentColor.withValues(alpha: 0.12))
              : (isHovered
                    ? colors.surfaceSubtle
                    : colors.surfaceSubtle.withValues(alpha: 0.0));

          final effectiveBorderColor = isSelected
              ? accentColor.withValues(alpha: isHovered ? 0.35 : 0.25)
              : accentColor.withValues(alpha: 0.0);

          return AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: effectiveBgColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: effectiveBorderColor, width: 0.8),
            ),
            child: Row(
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  child: Icon(
                    isSelected ? activeIcon : icon,
                    key: ValueKey<bool>(isSelected),
                    size: 18,
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
