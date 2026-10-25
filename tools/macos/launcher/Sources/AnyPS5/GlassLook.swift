import AnyPS5Core
import AppKit
import SwiftUI

/// How the interface draws its surfaces: the dark panels of Cosmic, Aurora and Sunset, or the
/// Glass theme's layers of frosted ice, drawn as macOS 26's Liquid Glass where it can be.
struct Look: Equatable {
    var glass = false
    var rendering = GlassRendering.frosted
    var reduceMotion = false
    /// The main window: opaque, or in the Glass look see-through to the desktop under a tint.
    var window = GlassWindowRecipe.opaque

    /// The look of views hosted outside the main window (the trophy banner's panel).
    static var current = Look()

    var liquid: Bool { glass && rendering == .liquid }
    var solid: Bool { glass && rendering == .solid }

    /// The previews' stand-in for Reduce Transparency (ANYPS5_PREVIEW_REDUCE_TRANSPARENCY=1).
    static var forceSolid = false

    /// `seeThrough` is false where nothing can be behind the window (an offscreen render without
    /// a mock desktop); `transparency` is Settings → Appearance → Glass Transparency.
    static func make(style: Theme, reduceTransparency: Bool, offscreen: Bool, reduceMotion: Bool, transparency: Int? = nil, seeThrough: Bool = true) -> Look {
        guard style.isGlass else { return Look(reduceMotion: reduceMotion) }
        let reduceTransparency = reduceTransparency || forceSolid
        var liquidAvailable = false
        if #available(macOS 26, *) { liquidAvailable = true }
        let window = seeThrough ? GlassWindowRecipe.make(glass: true, reduceTransparency: reduceTransparency, transparency: transparency) : .opaque
        // The slider at 0 % is a solid pane: solid surfaces with it.
        let rendering: GlassRendering = seeThrough && !window.translucent ? .solid
            : .choose(reduceTransparency: reduceTransparency, liquidAvailable: liquidAvailable, offscreen: offscreen)
        return Look(glass: true, rendering: rendering, reduceMotion: reduceMotion, window: window)
    }

    /// The window lets the desktop through.
    var seeThrough: Bool { window.translucent }
}

private struct LookKey: EnvironmentKey {
    static let defaultValue = Look()
}

extension EnvironmentValues {
    var look: Look {
        get { self[LookKey.self] }
        set { self[LookKey.self] = newValue }
    }
}

/// The Glass theme's colors (GlassRecipe's numbers, where the contrast is tested).
enum Ice {
    static let navy = Color(recipe: GlassRecipe.surfaceBase)
    static let scrim = Color(recipe: GlassRecipe.scrim)
    static let ink = Color(recipe: GlassRecipe.ink)
    static let solid = Color(recipe: GlassRecipe.solid)
    /// The cold light along a surface's lower edge, where the rim refracts.
    static let cyan = Color(red: 0.60, green: 0.90, blue: 1.0)
    static let frost = Color(red: 0.86, green: 0.94, blue: 1.0)
}

extension Color {
    init(recipe rgb: GlassRecipe.RGB) {
        self.init(red: rgb.x, green: rgb.y, blue: rgb.z)
    }

    /// Ink for text drawn on this color as a fill: dark on light accents (Ice, White).
    var onFill: Color {
        guard let rgb = NSColor(self).usingColorSpace(.sRGB) else { return .white }
        return GlassRecipe.prefersDarkInk(on: GlassRecipe.RGB(Double(rgb.redComponent), Double(rgb.greenComponent), Double(rgb.blueComponent))) ? Ice.ink : .white
    }
}

/// Fine static grain, the frost in the glass: one small tile, made once.
enum Grain {
    static let image: NSImage = {
        let side = 128
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        for index in 0..<(side * side) {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let value = UInt8(truncatingIfNeeded: seed >> 56)
            let light = value > 127
            let alpha = UInt8(min(255, Int(abs(Int(value) - 128)) * 2))
            let tone: UInt8 = light ? 255 : 0
            // Premultiplied: the tone scaled by its alpha.
            let premultiplied = UInt8(Int(tone) * Int(alpha) / 255)
            pixels[index * 4] = premultiplied
            pixels[index * 4 + 1] = premultiplied
            pixels[index * 4 + 2] = premultiplied
            pixels[index * 4 + 3] = alpha
        }
        let context = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let image = context?.makeImage() else { return NSImage() }
        return NSImage(cgImage: image, size: NSSize(width: side / 2, height: side / 2))
    }()
}

struct GrainLayer: View {
    var strength = 0.05

