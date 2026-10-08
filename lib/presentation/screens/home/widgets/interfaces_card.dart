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

    return Container(
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.cardBorder, width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: colors.isDark ? 0.16 : 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20.0),
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
                  letterSpacing: 0.6,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: interfaces.length,
            separatorBuilder: (context, index) =>
                Divider(color: colors.cardBorder, height: 18, thickness: 0.8),
            itemBuilder: (context, index) {
              final iface = interfaces[index];
              return Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colors.surfaceSubtle,
                      borderRadius: BorderRadius.circular(10),
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
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
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
