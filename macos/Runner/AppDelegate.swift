import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // DeskPocket is the PC host: closing the window must not stop the server
    // the phone is connected to. Click the Dock icon to bring it back; quit
    // with Cmd+Q.
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
