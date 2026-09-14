import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/universal/bounceable.dart';
import '../../../../data/services/windows_permission_service.dart';

/// Clean, cute, and premium one-time permission setup dialog for Windows.
/// Ensures all firewall and network permissions for PCLink are configured
/// upfront so users never experience permission interruptions while working.
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

  Future<void> _handleGrantPermissions() async {
    HapticFeedback.mediumImpact();
    setState(() {
      _isConfiguring = true;
      _errorMessage = null;
    });

    final success = await WindowsPermissionService.requestAllPermissions();

    if (!mounted) return;

    if (success) {
      setState(() {
        _isConfiguring = false;
        _isSuccess = true;
      });
      HapticFeedback.lightImpact();
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (mounted) {
          widget.onPermissionsGranted();
        }
      });
    } else {
      setState(() {
        _isConfiguring = false;
        _errorMessage =
            'Permission setup was not completed. You can grant PCLink permissions later in settings.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 520),
          child: Container(
            decoration: BoxDecoration(
              color: colors.cardSurface,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: colors.cardBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: context.isDark ? 0.35 : 0.12),
                  blurRadius: 28,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
            child: SingleChildScrollView(
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
                        Icons.verified_user_rounded,
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
                            'Welcome to PCLink',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: colors.textPrimary,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'One-Time Network Permission Setup',
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 18),

                Text(
                  'To ensure fast file sharing, real-time clipboard sync, and phone connectivity work smoothly without Windows Firewall interruptions while you work, let\'s configure PCLink permissions now.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: colors.textSecondary,
                  ),
                ),

                const SizedBox(height: 18),

                // 3 Benefit items
                _buildPermissionItem(
                  icon: Icons.wifi_rounded,
                  title: 'PCLink Local Sync',
                  description: 'Enables your phone and PC to discover each other seamlessly on Wi-Fi.',
                  accentColor: AppColors.secondary,
                  colors: colors,
                ),
                const SizedBox(height: 10),
                _buildPermissionItem(
                  icon: Icons.cloud_done_rounded,
                  title: 'PCLink Network Relay',
                  description: 'Enables secure encrypted transfers and controls across mobile networks.',
                  accentColor: AppColors.primary,
                  colors: colors,
                ),
                const SizedBox(height: 10),
                _buildPermissionItem(
                  icon: Icons.shield_rounded,
                  title: 'PCLink Firewall Authorization',
                  description: 'Registers rules once upfront so you never get prompted while working.',
                  accentColor: AppColors.accentWarm,
                  colors: colors,
                ),

                if (_errorMessage != null) ...[
                  const SizedBox(height: 14),
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
                  const SizedBox(height: 14),
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
                          'PCLink is fully authorized!',
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

                const SizedBox(height: 22),

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
                            : const Icon(Icons.security_rounded, size: 18),
                        label: Text(
                          _isConfiguring ? 'Configuring PCLink...' : 'Grant PCLink Permissions',
                          style: const TextStyle(fontWeight: FontWeight.w700),
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
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: const Text('Maybe Later', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

  Widget _buildPermissionItem({
    required IconData icon,
    required String title,
    required String description,
    required Color accentColor,
    required AppThemeColors colors,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.cardBorder.withValues(alpha: 0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: accentColor, size: 16),
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
        ],
      ),
    );
  }
}
