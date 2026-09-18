import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/universal/app_card_header.dart';
import '../../../../core/widgets/universal/status_badge.dart';
import '../../../../data/services/windows_autostart_service.dart';

/// Card showing live Windows system integration settings:
/// - Windows Startup (Silent background with no UI)
class WindowsSystemCard extends StatefulWidget {
  const WindowsSystemCard({super.key});

  @override
  State<WindowsSystemCard> createState() => _WindowsSystemCardState();
}

class _WindowsSystemCardState extends State<WindowsSystemCard> with WidgetsBindingObserver {
  bool _isAutostartEnabled = false;
  bool _isTogglingAutostart = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isAutostartEnabled = WindowsAutostartService.autostartNotifier.value;
    WindowsAutostartService.autostartNotifier.addListener(_onAutostartChanged);
    _loadStatus();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadStatus();
    }
  }

  void _onAutostartChanged() {
    if (mounted) {
      setState(() => _isAutostartEnabled = WindowsAutostartService.autostartNotifier.value);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WindowsAutostartService.autostartNotifier.removeListener(_onAutostartChanged);
    super.dispose();
  }

  Future<void> _loadStatus() async {
    if (kIsWeb || !Platform.isWindows) {
      return;
    }

    final autostart = await WindowsAutostartService.isAutostartEnabled();

    if (mounted) {
      setState(() {
        _isAutostartEnabled = autostart;
      });
    }
  }

  Future<void> _toggleAutostart(bool value) async {
    setState(() => _isTogglingAutostart = true);
    HapticFeedback.selectionClick();
    await WindowsAutostartService.setAutostartEnabled(value);
    if (mounted) {
      setState(() => _isTogglingAutostart = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || !Platform.isWindows) return const SizedBox.shrink();

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
            icon: Icons.laptop_windows_rounded,
            iconColor: const Color(0xFF6366F1),
            title: 'Windows System Integration',
            subtitle: 'Startup & Background Services',
            trailing: StatusBadge(
              label: _isAutostartEnabled ? 'Autostart Active' : 'Manual Launch',
              isActive: _isAutostartEnabled,
              activeColor: const Color(0xFF10B981),
            ),
          ),
          const SizedBox(height: 18),

          // Autostart on boot row
          _buildFeatureToggleRow(
            icon: Icons.power_settings_new_rounded,
            accentColor: const Color(0xFF6366F1),
            title: 'Auto-Start on Boot (Background)',
            subtitle:
                'Boots silently with Windows without UI. Clipboard, file transfer, and screen mirroring run instantly.',
            isEnabled: _isAutostartEnabled,
            isOperating: _isTogglingAutostart,
            onChanged: _toggleAutostart,
            colors: colors,
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureToggleRow({
    required IconData icon,
    required Color accentColor,
    required String title,
    required String subtitle,
    required bool isEnabled,
    required bool isOperating,
    required ValueChanged<bool> onChanged,
    required AppThemeColors colors,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Icon(icon, size: 18, color: accentColor),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: colors.textMuted,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        if (isOperating)
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          Switch(
            value: isEnabled,
            onChanged: onChanged,
            activeTrackColor: accentColor.withValues(alpha: 0.5),
            activeThumbColor: accentColor,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
      ],
    );
  }
}
