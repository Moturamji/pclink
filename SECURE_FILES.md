# Secure & Sensitive Files Reference

This document lists all sensitive credential files used by PCLink for authentication, Firebase Realtime Database access, and Google Firebase Cloud Messaging (FCM) v1 push alerts.

> [!CAUTION]
> **Production & Public Repository Security Notice:**
> The files listed below contain private keys, API secrets, and service account credentials. In production environments or public open-source repositories, these files are sensitive and should **not** be published to public GitHub repositories. If this repository is made public, revoke these keys in the Firebase/Google Cloud Console and re-generate new private credentials.

---

## Sensitive Files Registry

| File Name | Relative Location | Absolute Default Location | Description & Contents |
| :--- | :--- | :--- | :--- |
| **`credentials_backup.zip`** | `./` (Root) | `credentials_backup.zip` | Archive containing `pclink-34bfa-firebase-adminsdk-fbsvc-f965fa6b41ce5e66a9b96968603e4cb6d4159867.json`, `firebase_service_account.json`, and `fcm_server_key.txt`. |
| **`pclink-34bfa-firebase-adminsdk-fbsvc-f965fa6b41ce5e66a9b96968603e4cb6d4159867.json`** | `./` (Root) | `%APPDATA%\pclink\` & `./` | Google Cloud IAM Service Account private key (`type: service_account`, `project_id: pclink-34bfa`, key ID: `f965fa6b41ce5e66a9b96968603e4cb6d4159867`). Used by the Windows desktop server to authenticate via OAuth 2.0 to Google FCM HTTP v1 (`messages:send`). |
| **`firebase_service_account.json`** | `./` (Root) & `%APPDATA%\pclink\` | `.\firebase_service_account.json`<br>`%APPDATA%\pclink\firebase_service_account.json` | Standard copy of the Firebase Service Account JSON. Auto-detected by `DatabaseService` at runtime on Windows. |
| **`fcm_server_key.txt`** | `./` (Root) & `%APPDATA%\pclink\` | `.\fcm_server_key.txt`<br>`%APPDATA%\pclink\fcm_server_key.txt` | Cloud messaging key string (`<FCM_SERVER_KEY>`). Used for legacy server key fallback. |
| **`google-services.json`** | `android/app/` | `android\app\google-services.json` | Android Firebase client configuration file containing project number, mobile SDK app ID, and API keys. |
| **`firebase_options.dart`** | `lib/` | `lib\firebase_options.dart` | FlutterFire generated configuration containing client API keys, project ID, Realtime Database URL, and Storage bucket URLs. |

---

## How to Extract & Use Credentials from `credentials_backup.zip`

When setting up PCLink on a new device or cloning the repo:

1. **Extract the ZIP file in PowerShell**:
   ```powershell
   Expand-Archive -Path .\credentials_backup.zip -DestinationPath . -Force
   ```
2. **Copy to AppData for persistent Windows background discovery (optional)**:
   ```powershell
   New-Item -ItemType Directory -Force -Path "$env:APPDATA\pclink"
   Copy-Item .\firebase_service_account.json "$env:APPDATA\pclink\" -Force
   Copy-Item .\fcm_server_key.txt "$env:APPDATA\pclink\" -Force
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
