// Draws AnyPS5 Remote's 1024x1024 icon, the launcher's sibling: the cosmic theme's blue with
// flowing light, and a game controller.
//     swift icon.swift <output.png> full|background|foreground|tile
// full: the whole square (iOS rounds it itself); background and foreground: the two layers of
// Android's adaptive icon; tile: a rounded tile on transparent, for Android before 8.
import AppKit

let size: CGFloat = 1024
let kind = CommandLine.arguments[2]
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let context = NSGraphicsContext.current!.cgContext
let square = CGRect(x: 0, y: 0, width: size, height: size)
let tile = kind == "tile" ? square.insetBy(dx: 100, dy: 100) : square

if kind != "foreground" {
    context.saveGState()
    if kind == "tile" {
        context.addPath(CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil))
        context.clip()
    }
    let colors = [NSColor(red: 0.10, green: 0.30, blue: 0.80, alpha: 1).cgColor, NSColor(red: 0.02, green: 0.05, blue: 0.20, alpha: 1).cgColor] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: tile.midX, y: tile.maxY), end: CGPoint(x: tile.midX, y: tile.minY), options: [])
    let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [NSColor(red: 0.5, green: 0.75, blue: 1, alpha: 0.55).cgColor, NSColor(red: 0.5, green: 0.75, blue: 1, alpha: 0).cgColor] as CFArray, locations: [0, 1])!
    let light = CGPoint(x: tile.maxX - tile.width * 0.2, y: tile.maxY - tile.height * 0.15)
    context.drawRadialGradient(glow, startCenter: light, startRadius: 0, endCenter: light, endRadius: tile.width * 0.65, options: [])
    let unit = tile.width / 824
    for band in 0..<5 {
        let path = CGMutablePath()
        let b = CGFloat(band)
        path.move(to: CGPoint(x: tile.minX - 40, y: tile.minY + (250 + b * 26) * unit))
        path.addCurve(to: CGPoint(x: tile.maxX + 40, y: tile.minY + (300 + b * 18) * unit),
                      control1: CGPoint(x: tile.minX + 260 * unit, y: tile.minY + (420 - b * 30) * unit),
                      control2: CGPoint(x: tile.maxX - 260 * unit, y: tile.minY + (120 + b * 40) * unit))
        context.addPath(path)
        context.setStrokeColor(NSColor(red: 0.7, green: 0.85, blue: 1, alpha: 0.12 + 0.05 * b).cgColor)
        context.setLineWidth((5 - b * 0.6) * unit)
        context.setShadow(offset: .zero, blur: 18 * unit, color: NSColor(red: 0.6, green: 0.8, blue: 1, alpha: 0.8).cgColor)
        context.strokePath()
    }
    context.restoreGState()
}

if kind != "background" {
    // The controller fills less of a tile, and stays inside the adaptive icon's safe circle.
    let width = kind == "tile" ? size * 0.5 : size * (kind == "foreground" ? 0.46 : 0.6)
    let configuration = NSImage.SymbolConfiguration(pointSize: width, weight: .regular)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    let symbol = NSImage(systemSymbolName: "gamecontroller.fill", accessibilityDescription: nil)!.withSymbolConfiguration(configuration)!
    let height = width * symbol.size.height / symbol.size.width
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: NSColor(white: 0, alpha: 0.4).cgColor)
    symbol.draw(in: CGRect(x: (size - width) / 2, y: (size - height) / 2 + 10, width: width, height: height))
}
image.unlockFocus()

let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
