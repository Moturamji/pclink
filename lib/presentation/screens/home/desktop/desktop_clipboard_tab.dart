import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../../data/services/database_service.dart';
import '../../../../features/clipboard/services/clipboard_service.dart';
import '../../../../features/clipboard/widgets/clipboard_sync_card.dart';

class DesktopClipboardTab extends StatelessWidget {
  final bool isWindows;
  final User? user;
  final DatabaseService databaseService;
  final ClipboardService clipboardService;

  const DesktopClipboardTab({
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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: ClipboardSyncCard(
            isWindows: isWindows,
            user: user!,
            databaseService: databaseService,
            clipboardService: clipboardService,
          ),
        ),
      ),
    );
  }
}
