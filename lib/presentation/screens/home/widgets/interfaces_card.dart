import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/utils/clipboard_helper.dart';
import '../../../../data/models/device_details.dart';

/// Card listing all active network interfaces and their assigned IPs.
class InterfacesCard extends StatelessWidget {
  final List<NetworkAddressInfo> interfaces;

  const InterfacesCard({
    super.key,
    required this.interfaces,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.alt_route,
                    size: 18, color: AppColors.accentPurple),
                SizedBox(width: 8),
                Text(
                  AppStrings.activeInterfacesTitle,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: interfaces.length,
              separatorBuilder: (context, index) =>
                  const Divider(color: AppColors.cardBorder, height: 16),
              itemBuilder: (context, index) {
                final iface = interfaces[index];
                return Row(
                  children: [
                    Icon(
                      _getInterfaceIcon(iface.interfaceName),
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            iface.interfaceName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            iface.address,
                            style: const TextStyle(
                              fontFamily: 'Courier',
                              fontSize: 13,
                              color: AppColors.secondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy,
                          size: 16, color: AppColors.textSecondary),
                      tooltip: 'Copy IP',
                      onPressed: () => ClipboardHelper.copy(
                          context, iface.address, iface.interfaceName),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  IconData _getInterfaceIcon(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('wi-fi') || lower.contains('wlan')) {
      return Icons.wifi;
    }
    if (lower.contains('eth') || lower.contains('ethernet')) {
      return Icons.settings_ethernet;
    }
    return Icons.lan;
  }
}
