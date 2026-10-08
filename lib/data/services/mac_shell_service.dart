import 'dart:io';
import 'package:flutter/foundation.dart';

/// Service managing macOS Finder Quick Action / Services integration:
/// Creates a workflow in `~/Library/Services/Send to Phone with DeskPocket.workflow`
/// allowing users to right click any file or folder in Finder -> Quick Actions -> "Send to Phone with DeskPocket".
class MacShellService {
  static const String _workflowName =
      'Send to Phone with DeskPocket.workflow';

  static Directory get _workflowDir {
    final home = Platform.environment['HOME'] ?? '';
    return Directory('$home/Library/Services/$_workflowName');
  }

  /// Checks if the Finder Quick Action is installed.
  static Future<bool> isQuickActionRegistered() async {
    if (kIsWeb || !Platform.isMacOS) return false;
    try {
      return await _workflowDir.exists();
    } catch (e) {
      debugPrint('MacShellService: isQuickActionRegistered error: $e');
      return false;
    }
  }

  /// Registers or updates the Finder Quick Action workflow.
  static Future<bool> registerQuickAction() async {
    if (kIsWeb || !Platform.isMacOS) return false;

    try {
      final exePath = Platform.resolvedExecutable;
      final workflowDir = _workflowDir;
      final contentsDir = Directory('${workflowDir.path}/Contents');

      if (!await contentsDir.exists()) {
        await contentsDir.create(recursive: true);
      }

      // Write Info.plist
      final infoPlist = File('${contentsDir.path}/Info.plist');
      const infoPlistContent = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Send to Phone with DeskPocket</string>
    <key>NSServices</key>
    <array>
        <dict>
            <key>NSMenuItem</key>
            <dict>
                <key>default</key>
                <string>Send to Phone with DeskPocket</string>
            </dict>
            <key>NSMessage</key>
            <string>runWorkflowAsService</string>
            <key>NSSendFileTypes</key>
            <array>
                <string>public.item</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
''';
      await infoPlist.writeAsString(infoPlistContent, flush: true);

      // Write document.wflow
      final docWflow = File('${contentsDir.path}/document.wflow');
      final escapedExe = exePath.replaceAll('"', '\\"');
      final docWflowContent = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>AMApplicationBuild</key>
    <string>523</string>
    <key>AMApplicationVersion</key>
    <string>2.10</string>
    <key>AMDocumentVersion</key>
    <string>2</string>
    <key>actions</key>
    <array>
        <dict>
            <key>action</key>
            <dict>
                <key>ActionBundlePath</key>
                <string>/System/Library/Automator/Run Shell Script.action</string>
                <key>ActionName</key>
                <string>Run Shell Script</string>
                <key>ActionParameters</key>
                <dict>
                    <key>COMMAND_STRING</key>
                    <string>&quot;$escapedExe&quot; &quot;\$@&quot;</string>
                    <key>inputMethod</key>
                    <integer>1</integer>
                    <key>shell</key>
                    <string>/bin/zsh</string>
                    <key>source</key>
                    <string></string>
                </dict>
            </dict>
        </dict>
    </array>
    <key>workflowMetaData</key>
    <dict>
        <key>workflowTypeIdentifier</key>
        <string>com.apple.Automator.servicesMenu</string>
    </dict>
</dict>
</plist>
''';
      await docWflow.writeAsString(docWflowContent, flush: true);

      debugPrint('MacShellService: Quick Action registered at ${workflowDir.path}');
      return true;
    } catch (e) {
      debugPrint('MacShellService: registerQuickAction error: $e');
      return false;
    }
  }

  /// Unregisters the Quick Action by removing the workflow.
  static Future<bool> unregisterQuickAction() async {
    if (kIsWeb || !Platform.isMacOS) return false;
    try {
      final workflowDir = _workflowDir;
      if (await workflowDir.exists()) {
        await workflowDir.delete(recursive: true);
      }
      return true;
    } catch (e) {
      debugPrint('MacShellService: unregisterQuickAction error: $e');
      return false;
    }
  }

  /// Convenience method to register all macOS shell integrations.
  static Future<void> registerAll() async {
    if (kIsWeb || !Platform.isMacOS) return;
    await registerQuickAction();
  }
}
