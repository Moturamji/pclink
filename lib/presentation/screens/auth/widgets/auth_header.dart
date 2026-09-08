import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';

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
    return Column(
      children: [
        Center(
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withValues(alpha: 0.2),
                  AppColors.secondary.withValues(alpha: 0.1),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: const Icon(
              Icons.hub_rounded,
              size: 38,
              color: AppColors.primaryLight,
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          isWindows
              ? AppStrings.windowsSignIn
              : (isSignUp ? AppStrings.createAccount : AppStrings.welcomeBack),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
            color: AppColors.textPrimary,
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
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

