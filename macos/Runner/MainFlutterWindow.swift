import Cocoa
import FlutterMacOS
import ServiceManagement
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

class MainFlutterWindow: NSWindow {
  private var windowControlChannel: FlutterMethodChannel?
  private var autostartChannel: FlutterMethodChannel?
  private var screenShareChannel: FlutterMethodChannel?
  private let screenCaptureQueue = DispatchQueue(label: "pclink.native_screen_share", qos: .userInteractive)
  private var hasRequestedScreenCaptureAccess = false

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
    // Native screen share channel (mirrors windows/runner/native_screen_share.cpp).
    // Captures the main display with CoreGraphics, scales it down to `maxWidth`
    // and JPEG-encodes it with ImageIO, all off the main thread.
    screenShareChannel = FlutterMethodChannel(
      name: "pclink/native_screen_share",
      binaryMessenger: controller.engine.binaryMessenger
    )
    screenShareChannel?.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self else { return }
      switch call.method {
      case "isSupported":
        result(true)
      case "hasPermission":
        result(CGPreflightScreenCaptureAccess())
      case "requestPermission":
        result(CGRequestScreenCaptureAccess())
      case "captureFrame":
        let args = call.arguments as? [String: Any]
        let maxWidth = (args?["maxWidth"] as? Int) ?? 1920
        let quality = (args?["quality"] as? Int) ?? 85

        // Without Screen Recording permission macOS silently returns an image
        // containing only the wallpaper, so check explicitly and surface it.
        if !CGPreflightScreenCaptureAccess() {
          if !self.hasRequestedScreenCaptureAccess {
            self.hasRequestedScreenCaptureAccess = true
            _ = CGRequestScreenCaptureAccess()
          }
          result(FlutterError(
            code: "PERMISSION_DENIED",
            message: "Screen Recording permission is not granted. Enable it in System Settings > Privacy & Security > Screen Recording, then restart the app.",
            details: nil
          ))
          return
        }

        self.screenCaptureQueue.async {
          let data = MainFlutterWindow.captureMainDisplayJpeg(maxWidth: maxWidth, quality: quality)
          DispatchQueue.main.async {
            if let data = data, !data.isEmpty {
              result(FlutterStandardTypedData(bytes: data))
            } else {
              result(FlutterError(
                code: "CAPTURE_FAILED",
                message: "Failed to capture screen frame with CoreGraphics",
                details: nil
              ))
            }
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

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

  /// Captures the main display and returns a JPEG, scaled so width <= maxWidth.
  private static func captureMainDisplayJpeg(maxWidth: Int, quality: Int) -> Data? {
    guard let fullImage = CGDisplayCreateImage(CGMainDisplayID()) else {
      return nil
    }

    var image = fullImage
    if maxWidth > 0 && fullImage.width > maxWidth {
      let scale = Double(maxWidth) / Double(fullImage.width)
      let targetWidth = maxWidth
      let targetHeight = max(1, Int((Double(fullImage.height) * scale).rounded()))
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
      if let ctx = CGContext(
        data: nil,
        width: targetWidth,
        height: targetHeight,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
      ) {
        ctx.interpolationQuality = .medium
        ctx.draw(fullImage, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        if let scaled = ctx.makeImage() {
          image = scaled
        }
      }
    }

    let output = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(
      output as CFMutableData,
      UTType.jpeg.identifier as CFString,
      1,
      nil
    ) else {
      return nil
    }
    let clamped = Double(min(max(quality, 1), 100)) / 100.0
    let props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: clamped]
    CGImageDestinationAddImage(dest, image, props as CFDictionary)
    guard CGImageDestinationFinalize(dest) else {
      return nil
    }
    return output as Data
  }
}
