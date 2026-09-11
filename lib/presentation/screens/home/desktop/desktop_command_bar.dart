import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/universal/hoverable.dart';
import '../../../../data/models/server_info.dart';

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
          bottom: BorderSide(
            color: colors.cardBorder,
            width: 1,
          ),
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
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: colors.textPrimary,
                  letterSpacing: -0.2,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: colors.textMuted,
                ),
              ),
            ],
          ),

          const Spacer(),

          // Public Tunnel Pill (if live)
          if (isLive && publicUrl != null && publicUrl.isNotEmpty) ...[
            Hoverable(
              onTap: () {
                Clipboard.setData(ClipboardData(text: publicUrl));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Public Tunnel URL copied!'),
                    backgroundColor: colors.cardSurface,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: colors.primary.withValues(alpha: 0.3),
                  ),
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
                      'Cloudflare Tunnel',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: colors.primaryLight,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.copy_rounded,
                      size: 12,
                      color: colors.textMuted,
                    ),
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: colors.cardBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.folder_open_rounded,
                    size: 14,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Open Downloads',
                    style: TextStyle(
                      fontSize: 11,
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
