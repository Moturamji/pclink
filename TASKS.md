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
  - Resolves Public WAN IP (`api.ipify.org` / `icanhazip.com`) and publishes public URL
  - Real-time cloud announcement of server state to `/users/{userId}/server`
  - Password-protected authentication: Android Device ID acts as the secret pre-shared key
  - Clean platform isolation: completely bypassed on Android builds
- [x] Public Network & Cloud Relay Channel Support:
  - Supports cross-network connection over 4G/5G mobile data, remote Wi-Fi, and public WAN
  - Real-time Firebase RTDB cloud channel (`/users/{userId}/channel/`) handles cross-network requests & responses seamlessly without requiring router port-forwarding
  - Dual handshake strategy: Direct Public WAN attempt + Instant Cloud Relay fallback
- [x] Android Live Server Notification & 1-Click Connect (`ServerControlCard`):
  - Scoped strictly to the logged-in user's node in Firebase RTDB
  - Real-time live status notification when Windows PC starts the app
  - "Authenticate & Connect" action sending Android Device ID as password across local or public networks
- [x] Cute, Premium, Modern UI/UX Overhaul (`@ui-ux-pro-max`):
  - Warm Obsidian dark palette (`#0F1015`, `#16171F`, `#1D1F2B`) with Warm Honey Gold (`#F59E0B`, `#FBBF24`), Matcha Sage Teal (`#14B8A6`, `#2DD4BF`), and Soft Coral Rose (`#F43F5E`)
  - Organic non-AI aesthetic avoiding generic neon purple/cyan gradients
  - Generous border radiuses (20-24px), squircle icon containers with tinted halos, pill buttons and status capsules
  - Live pulsing status indicator with ambient blur, soft elevated shadows, and smooth micro-interactions
  - Material 3 tokens with modern `.withValues(alpha: ...)` transparency
- [x] Comprehensive Unit Testing & Static Analysis (`flutter test` & `flutter analyze` 100% passing)


