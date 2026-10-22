import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../core/constants/server_constants.dart';
import 'platform_helpers.dart';

/// Fully-automated public tunnel for the desktop clipboard and file server.
///
/// Zero user setup: on first use it downloads the free, token-less
/// `cloudflared` CLI from GitHub into system app data, then spawns
/// `cloudflared tunnel --url http://127.0.0.1:<port>`, extracts the ephemeral
/// `https://*.trycloudflare.com` address from its output, and exposes it
/// through [urlStream] so the app can publish it to Firebase. The phone then
/// reaches the host from any network - no port-forwarding, no account, no
/// manual configuration. If anything fails, the app silently falls back to
/// the WAN/LAN route.
class TunnelService {
  static String get downloadUrl {
    if (!kIsWeb && Platform.isMacOS) {
      // Apple Silicon gets the native build; the Intel one only runs there
      // if Rosetta happens to be installed.
      final arch = Platform.version.contains('arm64') ? 'arm64' : 'amd64';
      return 'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-darwin-$arch.tgz';
    }
    return 'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe';
  }

  static final RegExp _urlPattern =
      RegExp('https://[a-zA-Z0-9-]+[.]trycloudflare[.]com');

  final http.Client _client = http.Client();
  final StreamController<String?> _urlController =
      StreamController<String?>.broadcast();

  Process? _process;
  List<StreamSubscription<List<int>>>? _outputSubs;
  Timer? _restartTimer;
  Future<bool>? _ensureInFlight;
  String? _binaryPath;
  String? _lastUrl;
  bool _active = false;
  bool _processRunning = false;
  bool _starting = false;

  final int _targetPort;

  TunnelService({int targetPort = ServerConstants.defaultPort})
      : _targetPort = targetPort;

  Stream<String?> get urlStream => _urlController.stream;
  String? get currentUrl => _lastUrl;
  bool get isRunning => _process != null;

  /// Begins (or resumes) the automated tunnel. Completes with the first
  /// public URL, or `null` if it couldn't be established (the app keeps the
  /// WAN/LAN fallback in that case).
  Future<String?> start() async {
    if (kIsWeb || !isDesktopHost) {
      debugPrint('TunnelService: Tunnels are only supported on desktop hosts (Windows/macOS).');
      return null;
    }

    _active = true;

    // Already running (or starting) - return what we have / wait for it.
    if (_processRunning || _starting) {
      if (_lastUrl != null) return _lastUrl;
      return await _waitForFirstUrl(const Duration(seconds: 45));
    }
    _starting = true;

    if (!await _ensureBinary()) {
      _starting = false;
      return null;
    }

    try {
      debugPrint(
          'TunnelService: Launching DeskPocket Relay tunnel on port $_targetPort...');
      _process = await Process.start(
        _binaryPath!,
        [
          'tunnel',
          '--url',
          'http://127.0.0.1:$_targetPort',
          '--no-autoupdate',
        ],
        workingDirectory: _binaryParent,
      );
      _processRunning = true;
    } catch (e) {
      debugPrint('TunnelService: Failed to launch DeskPocket Relay service: $e');
      _process = null;
      _starting = false;
      return null;
    }
    _starting = false;

    _attachOutput(_process!);
    _watchProcess(_process!);
    return await _waitForFirstUrl(const Duration(seconds: 45));
  }

  /// Stops the tunnel and its restart loop (used on server toggle-off / exit).
  Future<void> stop() async {
    _active = false;
    _restartTimer?.cancel();
    _restartTimer = null;
    _outputSubs?.forEach((s) => s.cancel());
    _outputSubs = null;
    final p = _process;
    _process = null;
    if (p != null && _processRunning) {
      p.kill();
    }
    _processRunning = false;
    if (_lastUrl != null) {
      _lastUrl = null;
      if (!_urlController.isClosed) _urlController.add(null);
    }
    debugPrint('TunnelService: Tunnel stopped.');
  }

  Future<void> dispose() async {
    await stop();
    _urlController.close();
  }

  // ---------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------

  Future<String?> _waitForFirstUrl(Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (!_active) return null;
      if (_lastUrl != null) return _lastUrl;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return _lastUrl;
  }

