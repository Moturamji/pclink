# pclink

Cross-platform **clipboard sync** between a Windows PC and an Android phone.

- Windows runs a lightweight local HTTP server (`:8088`).
- Firebase Realtime Database is used **only** to tell the phone the PC's
  address + the server start time (used as a per-session password).
- Clipboard payloads travel **directly** between PC and phone over HTTP
  (`/api/clipboard`, `/api/clipboard/latest`) — no DB involvement.

## Downloads

Official builds organized chronologically by date:

| Release Date | Release Tag | Windows (x64) | Android (APK) | Complete Bundle |
| :--- | :--- | :--- | :--- | :--- |
| **2026-09-26** *(Latest)* | [`v2026-09-26`](https://github.com/Moturamji/pclink/releases/tag/v2026-09-26) | [Download ZIP](https://github.com/Moturamji/pclink/releases/download/v2026-09-26/pclink-windows-x64.zip) | [Download APK](https://github.com/Moturamji/pclink/releases/download/v2026-09-26/pclink-release.apk) | [Download Bundle](https://github.com/Moturamji/pclink/releases/download/v2026-09-26/pclink-release-2026-09-26.zip) |
| **2026-09-23** | [`v2026-09-23`](https://github.com/Moturamji/pclink/releases/tag/v2026-09-23) | [Download ZIP](https://github.com/Moturamji/pclink/releases/download/v2026-09-23/pclink-windows-x64.zip) | [Download APK](https://github.com/Moturamji/pclink/releases/download/v2026-09-23/pclink-release.apk) | [Download Bundle](https://github.com/Moturamji/pclink/releases/download/v2026-09-23/pclink-release-2026-09-23.zip) |
| **2026-09-22** | [`v2026-09-22`](https://github.com/Moturamji/pclink/releases/tag/v2026-09-22) | [Download ZIP](https://github.com/Moturamji/pclink/releases/download/v2026-09-22/pclink-windows-x64.zip) | [Download APK](https://github.com/Moturamji/pclink/releases/download/v2026-09-22/pclink-release.apk) | [Download Bundle](https://github.com/Moturamji/pclink/releases/download/v2026-09-22/pclink-release-2026-09-22.zip) |
| **2026-09-19** | [`v2026-09-19`](https://github.com/Moturamji/pclink/releases/tag/v2026-09-19) | [Download ZIP](https://github.com/Moturamji/pclink/releases/download/v2026-09-19/pclink-windows-x64.zip) | [Download APK](https://github.com/Moturamji/pclink/releases/download/v2026-09-19/pclink-release.apk) | [Download Bundle](https://github.com/Moturamji/pclink/releases/download/v2026-09-19/pclink-release-2026-09-19.zip) |
| **2026-09-17** | [`v2026-09-17`](https://github.com/Moturamji/pclink/releases/tag/v2026-09-17) | [Download ZIP](https://github.com/Moturamji/pclink/releases/download/v2026-09-17/pclink-windows-x64.zip) | [Download APK](https://github.com/Moturamji/pclink/releases/download/v2026-09-17/pclink-release.apk) | [Download Bundle](https://github.com/Moturamji/pclink/releases/download/v2026-09-17/pclink-release-2026-09-17.zip) |
| **2026-09-11** | [`v2026-09-11`](https://github.com/Moturamji/pclink/releases/tag/v2026-09-11) | [Download ZIP](https://github.com/Moturamji/pclink/releases/download/v2026-09-11/pclink-windows-x64.zip) | [Download APK](https://github.com/Moturamji/pclink/releases/download/v2026-09-11/pclink-release.apk) | [Download Bundle](https://github.com/Moturamji/pclink/releases/download/v2026-09-11/pclink-release-2026-09-11.zip) |

## Running

1. Sign in on both devices with the same account.
2. Keep PCLink open on the Windows PC (server auto-starts).

## Connecting from anywhere (public network) — fully automatic

PCLink now does **everything itself** — no port-forwarding, no accounts, no
commands for you to run:

1. On Windows, the app starts its local server (`:8088`) **and** launches a
   **cloudflared quick tunnel** automatically.
2. First run only: the app quietly downloads the free `cloudflared` client
   (~30 MB, one time) into `%APPDATA%\pclink\`.
3. The app grabs the temporary `https://…trycloudflare.com` HTTPS address and
   publishes it to Firebase. Your phone picks it up and syncs clipboard from
   **any network** (4G/5G, other Wi-Fi, CGNAT ISPs) — no manual setup.

If the tunnel can't be established (e.g. download blocked, offline), the app
automatically falls back to trying the public WAN IP and the LAN address.

> **Optional** manual override (no longer needed, but supported): put a public
> HTTPS URL in a file named `tunnel_url.txt` next to the PCLink app (see
> `tunnel_url.example.txt`), or run ngrok yourself — the app auto-detects it.

The phone needs no changes — it always tries the published public URL first,
then the LAN URL. Auth is enforced on the PC with the Android device ID +
server start-time (password) headers.

## Optional: FCM "PC is live" push

Direct push notification from PC to phone needs
`DatabaseService.fcmServerKey` set to your Firebase project's Cloud
Messaging **server key** (Firebase console → Project settings → Cloud
Messaging). Without it, the RTDB notification is still written and the
in-app banner shows the PC as live.
