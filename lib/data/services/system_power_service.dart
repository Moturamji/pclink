import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../core/constants/server_constants.dart';

/// Result of executing a system power command.
class PowerActionResult {
  final bool success;
  final String action;
  final String message;
  final int? exitCode;

  const PowerActionResult({
    required this.success,
    required this.action,
    required this.message,
    this.exitCode,
  });

  Map<String, dynamic> toMap() => {
        'success': success,
        'action': action,
        'message': message,
        if (exitCode != null) 'exitCode': exitCode,
      };

  @override
  String toString() =>
      'PowerActionResult(success: $success, action: $action, message: $message, exitCode: $exitCode)';
}

/// Service dedicated to executing Windows system power operations
/// (Sleep, Shutdown, Restart, Lock Workstation, Abort Shutdown).
class SystemPowerService {
  /// Executes a requested power action by name.
  static Future<PowerActionResult> executeAction({
    required String action,
    int timeoutSeconds = 0,
    bool force = true,
    String? comment,
  }) async {
    if (!kIsWeb && !Platform.isWindows) {
      return PowerActionResult(
        success: false,
        action: action,
        message: 'System power commands are only supported on Windows host systems.',
      );
    }

    switch (action.toLowerCase().trim()) {
      case ServerConstants.actionSleep:
        return sleep();
      case ServerConstants.actionShutdown:
        return shutdown(
          timeoutSeconds: timeoutSeconds,
          force: force,
          comment: comment ?? 'Remote shutdown initiated via DeskPocket',
        );
      case ServerConstants.actionRestart:
        return restart(
          timeoutSeconds: timeoutSeconds,
          force: force,
          comment: comment ?? 'Remote restart initiated via DeskPocket',
        );
      case ServerConstants.actionLock:
        return lockWorkstation();
      case ServerConstants.actionAbort:
        return abortShutdown();
      default:
        return PowerActionResult(
          success: false,
          action: action,
          message: 'Unknown power action: $action',
        );
    }
  }

  /// Puts the Windows PC into true Sleep (Suspend to RAM) state.
  static Future<PowerActionResult> sleep() async {
    try {
      debugPrint('SystemPowerService: Initiating Windows Sleep (Suspend)...');
      // Use PowerShell to trigger true Suspend (Sleep) rather than Hibernation
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        'Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.Application]::SetSuspendState([System.Windows.Forms.PowerState]::Suspend, \$false, \$false)',
      ]);

      if (result.exitCode == 0) {
        return const PowerActionResult(
          success: true,
          action: ServerConstants.actionSleep,
          message: 'Windows PC entering Sleep mode.',
          exitCode: 0,
        );
      }

      // Fallback to rundll32 if PowerShell fails
      debugPrint('SystemPowerService: PowerShell sleep exited with ${result.exitCode}, trying fallback...');
      final fallback = await Process.run('rundll32.exe', [
        'powrprof.dll,SetSuspendState',
        '0,1,0',
      ]);

      return PowerActionResult(
        success: fallback.exitCode == 0,
        action: ServerConstants.actionSleep,
        message: fallback.exitCode == 0
            ? 'Windows PC entering Sleep mode (fallback).'
            : 'Failed to put Windows PC to sleep: ${fallback.stderr}',
        exitCode: fallback.exitCode,
      );
    } catch (e) {
      debugPrint('SystemPowerService: Sleep exception: $e');
      return PowerActionResult(
        success: false,
        action: ServerConstants.actionSleep,
        message: 'Sleep command error: $e',
      );
    }
  }

  /// Shuts down the Windows PC, optionally with a countdown and comment.
  static Future<PowerActionResult> shutdown({
    int timeoutSeconds = 0,
    bool force = true,
    String? comment,
  }) async {
    try {
      final args = <String>['/s'];
      if (force) args.add('/f');
      args.addAll(['/t', '$timeoutSeconds']);
      if (comment != null && comment.isNotEmpty) {
        args.addAll(['/c', comment]);
      }

      debugPrint('SystemPowerService: Executing shutdown with args: $args');
      final result = await Process.run('shutdown', args);

      final isSuccess = result.exitCode == 0;
      return PowerActionResult(
        success: isSuccess,
        action: ServerConstants.actionShutdown,
        message: isSuccess
            ? (timeoutSeconds > 0
                ? 'Windows PC will shut down in $timeoutSeconds seconds.'
                : 'Windows PC shutting down now.')
            : 'Shutdown command failed: ${result.stderr}'.trim(),
        exitCode: result.exitCode,
      );
    } catch (e) {
      debugPrint('SystemPowerService: Shutdown exception: $e');
      return PowerActionResult(
        success: false,
        action: ServerConstants.actionShutdown,
        message: 'Shutdown command error: $e',
      );
    }
  }

  /// Reboots the Windows PC, optionally with a countdown.
  static Future<PowerActionResult> restart({
    int timeoutSeconds = 0,
    bool force = true,
    String? comment,
  }) async {
    try {
      final args = <String>['/r'];
      if (force) args.add('/f');
      args.addAll(['/t', '$timeoutSeconds']);
      if (comment != null && comment.isNotEmpty) {
        args.addAll(['/c', comment]);
      }

      debugPrint('SystemPowerService: Executing restart with args: $args');
      final result = await Process.run('shutdown', args);

      final isSuccess = result.exitCode == 0;
      return PowerActionResult(
        success: isSuccess,
        action: ServerConstants.actionRestart,
        message: isSuccess
            ? (timeoutSeconds > 0
                ? 'Windows PC will restart in $timeoutSeconds seconds.'
                : 'Windows PC restarting now.')
            : 'Restart command failed: ${result.stderr}'.trim(),
        exitCode: result.exitCode,
      );
    } catch (e) {
      debugPrint('SystemPowerService: Restart exception: $e');
      return PowerActionResult(
        success: false,
        action: ServerConstants.actionRestart,
        message: 'Restart command error: $e',
      );
    }
  }

  /// Instantly locks the Windows Workstation screen.
  static Future<PowerActionResult> lockWorkstation() async {
    try {
      debugPrint('SystemPowerService: Locking Windows Workstation...');
      final result = await Process.run('rundll32.exe', [
        'user32.dll,LockWorkStation',
      ]);

      final isSuccess = result.exitCode == 0;
      return PowerActionResult(
        success: isSuccess,
        action: ServerConstants.actionLock,
        message: isSuccess
            ? 'Windows Workstation locked successfully.'
            : 'Failed to lock Workstation: ${result.stderr}'.trim(),
        exitCode: result.exitCode,
      );
    } catch (e) {
      debugPrint('SystemPowerService: Lock exception: $e');
      return PowerActionResult(
        success: false,
        action: ServerConstants.actionLock,
        message: 'Lock Workstation error: $e',
      );
    }
  }

  /// Cancels an active scheduled shutdown or restart.
  static Future<PowerActionResult> abortShutdown() async {
    try {
      debugPrint('SystemPowerService: Aborting scheduled shutdown/restart...');
      final result = await Process.run('shutdown', ['/a']);

      final isSuccess = result.exitCode == 0;
      return PowerActionResult(
        success: isSuccess,
        action: ServerConstants.actionAbort,
        message: isSuccess
            ? 'Scheduled shutdown or restart has been cancelled.'
            : 'No scheduled shutdown was found to abort.',
        exitCode: result.exitCode,
      );
    } catch (e) {
      debugPrint('SystemPowerService: Abort exception: $e');
      return PowerActionResult(
        success: false,
        action: ServerConstants.actionAbort,
        message: 'Abort command error: $e',
      );
    }
  }
}
