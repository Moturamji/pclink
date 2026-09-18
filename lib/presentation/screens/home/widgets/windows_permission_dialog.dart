import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/universal/bounceable.dart';
import '../../../../data/services/screen_share_service.dart';
import '../../../../data/services/windows_autostart_service.dart';
import '../../../../data/services/windows_permission_service.dart';

/// Clean, cute, and premium one-time permission setup dialog for Windows.
/// Asks upfront permission with recommended options enabled by default (Autostart, Screen Mirror,
/// and Windows Firewall rules) and applies them directly to the Windows system.
class WindowsPermissionDialog extends StatefulWidget {
  final VoidCallback onDismiss;
  final VoidCallback onPermissionsGranted;

  const WindowsPermissionDialog({
    super.key,
    required this.onDismiss,
    required this.onPermissionsGranted,
  });

  @override
  State<WindowsPermissionDialog> createState() => _WindowsPermissionDialogState();
}

class _WindowsPermissionDialogState extends State<WindowsPermissionDialog> {
  bool _isConfiguring = false;
  bool _isSuccess = false;
  String? _errorMessage;

  // Options enabled by default on fresh setup, detected from system
  bool _autoStartOnBoot = true;
  bool _screenMirrorEnabled = true;
  bool _firewallRulesEnabled = true;

  @override
  void initState() {
    super.initState();
    _detectSystemState();
  }

  Future<void> _detectSystemState() async {
    final autostartRegistered = await WindowsAutostartService.isAutostartEnabled();
    final hasScreenConsent = await ScreenShareService.hasConsentPreference();
    final screenConsent = await ScreenShareService.isConsentGranted();
    final completed = await WindowsPermissionService.hasCompletedPermissionSetup();

    if (mounted) {
      setState(() {
        if (completed || hasScreenConsent) {
          _autoStartOnBoot = autostartRegistered;
          _screenMirrorEnabled = screenConsent;
        } else {
          _autoStartOnBoot = true;
          _screenMirrorEnabled = true;
        }
      });
    }
  }

  Future<void> _handleGrantPermissions() async {
    HapticFeedback.mediumImpact();
    setState(() {
      _isConfiguring = true;
      _errorMessage = null;
    });

    try {
      // 1. Configure system autostart directly in Windows Registry
      await WindowsAutostartService.setAutostartEnabled(_autoStartOnBoot);

      // 2. Configure screen mirror consent in system persistence & engine
      await ScreenShareService.setConsentGranted(_screenMirrorEnabled);

      // 3. Configure Windows firewall rules if selected
      if (_firewallRulesEnabled) {
        await WindowsPermissionService.requestAllPermissions();
      }

      // Mark setup as completed in persistence
      await WindowsPermissionService.markPermissionSetupCompleted();

      if (!mounted) return;

      setState(() {
        _isConfiguring = false;
        _isSuccess = true;
      });
      HapticFeedback.lightImpact();

      Future.delayed(const Duration(milliseconds: 1000), () {
        if (mounted) {
          widget.onPermissionsGranted();
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isConfiguring = false;
        _errorMessage = 'Configuration error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
          child: Container(
            decoration: BoxDecoration(
              color: colors.cardSurface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: colors.cardBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: context.isDark ? 0.4 : 0.15),
                  blurRadius: 32,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header: Icon + Title
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.25),
                          width: 1.5,
                        ),
                      ),
                      child: const Icon(
                        Icons.settings_suggest_rounded,
                        color: AppColors.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'PCLink System Setup',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: colors.textPrimary,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Recommended features are pre-selected for optimal experience',
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Scrollable Feature Selection List
                Flexible(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildOptionTile(
                          icon: Icons.power_settings_new_rounded,
                          title: 'Auto-Start on Windows Boot (Background)',
                          description:
                              'Launches silently in the background on startup with zero UI. Open PCLink anytime to see live status.',
                          accentColor: const Color(0xFF6366F1),
                          value: _autoStartOnBoot,
                          onChanged: (val) => setState(() => _autoStartOnBoot = val),
                          colors: colors,
                        ),
                        const SizedBox(height: 10),
                        _buildOptionTile(
                          icon: Icons.screenshot_monitor_rounded,
                          title: 'Real-Time Screen Mirroring',
                          description:
                              'Allows your connected phone to view your PC screen in ultra-low latency with hardware capture.',
                          accentColor: const Color(0xFF10B981),
                          value: _screenMirrorEnabled,
                          onChanged: (val) => setState(() => _screenMirrorEnabled = val),
                          colors: colors,
                        ),
                        const SizedBox(height: 10),
                        _buildOptionTile(
                          icon: Icons.security_rounded,
                          title: 'Windows Firewall & Network Rules',
                          description:
                              'Configures Port 8088 & Relay rules once upfront so Windows Firewall never interrupts you.',
                          accentColor: const Color(0xFFF59E0B),
                          value: _firewallRulesEnabled,
                          onChanged: (val) => setState(() => _firewallRulesEnabled = val),
                          colors: colors,
                        ),
                      ],
                    ),
                  ),
                ),

                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(fontSize: 11, color: AppColors.error),
                    ),
                  ),
                ],

                if (_isSuccess) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_rounded, color: AppColors.success, size: 18),
                        SizedBox(width: 8),
                        Text(
                          'System configured successfully!',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.success,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 18),

                // Buttons
                if (!_isSuccess) ...[
                  Bounceable(
                    onTap: _isConfiguring ? null : _handleGrantPermissions,
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isConfiguring ? null : _handleGrantPermissions,
                        icon: _isConfiguring
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.check_circle_outline_rounded, size: 18),
                        label: Text(
                          _isConfiguring ? 'Applying System Settings...' : 'Enable Selected & Continue',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _isConfiguring ? null : widget.onDismiss,
                    style: TextButton.styleFrom(
                      foregroundColor: colors.textMuted,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    child: const Text('Skip for Now', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required String title,
    required String description,
    required Color accentColor,
    required bool value,
    required ValueChanged<bool> onChanged,
    required AppThemeColors colors,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: value
            ? accentColor.withValues(alpha: 0.06)
            : colors.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: value
              ? accentColor.withValues(alpha: 0.35)
              : colors.cardBorder.withValues(alpha: 0.6),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: accentColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.textMuted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: value,
            onChanged: _isConfiguring ? null : onChanged,
            activeTrackColor: accentColor.withValues(alpha: 0.5),
            activeThumbColor: accentColor,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}
