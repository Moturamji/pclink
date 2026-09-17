import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../data/services/screen_share_service.dart';

/// One-time consent dialog shown on the Windows desktop on first launch.
/// Asks the PC user whether they want to allow their linked phone to
/// request a view-only live screen session.
///
/// Microsoft Store compliant: explicit opt-in, never auto-enabled,
/// user retains ability to disable from the dashboard toggle at any time.
class ScreenShareConsentDialog extends StatelessWidget {
  const ScreenShareConsentDialog({super.key});

  /// Shows the consent dialog if consent has not yet been granted or denied.
  /// Returns `true` if permission was granted.
  static Future<bool> showIfNeeded(BuildContext context) async {
    final alreadyGranted = await ScreenShareService.isConsentGranted();
    if (alreadyGranted) return true;

    // Check if user previously dismissed (we store 'disabled' in that case)
    // Only show if file doesn't exist at all (first launch)
    final fileExists = await ScreenShareService.isConsentGranted();
    if (fileExists) return false; // Already answered "Not Now" or "disabled"

    if (!context.mounted) return false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ScreenShareConsentDialog(),
    );

    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Dialog(
      backgroundColor: colors.cardSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 60, vertical: 80),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Security Shield Icon
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: colors.primary.withValues(alpha: 0.25),
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  Icons.screen_share_rounded,
                  color: colors.primary,
                  size: 32,
                ),
              ),
              const SizedBox(height: 20),

              // Title
              Text(
                'Screen Sharing Permission',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: colors.textPrimary,
                  letterSpacing: -0.3,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),

              // Description
              Text(
                'PCLink can let your linked phone view this PC\'s screen '
                'in read-only mode. This is a security feature — you\'ll '
                'always know what\'s happening on your PC.',
                style: TextStyle(
                  fontSize: 14,
                  color: colors.textSecondary,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),

              // Security guarantees
              _buildGuarantee(
                colors,
                Icons.visibility_rounded,
                'View-only',
                'Your phone can see but never control this PC',
              ),
              const SizedBox(height: 8),
              _buildGuarantee(
                colors,
                Icons.memory_rounded,
                'In-memory only',
                'Screen frames are never saved to disk',
              ),
              const SizedBox(height: 8),
              _buildGuarantee(
                colors,
                Icons.toggle_off_rounded,
                'You control it',
                'Disable anytime from the dashboard toggle',
              ),
              const SizedBox(height: 28),

              // Allow Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await ScreenShareService.setConsentGranted(true);
                    if (context.mounted) Navigator.of(context).pop(true);
                  },
                  icon: const Icon(Icons.check_circle_outline_rounded),
                  label: const Text('Allow Screen Viewing'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Not Now Button
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () async {
                    await ScreenShareService.setConsentGranted(false);
                    if (context.mounted) Navigator.of(context).pop(false);
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: colors.textMuted,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text(
                    'Not Now',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),

              // Fine print
              const SizedBox(height: 8),
              Text(
                'You can change this later from the dashboard.',
                style: TextStyle(
                  fontSize: 11,
                  color: colors.textMuted,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGuarantee(
    AppThemeColors colors,
    IconData icon,
    String title,
    String subtitle,
  ) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppColors.success, size: 18),
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
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
