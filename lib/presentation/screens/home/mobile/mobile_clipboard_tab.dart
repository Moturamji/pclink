import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../../data/services/database_service.dart';
import '../../../../features/clipboard/services/clipboard_service.dart';
import '../../../../features/clipboard/widgets/clipboard_sync_card.dart';

class MobileClipboardTab extends StatelessWidget {
  final bool isWindows;
  final User? user;
  final DatabaseService databaseService;
  final ClipboardService clipboardService;

  const MobileClipboardTab({
    super.key,
    required this.isWindows,
    this.user,
    required this.databaseService,
    required this.clipboardService,
  });

  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return const Center(
        child: Text('Sign in to access real-time clipboard sync.'),
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
      children: [
        ClipboardSyncCard(
          isWindows: isWindows,
          user: user!,
          databaseService: databaseService,
          clipboardService: clipboardService,
        ),
      ],
    );
  }
}
