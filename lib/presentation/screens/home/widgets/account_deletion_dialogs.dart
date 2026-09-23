import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../data/models/user_deletion_status.dart';

/// Confirmation dialog for scheduling account deletion with a 15-day grace period.
class AccountDeletionDialog extends StatelessWidget {
  const AccountDeletionDialog({super.key});

  /// Shows the dialog and returns `true` if the user confirmed scheduling deletion.
  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const AccountDeletionDialog(),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return AlertDialog(
      backgroundColor: colors.cardSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.error.withValues(alpha: 0.25),
                width: 1,
              ),
            ),
            child: const Icon(
              Icons.warning_amber_rounded,
              color: AppColors.error,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'Delete Account',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your account will enter a 15-day waiting period before actual deletion.',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.surfaceSubtle,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: colors.cardBorder,
                  width: 0.8,
                ),
              ),
              child: Column(
                children: [
                  _buildBullet(
                    colors,
                    icon: Icons.restore_rounded,
                    iconColor: AppColors.primary,
                    text:
                        'Within 15 days, you can select "Undelete Account" at any time from your PC or Phone to keep your account.',
                  ),
                  const SizedBox(height: 10),
                  _buildBullet(
                    colors,
                    icon: Icons.delete_forever_rounded,
                    iconColor: AppColors.error,
                    text:
                        'If you do not undelete within 15 days, your account and all associated data will be permanently deleted from the server.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            'Keep Account',
            style: TextStyle(
              color: colors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.error,
            foregroundColor: Colors.white,
            elevation: 1,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text(
            'Schedule Deletion (15 Days)',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  Widget _buildBullet(
    dynamic colors, {
    required IconData icon,
    required Color iconColor,
    required String text,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: iconColor),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

/// Confirmation dialog for undeleting / restoring a scheduled-for-deletion account.
class AccountUndeleteDialog extends StatelessWidget {
  const AccountUndeleteDialog({super.key});

  /// Shows the dialog and returns `true` if the user confirmed restoring their account.
  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const AccountUndeleteDialog(),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return AlertDialog(
      backgroundColor: colors.cardSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.success.withValues(alpha: 0.25),
                width: 1,
              ),
            ),
            child: const Icon(
              Icons.restore_rounded,
              color: AppColors.success,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'Undelete Account',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Text(
          'Would you like to cancel the scheduled deletion? Your account will remain active and fully functional across both your PC and Phone.',
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 13.5,
            height: 1.4,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            AppStrings.cancel,
            style: TextStyle(
              color: colors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.success,
            foregroundColor: Colors.white,
            elevation: 1,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text(
            'Undelete & Restore Account',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

/// Alert banner displayed when account is in the 15-day deletion grace period.
class AccountDeletionBanner extends StatelessWidget {
  final UserDeletionStatus status;
  final VoidCallback onUndelete;

  const AccountDeletionBanner({
    super.key,
    required this.status,
    required this.onUndelete,
  });

  @override
  Widget build(BuildContext context) {
    if (!status.isDeleteRequested) return const SizedBox.shrink();

    final colors = context.colors;
    final days = status.daysRemaining;
    final hours = status.hoursRemaining;

    final String timeLabel = days > 1
        ? '$days days remaining'
        : (days == 1 ? '1 day remaining' : '$hours hours remaining');

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.error.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.warning_amber_rounded,
              color: AppColors.error,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Account Scheduled for Deletion',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Permanent purge in $timeLabel. Select undelete to cancel.',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              textStyle: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            onPressed: onUndelete,
            icon: const Icon(Icons.restore_rounded, size: 16),
            label: const Text('Undelete'),
          ),
        ],
      ),
    );
  }
}
