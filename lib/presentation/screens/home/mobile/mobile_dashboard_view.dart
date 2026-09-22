import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/widgets/universal/animated_tab_bar.dart';
import '../../../../core/widgets/universal/app_logo.dart';
import '../../../../core/widgets/universal/bounceable.dart';
import '../../../../core/widgets/universal/theme_toggle_button.dart';
import '../../../../data/models/device_details.dart';
import '../../../../data/models/server_info.dart';
import '../../../../data/services/database_service.dart';
import '../../../../data/services/file_share_service.dart';
import '../../../../data/services/server_service.dart';
import '../../../../features/clipboard/services/clipboard_service.dart';
import 'mobile_clipboard_tab.dart';
import 'mobile_connect_tab.dart';
import 'mobile_files_tab.dart';
import 'mobile_live_share_tab.dart';

/// Complete Mobile Dashboard Shell with hero top bar, floating squircle
/// bottom tab bar, and spring micro-interactions.
class MobileDashboardView extends StatefulWidget {
  final DeviceDetails details;
  final User? user;
  final ServerInfo? currentServerInfo;
  final DatabaseService databaseService;
  final ServerService serverService;
  final ClipboardService clipboardService;
  final FileShareService fileShareService;
  final bool isRefreshing;
  final Future<void> Function() onRefresh;
  final VoidCallback onSignOut;
  final VoidCallback onToggleServer;
  final ValueChanged<bool> onConnectionStateChanged;
  final VoidCallback onDisconnectRequested;

  const MobileDashboardView({
    super.key,
    required this.details,
    this.user,
    this.currentServerInfo,
    required this.databaseService,
    required this.serverService,
    required this.clipboardService,
    required this.fileShareService,
    required this.isRefreshing,
    required this.onRefresh,
    required this.onSignOut,
    required this.onToggleServer,
    required this.onConnectionStateChanged,
    required this.onDisconnectRequested,
  });

  @override
  State<MobileDashboardView> createState() => _MobileDashboardViewState();
}

class _MobileDashboardViewState extends State<MobileDashboardView> {
  int _currentTabIndex = 0;

  static const List<TabItemData> _tabs = [
    TabItemData(
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      label: 'Home',
      activeColor: AppColors.primary,
    ),
    TabItemData(
      icon: Icons.folder_outlined,
      activeIcon: Icons.folder_rounded,
      label: 'Files',
      activeColor: AppColors.accentPurple,
    ),
    TabItemData(
      icon: Icons.content_paste_outlined,
      activeIcon: Icons.content_paste_rounded,
      label: 'Clipboard',
      activeColor: AppColors.secondary,
    ),
    TabItemData(
      icon: Icons.desktop_windows_outlined,
      activeIcon: Icons.desktop_windows_rounded,
      label: 'Screen Mirror',
      activeColor: AppColors.success,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Row(
          children: [
            const AppLogo(
              size: 32,
              borderRadius: 10,
              showGlow: false,
              isAnimated: false,
            ),
            const SizedBox(width: 10),
            Text(
              AppStrings.appName,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                fontSize: 18,
                color: colors.textPrimary,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          const ThemeToggleButton(),
          const SizedBox(width: 4),
          Bounceable(
            onTap: widget.isRefreshing ? null : widget.onRefresh,
            child: IconButton(
              icon: widget.isRefreshing
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.primary,
                      ),
                    )
                  : Icon(Icons.refresh_rounded, color: colors.textSecondary),
              tooltip: 'Refresh',
              onPressed: widget.isRefreshing ? null : widget.onRefresh,
            ),
          ),
          Bounceable(
            onTap: widget.onSignOut,
            child: IconButton(
              icon: const Icon(Icons.logout_rounded, color: AppColors.error),
              tooltip: AppStrings.signOut,
              onPressed: widget.onSignOut,
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Stack(
        children: [
          // Content View with Pull-To-Refresh
          Positioned.fill(
            child: RefreshIndicator(
              onRefresh: widget.onRefresh,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.02),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: KeyedSubtree(
                  key: ValueKey(_currentTabIndex),
                  child: _buildTabBody(),
                ),
              ),
            ),
          ),

          // Floating Bottom Navigation Bar
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedTabBar(
              selectedIndex: _currentTabIndex,
              onTabSelected: (index) =>
                  setState(() => _currentTabIndex = index),
              items: _tabs,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBody() {
    switch (_currentTabIndex) {
      case 0:
        return MobileConnectTab(
          details: widget.details,
          user: widget.user,
          currentServerInfo: widget.currentServerInfo,
          databaseService: widget.databaseService,
          onToggleServer: widget.onToggleServer,
          onConnectionStateChanged: widget.onConnectionStateChanged,
          onDisconnectRequested: widget.onDisconnectRequested,
        );
      case 1:
        return MobileFilesTab(
          isWindows: widget.details.isWindows,
          serverService:
              widget.details.isWindows ? widget.serverService : null,
          fileShareService:
              widget.details.isWindows ? null : widget.fileShareService,
        );
      case 2:
        return MobileClipboardTab(
          isWindows: widget.details.isWindows,
          user: widget.user,
          databaseService: widget.databaseService,
          clipboardService: widget.clipboardService,
        );
      case 3:
      default:
        return MobileLiveShareTab(
          fileShareService: widget.fileShareService,
          currentServerInfo: widget.currentServerInfo,
          localDeviceId: widget.details.deviceId,
          isConnected: widget.details.isConnected,
        );
    }
  }
}
