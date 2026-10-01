import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../core/constants/server_constants.dart';

typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

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

/// Service dedicated to executing desktop system power operations
/// (Sleep, Shutdown, Restart, Lock Workstation, Abort Shutdown) on Windows and macOS.
class SystemPowerService {
  /// Customizable command runner for testing and security isolation.
  static ProcessRunner processRunner = Process.run;

  /// Executes a requested power action by name.
  static Future<PowerActionResult> executeAction({
    required String action,
    int timeoutSeconds = 0,
    bool force = true,
    String? comment,
    bool? isWindowsOverride,
    bool? isMacOSOverride,
  }) async {
    final isWin = isWindowsOverride ?? (!kIsWeb && Platform.isWindows);
    final isMac = isMacOSOverride ?? (!kIsWeb && Platform.isMacOS);

    if (!isWin && !isMac) {
      return PowerActionResult(
        success: false,
        action: action,
        message: 'System power commands are only supported on Windows and macOS host systems.',
      );
    }

    final normalized = action.toLowerCase().trim();

    if (normalized != ServerConstants.actionSleep &&
        normalized != ServerConstants.actionShutdown &&
        normalized != ServerConstants.actionRestart &&
        normalized != ServerConstants.actionLock &&
        normalized != ServerConstants.actionAbort) {
      return PowerActionResult(
        success: false,
        action: action,
        message: 'Unknown power action: $action',
      );
    }

    if (isMac) {
      switch (normalized) {
        case ServerConstants.actionSleep:
          return _macSleep();
        case ServerConstants.actionShutdown:
          return _macShutdown();
        case ServerConstants.actionRestart:
          return _macRestart();
        case ServerConstants.actionLock:
          return _macLock();
        case ServerConstants.actionAbort:
          return _macAbort();
      }
    }

    switch (normalized) {
      case ServerConstants.actionSleep:
        return _windowsSleep();
      case ServerConstants.actionShutdown:
        return _windowsShutdown(
          timeoutSeconds: timeoutSeconds,
          force: force,
          comment: comment ?? 'Remote shutdown initiated via DeskPocket',
        );
      case ServerConstants.actionRestart:
        return _windowsRestart(
          timeoutSeconds: timeoutSeconds,
          force: force,
          comment: comment ?? 'Remote restart initiated via DeskPocket',
        );
      case ServerConstants.actionLock:
        return _windowsLock();
      case ServerConstants.actionAbort:
        return _windowsAbort();
      default:
        return PowerActionResult(
          success: false,
          action: action,
          message: 'Unknown power action: $action',
        );
    }
  }

  /// Puts the host into Sleep (Suspend) state.
  static Future<PowerActionResult> sleep() async {
    if (!kIsWeb && Platform.isMacOS) {
      return _macSleep();
    }
    return _windowsSleep();
  }

  /// Shuts down the host PC/Mac.
  static Future<PowerActionResult> shutdown({
    int timeoutSeconds = 0,
    bool force = true,
    String? comment,
  }) async {
    if (!kIsWeb && Platform.isMacOS) {
      return _macShutdown();
    }
    return _windowsShutdown(
      timeoutSeconds: timeoutSeconds,
      force: force,
      comment: comment,
    );
  }

  /// Reboots the host PC/Mac.
  static Future<PowerActionResult> restart({
    int timeoutSeconds = 0,
    bool force = true,
    String? comment,
  }) async {
    if (!kIsWeb && Platform.isMacOS) {
      return _macRestart();
    }
    return _windowsRestart(
      timeoutSeconds: timeoutSeconds,
      force: force,
      comment: comment,
    );
  }

  /// Locks the workstation/desktop screen.
  static Future<PowerActionResult> lockWorkstation() async {
    if (!kIsWeb && Platform.isMacOS) {
      return _macLock();
    }
    return _windowsLock();
  }

  /// Cancels scheduled shutdown if supported.
  static Future<PowerActionResult> abortShutdown() async {
    if (!kIsWeb && Platform.isMacOS) {
      return _macAbort();
    }
    return _windowsAbort();
  }

  // --- macOS Implementations ---

  static Future<PowerActionResult> _macSleep() async {
    try {
      debugPrint('SystemPowerService: Initiating macOS sleep...');
      final result = await processRunner('pmset', const ['sleepnow']);
      final isSuccess = result.exitCode == 0;
      return PowerActionResult(
        success: isSuccess,
        action: ServerConstants.actionSleep,
        message: isSuccess ? 'Mac entering sleep mode.' : 'Failed to put Mac to sleep: ${result.stderr}'.trim(),
        exitCode: result.exitCode,
      );
    } catch (e) {
      debugPrint('SystemPowerService: Mac sleep exception: $e');
      return PowerActionResult(
        success: false,
        action: ServerConstants.actionSleep,
        message: 'Mac sleep command error: $e',
      );
    }
  }

