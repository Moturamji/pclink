import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/universal/app_logo.dart';
import '../../../core/widgets/universal/bounceable.dart';
import '../../../core/widgets/universal/theme_toggle_button.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/database_service.dart';
import '../../../data/services/device_service.dart';
import '../../../data/services/session_service.dart';
import '../home/home_screen.dart';
import 'widgets/auth_header.dart';
import 'widgets/forgot_password_dialog.dart';

/// Primary authentication screen managing Sign In and Sign Up on both platforms.
/// Responsive studio split-view on desktop and tactile ergonomic layout on mobile.
class AuthScreen extends StatefulWidget {
  final AuthService? authService;
  final DeviceService? deviceService;
  final DatabaseService? databaseService;
  final SessionService? sessionService;
  final String? sessionExpiredMessage;

  const AuthScreen({
    super.key,
    this.authService,
    this.deviceService,
    this.databaseService,
    this.sessionService,
    this.sessionExpiredMessage,
  });

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  late final AuthService _authService;
  late final DeviceService _deviceService;
  late final DatabaseService _databaseService;
  late final SessionService _sessionService;

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _isSignUp = false;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _errorMessage;

  bool get _isWindows => !kIsWeb && Platform.isWindows;

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? AuthService();
    _deviceService = widget.deviceService ?? DeviceService();
    _databaseService = widget.databaseService ?? DatabaseService();
    _sessionService = widget.sessionService ?? SessionService();
    _errorMessage = widget.sessionExpiredMessage;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      UserCredential userCred;
      if (_isSignUp) {
        userCred = await _authService.signUpWithEmailAndPassword(
          email: _emailController.text,
          password: _passwordController.text,
        );
      } else {
        userCred = await _authService.signInWithEmailAndPassword(
          email: _emailController.text,
          password: _passwordController.text,
        );
      }

