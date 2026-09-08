# PCLink - Tasks & Development Progress

## Active Tasks

- [x] Project architecture & requirements definition
- [x] Remove unused platform targets (`ios`, `macos`, `linux`, `web`)
- [x] Retain and configure targets for **Windows** and **Android** only
- [x] Add required platform permissions (`INTERNET`, `ACCESS_NETWORK_STATE` for Android)
- [x] Add dependencies (`device_info_plus`, `firebase_core`, `firebase_auth`)
- [x] Implement `DeviceInfoService` to fetch:
  - Unique Device ID (Android ID on Android / Machine & Device ID on Windows)
  - Device Model / Computer Name
  - Operating System Details
  - Active IP Addresses (Primary IPv4 & all network interfaces)
- [x] Build Modern Responsive Home Screen UI:
  - Platform-specific badges (Android / Windows)
  - One-click copy for Device ID and IP Address
  - Interface breakdown (WiFi, Ethernet, Localhost)
  - User profile / active session banner with email
  - Sign Out action with confirmation dialog
  - Pull-to-refresh & manual refresh action
- [x] Implement Animated Splash Screen (`SplashScreen`)
  - Auto session check and smooth fade transition
- [x] Implement Firebase Email & Password Authentication (`AuthScreen`):
  - **Android**: Supports Sign In and Sign Up with confirm password validation
  - **Windows**: Supports Sign In ONLY (Registration blocked and guided to mobile)
  - Password visibility toggle and Forgot Password reset flow
- [x] Run verification (`flutter analyze` and `flutter test`)
