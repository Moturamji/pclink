import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../data/models/device_details.dart';
import '../../../../data/models/server_info.dart';
import '../../../../data/services/database_service.dart';
import '../widgets/platform_header.dart';
import '../widgets/server_control_card.dart';
import '../widgets/specs_card.dart';
import '../widgets/system_power_card.dart';

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
        StreamBuilder<ServerInfo?>(
          stream: user != null ? databaseService.watchUserServer(user!) : null,
          builder: (context, snapshot) {
            final server = snapshot.data ?? currentServerInfo;
            final colors = context.colors;
            return Container(
              decoration: BoxDecoration(
                color: colors.cardSurface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: colors.cardBorder, width: 0.8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: context.isDark ? 0.2 : 0.04),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  childrenPadding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.power_settings_new_rounded,
                      size: 18,
                      color: AppColors.primary,
                    ),
                  ),
                  title: Text(
                    'PC Power Options',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    'Sleep, Lock, Restart, Shutdown',
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.textMuted,
                    ),
                  ),
                  children: [
                    SystemPowerCard(
                      isWindows: details.isWindows,
                      currentServerInfo: server,
                      localDeviceId: details.deviceId,
                      isConnected: details.isConnected,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 14),
        SpecsCard(details: details),
      ],
    );
  }
}
