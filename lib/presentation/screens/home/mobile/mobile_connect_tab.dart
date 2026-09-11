import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../../data/models/device_details.dart';
import '../../../../data/models/server_info.dart';
import '../../../../data/services/database_service.dart';
import '../widgets/platform_header.dart';
import '../widgets/server_control_card.dart';
import '../widgets/specs_card.dart';

class MobileConnectTab extends StatelessWidget {
  final DeviceDetails details;
  final User? user;
  final ServerInfo? currentServerInfo;
  final DatabaseService databaseService;
  final VoidCallback onToggleServer;
  final ValueChanged<bool> onConnectionStateChanged;
  final VoidCallback onDisconnectRequested;

  const MobileConnectTab({
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
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
      children: [
        PlatformHeader(details: details),
        const SizedBox(height: 14),
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
        const SizedBox(height: 14),
        SpecsCard(details: details),
      ],
    );
  }
}
