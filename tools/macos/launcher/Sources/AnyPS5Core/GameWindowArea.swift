import CoreGraphics

/// The part of a game's window that share play, Remote Play and clips capture: the game, without
/// the title bar of a window that has one (the engine's windowed mode). WebRTC crops a 16:9
/// stream to 16:9, so a captured title bar showed half of itself and cut as much off the bottom.
public enum GameWindowArea {
    /// ScreenCaptureKit's sourceRect for `window` on `display`, both in global points with the
    /// origin top left (SCWindow and SCDisplay frames). A window as large as its display is full
    /// screen and has no title bar; any other loses the top `titleBar` points.
    public static func capture(window: CGRect, display: CGRect, titleBar: CGFloat) -> CGRect {
        let fullScreen = window.width >= display.width && window.height >= display.height
        let top = fullScreen || window.height <= titleBar * 2 ? 0 : max(0, titleBar)
        return CGRect(x: window.minX - display.minX, y: window.minY - display.minY + top, width: window.width, height: window.height - top)
    }
}
