import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  /// DeskPocket is a server for the phone (heartbeats, file transfer, screen
  /// mirroring). macOS App Nap throttles timers of apps whose windows are
  /// hidden or in the background - exactly when you mirror the screen - which
  /// made the frame rate drop to 0-4 fps and heartbeats go stale. Windows has
  /// no equivalent, so it never showed this. Opt out for the app's lifetime
  /// while still allowing the Mac to idle-sleep normally.
  private var appNapActivity: NSObjectProtocol?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    appNapActivity = ProcessInfo.processInfo.beginActivity(
      options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
      reason: "DeskPocket serves the linked phone (screen mirroring, transfers, heartbeats)"
    )
    super.applicationDidFinishLaunching(notification)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
