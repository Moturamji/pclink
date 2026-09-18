import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/universal/app_card_header.dart';
import '../../../../core/widgets/universal/status_badge.dart';

/// Card showing high-level security, encryption, and sync health in a clean, borderless container layout.
class SecurityStatusCard extends StatelessWidget {
  final bool isConnected;
  final bool isWindows;

  const SecurityStatusCard({
    super.key,
    required this.isConnected,
    required this.isWindows,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.cardBorder, width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: colors.isDark ? 0.2 : 0.04),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppCardHeader(
            icon: Icons.shield_outlined,
            iconColor: colors.primaryLight,
            title: 'Security & Privacy',
            subtitle: 'Private & Secure Connection',
            trailing: const StatusBadge(
              label: 'Protected',
              isActive: true,
              activeColor: AppColors.successLight,
            ),
          ),
          const SizedBox(height: 18),
          _buildSecurityRow(
            context: context,
            icon: Icons.vpn_key_rounded,
            title: 'Encryption',
            subtitle: 'End-to-end encrypted connection',
            color: colors.primaryLight,
          ),
          Divider(color: colors.cardBorder, height: 20, thickness: 0.8),
          _buildSecurityRow(
            context: context,
            icon: Icons.fingerprint_rounded,
            title: 'Device Access',
            subtitle: 'Only your authenticated devices can connect',
            color: colors.secondary,
          ),
          Divider(color: colors.cardBorder, height: 20, thickness: 0.8),
          _buildSecurityRow(
            context: context,
            icon: Icons.wifi_protected_setup_rounded,
            title: 'Direct Transfer',
            subtitle: 'Transfers stay on your local network whenever possible',
            color: colors.accentWarm,
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityRow({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    final colors = context.colors;
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Center(
            child: Icon(icon, size: 16, color: color),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: colors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
