import Cocoa
import CoreGraphics
import FlutterMacOS
import ServiceManagement

/// Files handed to DeskPocket by macOS (Finder Quick Action via `open -a`,
/// drag onto the Dock icon, "Open With"). Delivered through Flutter's
/// lifecycle delegate hook and queued until Dart is ready to receive them.
final class SharedFileInbox: NSObject, FlutterAppLifecycleDelegate {
  static let shared = SharedFileInbox()

  private var pending: [String] = []
  /// Becomes true once Dart has drained the queue, i.e. its handler is live.
  private var dartReady = false
  weak var channel: FlutterMethodChannel?

  func handleOpenURLs(_ urls: [URL]) -> Bool {
    let paths = urls.filter { $0.isFileURL }.map { $0.path }
    if paths.isEmpty { return false }
    if dartReady, let channel = channel {
      channel.invokeMethod("onSharedFilesReceived", arguments: paths)
    } else {
      pending.append(contentsOf: paths)
    }
    return true
  }

  func drain() -> [String] {
    dartReady = true
    let files = pending
    pending.removeAll()
    return files
  }
}

/// Fast native screen capture for live view: grabs the main display, scales
/// it down to the requested width and JPEG-encodes it off the main thread.
enum NativeScreenCapture {
  private typealias CreateImageFn = @convention(c) (CGDirectDisplayID) -> Unmanaged<CGImage>?

  /// Looked up at runtime: newer SDKs mark CGDisplayCreateImage unavailable
  /// at compile time, while the function itself still exists in the OS.
  private static let createImage: CreateImageFn? = {
    let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
    guard let symbol = dlsym(rtldDefault, "CGDisplayCreateImage") else { return nil }
    return unsafeBitCast(symbol, to: CreateImageFn.self)
  }()

  static var isAvailable: Bool { createImage != nil }

  static func captureJpeg(maxWidth: Int, quality: Int) -> Data? {
    guard let createImage = createImage,
          let full = createImage(CGMainDisplayID())?.takeRetainedValue() else { return nil }

    var image = full
    if maxWidth > 0 && full.width > maxWidth {
      let width = maxWidth
      let height = max(1, Int(Double(full.height) * Double(maxWidth) / Double(full.width)))
      guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
      ) else { return nil }
      context.interpolationQuality = .medium
      context.draw(full, in: CGRect(x: 0, y: 0, width: width, height: height))
      guard let scaled = context.makeImage() else { return nil }
      image = scaled
    }

    let factor = Double(min(max(quality, 1), 100)) / 100.0
    let rep = NSBitmapImageRep(cgImage: image)
    return rep.representation(using: .jpeg, properties: [.compressionFactor: factor])
  }
}

class MainFlutterWindow: NSWindow {
  private var windowControlChannel: FlutterMethodChannel?
  private var autostartChannel: FlutterMethodChannel?
  private var screenShareChannel: FlutterMethodChannel?
  private var activationObserver: NSObjectProtocol?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // The app keeps running (and serving the phone) when the window is
    // closed, so the window must survive being closed and reopened.
    self.isReleasedWhenClosed = false

    RegisterGeneratedPlugins(registry: flutterViewController)

    setupMethodChannels(controller: flutterViewController)

    // Files opened via Finder / Dock / `open -a` arrive through this hook.
    (NSApp.delegate as? FlutterAppDelegate)?.addApplicationLifecycleDelegate(SharedFileInbox.shared)

    // Clicking the Dock icon brings the closed window back.
    activationObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      guard let self = self, !self.isVisible else { return }
      self.makeKeyAndOrderFront(nil)
    }

    super.awakeFromNib()
  }

  private func setupMethodChannels(controller: FlutterViewController) {
    // Window control channel
    windowControlChannel = FlutterMethodChannel(
      name: "com.deskpocket.pclink/window_control",
      binaryMessenger: controller.engine.binaryMessenger
    )
    SharedFileInbox.shared.channel = windowControlChannel
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
      case "getPendingSharedFiles":
        result(SharedFileInbox.shared.drain())
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // Native live-view capture (same channel and methods as the Windows runner)
    screenShareChannel = FlutterMethodChannel(
      name: "pclink/native_screen_share",
      binaryMessenger: controller.engine.binaryMessenger
    )
    screenShareChannel?.setMethodCallHandler { (call, result) in
      switch call.method {
      case "captureFrame":
        guard NativeScreenCapture.isAvailable else {
          // Lets Dart switch to its built-in capture path.
          result(FlutterMethodNotImplemented)
          return
        }
        let args = call.arguments as? [String: Any]
        let maxWidth = args?["maxWidth"] as? Int ?? 1920
        let quality = args?["quality"] as? Int ?? 85
        DispatchQueue.global(qos: .userInitiated).async {
          let data = NativeScreenCapture.captureJpeg(maxWidth: maxWidth, quality: quality)
          DispatchQueue.main.async {
            if let data = data {
              result(FlutterStandardTypedData(bytes: data))
            } else {
              result(FlutterError(code: "CAPTURE_FAILED", message: "Failed to capture the screen", details: nil))
            }
          }
        }
      case "isSupported":
        result(NativeScreenCapture.isAvailable)
      case "requestPermission":
        if CGPreflightScreenCaptureAccess() {
          result(true)
        } else {
          result(CGRequestScreenCaptureAccess())
        }
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
