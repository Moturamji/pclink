import Cocoa
import FlutterMacOS
import ServiceManagement

class MainFlutterWindow: NSWindow {
  private var windowControlChannel: FlutterMethodChannel?
  private var autostartChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    setupMethodChannels(controller: flutterViewController)

    super.awakeFromNib()
  }

  private func setupMethodChannels(controller: FlutterViewController) {
    // Window control channel
    windowControlChannel = FlutterMethodChannel(
      name: "com.deskpocket.pclink/window_control",
      binaryMessenger: controller.engine.binaryMessenger
    )
    windowControlChannel?.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self else { return }
      switch call.method {
      case "showWindow":
        self.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        result(true)
      case "hideWindow":
        self.orderOut(nil)
        result(true)
      case "isStartedHidden":
        let isAutostart = CommandLine.arguments.contains("--autostart")
        result(isAutostart)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // Mac autostart channel using SMAppService (macOS 13+)
    autostartChannel = FlutterMethodChannel(
      name: "com.deskpocket.pclink/mac_autostart",
      binaryMessenger: controller.engine.binaryMessenger
    )
    autostartChannel?.setMethodCallHandler { (call, result) in
      switch call.method {
      case "isAutostartEnabled":
        if #available(macOS 13.0, *) {
          let status = SMAppService.mainApp.status
          result(status == .enabled)
        } else {
          result(nil)
        }
      case "setAutostartEnabled":
        guard let args = call.arguments as? [String: Any],
              let enabled = args["enabled"] as? Bool else {
          result(FlutterError(code: "INVALID_ARGS", message: "enabled boolean required", details: nil))
          return
        }
        if #available(macOS 13.0, *) {
          do {
            if enabled {
              try SMAppService.mainApp.register()
            } else {
              try SMAppService.mainApp.unregister()
            }
            result(true)
          } catch {
            result(FlutterError(code: "SMAPP_ERROR", message: error.localizedDescription, details: nil))
          }
        } else {
          result(nil)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
