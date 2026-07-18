import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var windowChannel: FlutterMethodChannel?
  private var pictureInPictureRestoreState: PictureInPictureRestoreState?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()

    // Yerel başlık çubuğunu tamamen kaldır: içerik pencerenin üst kenarına
    // kadar uzanır, trafik ışıkları içeriğin üzerinde yüzer ve pencerenin
    // herhangi bir noktasından sürükleme yapılabilir.
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.styleMask.insert(.fullSizeContentView)
    self.isMovableByWindowBackground = true

    let channel = FlutterMethodChannel(
      name: "com.usenews/window",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "window_unavailable", message: nil, details: nil))
        return
      }

      switch call.method {
      case "enterPictureInPicture":
        self.enterPictureInPicture()
        result(true)
      case "exitPictureInPicture":
        self.exitPictureInPicture()
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.windowChannel = channel
  }

  private func enterPictureInPicture() {
    guard pictureInPictureRestoreState == nil else { return }

    pictureInPictureRestoreState = PictureInPictureRestoreState(
      frame: frame,
      level: level,
      collectionBehavior: collectionBehavior,
      contentAspectRatio: contentAspectRatio,
      minSize: minSize
    )

    level = .floating
    collectionBehavior.formUnion([.canJoinAllSpaces, .fullScreenAuxiliary])
    contentAspectRatio = NSSize(width: 16, height: 9)
    minSize = NSSize(width: 320, height: 180)

    let contentSize = NSSize(width: 480, height: 270)
    var pictureInPictureFrame = frameRect(
      forContentRect: NSRect(origin: .zero, size: contentSize)
    )
    if let visibleFrame = (screen ?? NSScreen.main)?.visibleFrame {
      pictureInPictureFrame.origin = NSPoint(
        x: visibleFrame.maxX - pictureInPictureFrame.width - 24,
        y: visibleFrame.minY + 24
      )
    }
    setFrame(pictureInPictureFrame, display: true, animate: true)
    makeKeyAndOrderFront(nil)
  }

  private func exitPictureInPicture() {
    guard let restoreState = pictureInPictureRestoreState else { return }

    level = restoreState.level
    collectionBehavior = restoreState.collectionBehavior
    contentAspectRatio = restoreState.contentAspectRatio
    minSize = restoreState.minSize
    setFrame(restoreState.frame, display: true, animate: true)
    pictureInPictureRestoreState = nil
  }
}

private struct PictureInPictureRestoreState {
  let frame: NSRect
  let level: NSWindow.Level
  let collectionBehavior: NSWindow.CollectionBehavior
  let contentAspectRatio: NSSize
  let minSize: NSSize
}