      final user = userCred.user;
      if (user != null) {
        try {
          final details = await _deviceService.getDeviceDetails();
          final platformKey = details.isWindows ? 'windows' : 'android';
          await _sessionService.registerNewSession(
            user: user,
            platformKey: platformKey,
            deviceId: details.deviceId,
            databaseService: _databaseService,
          );
        } catch (sessionErr) {
          debugPrint('AuthScreen: session registration warning: $sessionErr');
        }
      }

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = AuthService.getErrorMessage(e);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final size = MediaQuery.sizeOf(context);
    final isDesktop = size.width >= 880;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: const [
          ThemeToggleButton(),
          SizedBox(width: 16),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: isDesktop ? 40.0 : 20.0,
              vertical: 20.0,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isDesktop ? 960 : 460,
              ),
              child: isDesktop
                  ? _buildDesktopSplitLayout(colors)
                  : _buildMobileLayout(colors),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopSplitLayout(AppThemeColors colors) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Left Column: Studio Brand Showcase
        Expanded(
          flex: 5,
          child: Padding(
            padding: const EdgeInsets.only(right: 48.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const AppLogo(
                      size: 48,
                      borderRadius: 14,
                      showGlow: true,
                      isAnimated: true,
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppStrings.appName,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                            color: colors.textPrimary,
                          ),
                        ),
                        Text(
                          'Seamless PC & Phone Link',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colors.primaryLight,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                Text(
                  'Unified PC & Android\nEcosystem.',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                    letterSpacing: -0.8,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Instantly sync your clipboard, share files of any size, and view your PC screen — all from your phone.',
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 32),
                _buildFeatureRow(
                  colors: colors,
                  icon: Icons.sync_alt_rounded,
                  title: 'Instant Clipboard Sync',
                  subtitle: 'Copy on one device, paste on the other',
                ),
                const SizedBox(height: 16),
                _buildFeatureRow(
                  colors: colors,
                  icon: Icons.speed_rounded,
                  title: 'Fast, Unrestricted File Sharing',
                  subtitle: 'Send any file, any size, directly between devices',
                ),
                const SizedBox(height: 16),
                _buildFeatureRow(
                  colors: colors,
                  icon: Icons.security_rounded,
                  title: 'Private & Securely Encrypted',
                  subtitle: 'Your data stays between your own devices',
                ),
              ],
            ),
          ),
        ),

        // Right Column: Auth Form Card
        Expanded(
          flex: 5,
          child: Container(
            padding: const EdgeInsets.all(36.0),
            decoration: BoxDecoration(
              color: colors.cardSurface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: colors.cardBorder, width: 0.8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: colors.isDark ? 0.16 : 0.04),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: _buildForm(colors),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout(AppThemeColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 28.0),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.cardBorder, width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: colors.isDark ? 0.16 : 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: _buildForm(colors),
    );
  }

  Widget _buildFeatureRow({
    required AppThemeColors colors,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: colors.primaryLight),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: colors.textMuted,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildForm(AppThemeColors colors) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthHeader(
            isWindows: _isWindows,
            isSignUp: _isSignUp,
          ),
          const SizedBox(height: 24),
          if (_errorMessage != null) ...[
            _buildErrorBanner(_errorMessage!),
            const SizedBox(height: 20),
          ],
          _buildAuthModeToggle(colors),
          const SizedBox(height: 24),
          _buildEmailField(colors),
          const SizedBox(height: 16),
          _buildPasswordField(colors),
          if (_isSignUp) ...[
            const SizedBox(height: 16),
            _buildConfirmPasswordField(colors),
          ],
          if (!_isSignUp) ...[
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => ForgotPasswordDialog.show(
                  context,
                  initialEmail: _emailController.text,
                  authService: _authService,
                ),
                child: Text(
                  AppStrings.forgotPassword,
                  style: TextStyle(
                    color: colors.primaryLight,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 16),
          ],
          const SizedBox(height: 8),
          _buildSubmitButton(colors),

        ],
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.error,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthModeToggle(AppThemeColors colors) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceSubtle,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(
            child: Bounceable(
              onTap: () {
                if (_isSignUp) {
                  setState(() {
                    _isSignUp = false;
                    _errorMessage = null;
                  });
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: !_isSignUp
                      ? colors.cardSurface
                      : colors.cardSurface.withValues(alpha: 0.0),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: !_isSignUp
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  AppStrings.signIn,
                  style: TextStyle(
                    fontWeight: !_isSignUp ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 13,
                    color: !_isSignUp ? colors.textPrimary : colors.textMuted,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Bounceable(
              onTap: () {
                if (!_isSignUp) {
                  setState(() {
                    _isSignUp = true;
                    _errorMessage = null;
                  });
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _isSignUp
                      ? colors.cardSurface
                      : colors.cardSurface.withValues(alpha: 0.0),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: _isSignUp
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  AppStrings.signUp,
                  style: TextStyle(
                    fontWeight: _isSignUp ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 13,
                    color: _isSignUp ? colors.textPrimary : colors.textMuted,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmailField(AppThemeColors colors) {
    return TextFormField(
      controller: _emailController,
      keyboardType: TextInputType.emailAddress,
      style: TextStyle(color: colors.textPrimary, fontSize: 14),
      decoration: const InputDecoration(
        labelText: AppStrings.emailLabel,
        prefixIcon: Icon(Icons.alternate_email_rounded, size: 18),
      ),
      validator: Validators.validateEmail,
    );
  }

  Widget _buildPasswordField(AppThemeColors colors) {
    return TextFormField(
      controller: _passwordController,
      obscureText: _obscurePassword,
      style: TextStyle(color: colors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        labelText: AppStrings.passwordLabel,
        prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePassword
                ? Icons.visibility_off_rounded
                : Icons.visibility_rounded,
            size: 18,
          ),
          onPressed: () =>
              setState(() => _obscurePassword = !_obscurePassword),
        ),
      ),
      validator: Validators.validatePassword,
    );
  }

  Widget _buildConfirmPasswordField(AppThemeColors colors) {
    return TextFormField(
      controller: _confirmPasswordController,
      obscureText: _obscureConfirmPassword,
      style: TextStyle(color: colors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        labelText: AppStrings.confirmPasswordLabel,
        prefixIcon: const Icon(Icons.verified_user_rounded, size: 18),
        suffixIcon: IconButton(
          icon: Icon(
            _obscureConfirmPassword
                ? Icons.visibility_off_rounded
                : Icons.visibility_rounded,
            size: 18,
          ),
          onPressed: () => setState(
            () => _obscureConfirmPassword = !_obscureConfirmPassword,
          ),
        ),
      ),
      validator: (val) =>
          Validators.validateConfirmPassword(val, _passwordController.text),
    );
  }

  Widget _buildSubmitButton(AppThemeColors colors) {
    return Bounceable(
      onTap: _isLoading ? null : _submit,
      scaleFactor: 0.98,
      child: SizedBox(
        height: 48,
        width: double.infinity,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: colors.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onPressed: _isLoading ? null : _submit,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Text(
                  _isSignUp ? AppStrings.signUp : AppStrings.signIn,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.1,
                  ),
                ),
        ),
      ),
    );
}
}
