import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/widgets/universal/app_logo.dart';

/// Cute & Premium Branding header for the authentication card.
class AuthHeader extends StatelessWidget {
  final bool isWindows;
  final bool isSignUp;

  const AuthHeader({
    super.key,
    required this.isWindows,
    required this.isSignUp,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      children: [
        const Center(
          child: AppLogo(
            size: 68,
            borderRadius: 18,
            showGlow: true,
            isAnimated: true,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          isWindows
              ? AppStrings.windowsSignIn
              : (isSignUp ? AppStrings.createAccount : AppStrings.welcomeBack),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.3,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          isWindows
              ? AppStrings.windowsSignInSubtitle
              : (isSignUp
                  ? AppStrings.signUpSubtitle
                  : AppStrings.signInSubtitle),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: colors.textSecondary,
          ),
        ),
      ],
    );
  }
}

