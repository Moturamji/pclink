import 'package:flutter/material.dart';
import '../../../../data/services/file_share_service.dart';
import '../../../../data/services/server_service.dart';
import '../../../../features/file_share/widgets/file_share_card.dart';

class DesktopFilesTab extends StatelessWidget {
  final bool isWindows;
  final ServerService? serverService;
  final FileShareService? fileShareService;

  const DesktopFilesTab({
    super.key,
    required this.isWindows,
    this.serverService,
    this.fileShareService,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: FileShareCard(
            isWindows: isWindows,
            serverService: serverService,
            fileShareService: fileShareService,
          ),
        ),
      ),
    );
  }
}
