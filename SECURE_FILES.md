# Secure & Sensitive Files Reference

This document lists all sensitive credential files used by PCLink for authentication, Firebase Realtime Database access, and Google Firebase Cloud Messaging (FCM) v1 push alerts.

> [!CAUTION]
> **Production & Public Repository Security Notice:**
> The files listed below contain private keys, API secrets, and service account credentials. In production environments or public open-source repositories, these files are sensitive and should **not** be published to public GitHub repositories. If this repository is made public, revoke these keys in the Firebase/Google Cloud Console and re-generate new private credentials.

---

## Sensitive Files Registry

| File Name | Relative Location | Absolute Default Location | Description & Contents |
| :--- | :--- | :--- | :--- |
| **`pclink-34bfa-firebase-adminsdk-fbsvc-*.json`** | `./` (Root) | `%APPDATA%\pclink\` & `./` | Google Cloud IAM Service Account private key (`type: service_account`, `project_id: pclink-34bfa`). Kept locally on Windows only and never committed. |
| **`firebase_service_account.json`** | `./` (Root) & `%APPDATA%\pclink\` | `.\firebase_service_account.json`<br>`%APPDATA%\pclink\firebase_service_account.json` | Standard copy of the Firebase Service Account JSON. Auto-detected by `DatabaseService` at runtime on Windows. |
| **`fcm_server_key.txt`** | `%APPDATA%\pclink\` | `%APPDATA%\pclink\fcm_server_key.txt` | Cloud messaging key string. Kept locally in `%APPDATA%\pclink\` for the Windows desktop app to dispatch push alerts. Never committed to Git. |
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

On Windows, `DatabaseService.sendDirectFcmPush` automatically checks for service account credentials in the following order:
1. `./firebase_service_account.json` (Working directory)
2. `./pclink-34bfa-firebase-adminsdk-fbsvc-f965fa6b41ce5e66a9b96968603e4cb6d4159867.json` (Working directory)
3. `<AppExecutableDir>\firebase_service_account.json`
4. `<AppExecutableDir>\pclink-34bfa-firebase-adminsdk-fbsvc-f965fa6b41ce5e66a9b96968603e4cb6d4159867.json`
5. `%APPDATA%\pclink\firebase_service_account.json`
6. `%APPDATA%\pclink\pclink-34bfa-firebase-adminsdk-fbsvc-f965fa6b41ce5e66a9b96968603e4cb6d4159867.json`
7. Any `*adminsdk*.json` file discovered in the current directory, executable directory, or `%APPDATA%\pclink\`
