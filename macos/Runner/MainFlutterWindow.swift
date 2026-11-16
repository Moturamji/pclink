import Cocoa
import FlutterMacOS
import ServiceManagement
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import ScreenCaptureKit
import VideoToolbox
import CoreMedia
import IOKit.pwr_mgt

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
      case "permissionInfo":
        let responsible = MainFlutterWindow.responsibleAppInfo()
        result([
          "granted": CGPreflightScreenCaptureAccess(),
          "responsibleIsSelf": responsible.isSelf,
          "responsibleApp": (responsible.name as Any?) ?? NSNull(),
        ])
      case "requestPermission":
        // Bring the app to the front first: macOS only shows this prompt once
        // per app, and it is easy to miss behind other windows.
        self.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.hasRequestedScreenCaptureAccess = true
        result(CGRequestScreenCaptureAccess())
      case "stopCapture":
        if #available(macOS 12.3, *) {
          MacScreenStreamer.shared.stop()
        }
        result(true)
      case "openPermissionSettings":
        // Deep link to System Settings > Privacy & Security > Screen Recording.
        let urls = [
          "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
          "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture",
        ]
        var opened = false
        for raw in urls {
          if let url = URL(string: raw), NSWorkspace.shared.open(url) {
            opened = true
            break
          }
        }
        result(opened)
      case "relaunchApp":
        // macOS applies a newly granted Screen Recording permission only after
        // the app restarts. Launch a fresh instance, then quit this one.
        let bundlePath = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; /usr/bin/open -n \"$0\"", bundlePath]
        do {
          try task.run()
          result(true)
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.terminate(nil)
          }
        } catch {
          result(FlutterError(code: "RELAUNCH_FAILED", message: error.localizedDescription, details: nil))
        }
      case "captureFrame":
        let args = call.arguments as? [String: Any]
        let maxWidth = (args?["maxWidth"] as? Int) ?? 1920
        let quality = (args?["quality"] as? Int) ?? 85

        // Without Screen Recording permission macOS silently returns an image
        // containing only the wallpaper, so check explicitly and surface it.
        if !CGPreflightScreenCaptureAccess() {
          if !self.hasRequestedScreenCaptureAccess {
            self.hasRequestedScreenCaptureAccess = true
            self.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            _ = CGRequestScreenCaptureAccess()
          }
          let responsible = MainFlutterWindow.responsibleAppInfo()
          result(FlutterError(
            code: "PERMISSION_DENIED",
            message: responsible.isSelf
              ? "Screen Recording permission is not granted. Enable it in System Settings > Privacy & Security > Screen Recording, then restart the app."
              : "macOS is checking Screen Recording for \(responsible.name ?? "the app that launched DeskPocket") because DeskPocket was started from it. Restart DeskPocket on its own, then allow it.",
            details: [
              "responsibleIsSelf": responsible.isSelf,
              "responsibleApp": (responsible.name as Any?) ?? NSNull(),
            ]
          ))
          return
        }

        if #available(macOS 12.3, *) {
          // ScreenCaptureKit: continuous, GPU-scaled capture of the whole main
          // display (~15 ms/frame on a 4K iMac vs ~170 ms for the legacy path).
          MacScreenStreamer.shared.latestJpeg(maxWidth: maxWidth, quality: quality) { outcome in
            DispatchQueue.main.async {
              switch outcome {
              case .frame(let data, let seq):
                // seq lets Dart skip re-sending an unchanged screen.
                result(["jpeg": FlutterStandardTypedData(bytes: data), "seq": Int(truncatingIfNeeded: seq)])
              case .noFrameYet:
                result(FlutterError(code: "NO_FRAME", message: "Waiting for first frame", details: nil))
              case .failed(let message):
                result(FlutterError(code: "CAPTURE_FAILED", message: message, details: nil))
              }
            }
          }
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

  /// macOS attributes privacy permissions (Screen Recording, etc.) to the
  /// "responsible" process. When DeskPocket is started directly by another
  /// process - e.g. `flutter run` from an IDE such as VS Code or Antigravity -
  /// that IDE is responsible, so the prompt names the IDE and the IDE's grant
  /// is what gets checked. Launching through Finder/`open` makes DeskPocket
  /// responsible for itself.
  private static func responsibleAppInfo() -> (isSelf: Bool, name: String?) {
    typealias ResponsibleFn = @convention(c) (pid_t) -> pid_t
    let selfPid = ProcessInfo.processInfo.processIdentifier
    guard let handle = dlopen(nil, RTLD_NOW),
          let sym = dlsym(handle, "responsibility_get_pid_responsible_for_pid") else {
      return (true, nil)
    }
    let fn = unsafeBitCast(sym, to: ResponsibleFn.self)
    let responsiblePid = fn(selfPid)
    if responsiblePid <= 0 || responsiblePid == selfPid {
      return (true, nil)
    }
    let name = NSRunningApplication(processIdentifier: responsiblePid)?.localizedName
    return (false, name)
  }
}

