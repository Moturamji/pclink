import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../data/services/screen_share_service.dart';

/// Windows dashboard-only privacy control for live screen sharing.
class ScreenShareStatusCard extends StatefulWidget {
  final ScreenShareService service;

  const ScreenShareStatusCard({super.key, required this.service});

  @override
  State<ScreenShareStatusCard> createState() => _ScreenShareStatusCardState();
}

class _ScreenShareStatusCardState extends State<ScreenShareStatusCard> {
  StreamSubscription<ScreenShareStatus>? _subscription;
  ScreenShareStatus? _status;
  bool _allowed = false;

  @override
  void initState() {
    super.initState();
    _status = widget.service.status;
    _allowed = ScreenShareService.consentNotifier.value;
    ScreenShareService.consentNotifier.addListener(_onConsentChanged);
    _subscription = widget.service.statusStream.listen((status) {
      if (mounted) setState(() => _status = status);
    });
    _loadConsent();
  }

  void _onConsentChanged() {
    if (mounted) setState(() => _allowed = ScreenShareService.consentNotifier.value);
  }

  Future<void> _loadConsent() async {
    final allowed = await ScreenShareService.isConsentGranted();
    if (mounted) setState(() => _allowed = allowed);
  }

  Future<void> _setAllowed(bool allowed) async {
    await ScreenShareService.setConsentGranted(allowed);
    if (!allowed) await widget.service.stop();
  }

  @override
  void dispose() {
    ScreenShareService.consentNotifier.removeListener(_onConsentChanged);
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final active = _status?.enabled == true;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: active ? colors.success.withValues(alpha: 0.10) : colors.cardSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: active ? colors.success.withValues(alpha: 0.45) : colors.cardBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                active ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                color: active ? colors.success : colors.textSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  active ? 'Screen mirroring is active' : 'Screen Mirroring (Phone View)',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              Switch(value: _allowed, onChanged: _setAllowed),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            active
                ? '${_status?.viewerName ?? 'A linked phone'} can view this PC screen. View-only; no remote control is enabled.'
                : 'Allow your linked phone to view your PC screen in real time. View-only; no touch or mouse control.',
            style: TextStyle(color: colors.textSecondary, height: 1.4),
          ),
          if (active) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: widget.service.stop,
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('Stop sharing now'),
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
            ),
          ],
        ],
      ),
    );
  }
}
