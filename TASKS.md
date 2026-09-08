# PCLink - Tasks & Development Progress

## Active Tasks

- [x] Project architecture & requirements definition
- [x] Remove unused platform targets (`ios`, `macos`, `linux`, `web`)
- [x] Retain and configure targets for **Windows** and **Android** only
- [x] Add required platform permissions (`INTERNET`, `ACCESS_NETWORK_STATE` for Android)
- [x] Add dependencies (`device_info_plus`, `firebase_core`, `firebase_auth`, `firebase_database`)
- [x] Layered Architecture & Codebase Refactoring (Industry Standards):
  - [x] `lib/core/constants/` (`app_colors.dart`, `app_strings.dart`)
  - [x] `lib/core/theme/` (`app_theme.dart`)
  - [x] `lib/core/utils/` (`validators.dart`, `clipboard_helper.dart`)
  - [x] `lib/data/models/` (`device_details.dart`, `linked_device.dart`)
  - [x] `lib/data/services/` (`auth_service.dart`, `device_service.dart`, `database_service.dart`)
  - [x] `lib/presentation/screens/splash/` (`splash_screen.dart`)
  - [x] `lib/presentation/screens/auth/` (`auth_screen.dart`, `widgets/`)
  - [x] `lib/presentation/screens/home/` (`home_screen.dart`, `widgets/`)
  - [x] `lib/app.dart` & clean bootstrap `lib/main.dart`
- [x] Implement Animated Splash Screen (`SplashScreen`)
- [x] Implement Firebase Email & Password Authentication (`AuthScreen`):
  - **Android**: Supports Sign In and Sign Up with confirm password validation
  - **Windows**: Supports Sign In ONLY (Registration blocked and guided to mobile)
  - Password visibility toggle and Forgot Password reset flow
- [x] Firebase Realtime Database Integration:
  - Auto-initializes `/users/{userId}` on sign in / sign up if missing
  - Stores Android node: `/users/{userId}/devices/android` with `deviceId`, `ipAddress`, `deviceName`, `osVersion`, `lastSeen`, `isOnline`
  - Stores Windows node: `/users/{userId}/devices/windows` with `deviceId`, `ipAddress`, `deviceName`, `osVersion`, `lastSeen`, `isOnline`
  - Real-time `LinkedDevicesCard` displaying all connected devices in dashboard
- [x] Comprehensive Unit Testing & Verification (`flutter test` & `flutter analyze`)
