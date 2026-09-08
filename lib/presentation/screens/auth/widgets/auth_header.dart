import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';

/// Branding header for the authentication card.
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
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.hub_outlined,
              size: 40,
              color: AppColors.primaryLight,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          isWindows
              ? AppStrings.windowsSignIn
              : (isSignUp ? AppStrings.createAccount : AppStrings.welcomeBack),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
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
