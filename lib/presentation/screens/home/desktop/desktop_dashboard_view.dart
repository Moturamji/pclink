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
import '../../../../data/models/user_deletion_status.dart';
import '../widgets/account_deletion_dialogs.dart';

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
  final UserDeletionStatus? deletionStatus;
  final VoidCallback? onDeleteAccount;
  final VoidCallback? onUndeleteAccount;

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
    this.deletionStatus,
    this.onDeleteAccount,
    this.onUndeleteAccount,
  });

  @override
  State<DesktopDashboardView> createState() => _DesktopDashboardViewState();
}

class _DesktopDashboardViewState extends State<DesktopDashboardView> {
  DesktopNavTab _currentTab = DesktopNavTab.overview;

  String _getTabTitle(DesktopNavTab tab) {
    switch (tab) {
      case DesktopNavTab.overview:
        return 'Overview';
      case DesktopNavTab.fileStudio:
        return 'Files';
      case DesktopNavTab.clipboard:
        return 'Clipboard';
      case DesktopNavTab.devices:
        return 'Connected Devices';
    }
  }

  String _getTabSubtitle(DesktopNavTab tab) {
    switch (tab) {
      case DesktopNavTab.overview:
        return 'Monitor your PC status, connection, and linked phone';
      case DesktopNavTab.fileStudio:
        return 'Send and receive files directly with your phone';
      case DesktopNavTab.clipboard:
        return 'Seamless real-time clipboard sync between PC and phone';
      case DesktopNavTab.devices:
        return 'Manage and view your linked devices';
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
            deletionStatus: widget.deletionStatus,
            onDeleteAccount: widget.onDeleteAccount,
            onUndeleteAccount: widget.onUndeleteAccount,
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
                if (widget.deletionStatus?.isDeleteRequested == true)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 16, 28, 0),
                    child: AccountDeletionBanner(
                      status: widget.deletionStatus!,
                      onUndelete: widget.onUndeleteAccount ?? () {},
                    ),
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
          serverService: widget.serverService,
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
