import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../data/models/device_details.dart';

/// Top banner showing platform target, device model, and OS version.
class PlatformHeader extends StatelessWidget {
  final DeviceDetails details;

  const PlatformHeader({
    super.key,
    required this.details,
  });

  @override
  Widget build(BuildContext context) {
    final isWindows = details.isWindows;
    final isAndroid = details.isAndroid;

    final primaryGlow = isWindows
        ? const Color(0xFF1E3A8A).withValues(alpha: 0.8)
        : const Color(0xFF065F46).withValues(alpha: 0.8);
    final borderColor = isWindows
        ? const Color(0xFF3B82F6).withValues(alpha: 0.3)
        : const Color(0xFF10B981).withValues(alpha: 0.3);
    final iconBg = isWindows
        ? Colors.blue.withValues(alpha: 0.15)
        : Colors.green.withValues(alpha: 0.15);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primaryGlow, AppColors.surface],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: iconBg,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isWindows
                  ? Icons.laptop_windows
                  : (isAndroid ? Icons.phone_android : Icons.device_unknown),
              size: 36,
              color: isWindows
                  ? const Color(0xFF60A5FA)
                  : const Color(0xFF34D399),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      details.platform.toUpperCase(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                        color: isWindows
                            ? const Color(0xFF93C5FD)
                            : const Color(0xFF6EE7B7),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        AppStrings.targetPlatform,
                        style: TextStyle(
                            fontSize: 10, color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  details.deviceName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  details.osVersion,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
