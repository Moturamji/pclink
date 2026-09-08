import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/clipboard_helper.dart';
import '../../../../data/models/linked_device.dart';

/// Card showing cloud-synchronized devices (Android & Windows) linked to the user account.
class LinkedDevicesCard extends StatelessWidget {
  final Stream<List<LinkedDevice>> devicesStream;

  const LinkedDevicesCard({
    super.key,
    required this.devicesStream,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.cloud_sync, size: 18, color: AppColors.secondary),
                    SizedBox(width: 8),
                    Text(
                      'LINKED DEVICES (CLOUD SYNC)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: AppColors.secondary.withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.sync, size: 12, color: AppColors.secondary),
                      SizedBox(width: 4),
                      Text(
                        'Realtime DB',
                        style: TextStyle(fontSize: 10, color: AppColors.secondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            StreamBuilder<List<LinkedDevice>>(
              stream: devicesStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16.0),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }

                final devices = snapshot.data ?? [];

                if (devices.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, color: AppColors.textMuted, size: 20),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'No other devices connected yet. Open PCLink on your Windows PC or Android phone to link them.',
                            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: devices.length,
                  separatorBuilder: (context, index) =>
                      const Divider(color: AppColors.cardBorder, height: 20),
                  itemBuilder: (context, index) {
                    final device = devices[index];
                    return _buildDeviceRow(context, device);
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceRow(BuildContext context, LinkedDevice device) {
    final isWindows = device.isWindows;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: (isWindows ? Colors.blue : Colors.green).withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(
            isWindows ? Icons.laptop_windows : Icons.phone_android,
            size: 22,
            color: isWindows ? const Color(0xFF60A5FA) : const Color(0xFF34D399),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    device.deviceName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: (device.isOnline ? AppColors.success : AppColors.textMuted)
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      device.isOnline ? 'ONLINE' : 'SAVED',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: device.isOnline
                            ? AppColors.successLight
                            : AppColors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                device.osVersion,
                style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
              const SizedBox(height: 8),
              // Device ID row
              Row(
                children: [
                  const Text('ID: ', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                  Expanded(
                    child: SelectableText(
                      device.deviceId,
                      style: const TextStyle(
                        fontFamily: 'Courier',
                        fontSize: 12,
                        color: AppColors.primaryLight,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 14, color: AppColors.textMuted),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Copy Device ID',
                    onPressed: () => ClipboardHelper.copy(
                        context, device.deviceId, '${device.deviceName} Device ID'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // IP Address row
              Row(
                children: [
                  const Text('IP: ', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                  Expanded(
                    child: SelectableText(
                      device.ipAddress,
                      style: const TextStyle(
                        fontFamily: 'Courier',
                        fontSize: 12,
                        color: AppColors.secondary,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 14, color: AppColors.textMuted),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Copy IP',
                    onPressed: () => ClipboardHelper.copy(
                        context, device.ipAddress, '${device.deviceName} IP Address'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
