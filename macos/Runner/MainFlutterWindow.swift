import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  private var windowChannel: FlutterMethodChannel?
  private var normalFrame: NSRect?
  private var normalMinSize = NSSize.zero
  private var normalLevel = NSWindow.Level.normal
  private var closeBehavior = "ask"

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    delegate = self
    let channel = FlutterMethodChannel(
      name: "ting_reader/window", binaryMessenger: flutterViewController.engine.binaryMessenger)
    windowChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      switch call.method {
      case "setWindowMode":
        self.setWindowMode(call.arguments as? String ?? "normal")
      case "setCloseBehavior":
        self.closeBehavior = call.arguments as? String ?? "ask"
      case "minimize": self.miniaturize(nil)
      case "close": self.performClose(nil)
      case "exit": NSApp.terminate(nil)
      case "toggleMaximize":
        self.zoom(nil)
        result(self.isZoomed)
        return
      case "startDragging":
        if let event = NSApp.currentEvent { self.performDrag(with: event) }
      default:
        result(FlutterMethodNotImplemented)
        return
      }
      result(nil)
    }

    super.awakeFromNib()
  }

  private func setWindowMode(_ mode: String) {
    if mode == "normal" {
      guard let previous = normalFrame else { return }
      minSize = normalMinSize
      level = normalLevel
      setFrame(previous, display: true)
      normalFrame = nil
      return
    }
    if normalFrame == nil {
      normalFrame = frame
      normalMinSize = minSize
      normalLevel = level
      level = .floating
    }
    if mode == "micro" {
      minSize = NSSize(width: 240, height: 88)
      setContentSize(NSSize(width: 300, height: 88))
    } else {
      minSize = NSSize(width: 420, height: 174)
      setContentSize(NSSize(width: 560, height: 174))
    }
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    if closeBehavior == "exit" { NSApp.terminate(nil) }
    else if closeBehavior == "minimize" { miniaturize(nil) }
    else { windowChannel?.invokeMethod("closeRequested", arguments: nil) }
    return false
  }
}
