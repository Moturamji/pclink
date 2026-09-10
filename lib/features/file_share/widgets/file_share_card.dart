import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/universal/app_card_header.dart';
import '../../../data/services/file_share_service.dart';
import '../../../data/services/server_service.dart';
import '../models/shared_file.dart';

/// Card managing bidirectional file sharing between the Windows PC and the
/// Android phone through the existing temporary server - zero cloud storage.
///
/// - Windows: pick PC files to publish for download + watch phone uploads.
/// - Android: send files to the PC + download files shared by the PC.
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
  List<SharedFile> _files = const [];
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
    } else {
      _refreshFiles();
    }
  }

  @override
  void dispose() {
    _fileSub?.cancel();
    super.dispose();
  }

  void _onFilesChanged(List<SharedFile> files) {
    if (mounted) {
      setState(() {
        _files = files;
      });
    }
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

    final files = await FilePicker.pickFiles();
    if (files.isEmpty) return;

    setState(() {
      _busy = true;
      _busyLabel = 'Copying into shared folder...';
    });

    var added = 0;
    for (final f in files) {
      if (f.path == null) continue;
      final item = await serverService.addLocalSharedFile(
        sourcePath: f.path!,
        deviceName: 'Windows PC',
      );
      if (item != null) added++;
    }

    if (!mounted) return;
    setState(() {
      _busy = false;
      _busyLabel = null;
    });
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

    final files = await FilePicker.pickFiles();
    if (files.isEmpty) return;

    setState(() {
      _busy = true;
      _busyLabel = 'Preparing files...';
    });

    var sent = 0;
    for (final f in files) {
      if (f.path == null) continue;
      setState(() => _busyLabel = 'Sending ${f.name}...');
      if (await service.uploadFile(f.path!)) sent++;
    }

    if (!mounted) return;
    setState(() {
      _busy = false;
      _busyLabel = null;
    });
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppCardHeader(
              icon: Icons.folder_shared_rounded,
              iconColor: AppColors.secondaryLight,
              title: 'SHARE FILES',
              trailing: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.secondary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppColors.secondary.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Text(
                        '${_files.length}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.successLight,
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 12),
            if (widget.isWindows)
              _buildWindowsPanel()
            else
              _buildAndroidPanel(),
            const SizedBox(height: 12),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildWindowsPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Share files from this PC with your phone, or receive files sent '
          'from the phone - all over the temporary server.',
          style: TextStyle(
            fontSize: 12,
            height: 1.4,
            color: AppColors.textSecondary,
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
                  backgroundColor: AppColors.secondary,
                  foregroundColor: AppColors.background,
                  elevation: 2,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          _files.isEmpty
              ? 'Nothing is being shared yet.'
              : 'Currently shared (${_files.length})',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        if (_files.isEmpty)
          _emptyState(
            icon: Icons.folder_open_rounded,
            title: 'No shared files',
            subtitle:
                'Tap "Add Files to Share" to make PC files downloadable '
                'from your phone. Files sent from the phone appear here too.',
          )
        else
          ..._files.take(6).map(_buildFileTile),
      ],
    );
  }

  Widget _buildAndroidPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Send files from this phone straight to your PC, or download files '
          'shared from the PC - over the temporary server, never via the cloud.',
          style: TextStyle(
            fontSize: 12,
            height: 1.4,
            color: AppColors.textSecondary,
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
                  backgroundColor: AppColors.secondary,
                  foregroundColor: AppColors.background,
                  elevation: 2,
                ),
              ),
            ),
            const SizedBox(width: 10),
            IconButton(
              onPressed: _busy ? null : _refreshFiles,
              tooltip: 'Refresh file list from PC',
              icon: const Icon(Icons.refresh_rounded, size: 20),
              color: AppColors.textSecondary,
              style: IconButton.styleFrom(
                backgroundColor: AppColors.surface,
                side: const BorderSide(color: AppColors.cardBorder),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          _files.isEmpty
              ? 'Shared files from your PC'
              : 'Files available from your PC (${_files.length})',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        if (_files.isEmpty)
          _emptyState(
            icon: Icons.download_for_offline_rounded,
            title: 'Nothing shared yet',
            subtitle:
                'Files you add here are sent instantly to your PC. '
                'Files shared from the PC can be downloaded with one tap.',
          )
        else
          ..._files.take(6).map(_buildFileTile),
      ],
    );
  }

  Widget _buildFileTile(SharedFile file) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: file.isFromAndroid
                  ? AppColors.primaryLight.withValues(alpha: 0.12)
                  : AppColors.secondary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _iconFor(file.name),
              size: 18,
              color: file.isFromAndroid
                  ? AppColors.primaryLight
                  : AppColors.successLight,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${file.sizeLabel}  •  ${file.isFromAndroid ? 'From phone' : 'From PC'}  •  ${_timeLabel(file.timestamp)}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
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
              color: AppColors.textMuted,
            )
          else if (_downloadingId == file.id)
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
                foregroundColor: AppColors.successLight,
                side: BorderSide(
                  color: AppColors.success.withValues(alpha: 0.4),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
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
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        children: [
          Icon(icon, size: 26, color: AppColors.textMuted),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.shield_outlined, size: 15, color: AppColors.textMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            widget.isWindows
                ? 'Files are copied to the shared folder and served to your phone only while the PC Link Service is active. Your phone also sees files it uploaded here.'
                : 'Transfers are direct between this phone and your PC via the temporary server - files never touch Firebase or any cloud storage.',
            style: const TextStyle(
              fontSize: 11,
              height: 1.4,
              color: AppColors.textMuted,
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
