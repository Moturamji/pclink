/// Centralized text constants and copy strings for PCLink.
abstract final class AppStrings {
  static const String appName = 'PCLink';
  static const String appTaglineDesktop = 'Desktop Hub for Windows';
  static const String appTaglineMobile = 'Mobile Hub for Android';

  // Auth Strings
  static const String welcomeBack = 'Welcome to PCLink';
  static const String createAccount = 'Create PCLink Account';
  static const String windowsSignIn = 'PCLink Windows Sign In';
  static const String signInSubtitle = 'Sign in to access your device connection hub';
  static const String signUpSubtitle = 'Register with your email and password';
  static const String windowsSignInSubtitle = 'Sign in with your registered credentials';
  static const String windowsRegistrationNotice =
      'Account registration is only available on the Android mobile app. Please register on your phone before signing in on Windows.';

  // Labels & Actions
  static const String signIn = 'Sign In';
  static const String signUp = 'Sign Up';
  static const String signOut = 'Sign Out';
  static const String emailLabel = 'Email Address';
  static const String passwordLabel = 'Password';
  static const String confirmPasswordLabel = 'Confirm Password';
  static const String forgotPassword = 'Forgot Password?';
  static const String resetPasswordTitle = 'Reset Password';
  static const String sendResetLink = 'Send Link';
  static const String cancel = 'Cancel';

  // Dashboard Metrics
  static const String deviceIdTitle = 'DEVICE ID';
  static const String primaryIpTitle = 'IP ADDRESS (PRIMARY IPv4)';
  static const String activeInterfacesTitle = 'ACTIVE NETWORK INTERFACES';
  static const String systemSpecsTitle = 'SYSTEM SPECIFICATIONS';
  static const String targetPlatform = 'Target Platform';
  static const String activeSession = 'Active Session';
  static const String signedInAs = 'SIGNED IN AS';
  static const String notConnected = 'Not Connected';
  static const String detectingDetails = 'Detecting Device & Network details...';
}
