import 'package:flutter/material.dart';
import 'core/constants/app_strings.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_service.dart';
import 'presentation/screens/splash/splash_screen.dart';

/// Root application widget for DeskPocket supporting both Light and Dark modes.
class DeskPocketApp extends StatelessWidget {
  const DeskPocketApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeService().themeModeNotifier,
      builder: (context, themeMode, child) {
        return MaterialApp(
          title: AppStrings.appName,
          debugShowCheckedModeBanner: false,
          themeMode: themeMode,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          home: const SplashScreen(),
        );
      },
    );
  }
}

/// Backwards compatibility alias for PCLinkApp.
typedef PCLinkApp = DeskPocketApp;
