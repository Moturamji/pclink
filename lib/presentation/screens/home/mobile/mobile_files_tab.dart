import 'package:flutter/material.dart';
import '../../../../data/services/file_share_service.dart';
import '../../../../data/services/server_service.dart';
import '../../../../features/file_share/widgets/file_share_card.dart';

class MobileFilesTab extends StatelessWidget {
  final bool isWindows;
  final ServerService? serverService;
  final FileShareService? fileShareService;

  const MobileFilesTab({
    super.key,
    required this.isWindows,
    this.serverService,
    this.fileShareService,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
      children: [
        FileShareCard(
          isWindows: isWindows,
          serverService: isWindows ? serverService : null,
          fileShareService: isWindows ? null : fileShareService,
        ),
      ],
    );
  }
}
