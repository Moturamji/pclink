import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../data/models/device_details.dart';
import '../../../../data/models/server_info.dart';
import '../../../../data/services/database_service.dart';
import '../../../../data/services/file_share_service.dart';
import '../../../../data/services/server_service.dart';
import '../../../../features/clipboard/services/clipboard_service.dart';
import 'desktop_clipboard_tab.dart';
import 'desktop_command_bar.dart';
import 'desktop_devices_tab.dart';
import 'desktop_files_tab.dart';
import 'desktop_overview_tab.dart';
import 'desktop_sidebar.dart';

/// Complete Desktop Dashboard Shell with dedicated sidebar, command bar,
/// and smooth multi-workbench tab transitions.
class DesktopDashboardView extends StatefulWidget {
  final DeviceDetails details;
  final User? user;
  final ServerInfo? currentServerInfo;
  final DatabaseService databaseService;
  final ServerService serverService;
  final ClipboardService clipboardService;
  final FileShareService fileShareService;
  final bool isRefreshing;
  final VoidCallback onRefresh;
  final VoidCallback onSignOut;
  final VoidCallback onToggleServer;
  final ValueChanged<bool> onConnectionStateChanged;
  final VoidCallback onDisconnectRequested;

  const DesktopDashboardView({
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
  State<DesktopDashboardView> createState() => _DesktopDashboardViewState();
}

class _DesktopDashboardViewState extends State<DesktopDashboardView> {
  DesktopNavTab _currentTab = DesktopNavTab.overview;

  String _getTabTitle(DesktopNavTab tab) {
    switch (tab) {
      case DesktopNavTab.overview:
        return 'Dashboard & Server Hub';
      case DesktopNavTab.fileStudio:
        return 'File Transfer Studio';
      case DesktopNavTab.clipboard:
        return 'Realtime Clipboard Stream';
      case DesktopNavTab.devices:
        return 'Linked Devices & Security Hub';
    }
  }

  String _getTabSubtitle(DesktopNavTab tab) {
    switch (tab) {
      case DesktopNavTab.overview:
        return 'Manage local server endpoints, network interfaces, and system health.';
      case DesktopNavTab.fileStudio:
        return 'High-speed encrypted bidirectional file transfer with native progress tracking.';
      case DesktopNavTab.clipboard:
        return 'Seamless real-time clipboard sync between Windows and Android devices.';
      case DesktopNavTab.devices:
        return 'Inspect authenticated peer devices, token authorizations, and encryption.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isLive = widget.currentServerInfo?.isLive == true;

    return Scaffold(
      backgroundColor: colors.background,
      body: Row(
        children: [
          // Desktop Navigation Rail
          DesktopSidebar(
            currentTab: _currentTab,
            onTabChanged: (tab) => setState(() => _currentTab = tab),
            userEmail: widget.user?.email,
            isServerLive: isLive,
            isRefreshing: widget.isRefreshing,
            onRefresh: widget.onRefresh,
            onSignOut: widget.onSignOut,
          ),

          // Main Desktop Content Area
          Expanded(
            child: Column(
              children: [
                DesktopCommandBar(
                  title: _getTabTitle(_currentTab),
                  subtitle: _getTabSubtitle(_currentTab),
                  serverInfo: widget.currentServerInfo,
                  isWindows: widget.details.isWindows,
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0.015, 0),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: KeyedSubtree(
                      key: ValueKey(_currentTab),
                      child: _buildCurrentTabView(),
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

  Widget _buildCurrentTabView() {
    switch (_currentTab) {
      case DesktopNavTab.overview:
        return DesktopOverviewTab(
          details: widget.details,
          user: widget.user,
          currentServerInfo: widget.currentServerInfo,
          databaseService: widget.databaseService,
          onToggleServer: widget.onToggleServer,
          onConnectionStateChanged: widget.onConnectionStateChanged,
          onDisconnectRequested: widget.onDisconnectRequested,
        );
      case DesktopNavTab.fileStudio:
        return DesktopFilesTab(
          isWindows: widget.details.isWindows,
          serverService:
              widget.details.isWindows ? widget.serverService : null,
          fileShareService:
              widget.details.isWindows ? null : widget.fileShareService,
        );
      case DesktopNavTab.clipboard:
        return DesktopClipboardTab(
          isWindows: widget.details.isWindows,
          user: widget.user,
          databaseService: widget.databaseService,
          clipboardService: widget.clipboardService,
        );
      case DesktopNavTab.devices:
        return DesktopDevicesTab(
          details: widget.details,
          user: widget.user,
          databaseService: widget.databaseService,
        );
    }
  }
}
