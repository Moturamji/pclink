import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../../data/models/device_details.dart';
import '../../../../data/models/server_info.dart';
import '../../../../data/services/database_service.dart';
import '../../../../data/services/screen_share_service.dart';
import '../../../../data/services/server_service.dart';
import '../widgets/platform_header.dart';
import '../widgets/screen_share_consent_dialog.dart';
import '../widgets/screen_share_status_card.dart';
import '../widgets/security_status_card.dart';
import '../widgets/server_control_card.dart';
import '../widgets/specs_card.dart';

class DesktopOverviewTab extends StatefulWidget {
  final DeviceDetails details;
  final User? user;
  final ServerInfo? currentServerInfo;
  final DatabaseService databaseService;
  final ServerService serverService;
  final VoidCallback onToggleServer;
  final ValueChanged<bool> onConnectionStateChanged;
  final VoidCallback onDisconnectRequested;

  const DesktopOverviewTab({
    super.key,
    required this.details,
    this.user,
    this.currentServerInfo,
    required this.databaseService,
    required this.serverService,
    required this.onToggleServer,
    required this.onConnectionStateChanged,
    required this.onDisconnectRequested,
  });

  @override
  State<DesktopOverviewTab> createState() => _DesktopOverviewTabState();
}

class _DesktopOverviewTabState extends State<DesktopOverviewTab> {
  bool _consentChecked = false;

  @override
  void initState() {
    super.initState();
    // Show the screen share consent dialog once on first render (Windows only)
    if (!kIsWeb && Platform.isWindows) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkAndShowConsent();
      });
    }
  }

  Future<void> _checkAndShowConsent() async {
    if (_consentChecked) return;
    _consentChecked = true;

    final alreadyAnswered = await ScreenShareService.isConsentGranted();
    if (alreadyAnswered) return;

    // Check if the preference file exists at all (user may have declined before)
    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.isNotEmpty) {
      final prefFile = File('$appData\\pclink\\pclink_screen_share_consent.txt');
      if (await prefFile.exists()) return; // User already answered (declined)
    }

    if (!mounted) return;
    await ScreenShareConsentDialog.showIfNeeded(context);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left Workbench Column: Server Control & Main Connectivity
              Expanded(
                flex: 6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ServerControlCard(
                      isWindows: widget.details.isWindows,
                      currentServerInfo: widget.currentServerInfo,
                      serverStream: widget.user != null
                          ? widget.databaseService
                              .watchUserServer(widget.user!)
                          : null,
                      onToggleServer: widget.onToggleServer,
                      localDeviceId: widget.details.deviceId,
                      user: widget.user,
                      databaseService: widget.databaseService,
                      onConnectionStateChanged:
                          widget.onConnectionStateChanged,
                      onDisconnectRequested: widget.onDisconnectRequested,
                    ),
                    const SizedBox(height: 16),
                    ScreenShareStatusCard(
                        service:
                            widget.serverService.screenShareService),
                  ],
                ),
              ),

              const SizedBox(width: 24),

              // Right Workbench Column: Platform Details, Specs & Security Audit
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PlatformHeader(details: widget.details),
                    const SizedBox(height: 16),
                    SecurityStatusCard(
                      isConnected: widget.details.isConnected,
                      isWindows: widget.details.isWindows,
                    ),
                    const SizedBox(height: 16),
                    SpecsCard(details: widget.details),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
