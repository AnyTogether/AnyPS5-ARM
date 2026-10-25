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

    /// The size to capture `area` (points) at: its pixels (`scale` pixels a point, 2 on Retina),
    /// fitted within `maxWidth` x `maxHeight` with its shape kept, never below 160 x 90, in even
    /// numbers for the encoder. A 60 % window on a Retina display is 1152 x 648 points but
    /// 2304 x 1296 pixels: it streams at 1280 x 720, not 1152 x 648.
    public static func outputSize(area: CGSize, scale: CGFloat, maxWidth: Int, maxHeight: Int) -> (width: Int, height: Int) {
        let pixels = CGSize(width: area.width * max(1, scale), height: area.height * max(1, scale))
        guard pixels.width > 0, pixels.height > 0 else { return (160, 90) }
        let fit = min(1, CGFloat(maxWidth) / pixels.width, CGFloat(maxHeight) / pixels.height)
        return (max(160, Int((pixels.width * fit).rounded()) & ~1), max(90, Int((pixels.height * fit).rounded()) & ~1))
    }
}
