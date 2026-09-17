import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/universal/app_card_header.dart';
import '../../../core/widgets/universal/status_badge.dart';
import '../../../data/services/file_share_service.dart';
import '../../../data/services/server_service.dart';
import '../models/shared_file.dart';
import '../models/transfer_progress.dart';

/// Card managing bidirectional file sharing between the Windows PC and the
/// Android phone through the existing temporary server with live real-time transfer indicators.
class FileShareCard extends StatefulWidget {
  final bool isWindows;
  final ServerService? serverService;
  final FileShareService? fileShareService;

  const FileShareCard({
    super.key,
    required this.isWindows,
    this.serverService,
    this.fileShareService,
  });

  @override
  State<FileShareCard> createState() => _FileShareCardState();
}

class _FileShareCardState extends State<FileShareCard> {
  StreamSubscription<List<SharedFile>>? _fileSub;
  StreamSubscription<TransferProgress?>? _progressSub;
  List<SharedFile> _files = const [];
  TransferProgress? _transferProgress;
  TransferProgress? _remoteTransferProgress;
  Timer? _remoteProgressTimer;
  bool _remoteProgressPollInFlight = false;
  bool _busy = false;
  String? _busyLabel;
  String? _downloadingId;

  @override
  void initState() {
    super.initState();
    if (widget.isWindows) {
      final serverService = widget.serverService;
      _files = serverService?.sharedFiles ?? const [];
      _fileSub = serverService?.sharedFilesStream.listen(_onFilesChanged);
      _transferProgress = serverService?.currentTransferProgress;
      _progressSub =
          serverService?.transferProgressStream.listen(_onProgressChanged);
    } else {
      _transferProgress = widget.fileShareService?.currentProgress;
      _progressSub =
          widget.fileShareService?.progressStream.listen(_onProgressChanged);
      _refreshFiles();
      _startRemoteProgressPolling();
    }
  }

