import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

/// Card showing high-level security, encryption, and sync health without exposing confidential IPs or hardware GUIDs.
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.shield_outlined,
                    size: 18,
                    color: AppColors.primaryLight,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'SECURITY & DATA PRIVACY',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.success.withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_rounded, size: 10, color: AppColors.successLight),
                      SizedBox(width: 4),
                      Text(
                        'E2EE Protected',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.successLight,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Column(
                children: [
                  _buildSecurityRow(
                    icon: Icons.vpn_key_rounded,
                    title: 'Transport Encryption',
                    subtitle: 'TLS 1.3 / HTTPS Cloud Relay',
                    color: AppColors.primaryLight,
                  ),
                  const Divider(color: AppColors.cardBorder, height: 18),
                  _buildSecurityRow(
                    icon: Icons.fingerprint_rounded,
                    title: 'Device Authorization',
                    subtitle: 'Paired Hardware Token Verification',
                    color: AppColors.secondary,
                  ),
                  const Divider(color: AppColors.cardBorder, height: 18),
                  _buildSecurityRow(
                    icon: Icons.wifi_protected_setup_rounded,
                    title: 'Network Privacy',
                    subtitle: 'Confidential IPs & Ports Masked',
                    color: AppColors.successLight,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecurityRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