// MARK: - ScreenCaptureKit streamer

/// Continuous capture of the entire main display (all apps + cursor) using
/// ScreenCaptureKit, the macOS equivalent of the Windows GDI path.
///
/// Why not CGDisplayCreateImage (the previous approach): on a 4096x2304 Retina
/// iMac it copies the full-resolution screen (~50 ms) and then needs a CPU
/// downscale (~110 ms) per frame, capping streaming at ~5 fps. It is also
/// obsoleted by Apple in macOS 15. ScreenCaptureKit scales on the GPU and
/// pushes frames continuously; we keep the newest one and JPEG-encode it on
/// demand (cached, so a static screen costs nothing extra to resend).
@available(macOS 12.3, *)
final class MacScreenStreamer: NSObject, SCStreamOutput, SCStreamDelegate {
  static let shared = MacScreenStreamer()

  enum Outcome {
    case frame(Data, UInt64)
    case noFrameYet
    case failed(String)
  }

  private let stateQueue = DispatchQueue(label: "pclink.sck.state")
  private let sampleQueue = DispatchQueue(label: "pclink.sck.samples", qos: .userInteractive)
  private let encodeQueue = DispatchQueue(label: "pclink.sck.encode", qos: .userInteractive)

  // State below is only touched on stateQueue.
  private var stream: SCStream?
  private var starting = false
  private var configuredWidth = 0
  private var displayPixelSize = CGSize.zero
  private var lastError: String?
  private var lastRequestAt = Date()
  private var idleTimer: DispatchSourceTimer?

  // Latest frame (guarded by frameLock).
  private let frameLock = NSLock()
  private var latestBuffer: CVPixelBuffer?
  private var latestSeq: UInt64 = 0

  // Encoded cache (only touched on encodeQueue).
  private var cachedSeq: UInt64 = 0
  private var cachedQuality = -1
  private var cachedMaxWidth = -1

  // Keeps the display awake while a phone is watching (stateQueue).
  private var displaySleepAssertion: IOPMAssertionID = 0
  private var cachedData: Data?

  func latestJpeg(maxWidth: Int, quality: Int, completion: @escaping (Outcome) -> Void) {
    stateQueue.async {
      self.lastRequestAt = Date()
      self.ensureRunning(maxWidth: maxWidth)
      let error = self.lastError

      self.frameLock.lock()
      let buffer = self.latestBuffer
      let seq = self.latestSeq
      self.frameLock.unlock()

      guard let pixelBuffer = buffer else {
        completion(error != nil ? .failed(error!) : .noFrameYet)
        return
      }
      self.encodeQueue.async {
        if seq == self.cachedSeq, quality == self.cachedQuality,
           maxWidth == self.cachedMaxWidth, let data = self.cachedData {
          completion(.frame(data, seq))
          return
        }
        // After an adaptive downgrade the newest buffer can still be at the old
        // (larger) size until the screen changes, so scale it here if needed.
        guard let data = MacScreenStreamer.encodeJpeg(pixelBuffer, quality: quality, maxWidth: maxWidth) else {
          completion(.failed("JPEG encoding failed"))
          return
        }
        self.cachedSeq = seq
        self.cachedQuality = quality
        self.cachedMaxWidth = maxWidth
        self.cachedData = data
        completion(.frame(data, seq))
      }
    }
  }

  func stop() {
    stateQueue.async { self.stopLocked() }
  }

  // MARK: Stream lifecycle (stateQueue)

  private func targetSize(maxWidth: Int) -> (Int, Int) {
    let pixelW = max(1, Int(displayPixelSize.width))
    let pixelH = max(1, Int(displayPixelSize.height))
    var w = (maxWidth > 0 && pixelW > maxWidth) ? maxWidth : pixelW
    var h = Int((Double(pixelH) * Double(w) / Double(pixelW)).rounded())
    w -= w % 2
    h -= h % 2
    return (max(2, w), max(2, h))
  }

  private func makeConfiguration(width: Int, height: Int) -> SCStreamConfiguration {
    let cfg = SCStreamConfiguration()
    cfg.width = width
    cfg.height = height
    cfg.minimumFrameInterval = CMTime(value: 1, timescale: 30)
    cfg.pixelFormat = kCVPixelFormatType_32BGRA
    cfg.showsCursor = true  // parity with Windows, which draws the cursor in
    cfg.queueDepth = 3
    return cfg
  }

