import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../../data/models/device_details.dart';
import '../../../../data/services/database_service.dart';
import '../widgets/linked_devices_card.dart';
import '../widgets/security_status_card.dart';

class MobileDevicesTab extends StatelessWidget {
  final DeviceDetails details;
  final User? user;
  final DatabaseService databaseService;

  const MobileDevicesTab({
    super.key,
    required this.details,
    this.user,
    required this.databaseService,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
      children: [
        if (user != null) ...[
          LinkedDevicesCard(
            devicesStream: databaseService.watchUserDevices(user!),
          ),
          const SizedBox(height: 14),
        ],
        SecurityStatusCard(
          isConnected: details.isConnected,
          isWindows: details.isWindows,
        ),
      ],
    );
  }
}
