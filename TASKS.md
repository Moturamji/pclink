# PCLink - Tasks & Development Progress

## Active Tasks

- [x] Project architecture & requirements definition
- [x] Remove unused platform targets (`ios`, `macos`, `linux`, `web`)
- [x] Retain and configure targets for **Windows** and **Android** only
- [x] Add required platform permissions (`INTERNET`, `ACCESS_NETWORK_STATE` for Android)
- [x] Add dependencies (`device_info_plus`, `firebase_core`, `firebase_auth`, `http`)
- [x] Layered Architecture & Codebase Refactoring (Industry Standards):
  - [x] `lib/core/constants/` (`app_colors.dart`, `app_strings.dart`, `server_constants.dart`)
  - [x] `lib/core/theme/` (`app_theme.dart`)
  - [x] `lib/core/utils/` (`validators.dart`, `clipboard_helper.dart`)
  - [x] `lib/data/models/` (`device_details.dart`, `linked_device.dart`, `server_info.dart`)
  - [x] `lib/data/services/` (`auth_service.dart`, `device_service.dart`, `database_service.dart`, `server_service.dart`)
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
- [x] Windows-Exclusive Lightweight Local Server (`ServerService`):
  - Automatically starts on Windows application launch (`http://<primaryIp>:8088`)
  - Real-time cloud announcement of server state to `/users/{userId}/server`
  - Password-protected authentication: Android Device ID acts as the secret pre-shared key
  - Clean platform isolation: completely bypassed on Android builds
- [x] Android Live Server Notification & 1-Click Connect (`ServerControlCard`):
  - Scoped strictly to the logged-in user's node in Firebase RTDB
  - Real-time live status notification when Windows PC starts the app
  - "Authenticate & Connect" action sending Android Device ID as header/payload
- [x] Comprehensive Unit Testing & Static Analysis (`flutter test` & `flutter analyze` 100% passing)

