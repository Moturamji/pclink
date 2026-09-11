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
    final colors = context.colors;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colors.secondary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.alt_route_rounded,
                    size: 18,
                    color: colors.secondary,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  AppStrings.activeInterfacesTitle,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: interfaces.length,
              separatorBuilder: (context, index) =>
                  Divider(color: colors.cardBorder, height: 20),
              itemBuilder: (context, index) {
                final iface = interfaces[index];
                return Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: colors.cardBorder),
                      ),
                      child: Icon(
                        _getInterfaceIcon(iface.interfaceName),
                        size: 18,
                        color: colors.secondary,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            iface.interfaceName,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: colors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            iface.address,
                            style: TextStyle(
                              fontFamily: 'Courier',
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: colors.secondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.copy_rounded,
                        size: 15,
                        color: colors.textMuted,
                      ),
                      tooltip: 'Copy IP',
                      onPressed: () => ClipboardHelper.copy(
                        context,
                        iface.address,
                        iface.interfaceName,
                      ),
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
      return Icons.wifi_rounded;
    }
    if (lower.contains('eth') || lower.contains('ethernet')) {
      return Icons.settings_ethernet_rounded;
    }
    return Icons.lan_rounded;
  }
}