  @override
  void didUpdateWidget(FileShareCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isWindows != oldWidget.isWindows ||
        widget.fileShareService != oldWidget.fileShareService ||
        widget.serverService != oldWidget.serverService) {
      _fileSub?.cancel();
      _progressSub?.cancel();
      if (widget.isWindows) {
        _files = widget.serverService?.sharedFiles ?? const [];
        _fileSub =
            widget.serverService?.sharedFilesStream.listen(_onFilesChanged);
        _transferProgress = widget.serverService?.currentTransferProgress;
        _progressSub = widget.serverService?.transferProgressStream
            .listen(_onProgressChanged);
      } else {
        _transferProgress = widget.fileShareService?.currentProgress;
        _progressSub =
            widget.fileShareService?.progressStream.listen(_onProgressChanged);
        _refreshFiles();
        _startRemoteProgressPolling();
      }
    }
  }

  @override
  void dispose() {
    _fileSub?.cancel();
    _progressSub?.cancel();
    _remoteProgressTimer?.cancel();
    super.dispose();
  }

  void _onFilesChanged(List<SharedFile> files) {
    if (mounted) {
      setState(() {
        _files = files;
      });
    }
  }

  void _onProgressChanged(TransferProgress? progress) {
    if (mounted) {
      setState(() {
        _transferProgress = progress;
      });
    }
  }

  /// The phone has its own byte stream for transfers it starts.  This polling
  /// feed fills the other half: PC-side file preparation and PC-to-phone sends
  /// update here about three times per second while the Files screen is open.
  void _startRemoteProgressPolling() {
    _remoteProgressTimer?.cancel();
    _remoteProgressTimer = Timer.periodic(
      const Duration(milliseconds: 350),
      (_) => _refreshRemoteProgress(),
    );
    _refreshRemoteProgress();
  }

  Future<void> _refreshRemoteProgress() async {
    if (_remoteProgressPollInFlight || !mounted || widget.isWindows) return;
    final service = widget.fileShareService;
    if (service == null) return;
    _remoteProgressPollInFlight = true;
    try {
      final transfers = await service.listRemoteTransfers();
      if (!mounted) return;
      final active = transfers.where((transfer) => transfer.isActive).toList();
      final next = active.isNotEmpty
          ? active.reduce(
              (latest, transfer) => transfer.timestamp.isAfter(latest.timestamp)
                  ? transfer
                  : latest,
            )
          : (transfers.isNotEmpty ? transfers.last : null);
      if (_remoteTransferProgress?.fileId != next?.fileId ||
          _remoteTransferProgress?.bytesTransferred != next?.bytesTransferred ||
          _remoteTransferProgress?.status != next?.status) {
        setState(() => _remoteTransferProgress = next);
      }
    } finally {
      _remoteProgressPollInFlight = false;
    }
  }

  TransferProgress? get _visibleTransferProgress {
    final local = _transferProgress;
    if (local?.isActive == true) return local;
    final remote = _remoteTransferProgress;
    if (remote?.isActive == true) return remote;
    return local ?? remote;
  }

  Future<void> _refreshFiles() async {
    final service = widget.fileShareService;
    if (service == null) return;
    final files = await service.listSharedFiles();
    if (mounted) {
      setState(() {
        _files = files;
      });
    }
  }

  /// Windows: pick local files and copy them into the shared folder.
  Future<void> _pickAndShareWindows() async {
    final serverService = widget.serverService;
    if (serverService == null) return;

    setState(() {
      _busy = true;
      _busyLabel = 'Opening file picker...';
    });
    // Render the acknowledgement before invoking the native picker.  This is
    // especially important on Windows where selecting a large file can take a
    // moment while Explorer resolves its metadata.
    await Future<void>.delayed(Duration.zero);
    var added = 0;
    try {
      final files = await FilePicker.pickFiles();
      if (files.isEmpty) return;
      if (mounted) setState(() => _busyLabel = 'Preparing selected files...');

      for (final f in files) {
        if (f.path == null) continue;
        if (mounted) {
          setState(() => _busyLabel = 'Sharing ${f.name}...');
        }
        final item = await serverService.addLocalSharedFile(
          sourcePath: f.path!,
          deviceName: 'Windows PC',
        );
        if (item != null) added++;
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyLabel = null;
        });
      }
    }
    if (!mounted) return;
    _showSnack(
      added > 0
          ? 'Added $added file(s) - your phone can now download them.'
          : 'No files were added.',
      isError: added == 0,
    );
  }

  /// Android: pick local files and upload them directly to the PC's server.
  Future<void> _pickAndSendFiles() async {
    final service = widget.fileShareService;
    if (service == null) {
      _showSnack(
        'PC link is not ready yet. Start PCLink on your PC first.',
        isError: true,
      );
      return;
    }

    setState(() {
      _busy = true;
      _busyLabel = 'Opening file picker...';
    });
    await Future<void>.delayed(Duration.zero);
    var sent = 0;
    try {
      final files = await FilePicker.pickFiles();
      if (files.isEmpty) return;
      for (final f in files) {
        if (f.path == null) continue;
        if (mounted) setState(() => _busyLabel = 'Sending ${f.name}...');
        if (await service.uploadFile(f.path!)) sent++;
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyLabel = null;
        });
      }
    }
    if (!mounted) return;
    _showSnack(
      sent > 0
          ? 'Sent $sent file(s) securely to your PC.'
          : 'Nothing was sent. Make sure PCLink is open and the Link Service is active on the PC.',
      isError: sent == 0,
    );
    if (sent > 0) await _refreshFiles();
  }

  /// Android: download a shared file from the PC into the phone's Downloads.
  Future<void> _downloadFile(SharedFile file) async {
    final service = widget.fileShareService;
    if (service == null) return;

    setState(() => _downloadingId = file.id);
    final dest = await service.downloadFile(file);
    if (!mounted) return;
    setState(() => _downloadingId = null);

    if (dest != null) {
      _showSnack('Saved to ${dest.path}');
    } else {
      _showSnack('Download failed. Is the PC link active?', isError: true);
    }
  }

  /// Windows: stop sharing a file (removes it from the shared folder too).
  Future<void> _stopSharing(SharedFile file) async {
    await widget.serverService?.removeSharedFile(file.id);
    if (mounted) _showSnack('Stopped sharing ${file.name}.');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.cardBorder, width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: colors.isDark ? 0.2 : 0.04),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppCardHeader(
            icon: Icons.folder_open_rounded,
            iconColor: colors.accentPurple,
            title: 'FILE TRANSFER STUDIO',
            subtitle: 'Direct local P2P streaming with HTTP 206 chunking',
            trailing: _files.isEmpty
                ? null
                : StatusBadge(
                    label: '${_files.length} Shared',
                    isActive: true,
                    activeColor: colors.accentPurple,
                  ),
          ),
          const SizedBox(height: 16),

          // Live Real-Time Transfer Indicator Panel
          if (_visibleTransferProgress != null) ...[
            _buildLiveTransferPanel(_visibleTransferProgress!, colors),
            const SizedBox(height: 16),
          ],

          if (widget.isWindows)
            _buildWindowsPanel(colors)
          else
            _buildAndroidPanel(colors),
          const SizedBox(height: 16),
          _buildFooter(colors),
        ],
      ),
    );
  }

  /// Dedicated real-time file transfer progress dashboard
  Widget _buildLiveTransferPanel(TransferProgress progress, AppThemeColors colors) {
    final isUpload = progress.isUpload;
    final isDone = progress.status == TransferStatus.completed;
    final isFailed = progress.status == TransferStatus.failed;
    final isCancelled = progress.status == TransferStatus.cancelled;
    final inProgress = progress.isActive;

    final themeColor = isDone
        ? colors.success
        : (isFailed || isCancelled
            ? AppColors.error
            : colors.primaryLight);

    final actionLabel = widget.isWindows &&
            (progress.status == TransferStatus.preparing ||
                progress.status == TransferStatus.verifying ||
                progress.status == TransferStatus.finalizing)
        ? 'Preparing secure shared copy'
        : isUpload
        ? (widget.isWindows ? 'Sending to Phone' : 'Sending to PC')
        : (widget.isWindows ? 'Receiving from Phone' : 'Receiving from PC');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceSubtle,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: themeColor.withValues(alpha: 0.3),
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Icon + File Name + Status Badge
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: themeColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isDone
                      ? Icons.check_circle_rounded
                      : (isUpload
                          ? Icons.cloud_upload_rounded
                          : Icons.cloud_download_rounded),
                  size: 18,
                  color: themeColor,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      progress.fileName,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      actionLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: themeColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: themeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isDone
                      ? '100%'
                      : (isFailed
                          ? 'FAILED'
                          : (isCancelled ? 'CANCELLED' : progress.percentageLabel)),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: themeColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Linear Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: inProgress
                  ? progress.fraction
                  : (isDone ? 1.0 : 0.0),
              minHeight: 6,
              backgroundColor: colors.surface,
              valueColor: AlwaysStoppedAnimation<Color>(themeColor),
            ),
          ),
          const SizedBox(height: 10),

          // Keep every status visible at narrow widths and when an error has a
          // long explanation.  A Wrap avoids the desktop overflow reported by
          // large-transfer failures without hiding useful information.
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 600;
              final transferWidth = compact ? constraints.maxWidth : 210.0;
              final remainingWidth = compact ? constraints.maxWidth : 230.0;
              return Wrap(
                spacing: 14,
                runSpacing: 8,
                children: [
              // Transferred / Total
              SizedBox(
                width: transferWidth,
                child: Row(
                  children: [
                    Icon(
                      Icons.data_usage_rounded,
                      size: 13,
                      color: colors.textMuted,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        progress.transferredLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: colors.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

              // Speed
              if (inProgress) ...[
                SizedBox(
                  width: compact ? constraints.maxWidth : 115,
                  child: Row(
                  children: [
                    Icon(
                      Icons.speed_rounded,
                      size: 13,
                      color: colors.textMuted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      progress.speedLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: colors.primaryLight,
                      ),
                    ),
                  ],
                  ),
                ),
              ],

              // Remaining
              SizedBox(
                width: remainingWidth,
                child: Row(
                children: [
                  Icon(
                    isDone
                        ? Icons.timer_off_rounded
                        : Icons.hourglass_bottom_rounded,
                    size: 13,
                    color: isDone ? colors.success : colors.textMuted,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      isDone ? 'Finished' : progress.remainingLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: inProgress
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: isDone
                            ? colors.success
                            : colors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              ),
            ],
              );
            },
          ),

          // Cancel Button for active transfer (isolated per-transfer cancellation)
          if (inProgress &&
              ((!widget.isWindows && widget.fileShareService != null) ||
                  (widget.isWindows && widget.serverService != null))) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  if (widget.isWindows) {
                    widget.serverService?.cancelTransfer(progress.fileId);
                  } else {
                    widget.fileShareService?.cancelTransfer(progress.fileId);
                  }
                },
                icon: const Icon(Icons.close_rounded, size: 14),
                label: const Text('Cancel Transfer'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.error,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  textStyle: const TextStyle(fontSize: 11),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWindowsPanel(AppThemeColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Share files from this PC with your phone, or receive files sent '
          'from the phone - all over the temporary server.',
          style: TextStyle(
            fontSize: 12,
            height: 1.4,
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _busy ? null : _pickAndShareWindows,
                icon: const Icon(Icons.upload_file_rounded, size: 18),
                label: Text(
                  _busy ? (_busyLabel ?? 'Working...') : 'Add Files to Share',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.secondary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          _files.isEmpty
              ? 'Nothing is being shared yet.'
              : 'Currently shared (${_files.length})',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        if (_files.isEmpty)
          _emptyState(
            colors: colors,
            icon: Icons.folder_open_rounded,
            title: 'No shared files',
            subtitle:
                'Tap "Add Files to Share" to make PC files downloadable '
                'from your phone. Files sent from the phone appear here too.',
          )
        else
          ..._files.take(6).map((f) => _buildFileTile(f, colors)),
      ],
    );
  }

  Widget _buildAndroidPanel(AppThemeColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Send files from this phone straight to your PC, or download files '
          'shared from the PC - over the temporary server, never via the cloud.',
          style: TextStyle(
            fontSize: 12,
            height: 1.4,
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _busy ? null : _pickAndSendFiles,
                icon: const Icon(Icons.send_rounded, size: 18),
                label: Text(
                  _busy ? (_busyLabel ?? 'Working...') : 'Send Files to PC',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.secondary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            IconButton(
              onPressed: _busy ? null : _refreshFiles,
              tooltip: 'Refresh file list from PC',
              icon: const Icon(Icons.refresh_rounded, size: 20),
              color: colors.textSecondary,
              style: IconButton.styleFrom(
                backgroundColor: colors.surfaceSubtle,
                side: BorderSide(color: colors.cardBorder, width: 0.8),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          _files.isEmpty
              ? 'Shared files from your PC'
              : 'Files available from your PC (${_files.length})',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        if (_files.isEmpty)
          _emptyState(
            colors: colors,
            icon: Icons.download_for_offline_rounded,
            title: 'Nothing shared yet',
            subtitle:
                'Files you add here are sent instantly to your PC. '
                'Files shared from the PC can be downloaded with one tap.',
          )
        else
          ..._files.take(6).map((f) => _buildFileTile(f, colors)),
      ],
    );
  }

  Widget _buildFileTile(SharedFile file, AppThemeColors colors) {
    final isDownloadingThis = _downloadingId == file.id;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surfaceSubtle,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: file.isFromAndroid
                  ? colors.primaryLight.withValues(alpha: 0.12)
                  : colors.secondary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _iconFor(file.name),
              size: 18,
              color: file.isFromAndroid
                  ? colors.primaryLight
                  : colors.success,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${file.sizeLabel}  •  ${file.isFromAndroid ? 'From phone' : 'From PC'}  •  ${_timeLabel(file.timestamp)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.textMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (widget.isWindows)
            IconButton(
              onPressed: _busy ? null : () => _stopSharing(file),
              tooltip: 'Stop sharing',
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              color: colors.textMuted,
            )
          else if (isDownloadingThis)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _downloadFile(file),
              icon: const Icon(Icons.download_rounded, size: 16),
              label: const Text('Get'),
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.success,
                side: BorderSide(
                  color: colors.success.withValues(alpha: 0.4),
                  width: 0.8,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                minimumSize: Size.zero,
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _emptyState({
    required AppThemeColors colors,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surfaceSubtle,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(icon, size: 28, color: colors.textMuted),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: colors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(AppThemeColors colors) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.shield_outlined, size: 15, color: colors.textMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            widget.isWindows
                ? 'Files are copied to the shared folder and served to your phone only while the PC Link Service is active. Real-time transfer speed and progress display automatically during transfers.'
                : 'Transfers are direct between this phone and your PC via the temporary server - real-time progress, speed, and bytes update live throughout the transfer.',
            style: TextStyle(
              fontSize: 11,
              height: 1.4,
              color: colors.textMuted,
            ),
          ),
        ),
      ],
    );
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
        backgroundColor: isError ? AppColors.error : AppColors.success,
      ),
    );
  }

  static IconData _iconFor(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf')) return Icons.picture_as_pdf_rounded;
    if (lower.endsWith('.zip') ||
        lower.endsWith('.rar') ||
        lower.endsWith('.7z') ||
        lower.endsWith('.tar') ||
        lower.endsWith('.gz')) {
      return Icons.folder_zip_rounded;
    }
    if (lower.endsWith('.mp3') ||
        lower.endsWith('.wav') ||
        lower.endsWith('.m4a') ||
        lower.endsWith('.flac')) {
      return Icons.music_note_rounded;
    }
    if (lower.endsWith('.mp4') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.mov')) {
      return Icons.movie_rounded;
    }
    if (lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.bmp') ||
        lower.endsWith('.webp')) {
      return Icons.image_rounded;
    }
    if (lower.endsWith('.doc') ||
        lower.endsWith('.docx') ||
        lower.endsWith('.txt') ||
        lower.endsWith('.md')) {
      return Icons.description_rounded;
    }
    return Icons.insert_drive_file_rounded;
  }

  static String _timeLabel(DateTime t) {
    final now = DateTime.now();
    final diff = now.difference(t);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
