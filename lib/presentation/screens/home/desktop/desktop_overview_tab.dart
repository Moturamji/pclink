import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../../data/models/device_details.dart';
import '../../../../data/models/server_info.dart';
import '../../../../data/services/database_service.dart';
import '../widgets/platform_header.dart';
import '../widgets/security_status_card.dart';
import '../widgets/server_control_card.dart';
import '../widgets/specs_card.dart';

class DesktopOverviewTab extends StatelessWidget {
  final DeviceDetails details;
  final User? user;
  final ServerInfo? currentServerInfo;
  final DatabaseService databaseService;
  final VoidCallback onToggleServer;
  final ValueChanged<bool> onConnectionStateChanged;
  final VoidCallback onDisconnectRequested;

  const DesktopOverviewTab({
    super.key,
    required this.details,
    this.user,
    this.currentServerInfo,
    required this.databaseService,
    required this.onToggleServer,
    required this.onConnectionStateChanged,
    required this.onDisconnectRequested,
  });

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
                      isWindows: details.isWindows,
                      currentServerInfo: currentServerInfo,
                      serverStream: user != null
                          ? databaseService.watchUserServer(user!)
                          : null,
                      onToggleServer: onToggleServer,
                      localDeviceId: details.deviceId,
                      user: user,
                      databaseService: databaseService,
                      onConnectionStateChanged: onConnectionStateChanged,
                      onDisconnectRequested: onDisconnectRequested,
                    ),
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
                    PlatformHeader(details: details),
                    const SizedBox(height: 16),
                    SecurityStatusCard(
                      isConnected: details.isConnected,
                      isWindows: details.isWindows,
                    ),
                    const SizedBox(height: 16),
                    SpecsCard(details: details),
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
