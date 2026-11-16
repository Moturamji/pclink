import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../data/services/screen_share_service.dart';

/// Inline warning shown on the Mac when Screen Recording permission is
/// missing. macOS only shows its own prompt once, so after a denial the user
/// must enable it in System Settings and then restart the app.
class ScreenRecordingPermissionPanel extends StatelessWidget {
  const ScreenRecordingPermissionPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: ScreenShareService.osPermissionResponsibleApp,
      builder: (context, responsibleApp, _) => _build(context, responsibleApp),
    );
  }

  Widget _build(BuildContext context, String? responsibleApp) {
    final colors = context.colors;
    final launchedByOtherApp = responsibleApp != null;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lock_outline_rounded,
                  color: AppColors.warning, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Screen Recording permission needed',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            launchedByOtherApp
                ? 'DeskPocket was started from "$responsibleApp", so macOS asks '
                    'for and checks Screen Recording for "$responsibleApp" '
                    'instead of DeskPocket. Click "Restart DeskPocket" to run it '
                    'on its own (a debugger session will disconnect), then '
                    'allow DeskPocket when macOS asks.'
                : 'Your phone can\'t see this Mac\'s screen until DeskPocket is '
                    'allowed in System Settings > Privacy & Security > Screen '
                    'Recording. After turning it on, restart DeskPocket.',
            style: TextStyle(color: colors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () async {
                  // Try the system prompt first (only appears if never
                  // answered), then open Settings for the denied case.
                  final granted = await ScreenShareService.requestOsPermission();
                  if (!granted) {
                    await ScreenShareService.openOsPermissionSettings();
                  }
                },
                icon: const Icon(Icons.settings_rounded, size: 18),
                label: const Text('Open System Settings'),
              ),
              OutlinedButton.icon(
                onPressed: ScreenShareService.relaunchApp,
                icon: const Icon(Icons.restart_alt_rounded, size: 18),
                label: const Text('Restart DeskPocket'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

bool _dialogOpen = false;

/// Shows the permission dialog on the Mac (once at a time). Used when a phone
/// tries to stream and capture fails for lack of permission.
Future<void> showScreenRecordingPermissionDialog(BuildContext context) async {
  if (_dialogOpen || !ScreenShareService.requiresOsPermission) return;
  _dialogOpen = true;
  try {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Allow screen sharing'),
        content: const SizedBox(
          width: 420,
          child: ScreenRecordingPermissionPanel(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Not now'),
          ),
        ],
      ),
    );
  } finally {
    _dialogOpen = false;
  }
}
