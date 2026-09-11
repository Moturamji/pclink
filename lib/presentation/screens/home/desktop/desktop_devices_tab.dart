import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../../data/models/device_details.dart';
import '../../../../data/services/database_service.dart';
import '../widgets/linked_devices_card.dart';
import '../widgets/security_status_card.dart';

class DesktopDevicesTab extends StatelessWidget {
  final DeviceDetails details;
  final User? user;
  final DatabaseService databaseService;

  const DesktopDevicesTab({
    super.key,
    required this.details,
    this.user,
    required this.databaseService,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (user != null) ...[
                LinkedDevicesCard(
                  devicesStream: databaseService.watchUserDevices(user!),
                ),
                const SizedBox(height: 20),
              ],
              SecurityStatusCard(
                isConnected: details.isConnected,
                isWindows: details.isWindows,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
