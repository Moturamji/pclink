# Secure & Sensitive Files Reference

This document lists all sensitive credential files used by PCLink for authentication, Firebase Realtime Database access, and Google Firebase Cloud Messaging (FCM) v1 push alerts.

> [!CAUTION]
> **Production & Public Repository Security Notice:**
> The files listed below contain private keys, API secrets, and service account credentials. In production environments or public open-source repositories, these files are sensitive and should **not** be published to public GitHub repositories. If this repository is made public, revoke these keys in the Firebase/Google Cloud Console and re-generate new private credentials.

---

## Sensitive Files Registry

| File Name | Relative Location | Absolute Default Location | Description & Contents |
| :--- | :--- | :--- | :--- |
| **`firebase-admin-sdk.json`** | `./` (Root) & `%APPDATA%\pclink\` | `.\firebase-admin-sdk.json`<br>`%APPDATA%\pclink\firebase-admin-sdk.json` | Firebase Admin SDK service account key. Primary candidate detected by `DatabaseService` at runtime. |
| **`firebase_service_account.json`** | `./` (Root) & `%APPDATA%\pclink\` | `.\firebase_service_account.json`<br>`%APPDATA%\pclink\firebase_service_account.json` | Standard copy of the Firebase Service Account JSON. Auto-detected by `DatabaseService` at runtime on Windows and macOS. |
| **`pclink-34bfa-firebase-adminsdk-fbsvc-*.json`** | `./` (Root) | `%APPDATA%\pclink\` & `./` | Google Cloud IAM Service Account private key (`type: service_account`, `project_id: pclink-34bfa`). Kept locally only and never committed. |
| **`fcm_server_key.txt`** | `./` (Root) & `%APPDATA%\pclink\` | `.\fcm_server_key.txt`<br>`%APPDATA%\pclink\fcm_server_key.txt` | Cloud messaging key string. Kept locally in `%APPDATA%\pclink\` or project root for the desktop app to dispatch push alerts. Never committed to Git. |
| **`google-services.json`** | `android/app/` | `android\app\google-services.json` | Android Firebase client configuration file containing project number, mobile SDK app ID, and API keys. |
| **`firebase_options.dart`** | `lib/` | `lib\firebase_options.dart` | FlutterFire generated configuration containing client API keys, project ID, Realtime Database URL, and Storage bucket URLs. |

---

## Local Setup on Windows (Keys are Never Committed)

The Windows app requires the FCM credentials locally to dispatch push notifications to mobile devices when the PC comes online. The mobile app does not need this key (it only receives notifications).

To configure locally on Windows without exposing credentials:

1. **Place `fcm_server_key.txt` in `%APPDATA%\pclink\`**:
   ```powershell
   New-Item -ItemType Directory -Force -Path "$env:APPDATA\pclink"
   Set-Content -Path "$env:APPDATA\pclink\fcm_server_key.txt" -Value "<YOUR_FCM_SERVER_KEY>"
   ```
2. **Or keep it in the project root** (which is ignored by `.gitignore`):
   ```powershell
   Set-Content -Path ".\fcm_server_key.txt" -Value "<YOUR_FCM_SERVER_KEY>"
   ```

---

## App Runtime Discovery

On Windows and macOS, `DatabaseService.sendDirectFcmPush` automatically checks for service account credentials in the following order:
1. `./firebase-admin-sdk.json` (Working directory)
2. `./firebase_service_account.json` (Working directory)
3. Candidate specific files such as `pclink-34bfa-*.json`
4. App executable directories (`<AppExecutableDir>\firebase-admin-sdk.json`, `<AppExecutableDir>\firebase_service_account.json`)
5. System application support folders (`%APPDATA%\pclink\` on Windows, `~/Library/Application Support/pclink/` on macOS)
6. Any `*adminsdk*.json` or `*admin-sdk*.json` file discovered in the current directory or app support paths
