# pclink

Cross-platform **clipboard sync** between a Windows PC and an Android phone.

- Windows runs a lightweight local HTTP server (`:8088`).
- Firebase Realtime Database is used **only** to tell the phone the PC's
  address + the server start time (used as a per-session password).
- Clipboard payloads travel **directly** between PC and phone over HTTP
  (`/api/clipboard`, `/api/clipboard/latest`) — no DB involvement.

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