  private func ensureRunning(maxWidth: Int) {
    startIdleTimerIfNeeded()

    if let stream = stream {
      // Adaptive quality changed the resolution: reconfigure on the GPU.
      let (w, h) = targetSize(maxWidth: maxWidth)
      if w != configuredWidth {
        configuredWidth = w
        stream.updateConfiguration(makeConfiguration(width: w, height: h)) { _ in }
      }
      return
    }
    if starting { return }
    starting = true
    lastError = nil

    SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, error in
      self.stateQueue.async {
        guard let content = content else {
          self.starting = false
          self.lastError = CGPreflightScreenCaptureAccess()
            ? "ScreenCaptureKit unavailable: \(error?.localizedDescription ?? "unknown error")"
            : "Screen Recording permission is not granted"
          return
        }
        let mainId = CGMainDisplayID()
        guard let display = content.displays.first(where: { $0.displayID == mainId }) ?? content.displays.first else {
          self.starting = false
          self.lastError = "No display found"
          return
        }
        if let mode = CGDisplayCopyDisplayMode(display.displayID) {
          self.displayPixelSize = CGSize(width: mode.pixelWidth, height: mode.pixelHeight)
        } else {
          self.displayPixelSize = CGSize(width: display.width, height: display.height)
        }

        // Entire display, nothing excluded: every app's windows are shared.
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let (w, h) = self.targetSize(maxWidth: maxWidth)
        self.configuredWidth = w
        let newStream = SCStream(filter: filter, configuration: self.makeConfiguration(width: w, height: h), delegate: self)
        do {
          try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: self.sampleQueue)
        } catch {
          self.starting = false
          self.lastError = "Could not attach stream output: \(error.localizedDescription)"
          return
        }
        newStream.startCapture { error in
          self.stateQueue.async {
            self.starting = false
            if let error = error {
              self.lastError = "Screen capture failed to start: \(error.localizedDescription)"
              return
            }
            self.stream = newStream
            // macOS stops compositing when the display idles to sleep, and the
            // phone then sees a frozen or black picture. Windows keeps
            // rendering the desktop with the monitor off, so it never hit this.
            if self.displaySleepAssertion == 0 {
              IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "DeskPocket screen mirroring to linked phone" as CFString,
                &self.displaySleepAssertion
              )
            }
          }
        }
      }
    }
  }

  private func stopLocked() {
    idleTimer?.cancel()
    idleTimer = nil
    if let stream = stream {
      stream.stopCapture { _ in }
    }
    stream = nil
    starting = false
    if displaySleepAssertion != 0 {
      IOPMAssertionRelease(displaySleepAssertion)
      displaySleepAssertion = 0
    }
    frameLock.lock()
    latestBuffer = nil
    frameLock.unlock()
  }

  /// Stop capturing (and drop the macOS recording indicator) once no viewer
  /// has asked for a frame for a few seconds.
  private func startIdleTimerIfNeeded() {
    if idleTimer != nil { return }
    let timer = DispatchSource.makeTimerSource(queue: stateQueue)
    timer.schedule(deadline: .now() + 1, repeating: 1)
    timer.setEventHandler { [weak self] in
      guard let self = self else { return }
      if Date().timeIntervalSince(self.lastRequestAt) > 4 {
        self.stopLocked()
      }
    }
    idleTimer = timer
    timer.resume()
  }

  // MARK: SCStreamOutput / SCStreamDelegate

  func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
    guard type == .screen, sampleBuffer.isValid else { return }
    // Skip idle/blank status buffers; only complete frames carry an image.
    if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
       let rawStatus = attachments.first?[.status] as? Int,
       let status = SCFrameStatus(rawValue: rawStatus),
       status != .complete {
      return
    }
    guard let pixelBuffer = sampleBuffer.imageBuffer else { return }
    frameLock.lock()
    latestBuffer = pixelBuffer
    latestSeq &+= 1
    frameLock.unlock()
  }

  func stream(_ stream: SCStream, didStopWithError error: Error) {
    stateQueue.async {
      self.stream = nil
      self.starting = false
      self.lastError = "Screen capture stopped: \(error.localizedDescription)"
    }
  }

  private static func encodeJpeg(_ pixelBuffer: CVPixelBuffer, quality: Int, maxWidth: Int) -> Data? {
    var cgImage: CGImage?
    VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cgImage)
    guard var image = cgImage else { return nil }
    if maxWidth > 0 && image.width > maxWidth + 2 {
      let w = maxWidth - maxWidth % 2
      var h = Int((Double(image.height) * Double(w) / Double(image.width)).rounded())
      h -= h % 2
      if let ctx = CGContext(
        data: nil, width: w, height: max(2, h), bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
      ) {
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: max(2, h)))
        if let scaled = ctx.makeImage() { image = scaled }
      }
    }
    let output = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(
      output as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil
    ) else { return nil }
    let q = Double(min(max(quality, 1), 100)) / 100.0
    CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: q] as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { return nil }
    return output as Data
  }
}
