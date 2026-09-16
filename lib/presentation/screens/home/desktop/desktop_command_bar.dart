import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/universal/bounceable.dart';
import '../../../../core/widgets/universal/hoverable.dart';
import '../../../../data/models/server_info.dart';

/// Top desktop command bar with contextual title, subtitle, and hardware quick actions.
class DesktopCommandBar extends StatelessWidget {
  final String title;
  final String subtitle;
  final ServerInfo? serverInfo;
  final bool isWindows;

  const DesktopCommandBar({
    super.key,
    required this.title,
    required this.subtitle,
    this.serverInfo,
    required this.isWindows,
  });

  Future<void> _openDownloadsFolder(BuildContext context) async {
    try {
      String? dirPath;
      if (!kIsWeb && Platform.isWindows) {
        final userProfile = Platform.environment['USERPROFILE'];
        if (userProfile != null && userProfile.isNotEmpty) {
          final candidate = Directory('$userProfile\\Downloads\\PCLink');
          if (await candidate.exists()) {
            dirPath = candidate.path;
          } else {
            dirPath = '$userProfile\\Downloads';
          }
        }
        if (dirPath != null) {
          await Process.run('explorer.exe', [dirPath]);
          return;
        }
      }
      dirPath ??= (await getDownloadsDirectory())?.path;

      if (context.mounted && dirPath != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Downloads located at: $dirPath'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open downloads folder: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isLive = serverInfo?.isLive == true;
    final publicUrl = serverInfo?.publicUrl;

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        border: Border(
          bottom: BorderSide(color: colors.cardBorder, width: 0.8),
        ),
      ),
      child: Row(
        children: [
          // Title and Subtitle
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: colors.textMuted,
                ),
              ),
            ],
          ),

          const Spacer(),

          // Public Tunnel Pill (if live)
          if (isLive && publicUrl != null && publicUrl.isNotEmpty) ...[
            Bounceable(
              onTap: () {
                Clipboard.setData(ClipboardData(text: publicUrl));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text(
                      'Public Tunnel URL copied to clipboard!',
                    ),
                    backgroundColor: colors.surface,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              scaleFactor: 0.96,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.cloud_done_rounded,
                      size: 14,
                      color: AppColors.primaryLight,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'PCLink Cloud Relay',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: colors.primaryLight,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.copy_rounded, size: 11, color: colors.textMuted),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],

          // Quick Action: Open Downloads
          Hoverable(
            onTap: () => _openDownloadsFolder(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: colors.surfaceSubtle,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.folder_open_rounded,
                    size: 15,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Open Downloads',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