  void _attachOutput(Process process) {
    final List<String> tails = ['', ''];
    final outputs = [process.stdout, process.stderr];

    for (var i = 0; i < outputs.length; i++) {
      final sub = outputs[i].listen((List<int> chunk) {
        if (chunk.isEmpty) return;
        tails[i] += utf8.decoder.convert(chunk);
        if (tails[i].length > 16000) {
          tails[i] = tails[i].substring(tails[i].length - 16000);
        }
        final match = _urlPattern.firstMatch(tails[i]);
        if (match != null) {
          final url = match.group(0)!;
          if (url != _lastUrl) {
            _lastUrl = url;
            debugPrint('TunnelService: Public tunnel ready: $url');
            if (!_urlController.isClosed) {
              _urlController.add(url);
            }
          }
        }
      });
      (_outputSubs ??= []).add(sub);
    }
  }
void _watchProcess(Process process) {
    process.exitCode.whenComplete(() {
      final needsRestart = _active && _processRunning;
      if (identical(process, _process)) {
        _process = null;
      }
      _processRunning = false;
      _outputSubs?.forEach((s) => s.cancel());
      _outputSubs = null;
      debugPrint('TunnelService: cloudflared process exited.');
      if (_lastUrl != null) {
        _lastUrl = null;
        if (!_urlController.isClosed) {
          _urlController.add(null);
        }
      }
      if (needsRestart) {
        _restartTimer?.cancel();
        _restartTimer = Timer(const Duration(seconds: 5), () {
          _restartTimer = null;
          start();
        });
      }
    });
  }

  Future<bool> _ensureBinary() async {
    if (_binaryPath != null) return true;
    try {
      return await (_ensureInFlight ??= _downloadBinary());
    } finally {
      // Reset on failure so a later start() retries the download instead of
      // caching the failure forever (e.g. first run while offline).
      if (_binaryPath == null) _ensureInFlight = null;
    }
  }

  Future<bool> _downloadBinary() async {
    try {
      String baseDir;
      String binPath;
      if (!kIsWeb && Platform.isWindows) {
        final appData = Platform.environment['APPDATA'];
        baseDir = (appData != null && appData.isNotEmpty)
            ? '$appData\\pclink'
            : '.';
        binPath = '$baseDir\\pclink-relay.exe';
        final oldBinPath = '$baseDir\\cloudflared.exe';

        // Auto-migrate previous binary name if present
        final file = File(binPath);
        final oldFile = File(oldBinPath);

        if (!await file.exists() && await oldFile.exists()) {
          try {
            await oldFile.rename(binPath);
            debugPrint('TunnelService: Migrated binary to $binPath');
          } catch (_) {
            try {
              await oldFile.copy(binPath);
            } catch (_) {}
          }
        }
      } else if (!kIsWeb && Platform.isMacOS) {
        for (final sysPath in [
          '/opt/homebrew/bin/cloudflared',
          '/usr/local/bin/cloudflared',
        ]) {
          if (File(sysPath).existsSync()) {
            _binaryPath = sysPath;
            _binaryParent = File(sysPath).parent.path;
            debugPrint('TunnelService: Using system cloudflared at $sysPath');
            return true;
          }
        }
        final home = Platform.environment['HOME'] ?? '.';
        baseDir = '$home/Library/Application Support/pclink';
        binPath = '$baseDir/pclink-relay';
      } else {
        return false;
      }

      final file = File(binPath);
      if (await file.exists()) {
        _binaryPath = binPath;
        _binaryParent = baseDir;
        debugPrint('TunnelService: DeskPocket Relay binary ready at $binPath');
        return true;
      }

      debugPrint(
          'TunnelService: First run - downloading DeskPocket Relay service (one time only)...');
      final request = http.Request('GET', Uri.parse(downloadUrl));
      final streamed = await _client.send(request).timeout(
            const Duration(minutes: 10),
          );
      if (streamed.statusCode != 200) {
        debugPrint(
            'TunnelService: DeskPocket Relay download failed (HTTP ${streamed.statusCode}). Falling back to WAN/LAN route.');
        return false;
      }

      final dir = Directory(baseDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final isArchive =
          downloadUrl.endsWith('.tgz') || downloadUrl.endsWith('.tar.gz');
      final tmp = File(isArchive ? '$binPath.tgz' : '$binPath.download');
      final sink = tmp.openWrite();
      try {
        await for (final chunk in streamed.stream) {
          sink.add(chunk);
        }
      } finally {
        await sink.close();
      }

      if (isArchive) {
        await Process.run('tar', ['-xzf', tmp.path, '-C', baseDir]);
        final extracted = File('$baseDir/cloudflared');
        if (await extracted.exists()) {
          if (await file.exists()) await file.delete();
          await extracted.rename(binPath);
        }
        try {
          await tmp.delete();
        } catch (_) {}
      } else {
        await tmp.rename(binPath);
      }

      if (!kIsWeb && Platform.isMacOS) {
        await Process.run('chmod', ['+x', binPath]);
      }

      _binaryPath = binPath;
      _binaryParent = baseDir;
      debugPrint('TunnelService: DeskPocket Relay installed at $binPath');
      return true;
    } catch (e) {
      debugPrint(
          'TunnelService: DeskPocket Relay setup failed: $e. Falling back to WAN/LAN route.');
      return false;
    }
  }

  String _binaryParent = '.';
}
