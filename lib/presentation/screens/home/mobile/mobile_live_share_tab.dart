import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/server_constants.dart';
import '../../../../core/widgets/universal/bounceable.dart';
import '../../../../data/models/server_info.dart';
import '../../../../data/services/file_share_service.dart';
import '../../../../data/services/screen_share_start_result.dart';
import '../../../../data/services/server_service.dart';

/// Phone-only entry point for a read-only Windows screen session with
/// integrated system power controls (Sleep, Lock, Restart, Shutdown).
class MobileLiveShareTab extends StatefulWidget {
  final FileShareService fileShareService;
  final ServerInfo? currentServerInfo;
  final String? localDeviceId;
  final bool isConnected;

  const MobileLiveShareTab({
    super.key,
    required this.fileShareService,
    this.currentServerInfo,
    this.localDeviceId,
    this.isConnected = false,
  });

  @override
  State<MobileLiveShareTab> createState() => _MobileLiveShareTabState();
}

class _MobileLiveShareTabState extends State<MobileLiveShareTab> {
  bool _starting = false;
  bool _isProcessing = false;
  String? _pendingAction;
  int _countdownSeconds = 0;
  Timer? _countdownTimer;

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  bool get _isLiveOrConnected =>
      widget.isConnected ||
      (widget.currentServerInfo?.isFreshlyLive() ?? false);

