# Secure & Sensitive Files Reference

This document lists all sensitive credential files used by PCLink for authentication, Firebase Realtime Database access, and Google Firebase Cloud Messaging (FCM) v1 push alerts.

> [!CAUTION]
> **Production & Public Repository Security Notice:**
> The files listed below contain private keys, API secrets, and service account credentials. In production environments or public open-source repositories, these files are sensitive and should **not** be published to public GitHub repositories. If this repository is made public, revoke these keys in the Firebase/Google Cloud Console and re-generate new private credentials.

---

## Sensitive Files Registry

| File Name | Relative Location | Absolute Default Location | Description & Contents |
| :--- | :--- | :--- | :--- |
| **`credentials_backup.zip`** | `./` (Root) | `c:\Users\Admin\Documents\Mohit\pclink\credentials_backup.zip` | Archive containing `pclink-34bfa-firebase-adminsdk-fbsvc-f59d05ec0b.json`, `firebase_service_account.json`, and `fcm_server_key.txt`. |
| **`pclink-34bfa-firebase-adminsdk-fbsvc-f59d05ec0b.json`** | `./` (Root) | `c:\Users\Admin\Documents\Mohit\pclink\pclink-34bfa-firebase-adminsdk-fbsvc-f59d05ec0b.json` | Google Cloud IAM Service Account private key (`type: service_account`, `project_id: pclink-34bfa`). Used by the Windows desktop server to authenticate via OAuth 2.0 to Google FCM HTTP v1 (`messages:send`). |
| **`firebase_service_account.json`** | `./` (Root) & `%APPDATA%\pclink\` | `c:\Users\Admin\Documents\Mohit\pclink\firebase_service_account.json`<br>`C:\Users\Admin\AppData\Roaming\pclink\firebase_service_account.json` | Standard copy of the Firebase Service Account JSON. Auto-detected by `DatabaseService` at runtime on Windows. |
| **`fcm_server_key.txt`** | `./` (Root) & `%APPDATA%\pclink\` | `c:\Users\Admin\Documents\Mohit\pclink\fcm_server_key.txt`<br>`C:\Users\Admin\AppData\Roaming\pclink\fcm_server_key.txt` | Cloud messaging key string (`16d727ddb293fdb8905bc668b1f1e61ed62ed072`). Used for legacy server key fallback. |
| **`google-services.json`** | `android/app/` | `c:\Users\Admin\Documents\Mohit\pclink\android\app\google-services.json` | Android Firebase client configuration file containing project number, mobile SDK app ID, and API keys. |
| **`firebase_options.dart`** | `lib/` | `c:\Users\Admin\Documents\Mohit\pclink\lib\firebase_options.dart` | FlutterFire generated configuration containing client API keys, project ID, Realtime Database URL, and Storage bucket URLs. |

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
2. `./pclink-34bfa-firebase-adminsdk-fbsvc-f59d05ec0b.json` (Working directory)
3. `<AppExecutableDir>\firebase_service_account.json`
4. `<AppExecutableDir>\pclink-34bfa-firebase-adminsdk-fbsvc-f59d05ec0b.json`
5. `%APPDATA%\pclink\firebase_service_account.json`
6. `%APPDATA%\pclink\pclink-34bfa-firebase-adminsdk-fbsvc-f59d05ec0b.json`
7. Any `*adminsdk*.json` file discovered in the active directory
