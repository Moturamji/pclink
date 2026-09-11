import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/widgets/universal/app_logo.dart';
import '../../../../core/widgets/universal/hoverable.dart';
import '../../../../core/widgets/universal/theme_toggle_button.dart';

enum DesktopNavTab {
  overview,
  fileStudio,
  clipboard,
  devices,
}

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
        border: Border(
          right: BorderSide(
            color: colors.cardBorder,
            width: 1,
          ),
        ),
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
                      ShaderMask(
                        shaderCallback: (bounds) => LinearGradient(
                          colors: [
                            colors.textPrimary,
                            colors.primaryLight,
                          ],
                        ).createShader(bounds),
                        child: const Text(
                          AppStrings.appName,
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                            fontSize: 18,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isServerLive
                                  ? AppColors.success
                                  : colors.textMuted,
                              boxShadow: isServerLive
                                  ? [
                                      BoxShadow(
                                        color: AppColors.success
                                            .withValues(alpha: 0.5),
                                        blurRadius: 6,
                                        spreadRadius: 1,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              isServerLive ? 'Live & Connected' : 'Standby Mode',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colors.cardBorder),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            colors.primary,
                            colors.accentPurple,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          userEmail!.isNotEmpty
                              ? userEmail![0].toUpperCase()
                              : 'U',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
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
                              fontWeight: FontWeight.w700,
                              color: colors.textPrimary,
                            ),
                          ),
                          Text(
                            'Authenticated User',
                            style: TextStyle(
                              fontSize: 10,
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

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Text(
              'WORKSPACES',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: Color(0xFF64748B),
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
                  accentColor: colors.primary,
                ),
                _buildNavItem(
                  context,
                  tab: DesktopNavTab.fileStudio,
                  icon: Icons.folder_open_outlined,
                  activeIcon: Icons.folder_rounded,
                  label: 'File Transfer Studio',
                  accentColor: colors.accentPurple,
                ),
                _buildNavItem(
                  context,
                  tab: DesktopNavTab.clipboard,
                  icon: Icons.content_paste_outlined,
                  activeIcon: Icons.content_paste_rounded,
                  label: 'Clipboard Stream',
                  accentColor: colors.secondary,
                ),
                _buildNavItem(
                  context,
                  tab: DesktopNavTab.devices,
                  icon: Icons.devices_outlined,
                  activeIcon: Icons.devices_rounded,
                  label: 'Devices & Security',
                  accentColor: colors.accentWarm,
                ),
              ],
            ),
          ),

          // Bottom Action Bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surface.withValues(alpha: 0.5),
              border: Border(
                top: BorderSide(color: colors.cardBorder),
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
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: colors.cardSurface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: colors.cardBorder),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (isRefreshing)
                                const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              else
                                Icon(
                                  Icons.refresh_rounded,
                                  size: 16,
                                  color: colors.textSecondary,
                                ),
                              const SizedBox(width: 6),
                              Text(
                                'Sync',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: colors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Hoverable(
                  onTap: onSignOut,
                  hoverBorderColor: AppColors.error,
                  child: Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.error.withValues(alpha: 0.25),
                      ),
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
      padding: const EdgeInsets.only(bottom: 6),
      child: Hoverable(
        onTap: () => onTabChanged(tab),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? accentColor.withValues(alpha: colors.isDark ? 0.16 : 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? accentColor.withValues(alpha: colors.isDark ? 0.4 : 0.3)
                  : Colors.transparent,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isSelected ? activeIcon : icon,
                size: 20,
                color: isSelected ? accentColor : colors.textMuted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? colors.textPrimary : colors.textSecondary,
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
        ),
      ),
    );
  }
}
