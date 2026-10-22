import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:path_provider/path_provider.dart';
import 'windows_shell_service.dart';
import 'mac_shell_service.dart';

/// Unified service managing incoming shared files and media across both Android
/// (system share sheet intents) and Windows (Explorer SendTo & context menus).
class ShareTargetService {
  static final ShareTargetService _instance = ShareTargetService._internal();
  factory ShareTargetService() => _instance;
  ShareTargetService._internal();

  static const MethodChannel _androidChannel =
      MethodChannel('com.example.pclink/share_intent');
  static const MethodChannel _windowsChannel =
      MethodChannel('pclink/window_control');
  // The macOS runner registers its window channel under this name.
  static const MethodChannel _macChannel =
      MethodChannel('com.deskpocket.pclink/window_control');

  static final List<String> _initialFiles = [];
  final StreamController<List<String>> _sharedFilesController =
      StreamController<List<String>>.broadcast();

  bool _initialized = false;

  /// Stream of incoming files shared while the app is active.
  Stream<List<String>> get sharedFilesStream => _sharedFilesController.stream;

  /// Sets initial files provided directly as process launch arguments (Windows CLI / SendTo).
  static void setInitialFiles(List<String> files) {
    _initialFiles.addAll(files);
  }

  /// Initializes native platform channels and Windows shell integrations.
  Future<void> initialize() async {
    if (_initialized || kIsWeb) return;
    _initialized = true;

    if (Platform.isAndroid) {
      _androidChannel.setMethodCallHandler((call) async {
        if (call.method == 'onSharedFilesReceived') {
          final rawFiles = call.arguments;
          if (rawFiles is List) {
            final filePaths = rawFiles
                .map((e) => e.toString())
                .where((p) => p.isNotEmpty)
                .toList();
            if (filePaths.isNotEmpty) {
              debugPrint(
                'ShareTargetService: Android received ${filePaths.length} live shared file(s)',
              );
              _sharedFilesController.add(filePaths);
            }
          }
        }
      });
    } else if (Platform.isWindows) {
      _windowsChannel.setMethodCallHandler((call) async {
        if (call.method == 'onSharedFilesReceived') {
          final rawFiles = call.arguments;
          if (rawFiles is List) {
            final filePaths = rawFiles
                .map((e) => e.toString())
                .where((p) => p.isNotEmpty)
                .toList();
            if (filePaths.isNotEmpty) {
              debugPrint(
                'ShareTargetService: Windows received ${filePaths.length} live shared file(s)',
              );
              _sharedFilesController.add(filePaths);
            }
          }
        }
      });

      // Automatically ensure Windows SendTo shortcut and Context Menu are registered
      unawaited(WindowsShellService.registerAll());
    } else if (Platform.isMacOS) {
      _macChannel.setMethodCallHandler((call) async {
        if (call.method == 'onSharedFilesReceived') {
          final rawFiles = call.arguments;
          if (rawFiles is List) {
            final filePaths = rawFiles
                .map((e) => e.toString())
                .where((p) => p.isNotEmpty)
                .toList();
            if (filePaths.isNotEmpty) {
              debugPrint(
                'ShareTargetService: macOS received ${filePaths.length} live shared file(s)',
              );
              _sharedFilesController.add(filePaths);
            }
          }
        }
      });

      // Automatically register macOS Finder Quick Action
      unawaited(MacShellService.registerAll());
    } else if (Platform.isIOS) {
      // Files opened with "Open in DeskPocket" while the app is running only
      // show up in Documents/Inbox; pick them up whenever the app resumes.
      AppLifecycleListener(
        onResume: () async {
          final files = await _takeIosInboxFiles();
          if (files.isNotEmpty) _sharedFilesController.add(files);
        },
      );
    }
  }

  /// Moves files out of the iOS Documents/Inbox (where "Open in" copies them)
  /// into a temporary folder, so each shared file is delivered exactly once.
  Future<List<String>> _takeIosInboxFiles() async {
    final taken = <String>[];
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final inbox = Directory('${docsDir.path}/Inbox');
      if (!await inbox.exists()) return taken;
      final tmp = await getTemporaryDirectory();
      final outgoing = Directory('${tmp.path}/DeskPocketShared');
      if (!await outgoing.exists()) await outgoing.create(recursive: true);
      await for (final entity in inbox.list()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        var target = File('${outgoing.path}/$name');
        var n = 1;
        while (await target.exists()) {
          target = File('${outgoing.path}/${n++}_$name');
        }
        try {
          taken.add((await entity.rename(target.path)).path);
        } catch (_) {
          taken.add((await entity.copy(target.path)).path);
          await entity.delete();
        }
      }
    } catch (e) {
      debugPrint('ShareTargetService: Error reading iOS Documents/Inbox: $e');
    }
    return taken;
  }

  /// Consumes and returns any pending files queued from process start or cold-start share intents.
  Future<List<String>> consumeInitialAndPendingFiles() async {
    if (kIsWeb) return const [];

    final collected = <String>{};

    // 1. Collect launch arguments (e.g. Windows Explorer SendTo / macOS CLI args)
    if (_initialFiles.isNotEmpty) {
      collected.addAll(_initialFiles);
      _initialFiles.clear();
    }

    // 2. Fetch pending share files from native platform channel
    try {
      if (Platform.isAndroid) {
        final List<dynamic>? files =
            await _androidChannel.invokeMethod('getPendingSharedFiles');
        if (files != null) {
          collected.addAll(files.map((e) => e.toString()).where((p) => p.isNotEmpty));
        }
      } else if (Platform.isWindows || Platform.isMacOS) {
        final channel = Platform.isMacOS ? _macChannel : _windowsChannel;
        final List<dynamic>? files =
            await channel.invokeMethod('getPendingSharedFiles');
        if (files != null) {
          collected.addAll(files.map((e) => e.toString()).where((p) => p.isNotEmpty));
        }
      } else if (Platform.isIOS) {
        // Files delivered via "Open in DeskPocket" land in Documents/Inbox.
        collected.addAll(await _takeIosInboxFiles());
      }
    } catch (e) {
      debugPrint('ShareTargetService: Error fetching pending shared files: $e');
    }

    final validList = collected.where((path) {
      final f = File(path);
      final d = Directory(path);
      return f.existsSync() || d.existsSync();
    }).toList();

    return validList;
  }
}