    var body: some View {
        Image(nsImage: Grain.image)
            .resizable(resizingMode: .tile)
            .opacity(strength)
            .allowsHitTesting(false)
    }
}

/// Light on a glass edge: bright where it enters at the top, a cold glint where it leaves at the
/// lower corner, and a thin specular line just inside the top.
struct IceRim<S: InsettableShape>: View {
    let shape: S
    var strength = 1.0

    var body: some View {
        ZStack {
            shape.strokeBorder(LinearGradient(stops: [
                .init(color: .white.opacity(0.52 * strength), location: 0),
                .init(color: .white.opacity(0.12 * strength), location: 0.42),
                .init(color: .white.opacity(0.05 * strength), location: 0.7),
                .init(color: Ice.cyan.opacity(0.32 * strength), location: 1),
            ], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            shape.inset(by: 1).strokeBorder(LinearGradient(stops: [
                .init(color: .white.opacity(0.2 * strength), location: 0),
                .init(color: .white.opacity(0), location: 0.22),
            ], startPoint: .top, endPoint: .bottom), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

/// The frosted layers under a surface, where Liquid Glass is not drawn: the system's blur in a
/// window, a dark base that keeps white text readable, a sheen lit from the top left, and grain.
struct IceLayers<S: InsettableShape>: View {
    let shape: S
    var base = GlassRecipe.surfaceOpacity
    @Environment(\.look) private var look
    @Environment(\.previewRender) private var offscreen

    var body: some View {
        ZStack {
            if look.solid {
                shape.fill(Ice.solid)
            } else {
                if !offscreen { shape.fill(.ultraThinMaterial) }
                shape.fill(Ice.navy.opacity(base))
                shape.fill(LinearGradient(stops: [
                    .init(color: .white.opacity(GlassRecipe.sheenOpacity), location: 0),
                    .init(color: .white.opacity(0.03), location: 0.55),
                    .init(color: Ice.cyan.opacity(0.045), location: 1),
                ], startPoint: .topLeading, endPoint: .bottomTrailing))
                GrainLayer().clipShape(shape)
            }
        }
        .allowsHitTesting(false)
    }
}

/// A surface of the Glass look (Liquid Glass, frost or solid), or the dark frosted panel of the
/// other themes.
struct IceSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    /// The other themes' black under the material.
    var classicOpacity: Double = 0.38
    var interactive = false
    var shadow = true
    @Environment(\.look) private var look
    @Environment(\.scale) private var scale

    func body(content: Content) -> some View {
        if !look.glass {
            content
                .background(.ultraThinMaterial.opacity(0.55), in: shape)
                .background(Color.black.opacity(classicOpacity), in: shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
        } else if look.liquid {
            if #available(macOS 26, *) {
                content
                    .glassEffect(.regular.tint(Ice.navy.opacity(0.34)).interactive(interactive), in: shape)
                    .overlay(IceRim(shape: shape, strength: 0.45))
            } else {
                frosted(content)
            }
        } else {
            frosted(content)
        }
    }

    private func frosted(_ content: Content) -> some View {
        // A surface the other themes darken more floats over the interface (a toast, a notice):
        // its frost covers more of what is under it.
        let base = min(0.84, GlassRecipe.surfaceOpacity + max(0, classicOpacity - 0.38) * 1.5)
        return content
            .background(IceLayers(shape: shape, base: base))
            .overlay(IceRim(shape: shape))
            .shadow(color: .black.opacity(shadow ? 0.3 : 0), radius: 22 * scale, y: 10 * scale)
    }
}

/// The focused element in the Glass look: a bright frosted chip that dark ink reads on.
struct IceChip<S: InsettableShape>: View {
    let shape: S

    var body: some View {
        shape.fill(LinearGradient(colors: [Color.white.opacity(0.97), Ice.frost.opacity(0.88)], startPoint: .top, endPoint: .bottom))
            .overlay(shape.strokeBorder(LinearGradient(colors: [.white, Ice.cyan.opacity(0.75)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .allowsHitTesting(false)
    }
}

/// A button of the Glass look: a pane of glass that turns into the bright ice chip when focused.
/// With Liquid Glass, the focused button's glass carries the `lens` id, so that the focus slides
/// from button to button as one liquid shape inside their GlassEffectContainer.
struct ButtonGlass<S: InsettableShape>: ViewModifier {
    let shape: S
    let focused: Bool
    /// White over the frost while not focused (a prominent button, the pointer over it).
    var idle = 0.0
    var lens: (id: String, namespace: Namespace.ID)?
    @Environment(\.look) private var look
    @Environment(\.scale) private var scale

    func body(content: Content) -> some View {
        if look.liquid {
            if #available(macOS 26, *) {
                liquid(content)
            } else {
                frosted(content)
            }
        } else {
            frosted(content)
        }
    }

    @available(macOS 26, *)
    @ViewBuilder private func liquid(_ content: Content) -> some View {
        let glass = focused ? SwiftUI.Glass.regular.tint(Color.white.opacity(0.9)).interactive() : SwiftUI.Glass.regular.tint(Ice.navy.opacity(max(0.12, 0.32 - idle))).interactive()
        if let lens {
            content
                .glassEffect(glass, in: shape)
                .glassEffectID(focused ? "lens" : lens.id, in: lens.namespace)
                .shadow(color: Ice.cyan.opacity(focused ? 0.3 : 0), radius: 16 * scale)
        } else {
            content
                .glassEffect(glass, in: shape)
                .shadow(color: Ice.cyan.opacity(focused ? 0.3 : 0), radius: 16 * scale)
        }
    }

    private func frosted(_ content: Content) -> some View {
        content
            .background(
                ZStack {
                    if focused {
                        IceChip(shape: shape).transition(.opacity)
                    } else {
                        IceLayers(shape: shape, base: 0.34)
                        shape.fill(Color.white.opacity(idle))
                        IceRim(shape: shape, strength: 0.85)
                    }
                }
            )
            .shadow(color: focused ? Ice.cyan.opacity(0.34) : .black.opacity(0.22), radius: (focused ? 18 : 12) * scale, y: focused ? 0 : 5 * scale)
    }
}

/// A row's or button's fill: white when focused and `idle` otherwise, or in the Glass look the
/// ice chip with a cold glow when focused.
struct FocusFill<S: InsettableShape>: View {
    let shape: S
    let focused: Bool
    let idle: Color
    var rim = false
    @Environment(\.look) private var look
    @Environment(\.scale) private var scale

    init(_ shape: S, focused: Bool, idle: Color, rim: Bool = false) {
        self.shape = shape
        self.focused = focused
        self.idle = idle
        self.rim = rim
    }

    var body: some View {
        if look.glass {
            ZStack {
                if focused {
                    IceChip(shape: shape)
                        .shadow(color: Ice.cyan.opacity(0.32), radius: 16 * scale)
                        .transition(.opacity)
                } else {
                    shape.fill(idle)
                    if rim { IceRim(shape: shape, strength: 0.5) }
                }
            }
        } else {
            shape.fill(focused ? Color.white : idle)
        }
    }
}

/// A full-screen layer under a panel's content (settings, library, profile, the start splash):
/// black over the material, or the Glass look's navy frost with light from the top left.
struct FrostFill: View {
    var opacity: Double
    var tone = Color.black
    @Environment(\.look) private var look
    @Environment(\.previewRender) private var offscreen

    var body: some View {
        if look.glass {
            ZStack {
                if look.solid {
                    LinearGradient(colors: [Ice.solid, Color(recipe: GlassRecipe.scrim)], startPoint: .top, endPoint: .bottom)
                } else {
                    if !offscreen { Rectangle().fill(.ultraThinMaterial) }
                    Ice.scrim.opacity(GlassRecipe.screenOpacity * min(1, opacity / 0.74 * 0.9 + 0.1))
                    RadialGradient(colors: [Color.white.opacity(0.075), .clear], center: UnitPoint(x: 0.18, y: -0.15), startRadius: 0, endRadius: 1100)
                    LinearGradient(colors: [.clear, Ice.cyan.opacity(0.035)], startPoint: .top, endPoint: .bottom)
                    GrainLayer(strength: 0.035)
                }
            }
            .allowsHitTesting(false)
        } else {
            tone.opacity(opacity).background(.ultraThinMaterial)
        }
    }
}

/// A panel that slides in from the right: in the Glass look a sheet of glass whose left edge
/// catches the light.
struct PanelFrost: ViewModifier {
    var classic = 0.92
    @Environment(\.look) private var look
    @Environment(\.previewRender) private var offscreen

    func body(content: Content) -> some View {
        if !look.glass {
            content.background(Color(white: 0.06).opacity(classic).background(.ultraThinMaterial))
        } else if look.liquid {
            if #available(macOS 26, *) {
                content
                    .glassEffect(.regular.tint(Ice.navy.opacity(0.62)), in: Rectangle())
                    .overlay(edge, alignment: .leading)
            } else {
                frosted(content)
            }
        } else {
            frosted(content)
        }
    }

    private var edge: some View {
        LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.1), Ice.cyan.opacity(0.3)], startPoint: .top, endPoint: .bottom)
            .frame(width: 1)
    }

    private func frosted(_ content: Content) -> some View {
        content
            .background(ZStack {
                FrostFill(opacity: 0.92)
                // Offscreen nothing blurs what the panel covers, so it covers more of it.
                Ice.navy.opacity(look.solid ? 0 : (offscreen ? 0.86 : 0.22))
            })
            .overlay(edge, alignment: .leading)
            .shadow(color: .black.opacity(0.35), radius: 30, x: -8)
    }
}

/// A single sweep of light across a surface when it takes the focus, as over a pane of glass
/// turned towards the light. Glass look only, and not with Reduce Motion.
struct SheenSweep<S: Shape>: ViewModifier {
    let active: Bool
    let shape: S
    @Environment(\.look) private var look
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                if look.glass && !look.reduceMotion {
                    GeometryReader { proxy in
                        LinearGradient(stops: [.init(color: .white.opacity(0), location: 0), .init(color: .white.opacity(0.75), location: 0.5), .init(color: .white.opacity(0), location: 1)],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: max(40, proxy.size.width * 0.35), height: proxy.size.height * 2.2)
                            .rotationEffect(.degrees(20))
                            .position(x: proxy.size.width * (0.5 + phase * 0.95), y: proxy.size.height / 2)
                    }
                    .clipShape(shape)
                    .blendMode(.plusLighter)
                    .opacity(0.55)
                    .allowsHitTesting(false)
                }
            }
            .onChange(of: active) { _, now in
                guard now, look.glass, !look.reduceMotion else { return }
                var reset = Transaction()
                reset.disablesAnimations = true
                withTransaction(reset) { phase = -1 }
                withAnimation(.easeOut(duration: 0.7).delay(0.05)) { phase = 1 }
            }
    }
}

extension View {
    func iceSurface<S: InsettableShape>(_ shape: S, classicOpacity: Double = 0.38, interactive: Bool = false, shadow: Bool = true) -> some View {
        modifier(IceSurface(shape: shape, classicOpacity: classicOpacity, interactive: interactive, shadow: shadow))
    }

    /// The full-screen frost under a panel's content.
    func screenFrost(_ opacity: Double) -> some View { background(FrostFill(opacity: opacity)) }

    func panelFrost(classic: Double = 0.92) -> some View { modifier(PanelFrost(classic: classic)) }

    func sheenSweep<S: Shape>(_ active: Bool, in shape: S) -> some View { modifier(SheenSweep(active: active, shape: shape)) }

    /// Groups Liquid Glass shapes so that they blend and morph into each other as they move.
    @ViewBuilder func glassGroup(_ look: Look, spacing: CGFloat) -> some View {
        if look.liquid {
            if #available(macOS 26, *) {
                GlassEffectContainer(spacing: spacing) { self }
            } else {
                self
            }
        } else {
            self
        }
    }
}

/// The card that drops in over a game (trophies, notices, calls), in its own panel above every
/// window: dark, or in the Glass theme a pane of ice over whatever the game shows. The glass is a
/// layer behind the card's content, never around it, so the card always reads even where Liquid
/// Glass cannot draw; its navy keeps white text readable over a white game frame.
struct BannerGlass: ViewModifier {
    var radius: CGFloat = 20
    var still = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let look = Look.current
        if !look.glass {
            content.background(shape.fill(Color(white: 0.07).opacity(0.94)))
        } else {
            content
                .background {
                    ZStack {
                        if look.solid {
                            shape.fill(Ice.solid)
                        } else {
                            if look.liquid && !still {
                                if #available(macOS 26, *) {
                                    Color.clear.glassEffect(.regular, in: shape)
                                }
                            } else if !still {
                                shape.fill(.ultraThinMaterial)
                            }
                            shape.fill(Ice.navy.opacity(GlassRecipe.bannerOpacity))
                            shape.fill(LinearGradient(stops: [
                                .init(color: .white.opacity(GlassRecipe.sheenOpacity), location: 0),
                                .init(color: .white.opacity(0.02), location: 0.6),
                                .init(color: Ice.cyan.opacity(0.06), location: 1),
                            ], startPoint: .topLeading, endPoint: .bottomTrailing))
                            GrainLayer(strength: 0.04).clipShape(shape)
                        }
                    }
                }
                .overlay(IceRim(shape: shape))
                .environment(\.colorScheme, .dark)
        }
    }
}
