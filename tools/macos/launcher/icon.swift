// Draws the launcher's 1024x1024 icon: the cosmic theme's blue with flowing light, and a play mark.
//     swift icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let context = NSGraphicsContext.current!.cgContext
let inset: CGFloat = 100
let tile = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let shape = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

context.saveGState()
context.addPath(shape)
context.clip()
let colors = [NSColor(red: 0.10, green: 0.30, blue: 0.80, alpha: 1).cgColor, NSColor(red: 0.02, green: 0.05, blue: 0.20, alpha: 1).cgColor] as CFArray
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
context.drawLinearGradient(gradient, start: CGPoint(x: tile.midX, y: tile.maxY), end: CGPoint(x: tile.midX, y: tile.minY), options: [])
let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [NSColor(red: 0.5, green: 0.75, blue: 1, alpha: 0.55).cgColor, NSColor(red: 0.5, green: 0.75, blue: 1, alpha: 0).cgColor] as CFArray, locations: [0, 1])!
context.drawRadialGradient(glow, startCenter: CGPoint(x: tile.maxX - 160, y: tile.maxY - 120), startRadius: 0, endCenter: CGPoint(x: tile.maxX - 160, y: tile.maxY - 120), endRadius: 520, options: [])
for band in 0..<5 {
    let path = CGMutablePath()
    let b = CGFloat(band)
    path.move(to: CGPoint(x: tile.minX - 40, y: tile.minY + 250 + b * 26))
    path.addCurve(to: CGPoint(x: tile.maxX + 40, y: tile.minY + 300 + b * 18), control1: CGPoint(x: tile.minX + 260, y: tile.minY + 420 - b * 30), control2: CGPoint(x: tile.maxX - 260, y: tile.minY + 120 + b * 40))
    context.addPath(path)
    context.setStrokeColor(NSColor(red: 0.7, green: 0.85, blue: 1, alpha: 0.12 + 0.05 * b).cgColor)
    context.setLineWidth(5 - b * 0.6)
    context.setShadow(offset: .zero, blur: 18, color: NSColor(red: 0.6, green: 0.8, blue: 1, alpha: 0.8).cgColor)
    context.strokePath()
}
context.restoreGState()

// The play mark: a rounded triangle in a thin ring.
let center = CGPoint(x: size / 2, y: size / 2 + 20)
context.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: NSColor(white: 0, alpha: 0.4).cgColor)
context.setStrokeColor(NSColor(white: 1, alpha: 0.9).cgColor)
context.setLineWidth(26)
context.strokeEllipse(in: CGRect(x: center.x - 230, y: center.y - 230, width: 460, height: 460))
let triangle = CGMutablePath()
let radius: CGFloat = 120
let points = (0..<3).map { index -> CGPoint in
    let angle = CGFloat(index) * 2 * .pi / 3
    return CGPoint(x: center.x + 18 + cos(angle) * radius * 1.15, y: center.y + sin(angle) * radius * 1.15)
}
triangle.move(to: CGPoint(x: (points[0].x + points[1].x) / 2, y: (points[0].y + points[1].y) / 2))
for index in 0..<3 {
    let corner = points[(index + 1) % 3]
    let next = points[(index + 2) % 3]
    triangle.addArc(tangent1End: corner, tangent2End: CGPoint(x: (corner.x + next.x) / 2, y: (corner.y + next.y) / 2), radius: 34)
}
triangle.closeSubpath()
context.addPath(triangle)
context.setFillColor(NSColor.white.cgColor)
context.fillPath()
image.unlockFocus()

let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