  // ───────────────────────────────── Live Share Start ──────────────────────
  Future<void> _start() async {
    setState(() => _starting = true);
    final ScreenShareStartResult result =
        await widget.fileShareService.startScreenShare();
    if (!mounted) return;
    setState(() => _starting = false);
    if (!result.started) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => LiveShareViewer(
          fileShareService: widget.fileShareService,
          currentServerInfo: widget.currentServerInfo,
          localDeviceId: widget.localDeviceId,
          onPowerAction: _executePowerAction,
        ),
      ),
    );
  }

  // ───────────────────────────────── Power Actions ────────────────────────
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
        setState(() => _countdownSeconds--);
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

  Future<void> _executePowerAction(String action,
      {int timeoutSeconds = 0}) async {
    HapticFeedback.mediumImpact();
    setState(() => _isProcessing = true);

    try {
      final server = widget.currentServerInfo;
      if (server == null || !server.isLive) {
        setState(() => _isProcessing = false);
        _showSnackBar('Windows PC is offline or not reachable.',
            isError: true);
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
        comment: 'Remote $action initiated via PCLink Live Share',
      );

      if (!mounted) return;
      setState(() => _isProcessing = false);

      final isSuccess = result['success'] == true;
      final message = result['message']?.toString() ??
          (isSuccess
              ? 'Command sent to Windows PC'
              : (result['error']?.toString() ?? 'Failed to send command'));

      if (isSuccess && timeoutSeconds > 0) {
        _startCountdown(action, timeoutSeconds);
      } else if (action == ServerConstants.actionAbort) {
        _cancelCountdown();
      }

      _showSnackBar(message, isError: !isSuccess);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      _showSnackBar('Error executing command: $e', isError: true);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
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
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
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
              // Grab Handle
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: colors.textMuted.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              // Icon Badge
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: accentColor.withValues(alpha: 0.25), width: 1.5),
                ),
                child: Icon(icon, color: accentColor, size: 28),
              ),
              const SizedBox(height: 14),
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

              if (allowCountdown) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _executePowerAction(action, timeoutSeconds: 30);
                    },
                    icon: const Icon(Icons.timer_outlined, size: 18),
                    label: const Text('30s Countdown (Allows Cancel)'),
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
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _executePowerAction(action, timeoutSeconds: 0);
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: accentColor,
                      side: BorderSide(
                          color: accentColor.withValues(alpha: 0.35)),
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
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(sheetContext),
                  style: TextButton.styleFrom(
                    foregroundColor: colors.textMuted,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Cancel',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ───────────────────────────────── Build ────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 112),
      children: [
        // Header
        Text(
          'Live Share',
          style: TextStyle(
            color: colors.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 28,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'View your PC screen securely from this phone.',
          style: TextStyle(color: colors.textSecondary, fontSize: 16),
        ),
        const SizedBox(height: 28),

        // ─── Screen View Card ───
        _buildScreenViewCard(colors),
        const SizedBox(height: 20),

        // ─── System Power Controls ───
        _buildPowerControlsCard(colors),
      ],
    );
  }

  Widget _buildScreenViewCard(AppThemeColors colors) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: colors.primary.withValues(alpha: 0.10),
            blurRadius: 26,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(15),
            ),
            child:
                Icon(Icons.desktop_windows_rounded, color: colors.primary),
          ),
          const SizedBox(height: 18),
          Text(
            'PC screen view is off',
            style: TextStyle(
              color: colors.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'This is view-only. Your phone cannot control the PC. '
            'The PC dashboard shows who is watching and can stop sharing at any time.',
            style: TextStyle(color: colors.textSecondary, height: 1.45),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _starting ? null : _start,
              icon: _starting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.play_arrow_rounded),
              label: Text(
                  _starting ? 'Starting secure view…' : 'Start live view'),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPowerControlsCard(AppThemeColors colors) {
    final enabled = _isLiveOrConnected && !_isProcessing;

    return Container(
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.cardBorder, width: 0.8),
        boxShadow: [
          BoxShadow(
            color:
                Colors.black.withValues(alpha: context.isDark ? 0.2 : 0.04),
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
                      style:
                          TextStyle(fontSize: 12, color: colors.textMuted),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _isLiveOrConnected
                        ? AppColors.success.withValues(alpha: 0.12)
                        : colors.textMuted.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _isLiveOrConnected ? 'Ready' : 'PC Offline',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: _isLiveOrConnected
                          ? AppColors.successLight
                          : colors.textMuted,
                    ),
                  ),
                ),
            ],
          ),

          // Active Countdown / Abort Banner
          if (_pendingAction != null && _countdownSeconds > 0) ...[
            const SizedBox(height: 14),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.alarm_on_rounded,
                      size: 20, color: AppColors.error),
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
                          style: TextStyle(
                              fontSize: 10,
                              color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () =>
                        _executePowerAction(ServerConstants.actionAbort),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Abort',
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 14),

          // 4 Action Tiles
          Row(
            children: [
              Expanded(
                child: _buildActionTile(
                  title: 'Sleep',
                  subtitle: 'Standby mode',
                  icon: Icons.bedtime_rounded,
                  accentColor: AppColors.accentWarm,
                  enabled: enabled,
                  onTap: () => _showConfirmationSheet(
                    action: ServerConstants.actionSleep,
                    title: 'Put PC to Sleep?',
                    description:
                        'Your Windows PC will enter low-power sleep mode and can be awakened at any time.',
                    icon: Icons.bedtime_rounded,
                    accentColor: AppColors.accentWarm,
                    allowCountdown: false,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildActionTile(
                  title: 'Lock',
                  subtitle: 'Secure screen',
                  icon: Icons.lock_person_rounded,
                  accentColor: AppColors.accentPurple,
                  enabled: enabled,
                  onTap: () =>
                      _executePowerAction(ServerConstants.actionLock),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildActionTile(
                  title: 'Restart',
                  subtitle: 'Reboot PC',
                  icon: Icons.restart_alt_rounded,
                  accentColor: AppColors.primary,
                  enabled: enabled,
                  onTap: () => _showConfirmationSheet(
                    action: ServerConstants.actionRestart,
                    title: 'Restart Windows PC?',
                    description:
                        'Your PC will safely close running applications and reboot.',
                    icon: Icons.restart_alt_rounded,
                    accentColor: AppColors.primary,
                    allowCountdown: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildActionTile(
                  title: 'Shut Down',
                  subtitle: 'Power off',
                  icon: Icons.power_settings_new_rounded,
                  accentColor: AppColors.error,
                  enabled: enabled,
                  onTap: () => _showConfirmationSheet(
                    action: ServerConstants.actionShutdown,
                    title: 'Shut Down Windows PC?',
                    description:
                        'Your PC will turn off completely. Any unsaved files on the PC may be lost.',
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

  Widget _buildActionTile({
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
                color: enabled
                    ? accentColor.withValues(alpha: 0.15)
                    : colors.textMuted.withValues(alpha: 0.1),
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
                      color:
                          enabled ? colors.textSecondary : colors.textMuted,
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

// ═══════════════════════════════════════════════════════════════════════════
//  Full-Screen Live Viewer with WebSocket stream, high clarity, zoom & HUD
// ═══════════════════════════════════════════════════════════════════════════

class LiveShareViewer extends StatefulWidget {
  final FileShareService fileShareService;
  final ServerInfo? currentServerInfo;
  final String? localDeviceId;
  final Future<void> Function(String action, {int timeoutSeconds})? onPowerAction;

  const LiveShareViewer({
    super.key,
    required this.fileShareService,
    this.currentServerInfo,
    this.localDeviceId,
    this.onPowerAction,
  });

  @override
  State<LiveShareViewer> createState() => _LiveShareViewerState();
}

class _LiveShareViewerState extends State<LiveShareViewer>
    with SingleTickerProviderStateMixin {
  WebSocket? _socket;
  StreamSubscription? _wsSubscription;
  Timer? _fpsTimer;
  Timer? _fallbackPollTimer;
  Timer? _hudTimer;

  Uint8List? _frame;
  bool _isStreaming = false;
  bool _isConnecting = true;
  bool _showHud = true;
  int _consecutiveNulls = 0;

  // Real-time telemetry
  int _framesInLastSecond = 0;
  int _currentFps = 0;
  int _currentLatencyMs = 0;
  DateTime? _lastFrameReceivedAt;
  String _currentQuality = 'ultra'; // 'ultra' (1080p, Q85), 'high', 'fast'

  late AnimationController _pulseController;
  final TransformationController _transformController = TransformationController();
  bool _isZoomed = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _transformController.addListener(() {
      final zoomed = _transformController.value.getMaxScaleOnAxis() > 1.05;
      if (zoomed != _isZoomed) {
        setState(() => _isZoomed = zoomed);
      }
    });

    // Force landscape orientation for true desktop aspect ratio
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // FPS calculation ticker
    _fpsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _currentFps = _framesInLastSecond;
          _framesInLastSecond = 0;
        });
      }
    });

    _startStream();
    _resetHudTimer();
  }

  void _resetHudTimer() {
    _hudTimer?.cancel();
    _hudTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _showHud) {
        setState(() => _showHud = false);
      }
    });
  }

  void _toggleHud() {
    setState(() => _showHud = !_showHud);
    if (_showHud) _resetHudTimer();
  }

  Future<void> _startStream() async {
    setState(() => _isConnecting = true);

    try {
      final socket = await widget.fileShareService.connectScreenShareWebSocket(
        localDeviceId: widget.localDeviceId ?? 'AndroidClient',
        serverStartTime: widget.currentServerInfo?.startedAt?.toIso8601String() ?? '',
        quality: _currentQuality,
        deviceName: 'Mobile App',
      );

      if (socket != null && mounted) {
        _socket = socket;
        _listenToWebSocket(socket);
        return;
      }
    } catch (e) {
      debugPrint('LiveShareViewer: WebSocket direct connect failed: $e');
    }

    if (mounted) {
      _startRapidPolling();
    }
  }

  void _listenToWebSocket(WebSocket socket) {
    _wsSubscription?.cancel();
    _wsSubscription = socket.listen(
      (data) {
        if (data is List<int>) {
          final now = DateTime.now();
          if (_lastFrameReceivedAt != null) {
            final diff = now.difference(_lastFrameReceivedAt!).inMilliseconds;
            if (diff > 0 && diff < 1500) {
              _currentLatencyMs = diff;
            }
          }
          _lastFrameReceivedAt = now;
          _framesInLastSecond++;

          final bytes = data is Uint8List ? data : Uint8List.fromList(data);
          if (mounted) {
            setState(() {
              _frame = bytes;
              _isStreaming = true;
              _isConnecting = false;
              _consecutiveNulls = 0;
            });
          }

          // Crucial ACK backpressure: signals PC to send next frame
          try {
            socket.add('ack');
          } catch (_) {}
        }
      },
      onError: (e) {
        debugPrint('LiveShareViewer: WS stream error: $e');
        _startRapidPolling();
      },
      onDone: () {
        debugPrint('LiveShareViewer: WS stream finished');
        _startRapidPolling();
      },
      cancelOnError: true,
    );
  }

  void _startRapidPolling() {
    if (_fallbackPollTimer != null) return;
    debugPrint('LiveShareViewer: Falling back to rapid frame polling');
    _fallbackPollTimer = Timer.periodic(
      const Duration(milliseconds: 66), // ~15 FPS
      (_) => _pollFrame(),
    );
    _pollFrame();
  }

  bool _pollInFlight = false;
  Future<void> _pollFrame() async {
    if (_pollInFlight || !mounted) return;
    _pollInFlight = true;
    try {
      final frame = await widget.fileShareService.getScreenShareFrame();
      if (mounted) {
        if (frame != null) {
          _framesInLastSecond++;
          setState(() {
            _frame = frame;
            _isStreaming = true;
            _isConnecting = false;
            _consecutiveNulls = 0;
          });
        } else {
          _consecutiveNulls++;
          if (_consecutiveNulls > 10) {
            setState(() => _isStreaming = false);
          }
        }
      }
    } finally {
      _pollInFlight = false;
    }
  }

  void _setQuality(String quality) {
    if (_currentQuality == quality) return;
    setState(() => _currentQuality = quality);
    if (_socket != null) {
      try {
        _socket!.add('quality:$quality');
      } catch (_) {}
    }
    _resetHudTimer();
  }

  void _resetZoom() {
    _transformController.value = Matrix4.identity();
    _resetHudTimer();
  }

  Future<void> _stopAndClose() async {
    _wsSubscription?.cancel();
    try {
      _socket?.close();
    } catch (_) {}
    await widget.fileShareService.stopScreenShare();
    if (mounted) Navigator.of(context).pop();
  }

  void _showPowerControlsSheet() {
    _hudTimer?.cancel();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E2128),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Text(
                  'Quick PC Power Controls',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _powerButton(
                      icon: Icons.nightlight_round,
                      label: 'Sleep',
                      color: AppColors.primary,
                      onTap: () {
                        Navigator.pop(ctx);
                        widget.onPowerAction?.call(ServerConstants.actionSleep);
                      },
                    ),
                    _powerButton(
                      icon: Icons.lock_outline_rounded,
                      label: 'Lock',
                      color: AppColors.primaryLight,
                      onTap: () {
                        Navigator.pop(ctx);
                        widget.onPowerAction?.call(ServerConstants.actionLock);
                      },
                    ),
                    _powerButton(
                      icon: Icons.restart_alt_rounded,
                      label: 'Restart',
                      color: AppColors.accentWarm,
                      onTap: () {
                        Navigator.pop(ctx);
                        widget.onPowerAction
                            ?.call(ServerConstants.actionRestart, timeoutSeconds: 30);
                      },
                    ),
                    _powerButton(
                      icon: Icons.power_settings_new_rounded,
                      label: 'Shutdown',
                      color: AppColors.error,
                      onTap: () {
                        Navigator.pop(ctx);
                        widget.onPowerAction
                            ?.call(ServerConstants.actionShutdown, timeoutSeconds: 30);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    ).then((_) => _resetHudTimer());
  }

  Widget _powerButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                shape: BoxShape.circle,
                border: Border.all(color: color.withValues(alpha: 0.4)),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _fpsTimer?.cancel();
    _fallbackPollTimer?.cancel();
    _hudTimer?.cancel();
    _wsSubscription?.cancel();
    try {
      _socket?.close();
    } catch (_) {}
    _pulseController.dispose();
    _transformController.dispose();

    // Restore portrait orientation and system UI
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Gesture detector for screen tap & pinch-to-zoom viewer
          GestureDetector(
            onTap: _toggleHud,
            behavior: HitTestBehavior.opaque,
            child: _frame != null
                ? InteractiveViewer(
                    transformationController: _transformController,
                    minScale: 1.0,
                    maxScale: 5.0,
                    panAxis: PanAxis.free,
                    clipBehavior: Clip.none,
                    child: Center(
                      child: Image.memory(
                        _frame!,
                        gaplessPlayback: true,
                        filterQuality: FilterQuality.medium,
                        fit: BoxFit.contain,
                      ),
                    ),
                  )
                : Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 40,
                          height: 40,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          _isConnecting
                              ? 'Connecting to real-time stream (1080p)…'
                              : (_consecutiveNulls > 6
                                  ? 'Reconnecting to your PC…'
                                  : 'Waiting for screen frames…'),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'View-only • Ultra low latency pipeline',
                          style: TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
          ),

          // 2. Animated HUD Overlay (Top & Bottom bars)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            top: _showHud ? 0 : -90,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.85),
                    Colors.black.withValues(alpha: 0.4),
                    Colors.transparent,
                  ],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Row(
                  children: [
                    // Back / Stop Button
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                      tooltip: 'Exit full screen',
                      onPressed: _stopAndClose,
                    ),
                    const SizedBox(width: 4),

                    // Connection Dot & Title
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        return Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isStreaming
                                ? AppColors.success.withValues(
                                    alpha: 0.5 + (_pulseController.value * 0.5))
                                : AppColors.accentWarm.withValues(
                                    alpha: 0.5 + (_pulseController.value * 0.5)),
                            boxShadow: [
                              BoxShadow(
                                color: (_isStreaming
                                        ? AppColors.success
                                        : AppColors.accentWarm)
                                    .withValues(
                                        alpha: 0.4 * _pulseController.value),
                                blurRadius: 6,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'PC Live Screen',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Telemetry Pill (FPS & Latency)
                    if (_isStreaming) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.18),
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$_currentFps FPS',
                              style: const TextStyle(
                                color: AppColors.success,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (_currentLatencyMs > 0) ...[
                              const SizedBox(width: 6),
                              Container(
                                width: 3,
                                height: 3,
                                decoration: const BoxDecoration(
                                  color: Colors.white38,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${_currentLatencyMs}ms',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],

                    const Spacer(),

                    // Reset Zoom Button (when zoomed)
                    if (_isZoomed)
                      IconButton(
                        icon: const Icon(Icons.zoom_out_map_rounded,
                            color: Colors.white70, size: 20),
                        tooltip: 'Reset Zoom (1:1)',
                        onPressed: _resetZoom,
                      ),

                    // Quality Selector Popup Menu
                    PopupMenuButton<String>(
                      initialValue: _currentQuality,
                      tooltip: 'Stream Quality',
                      onSelected: _setQuality,
                      color: const Color(0xFF222630),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      icon: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _currentQuality == 'ultra'
                                  ? '1080p'
                                  : (_currentQuality == 'high' ? '720p' : 'Fast'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Icon(Icons.arrow_drop_down,
                                color: Colors.white70, size: 16),
                          ],
                        ),
                      ),
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'ultra',
                          child: Row(
                            children: [
                              Icon(Icons.hd_rounded,
                                  color: AppColors.primary, size: 18),
                              SizedBox(width: 10),
                              Text(
                                'Ultra Sharp (1080p • 85% Q)',
                                style: TextStyle(color: Colors.white, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'high',
                          child: Row(
                            children: [
                              Icon(Icons.high_quality_rounded,
                                  color: AppColors.primaryLight, size: 18),
                              SizedBox(width: 10),
                              Text(
                                'Balanced (1440px • 78% Q)',
                                style: TextStyle(color: Colors.white, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'fast',
                          child: Row(
                            children: [
                              Icon(Icons.speed_rounded,
                                  color: AppColors.accentWarm, size: 18),
                              SizedBox(width: 10),
                              Text(
                                'Fast Motion (Smooth • 70% Q)',
                                style: TextStyle(color: Colors.white, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(width: 6),

                    // Quick Power Actions Button
                    if (widget.onPowerAction != null)
                      IconButton(
                        icon: const Icon(Icons.power_settings_new_rounded,
                            color: Colors.white, size: 22),
                        tooltip: 'PC Power Actions',
                        onPressed: _showPowerControlsSheet,
                      ),

                    const SizedBox(width: 4),

                    // Stop Button
                    TextButton.icon(
                      onPressed: _stopAndClose,
                      icon: const Icon(Icons.stop_circle_outlined,
                          color: AppColors.error, size: 18),
                      label: const Text(
                        'Stop',
                        style: TextStyle(
                            color: AppColors.error, fontWeight: FontWeight.bold),
                      ),
                      style: TextButton.styleFrom(
                        backgroundColor: AppColors.error.withValues(alpha: 0.15),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 3. Hint overlay at bottom (tap to hide/show controls, pinch to zoom)
          if (_showHud && _isStreaming)
            Positioned(
              left: 16,
              right: 16,
              bottom: 12,
              child: SafeArea(
                top: false,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    child: const Text(
                      'Pinch to zoom in • Tap screen to hide controls',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