  static Future<PowerActionResult> _macShutdown() async {
    try {
      debugPrint('SystemPowerService: Initiating macOS shutdown...');
      final result = await processRunner('osascript', const [
        '-e',
        'tell application "System Events" to shut down',
      ]);
      final isSuccess = result.exitCode == 0;
      return PowerActionResult(
        success: isSuccess,
        action: ServerConstants.actionShutdown,
        message: isSuccess ? 'Mac shutting down.' : 'Failed to shut down Mac: ${result.stderr}'.trim(),
        exitCode: result.exitCode,
      );
    } catch (e) {
      debugPrint('SystemPowerService: Mac shutdown exception: $e');
      return PowerActionResult(
        success: false,
        action: ServerConstants.actionShutdown,
        message: 'Mac shutdown command error: $e',
      );
    }
  }

  static Future<PowerActionResult> _macRestart() async {
    try {
      debugPrint('SystemPowerService: Initiating macOS restart...');
      final result = await processRunner('osascript', const [
        '-e',
        'tell application "System Events" to restart',
      ]);
      final isSuccess = result.exitCode == 0;
      return PowerActionResult(
        success: isSuccess,
        action: ServerConstants.actionRestart,
        message: isSuccess ? 'Mac restarting.' : 'Failed to restart Mac: ${result.stderr}'.trim(),
        exitCode: result.exitCode,
      );
    } catch (e) {
      debugPrint('SystemPowerService: Mac restart exception: $e');
      return PowerActionResult(
        success: false,
        action: ServerConstants.actionRestart,
        message: 'Mac restart command error: $e',
      );
    }
  }

  static Future<PowerActionResult> _macLock() async {
    try {
      debugPrint('SystemPowerService: Locking macOS screen...');
      await processRunner('pmset', const ['displaysleepnow']);
      final result = await processRunner('osascript', const [
        '-e',
        'tell application "System Events" to keystroke "q" using {control down, command down}',
      ]);
      final isSuccess = result.exitCode == 0;
      return PowerActionResult(
        success: isSuccess,
        action: ServerConstants.actionLock,
        message: isSuccess ? 'Mac screen locked successfully.' : 'Failed to lock Mac: ${result.stderr}'.trim(),
        exitCode: result.exitCode,
      );
    } catch (e) {
      debugPrint('SystemPowerService: Mac lock exception: $e');
      return PowerActionResult(
        success: false,
        action: ServerConstants.actionLock,
        message: 'Mac lock command error: $e',
      );
    }
  }

  static Future<PowerActionResult> _macAbort() async {
    try {
      debugPrint('SystemPowerService: Aborting macOS shutdown (best-effort)...');
      final result = await processRunner('killall', const ['shutdown']);
      return PowerActionResult(
        success: result.exitCode == 0,
        action: ServerConstants.actionAbort,
        message: result.exitCode == 0
            ? 'Scheduled shutdown cancelled.'
            : 'No scheduled macOS shutdown was found to abort.',
        exitCode: result.exitCode,
      );
    } catch (e) {
      debugPrint('SystemPowerService: Mac abort exception: $e');
      return PowerActionResult(
        success: false,
        action: ServerConstants.actionAbort,
        message: 'Mac abort command error: $e',
      );
    }
  }

  // --- Windows Implementations ---

  static Future<PowerActionResult> _windowsSleep() async {
    try {
      debugPrint('SystemPowerService: Initiating Windows Sleep (Suspend)...');
      final result = await processRunner('powershell', const [
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

      debugPrint('SystemPowerService: PowerShell sleep exited with ${result.exitCode}, trying fallback...');
      final fallback = await processRunner('rundll32.exe', const [
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

  static Future<PowerActionResult> _windowsShutdown({
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
      final result = await processRunner('shutdown', args);

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

  static Future<PowerActionResult> _windowsRestart({
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
      final result = await processRunner('shutdown', args);

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

  static Future<PowerActionResult> _windowsLock() async {
    try {
      debugPrint('SystemPowerService: Locking Windows Workstation...');
      final result = await processRunner('rundll32.exe', const [
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

  static Future<PowerActionResult> _windowsAbort() async {
    try {
      debugPrint('SystemPowerService: Aborting scheduled shutdown/restart...');
      final result = await processRunner('shutdown', const ['/a']);

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
