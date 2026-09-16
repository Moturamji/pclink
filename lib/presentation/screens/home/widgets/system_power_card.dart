import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/server_constants.dart';
import '../../../../core/widgets/universal/bounceable.dart';
import '../../../../data/models/server_info.dart';
import '../../../../data/services/server_service.dart';
import '../../../../data/services/system_power_service.dart';

/// Premium, minimal and cute remote system power controls card
/// for Windows PC (Sleep, Lock, Restart, Shutdown, Abort).
class SystemPowerCard extends StatefulWidget {
  final bool isWindows;
  final ServerInfo? currentServerInfo;
  final String? localDeviceId;
  final bool isConnected;

  const SystemPowerCard({
    super.key,
    required this.isWindows,
    this.currentServerInfo,
    this.localDeviceId,
    this.isConnected = false,
  });

  @override
  State<SystemPowerCard> createState() => _SystemPowerCardState();
}

class _SystemPowerCardState extends State<SystemPowerCard> {
  bool _isProcessing = false;
  String? _pendingAction;
  int _countdownSeconds = 0;
  Timer? _countdownTimer;

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdown(String action, int seconds) {
    _countdownTimer?.cancel();
    setState(() {
      _pendingAction = action;
      _countdownSeconds = seconds;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_countdownSeconds <= 1) {
        timer.cancel();
        setState(() {
          _countdownSeconds = 0;
          _pendingAction = null;
        });
      } else {
        setState(() {
          _countdownSeconds--;
        });
      }
    });
  }

  void _cancelCountdown() {
    _countdownTimer?.cancel();
    setState(() {
      _countdownSeconds = 0;
      _pendingAction = null;
    });
  }

  Future<void> _executePowerAction(String action, {int timeoutSeconds = 0}) async {
    HapticFeedback.mediumImpact();
    setState(() => _isProcessing = true);

    try {
      if (widget.isWindows) {
        // Direct local execution on Windows PC
        final result = await SystemPowerService.executeAction(
          action: action,
          timeoutSeconds: timeoutSeconds,
          comment: 'Initiated via PCLink Desktop Controls',
        );

        if (!mounted) return;
        setState(() => _isProcessing = false);

        if (result.success && timeoutSeconds > 0) {
          _startCountdown(action, timeoutSeconds);
        } else if (action == ServerConstants.actionAbort) {
          _cancelCountdown();
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: result.success ? AppColors.success : AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      } else {
        // Remote dispatch from Android to Windows PC
        final server = widget.currentServerInfo;
        if (server == null || !server.isLive) {
          setState(() => _isProcessing = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Windows PC is offline or not reachable.'),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
          return;
        }

        final deviceId = widget.localDeviceId ?? 'AndroidClient';
        final startTime = server.startedAt?.toIso8601String() ?? '';

        final result = await ServerService.sendSystemPowerAction(
          serverUrl: server.url,
          publicUrl: server.publicUrl,
          androidDeviceId: deviceId,
          serverStartTime: startTime,
          action: action,
          timeoutSeconds: timeoutSeconds,
          comment: 'Remote $action initiated via PCLink Android',
        );

        if (!mounted) return;
        setState(() => _isProcessing = false);

        final isSuccess = result['success'] == true;
        final message = result['message']?.toString() ??
            (isSuccess ? 'Command sent to Windows PC' : (result['error']?.toString() ?? 'Failed to send command'));

        if (isSuccess && timeoutSeconds > 0) {
          _startCountdown(action, timeoutSeconds);
        } else if (action == ServerConstants.actionAbort) {
          _cancelCountdown();
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: isSuccess ? AppColors.success : AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error executing command: $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  void _showConfirmationSheet({
    required String action,
    required String title,
    required String description,
    required IconData icon,
    required Color accentColor,
    bool allowCountdown = true,
  }) {
    HapticFeedback.selectionClick();
    final colors = context.colors;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Container(
          decoration: BoxDecoration(
            color: colors.cardSurface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Cute Grab Handle
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: colors.textMuted.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),

              // Cute Pastel Icon Badge
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                  border: Border.all(color: accentColor.withValues(alpha: 0.25), width: 1.5),
                ),
                child: Icon(icon, color: accentColor, size: 28),
              ),
              const SizedBox(height: 14),

              // Title & Description
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                description,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: colors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 22),

              // Action Options
              if (allowCountdown) ...[
                // Option 1: Timed (with abort safety)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _executePowerAction(action, timeoutSeconds: 30);
                    },
                    icon: const Icon(Icons.timer_outlined, size: 18),
                    label: Text('30s Countdown (Allows Cancel)'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // Option 2: Immediate
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _executePowerAction(action, timeoutSeconds: 0);
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: accentColor,
                      side: BorderSide(color: accentColor.withValues(alpha: 0.35)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Execute Immediately',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ] else ...[
                // Single direct action (e.g. Sleep / Lock)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _executePowerAction(action, timeoutSeconds: 0);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text('Confirm $title'),
                  ),
                ),
              ],

              const SizedBox(height: 10),
              // Cancel Button
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(sheetContext),
                  style: TextButton.styleFrom(
                    foregroundColor: colors.textMuted,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isWindows) {
      return const SizedBox.shrink();
    }

    final colors = context.colors;
    final isLiveOrConnected = widget.isConnected || (widget.currentServerInfo?.isFreshlyLive() ?? false);

    return Container(
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.cardBorder, width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: context.isDark ? 0.2 : 0.04),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.power_settings_new_rounded,
                  size: 18,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SYSTEM CONTROLS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      'Remote Windows Power Controls',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (_isProcessing)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isLiveOrConnected
                        ? AppColors.success.withValues(alpha: 0.12)
                        : colors.textMuted.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isLiveOrConnected ? 'Ready' : 'PC Offline',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: isLiveOrConnected ? AppColors.successLight : colors.textMuted,
                    ),
                  ),
                ),
            ],
          ),

          // Active Countdown / Abort Banner
          if (_pendingAction != null && _countdownSeconds > 0) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.alarm_on_rounded, size: 20, color: AppColors.error),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$_pendingAction in $_countdownSeconds seconds',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.error,
                          ),
                        ),
                        const Text(
                          'Windows is preparing to execute power action.',
                          style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => _executePowerAction(ServerConstants.actionAbort),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Abort', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 14),

          // 4 Cute Action Grid
          Row(
            children: [
              Expanded(
                child: _buildCuteActionTile(
                  context: context,
                  title: 'Sleep',
                  subtitle: 'Standby mode',
                  icon: Icons.bedtime_rounded,
                  accentColor: AppColors.accentWarm,
                  enabled: isLiveOrConnected && !_isProcessing,
                  onTap: () => _showConfirmationSheet(
                    action: ServerConstants.actionSleep,
                    title: 'Put PC to Sleep?',
                    description: 'Your Windows PC will enter low-power sleep mode and can be awakened at any time.',
                    icon: Icons.bedtime_rounded,
                    accentColor: AppColors.accentWarm,
                    allowCountdown: false,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildCuteActionTile(
                  context: context,
                  title: 'Lock',
                  subtitle: 'Secure screen',
                  icon: Icons.lock_person_rounded,
                  accentColor: AppColors.accentPurple,
                  enabled: isLiveOrConnected && !_isProcessing,
                  onTap: () => _executePowerAction(ServerConstants.actionLock),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildCuteActionTile(
                  context: context,
                  title: 'Restart',
                  subtitle: 'Reboot PC',
                  icon: Icons.restart_alt_rounded,
                  accentColor: AppColors.primary,
                  enabled: isLiveOrConnected && !_isProcessing,
                  onTap: () => _showConfirmationSheet(
                    action: ServerConstants.actionRestart,
                    title: 'Restart Windows PC?',
                    description: 'Your PC will safely close running applications and reboot.',
                    icon: Icons.restart_alt_rounded,
                    accentColor: AppColors.primary,
                    allowCountdown: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildCuteActionTile(
                  context: context,
                  title: 'Shut Down',
                  subtitle: 'Power off',
                  icon: Icons.power_settings_new_rounded,
                  accentColor: AppColors.error,
                  enabled: isLiveOrConnected && !_isProcessing,
                  onTap: () => _showConfirmationSheet(
                    action: ServerConstants.actionShutdown,
                    title: 'Shut Down Windows PC?',
                    description: 'Your PC will turn off completely. Any unsaved files on the PC may be lost.',
                    icon: Icons.power_settings_new_rounded,
                    accentColor: AppColors.error,
                    allowCountdown: true,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCuteActionTile({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final colors = context.colors;

    return Bounceable(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: enabled
              ? accentColor.withValues(alpha: 0.07)
              : colors.surface.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: enabled
                ? accentColor.withValues(alpha: 0.22)
                : colors.cardBorder.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: enabled ? accentColor.withValues(alpha: 0.15) : colors.textMuted.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: enabled ? accentColor : colors.textMuted,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: enabled ? colors.textPrimary : colors.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 10,
                      color: enabled ? colors.textSecondary : colors.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
