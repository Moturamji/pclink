# macOS and iOS setup

DeskPocket's Mac host and iPhone client need a few one-time steps that can't
live in the code: your Firebase project and your Apple signing identity.
Windows and Android don't need any of this.

These steps were written alongside the Mac/iOS fixes on a Windows machine, so
the Apple builds haven't been compiled or run yet. Expect to do a first build
and smoke test on a real Mac and iPhone.

## 1. Register the Apple apps in Firebase (required)

Without this, the app starts but sign-in and everything after it fail on
macOS and iOS: `lib/firebase_options.dart` only has Android, Windows and web
settings.

From the project root, with your Firebase account:

```bash
dart pub global activate flutterfire_cli
flutterfire configure
```

Choose the existing project (`pclink-34bfa`) and select **iOS** and **macOS**
(keep Android and Windows selected). This regenerates
`lib/firebase_options.dart`; commit the result.

Both Apple apps use the bundle ID `com.example.pclink`. If you change it, also
update the keychain group in `macos/Runner/DebugProfile.entitlements` and
`macos/Runner/Release.entitlements`.

## 2. Mac: choose a signing team (required)

Open `macos/Runner.xcworkspace` in Xcode, select the **Runner** target, go to
**Signing & Capabilities** and pick your **Team**. A free Apple ID works.

The Mac app now requests the keychain access Firebase Auth needs to keep you
signed in. That permission only works on a team-signed build, so **until a
team is set the Mac app may not launch at all**.

## 3. iPhone: signing and push (team required; push optional)

Open `ios/Runner.xcworkspace` in Xcode, select **Runner** →
**Signing & Capabilities**:

1. Pick your **Team**.
2. For the "your PC is live" notification: click **+ Capability** →
   **Push Notifications**. Background push is already enabled in
   `Info.plist`.
3. In the Apple Developer portal create an **APNs key** (Keys → +, enable
   Apple Push Notifications service), then upload it in the Firebase console
   under **Project settings → Cloud Messaging → Apple app configuration**.

Free Apple IDs can't use push notifications. Everything else works without
them.

## 4. First run on the Mac

- **Screen Recording:** turning on screen sharing shows the macOS prompt.
  Allow DeskPocket in System Settings → Privacy & Security → Screen
  Recording, then restart DeskPocket. Until then the phone sees only the
  wallpaper.
- **Automation:** the first remote shutdown or restart asks to let DeskPocket
  control System Events. Allow it.
- **Finder:** right-click any file → **Quick Actions** →
  **Send to Phone with DeskPocket**. The action is (re)installed on every
  launch.
- **Closing the window keeps DeskPocket running** so the phone stays
  connected. Click the Dock icon to bring it back, and quit with Cmd+Q.

## 5. First run on the iPhone

- **Clipboard:** iOS asks permission every time an app reads the clipboard,
  so DeskPocket never reads it in the background. Use **Send clipboard to
  PC** on the Clipboard tab; it also fetches the PC's latest clip.
- **Sending files from other apps:** use the share sheet → **Copy to
  DeskPocket** (or **Open in DeskPocket** in Files). The file is sent to the
  PC when DeskPocket opens or comes back to the foreground.
- **Received files** are in the Files app under
  **On My iPhone → DeskPocket**.

## Known limitations

- **iPhone transfers pause in the background.** iOS suspends the app about 30
  seconds after you leave it; keep DeskPocket open for large transfers.
- **No dedicated share panel on iPhone.** Sharing goes through "Copy to /
  Open in DeskPocket"; a full Share Extension would be a separate Xcode
  target.
- **Lock screen and admin prompts can't be captured** on the Mac (same as
  Windows). This needs a privileged helper service, planned for v2.
- The Mac app isn't sandboxed (it's a personal PC host, not a Mac App Store
  app), so it isn't suitable for Mac App Store distribution as-is.
