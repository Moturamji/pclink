import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../core/constants/server_constants.dart';

/// Service managing one-time Windows network and firewall permissions for PCLink.
/// Ensures that on first-time launch, all network, server, and relay permissions
/// are configured under the official app name "PCLink" so that users are never
/// interrupted by Windows Firewall or Defender prompts during normal work.
class WindowsPermissionService {
  static const String _prefFileName = 'pclink_permissions_granted.txt';

  /// Path to the PCLink AppData directory.
  static String get _appDataDir {
    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.isNotEmpty) {
      return '$appData\\pclink';
    }
    return '.';
  }

  /// Path to the local persistence token file.
  static File get _tokenFile => File('$_appDataDir\\$_prefFileName');

  /// Checks if PCLink permissions have already been configured and verified.
  static Future<bool> hasCompletedPermissionSetup() async {
    if (kIsWeb || !Platform.isWindows) return true;

    try {
      if (await _tokenFile.exists()) {
        return true;
      }

      // Check if firewall rules already exist in Windows
      final checkResult = await Process.run('netsh', [
        'advfirewall',
        'firewall',
        'show',
        'rule',
        'name=PCLink Server',
      ]);

      if (checkResult.exitCode == 0 && checkResult.stdout.toString().contains('8088')) {
        // Rules already present - persist token so we don't query netsh repeatedly
        await markPermissionSetupCompleted();
        return true;
      }
    } catch (e) {
      debugPrint('WindowsPermissionService: Check error: $e');
    }
    return false;
  }

  /// Marks permission setup as completed in the local app directory.
  static Future<void> markPermissionSetupCompleted() async {
    try {
      final dir = Directory(_appDataDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      await _tokenFile.writeAsString(DateTime.now().toIso8601String());
    } catch (e) {
      debugPrint('WindowsPermissionService: Could not save token: $e');
    }
  }

  /// Requests and configures all Windows Firewall rules for PCLink in a single
  /// elevated prompt. All rules explicitly mention only "PCLink".
  static Future<bool> requestAllPermissions() async {
    if (kIsWeb || !Platform.isWindows) return true;

    try {
      final appExe = Platform.resolvedExecutable;
      final relayExe = '$_appDataDir\\pclink-relay.exe';
      const port = ServerConstants.defaultPort;

      debugPrint('WindowsPermissionService: Requesting one-time Windows permissions for PCLink...');

      // Build PowerShell script that configures all PCLink firewall rules at once
      final psScript = '''
\$appExe = '$appExe';
\$relayExe = '$relayExe';
\$port = $port;

# 1. PCLink Application Rule (Inbound TCP & UDP for main app)
netsh advfirewall firewall delete rule name="PCLink Application" > \$null 2>&1;
netsh advfirewall firewall add rule name="PCLink Application" dir=in action=allow program="\$appExe" enable=yes profile=any description="PCLink Device Discovery and Synchronization Service" > \$null 2>&1;

# 2. PCLink Network Relay Service Rule
netsh advfirewall firewall delete rule name="PCLink Relay Service" > \$null 2>&1;
if (Test-Path "\$relayExe") {
    netsh advfirewall firewall add rule name="PCLink Relay Service" dir=in action=allow program="\$relayExe" enable=yes profile=any description="PCLink Encrypted Cloud Relay Network Service" > \$null 2>&1;
}

# 3. PCLink Local Service Port Rule
netsh advfirewall firewall delete rule name="PCLink Server" > \$null 2>&1;
netsh advfirewall firewall add rule name="PCLink Server" dir=in action=allow protocol=TCP localport="\$port" enable=yes profile=any description="PCLink Inbound Synchronization Service Port" > \$null 2>&1;

exit 0;
''';

      // Create a temporary script in the PCLink directory
      final dir = Directory(_appDataDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final scriptFile = File('$_appDataDir\\setup_pclink_firewall.ps1');
      await scriptFile.writeAsString(psScript);

      // Launch elevated PowerShell process with RunAs (prompts user once for PCLink permission)
      final elevateCommand =
          "Start-Process powershell -Verb RunAs -Wait -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"${scriptFile.path}\"'";

      final result = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        elevateCommand,
      ]);

      // Clean up script
      try {
        if (await scriptFile.exists()) {
          await scriptFile.delete();
        }
      } catch (_) {}

      if (result.exitCode == 0) {
        await markPermissionSetupCompleted();
        debugPrint('WindowsPermissionService: ✅ All PCLink firewall permissions successfully configured!');
        return true;
      } else {
        debugPrint('WindowsPermissionService: Process exited with code ${result.exitCode}: ${result.stderr}');
      }
    } catch (e) {
      debugPrint('WindowsPermissionService: Exception during permission setup: $e');
    }

    return false;
  }
}
