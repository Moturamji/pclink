import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
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
  StreamSubscription<Map<String, TransferProgress>>? _allTransfersSub;
  List<SharedFile> _files = const [];
  TransferProgress? _transferProgress;
  TransferProgress? _remoteTransferProgress;
  Map<String, TransferProgress> _transfers = {};
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
      _transfers = Map.of(serverService?.allTransfers ?? {});
      _allTransfersSub =
          serverService?.allTransfersStream.listen(_onAllTransfersChanged);
    } else {
      _transferProgress = widget.fileShareService?.currentProgress;
      _progressSub =
          widget.fileShareService?.progressStream.listen(_onProgressChanged);
      _transfers = Map.of(widget.fileShareService?.allTransfers ?? {});
      _allTransfersSub = widget.fileShareService?.allTransfersStream
          .listen(_onAllTransfersChanged);
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
      _allTransfersSub?.cancel();
      if (widget.isWindows) {
        _files = widget.serverService?.sharedFiles ?? const [];
        _fileSub =
            widget.serverService?.sharedFilesStream.listen(_onFilesChanged);
        _transferProgress = widget.serverService?.currentTransferProgress;
        _progressSub = widget.serverService?.transferProgressStream
            .listen(_onProgressChanged);
        _transfers = Map.of(widget.serverService?.allTransfers ?? {});
        _allTransfersSub = widget.serverService?.allTransfersStream
            .listen(_onAllTransfersChanged);
      } else {
        _transferProgress = widget.fileShareService?.currentProgress;
        _progressSub =
            widget.fileShareService?.progressStream.listen(_onProgressChanged);
        _transfers = Map.of(widget.fileShareService?.allTransfers ?? {});
        _allTransfersSub = widget.fileShareService?.allTransfersStream
            .listen(_onAllTransfersChanged);
        _refreshFiles();
        _startRemoteProgressPolling();
      }
    }
  }

  @override
  void dispose() {
    _fileSub?.cancel();
    _progressSub?.cancel();
    _allTransfersSub?.cancel();
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
        if (progress != null) {
          _transfers[progress.fileId] = progress;
        }
      });
    }
  }

  void _onAllTransfersChanged(Map<String, TransferProgress> map) {
    if (mounted) {
      setState(() {
        _transfers = Map.of(map);
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
      if (transfers.isNotEmpty) {
        setState(() {
          for (final t in transfers) {
            final local = _transfers[t.fileId];
            if (local == null ||
                (local.status != TransferStatus.transferring &&
                    local.status != TransferStatus.resuming &&
                    local.status != TransferStatus.verifying)) {
              _transfers[t.fileId] = t;
            }
          }
        });

        // Auto-pull any PC-queued files
        final hasQueuedFromPC = transfers.any((t) =>
            t.status == TransferStatus.queued &&
            t.isUpload &&
            (!_transfers.containsKey(t.fileId) ||
                _transfers[t.fileId]?.status == TransferStatus.queued));
        if (hasQueuedFromPC) {
          unawaited(service.syncPendingDownloads(remoteTransfers: transfers));
        }
      }

      // Check if any transfer is not in _files, and refresh _files if needed
      final knownFileIds = _files.map((f) => f.id).toSet();
      final hasUnknownFiles =
          transfers.any((t) => !knownFileIds.contains(t.fileId));
      if (hasUnknownFiles || _files.isEmpty) {
        final updatedFiles = await service.listSharedFiles();
        if (mounted && updatedFiles.isNotEmpty) {
          setState(() {
            _files = updatedFiles;
          });
        }
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

  List<TransferProgress> get _activeOrRecentTransfers {
    if (_transfers.isEmpty) {
      final vis = _visibleTransferProgress;
      return vis != null ? [vis] : const [];
    }
    final list = _transfers.values.toList();
    list.sort((a, b) {
      int score(TransferProgress p) {
        if (p.status == TransferStatus.transferring ||
            p.status == TransferStatus.resuming ||
            p.status == TransferStatus.verifying ||
            p.status == TransferStatus.finalizing) {
          return 0;
        }
        if (p.status == TransferStatus.preparing) return 1;
        if (p.status == TransferStatus.queued) return 2;
        if (p.status == TransferStatus.paused) return 3;
        if (p.status == TransferStatus.completed) return 4;
        return 5;
      }

      final sA = score(a);
      final sB = score(b);
      if (sA != sB) return sA.compareTo(sB);
      return b.timestamp.compareTo(a.timestamp);
    });
    return list;
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

  /// Windows: pick local files and share them instantly with immediate card creation.
  Future<void> _pickAndShareWindows() async {
    final serverService = widget.serverService;
    if (serverService == null) return;

    setState(() {
      _busy = true;
      _busyLabel = 'Opening file picker...';
    });
    await Future<void>.delayed(Duration.zero);
    try {
      final files = await FilePicker.pickFiles();
      if (files.isEmpty) return;
      if (mounted) setState(() => _busyLabel = 'Enqueuing selected files...');

      final validPaths = files
          .map((f) => f.path)
          .whereType<String>()
          .where((p) => p.isNotEmpty)
          .toList();

      if (validPaths.isEmpty) return;

      final enqueued = await serverService.enqueueLocalSharedFiles(
        sourcePaths: validPaths,
        deviceName: 'Windows PC',
      );

      if (mounted) {
        _showSnack(
          enqueued.isNotEmpty
              ? 'Added ${enqueued.length} file(s) for immediate sharing.'
              : 'No files were added.',
          isError: enqueued.isEmpty,
        );
      }
    } catch (e) {
      if (mounted) _showSnack('File selection error: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyLabel = null;
        });
      }
    }
  }

  /// Android: pick local files and immediately enqueue them for streaming upload to PC.
  Future<void> _pickAndSendFiles() async {
    final service = widget.fileShareService;
    if (service == null) {
      _showSnack(
        'PC link is not ready yet. Start DeskPocket on your PC first.',
        isError: true,
      );
      return;
    }

    setState(() {
      _busy = true;
      _busyLabel = 'Opening file picker...';
    });
    await Future<void>.delayed(Duration.zero);
    try {
      final files = await FilePicker.pickFiles();
      if (files.isEmpty) return;
      if (mounted) setState(() => _busyLabel = 'Enqueuing files for upload...');

      final validPaths = files
          .map((f) => f.path)
          .whereType<String>()
          .where((p) => p.isNotEmpty)
          .toList();

      if (validPaths.isEmpty) return;

      service.enqueueUploadFiles(validPaths);

      if (mounted) {
        _showSnack(
          'Enqueued ${validPaths.length} file(s) for immediate transfer.',
        );
      }
    } catch (e) {
      if (mounted) _showSnack('File selection error: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyLabel = null;
        });
      }
    }
  }

  /// Android: download a shared file from the PC into the phone's Downloads.
  Future<void> _downloadFile(SharedFile file) async {
    final service = widget.fileShareService;
    if (service == null) return;

    setState(() => _downloadingId = file.id);
    final results = await service.enqueueDownloadFiles([file]);
    final dest = results.isNotEmpty ? results.first : null;
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

  /// Open file with default system application
  Future<void> _openFile(SharedFile file) async {
    final path = file.filePath;
    if (path == null) {
      _showSnack('File path is unavailable.', isError: true);
      return;
    }
    try {
      if (!kIsWeb && Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', path]);
      }
    } catch (e) {
      _showSnack('Could not open file: $e', isError: true);
    }
  }

  /// Reveal file in Windows Explorer
  Future<void> _showInFolder(SharedFile file) async {
    final path = file.filePath;
    if (path == null) {
      _showSnack('File path is unavailable.', isError: true);
      return;
    }
    try {
      if (!kIsWeb && Platform.isWindows) {
        await Process.run('explorer.exe', ['/select,', path]);
      }
    } catch (e) {
      _showSnack('Could not show in folder: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final activeTransfers = _activeOrRecentTransfers;

    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(18),
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
            title: 'FILE SHARING',
            subtitle: 'Send and receive files directly between your devices',
            trailing: _files.isEmpty
                ? null
                : StatusBadge(
                    label: '${_files.length} Shared',
                    isActive: true,
                    activeColor: colors.accentPurple,
                  ),
          ),
          const SizedBox(height: 16),

          // Live Real-Time Transfer Indicator Panel(s)
          if (activeTransfers.isNotEmpty) ...[
            _buildLiveTransfersSection(activeTransfers, colors),
            const SizedBox(height: 16),
          ] else if (_visibleTransferProgress != null) ...[
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

  /// Displays all active and recent transfers
  Widget _buildLiveTransfersSection(
    List<TransferProgress> transfers,
    AppThemeColors colors,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (transfers.length > 1) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 4),
            child: Row(
              children: [
                Icon(
                  Icons.swap_vert_rounded,
                  size: 15,
                  color: colors.primaryLight,
                ),
                const SizedBox(width: 6),
                Text(
                  'ACTIVE TRANSFERS (${transfers.length})',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
        for (int i = 0; i < transfers.length; i++) ...[
          _buildLiveTransferPanel(transfers[i], colors),
          if (i < transfers.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }

  /// Dedicated real-time file transfer progress card with dual sender/receiver tracking
  Widget _buildLiveTransferPanel(
    TransferProgress progress,
    AppThemeColors colors,
  ) {
    final isUpload = progress.isUpload;
    final isDone = progress.status == TransferStatus.completed;
    final isFailed = progress.status == TransferStatus.failed;
    final isCancelled = progress.status == TransferStatus.cancelled;
    final isQueued = progress.status == TransferStatus.queued;
    final isPaused = progress.status == TransferStatus.paused;
    final inProgress = progress.isActive;

    final themeColor = isDone
        ? colors.success
        : (isFailed || isCancelled
            ? AppColors.error
            : (isPaused
                ? colors.accentWarm
                : (isQueued ? colors.textMuted : colors.primaryLight)));

    final actionLabel = () {
      switch (progress.status) {
        case TransferStatus.idle:
          return 'Idle';
        case TransferStatus.queued:
          return 'Queued in transfer line';
        case TransferStatus.preparing:
          return 'Preparing transfer metadata';
        case TransferStatus.connecting:
          return 'Connecting to peer';
        case TransferStatus.paused:
          return 'Transfer paused / reconnecting';
        case TransferStatus.resuming:
          return 'Resuming from verified offset';
        case TransferStatus.verifying:
          return 'Verifying chunk integrity';
        case TransferStatus.finalizing:
          return 'Finalizing destination file';
        case TransferStatus.completed:
          return 'Transfer complete';
        case TransferStatus.failed:
          return 'Transfer failed';
        case TransferStatus.cancelled:
          return 'Transfer cancelled';
        case TransferStatus.transferring:
        case TransferStatus.inProgress:
          return isUpload
              ? (widget.isWindows ? 'Sending to Phone' : 'Sending to PC')
              : (widget.isWindows
                  ? 'Receiving from Phone'
                  : 'Receiving from PC');
      }
    }();

    final statusBadgeLabel = () {
      switch (progress.status) {
        case TransferStatus.idle:
          return 'IDLE';
        case TransferStatus.queued:
          return 'QUEUED';
        case TransferStatus.preparing:
          return 'PREPARING';
        case TransferStatus.connecting:
          return 'CONNECTING';
        case TransferStatus.paused:
          return 'PAUSED';
        case TransferStatus.resuming:
          return 'RESUMING';
        case TransferStatus.verifying:
          return 'VERIFYING';
        case TransferStatus.finalizing:
          return 'FINALIZING';
        case TransferStatus.completed:
          return '100% DONE';
        case TransferStatus.failed:
          return 'FAILED';
        case TransferStatus.cancelled:
          return 'CANCELLED';
        case TransferStatus.transferring:
        case TransferStatus.inProgress:
          return progress.percentageLabel;
      }
    }();

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
                      : (isQueued
                          ? Icons.hourglass_top_rounded
                          : (isUpload
                              ? Icons.cloud_upload_rounded
                              : Icons.cloud_download_rounded)),
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
                  statusBadgeLabel,
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

          // Dual Progress Bar: background is sender read/buffer, foreground is receiver confirmed
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 7,
              child: Stack(
                children: [
                  Container(color: colors.surface),
                  if (!isQueued) ...[
                    // Sender progress (buffer)
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: isDone
                          ? 1.0
                          : progress.senderFraction.clamp(0.0, 1.0),
                      child: Container(
                        color: themeColor.withValues(alpha: 0.35),
                      ),
                    ),
                    // Receiver progress (confirmed to disk)
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: isDone
                          ? 1.0
                          : progress.receiverFraction.clamp(0.0, 1.0),
                      child: Container(
                        color: themeColor,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Dual progress percentage indicator
          if (progress.totalBytes > 0 && !isQueued) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Sender: ${progress.senderPercentageLabel}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: themeColor.withValues(alpha: 0.8),
                  ),
                ),
                Text(
                  'Receiver: ${progress.receiverPercentageLabel}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: themeColor,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),

          // Details Row (Wrap for responsiveness)
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
                              : (isQueued
                                  ? Icons.hourglass_top_rounded
                                  : Icons.hourglass_bottom_rounded),
                          size: 13,
                          color: isDone ? colors.success : colors.textMuted,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            isDone
                                ? 'Finished'
                                : (isQueued
                                    ? 'Waiting in queue'
                                    : (isFailed
                                        ? (progress.errorMessage ?? 'Failed')
                                        : progress.remainingLabel)),
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

          // Cancel Button for active or queued transfer
          if ((inProgress || isQueued) &&
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
          if (widget.isWindows) ...[
            if (file.filePath != null) ...[
              Tooltip(
                message: 'Open file',
                child: IconButton(
                  onPressed: _busy ? null : () => _openFile(file),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  color: colors.primaryLight,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              Tooltip(
                message: 'Show in folder',
                child: IconButton(
                  onPressed: _busy ? null : () => _showInFolder(file),
                  icon: const Icon(Icons.folder_open_rounded, size: 18),
                  color: colors.textSecondary,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
            Tooltip(
              message: 'Remove',
              child: IconButton(
                onPressed: _busy ? null : () => _stopSharing(file),
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                color: colors.textMuted,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ] else ...[
            Builder(
              builder: (context) {
                final tx = _transfers[file.id];
                final isTxDownloading = isDownloadingThis ||
                    (tx != null &&
                        (tx.status == TransferStatus.transferring ||
                            tx.status == TransferStatus.resuming ||
                            tx.status == TransferStatus.verifying ||
                            tx.status == TransferStatus.preparing));
                final isTxQueued =
                    tx != null && tx.status == TransferStatus.queued;
                final isTxCompleted =
                    tx != null && tx.status == TransferStatus.completed;

                if (isTxDownloading) {
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.primaryLight,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        tx?.percentageLabel ?? '...',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: colors.primaryLight,
                        ),
                      ),
                    ],
                  );
                } else if (isTxQueued) {
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: colors.textMuted.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.hourglass_top_rounded,
                          size: 13,
                          color: colors.textMuted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Queued',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: colors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  );
                } else if (isTxCompleted) {
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: colors.success.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle_rounded,
                          size: 13,
                          color: colors.success,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Saved',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: colors.success,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return OutlinedButton.icon(
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
                );
              },
            ),
          ],
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
                ? 'Files are shared with your phone while the PC Link Service is running. Transfer progress updates live.'
                : 'Files transfer directly between your phone and PC. Progress, speed, and status update in real time.',
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
