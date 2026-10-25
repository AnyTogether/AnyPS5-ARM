import MetalKit
import SwiftUI

/// The themes' animated backgrounds, drawn by a fragment shader compiled at startup from the
/// source below (no metal toolchain needed to build the launcher). It renders at half the
/// window's pixel size: the backgrounds are soft, and the GPU is left to the games.
struct ThemeBackground: NSViewRepresentable {
    let theme: Theme
    /// A made theme's own colors in place of the built-in theme's.
    var palette: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)?
    var paused: Bool
    var speed: Float = 1

    func makeNSView(context: Context) -> BackgroundView {
        let view = BackgroundView()
        view.configure(theme: theme, palette: palette, paused: paused, speed: speed)
        return view
    }

    func updateNSView(_ view: BackgroundView, context: Context) {
        view.configure(theme: theme, palette: palette, paused: paused, speed: speed)
    }
}

final class BackgroundView: MTKView, MTKViewDelegate {
    struct Uniforms {
        var deep: SIMD4<Float>
        var middle: SIMD4<Float>
        var bright: SIMD4<Float>
        var size: SIMD2<Float>
        var time: Float
        var theme: Int32
    }

    private var queue: MTLCommandQueue?
    private var pipeline: MTLRenderPipelineState?
    private var theme = Theme.cosmic
    private var speed: Float = 1
    private var clock: Double = 0
    private var last = CACurrentMediaTime()
    private var palette: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>) = Theme.cosmic.palette

    init() {
        let device = MTLCreateSystemDefaultDevice()
        super.init(frame: .zero, device: device)
        delegate = self
        framebufferOnly = true
        autoResizeDrawable = false
        preferredFramesPerSecond = 60
        colorPixelFormat = .bgra8Unorm
        layer?.isOpaque = true
        // The clock starts somewhere in the middle of the animation, not at its quiet first frame.
        clock = Double.random(in: 40...400)
        guard let device else { return }
        queue = device.makeCommandQueue()
        do {
            let library = try device.makeLibrary(source: BackgroundView.shader, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "background_vertex")
            descriptor.fragmentFunction = library.makeFunction(name: "background_fragment")
            descriptor.colorAttachments[0].pixelFormat = colorPixelFormat
            pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            NSLog("AnyPS5 background shader: \(error)")
        }
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(theme: Theme, palette: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)? = nil, paused: Bool, speed: Float) {
        self.theme = theme
        let wanted = palette ?? theme.palette
        if wanted != self.palette {
            self.palette = wanted
            // A paused background shows the new colors too.
            if isPaused { needsDisplay = true }
        }
        self.speed = speed
        if isPaused != paused {
            isPaused = paused
            last = CACurrentMediaTime()
            if paused { needsDisplay = true }
        }
    }

    override func layout() {
        super.layout()
        let scale = (window?.backingScaleFactor ?? 2) * 0.5
        drawableSize = CGSize(width: max(1, bounds.width * scale), height: max(1, bounds.height * scale))
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        clock += min(0.1, now - last) * Double(speed)
        last = now
        guard let pipeline, let queue, let pass = currentRenderPassDescriptor, let drawable = currentDrawable,
              let commands = queue.makeCommandBuffer(), let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return }
        var uniforms = Uniforms(deep: SIMD4(palette.0, 1), middle: SIMD4(palette.1, 1), bright: SIMD4(palette.2, 1), size: SIMD2(Float(drawableSize.width), Float(drawableSize.height)), time: Float(clock.truncatingRemainder(dividingBy: 3600)), theme: Int32(theme.rawValue))
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commands.present(drawable)
        commands.commit()
    }

    /// One frame of a theme, drawn offscreen.
    static func still(theme: Theme, palette custom: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)? = nil, width: Int, height: Int, time: Float) -> NSImage? {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: shader, options: nil) else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "background_vertex")
        descriptor.fragmentFunction = library.makeFunction(name: "background_fragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        textureDescriptor.usage = [.renderTarget, .shaderRead]
        textureDescriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: textureDescriptor), let commands = queue.makeCommandBuffer() else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        let palette = custom ?? theme.palette
        var uniforms = Uniforms(deep: SIMD4(palette.0, 1), middle: SIMD4(palette.1, 1), bright: SIMD4(palette.2, 1), size: SIMD2(Float(width), Float(height)), time: time, theme: Int32(theme.rawValue))
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        guard let context = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
              let image = context.makeImage() else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: width, height: height))
    }

    static let shader = """
    #include <metal_stdlib>
    using namespace metal;

    struct Varyings { float4 position [[position]]; float2 uv; };
    struct Uniforms { float4 deep; float4 middle; float4 bright; float2 size; float time; int theme; };

    vertex Varyings background_vertex(uint id [[vertex_id]]) {
        float2 corner = float2((id << 1) & 2, id & 2);
        Varyings out;
        out.position = float4(corner * 2.0 - 1.0, 0.0, 1.0);
        out.uv = float2(corner.x, 1.0 - corner.y);
        return out;
    }

    float hash(float2 p) { p = fract(p * float2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
    float2 hash2(float2 p) { return float2(hash(p), hash(p + 17.17)); }

    float noise(float2 p) {
        float2 i = floor(p), f = fract(p);
        float2 u = f * f * (3.0 - 2.0 * f);
        return mix(mix(hash(i), hash(i + float2(1, 0)), u.x), mix(hash(i + float2(0, 1)), hash(i + float2(1, 1)), u.x), u.y);
    }

    float fbm(float2 p) {
        float value = 0.0, amplitude = 0.5;
        for (int octave = 0; octave < 5; octave++) { value += amplitude * noise(p); p = p * 2.03 + 11.7; amplitude *= 0.5; }
        return value;
    }

    // Drifting soft discs of light; `rate` moves them upwards.
    float bokeh(float2 p, float time, float cells, float rate, float seed) {
        float2 grid = p * cells;
        grid.y -= time * rate;
        float2 cell = floor(grid);
        float light = 0.0;
        for (int y = -1; y <= 1; y++) for (int x = -1; x <= 1; x++) {
            float2 here = cell + float2(x, y);
            float2 random = hash2(here + seed);
            float2 center = here + 0.5 + 0.38 * sin(random * 6.2831 + time * (0.15 + 0.2 * random.yx));
            float radius = mix(0.06, 0.24, random.x * random.x);
            float distance = length(grid - center);
            float twinkle = 0.55 + 0.45 * sin(time * (0.4 + random.y) + random.x * 40.0);
            float present = step(0.55, hash(here + seed * 3.1));
            light += present * twinkle * smoothstep(radius, radius * 0.25, distance) * (0.35 + 0.65 * random.y);
        }
        return light;
    }

    float3 cosmic(float2 uv, float aspect, float time, constant Uniforms& u) {
        float3 color = mix(u.middle.rgb * 1.15, u.deep.rgb, smoothstep(0.0, 1.0, uv.y * 0.85 + 0.08));
        color += u.bright.rgb * 0.28 * exp(-2.8 * length(float2((uv.x - 0.8) * aspect, uv.y - 0.08)));
        // Ribbons of light flowing across the lower half, as on the console's home screen.
        for (int band = 0; band < 6; band++) {
            float b = float(band);
            float center = 0.56 + 0.028 * b
                + 0.075 * sin(uv.x * (1.4 + 0.22 * b) + time * (0.10 + 0.021 * b) + b * 1.9)
                + 0.03 * sin(uv.x * 4.1 - time * 0.12 + b * 3.1);
            float distance = abs(uv.y - center);
            float core = 0.0016 / (distance + 0.0028);
            float haze = exp(-distance * 14.0);
            float fade = smoothstep(-0.15, 0.4, uv.x) * smoothstep(1.2, 0.6, uv.x);
            float pulse = 0.75 + 0.25 * sin(time * 0.3 + b * 1.7 + uv.x * 2.0);
            float3 tint = mix(u.bright.rgb, float3(0.85, 0.92, 1.0), 0.25 + 0.1 * b);
            color += tint * (core * 0.16 + haze * 0.1) * fade * pulse;
        }
        float2 p = float2(uv.x * aspect, uv.y);
        color += u.bright.rgb * 0.22 * bokeh(p, time, 5.0, 0.012, 1.0);
        color += float3(0.9, 0.95, 1.0) * 0.14 * bokeh(p, time * 1.3, 11.0, 0.02, 7.0);
        return color;
    }

    float3 aurora(float2 uv, float aspect, float time, constant Uniforms& u) {
        float3 color = mix(u.deep.rgb * 1.8, u.deep.rgb * 0.7, uv.y);
        float2 p = float2(uv.x * aspect, uv.y);
        for (int layer = 0; layer < 3; layer++) {
            float l = float(layer);
            float sway = fbm(float2(p.x * 0.7 + l * 3.7 + time * 0.02, time * 0.03 + l));
            float center = 0.30 + 0.09 * l + 0.36 * (sway - 0.5) + 0.05 * sin(p.x * 1.7 + time * 0.08 + l * 2.0);
            float thickness = 6.0 + 2.0 * l + 2.5 * sin(p.x * 1.3 + time * 0.05 + l);
            float below = uv.y - center;
            float curtain = exp(-below * below * thickness * thickness) * smoothstep(-0.35, 0.0, below + 0.12);
            float rays = smoothstep(0.15, 0.95, noise(float2(p.x * 16.0 + l * 7.0, time * 0.18 + p.x * 0.5)));
            float glow = curtain * (0.45 + 0.55 * rays);
            float3 tint = mix(u.bright.rgb, mix(float3(0.35, 0.55, 1.0), float3(0.75, 0.4, 1.0), l * 0.5), smoothstep(-0.05, 0.12, -below));
            color += tint * glow * (0.62 - 0.14 * l);
        }
        float2 starCell = floor(p * 150.0);
        float star = step(0.9965, hash(starCell)) * (0.55 + 0.45 * sin(time * 1.6 + hash(starCell + 3.0) * 30.0));
        float2 local = fract(p * 150.0) - 0.5;
        color += star * smoothstep(0.35, 0.0, length(local)) * smoothstep(0.8, 0.1, uv.y) * 0.9;
        color += u.middle.rgb * 0.45 * smoothstep(0.6, 1.0, uv.y) * (0.6 + 0.4 * fbm(float2(p.x * 1.5, time * 0.03)));
        return color;
    }

    float3 sunset(float2 uv, float aspect, float time, constant Uniforms& u) {
        float3 top = u.deep.rgb * 1.4;
        float3 middle = u.middle.rgb;
        float3 low = mix(u.bright.rgb, float3(1.0, 0.42, 0.38), 0.45) * 0.85;
        float3 color = mix(top, middle, smoothstep(0.0, 0.6, uv.y));
        color = mix(color, low, smoothstep(0.5, 1.1, uv.y));
        float2 p = float2(uv.x * aspect, uv.y);
        for (int blob = 0; blob < 6; blob++) {
            float b = float(blob);
            float2 center = float2((0.15 + 0.16 * b) * aspect + 0.14 * sin(time * (0.05 + 0.013 * b) + b * 2.0), 0.5 + 0.24 * sin(time * (0.04 + 0.01 * b) + b * 1.3));
            float radius = 0.2 + 0.07 * sin(b * 4.1);
            float light = exp(-dot(p - center, p - center) / (radius * radius));
            color += mix(u.bright.rgb, float3(1.0, 0.35, 0.6), fract(b * 0.37)) * light * 0.2;
        }
        color += mix(u.bright.rgb, float3(1.0, 0.8, 0.6), 0.4) * 0.22 * exp(-abs(uv.y - 0.76) * 5.0) * (0.85 + 0.15 * sin(uv.x * 2.4 + time * 0.15));
        color += float3(1.0, 0.85, 0.7) * 0.1 * bokeh(p, time, 7.0, -0.01, 3.0);
        return color;
    }

    // Glass: soft fields of glacier light seen through a pane of frosted ice. They drift very
    // slowly; two streaks of light cross where the pane refracts, cold at one edge; frost gathers
    // towards the corners; a fine grain that stays still, as frost does.
    float3 glass(float2 uv, float aspect, float time, constant Uniforms& u, float2 pixel) {
        float2 p = float2(uv.x * aspect, uv.y);
        float3 color = mix(u.middle.rgb * 0.8, u.deep.rgb, smoothstep(-0.15, 1.05, uv.y * 0.85 + 0.15 * (1.0 - uv.x)));
        for (int field = 0; field < 5; field++) {
            float f = float(field);
            float2 center = float2((0.12 + 0.2 * f) * aspect + 0.16 * sin(time * (0.019 + 0.005 * f) + f * 1.7),
                                   0.38 + 0.28 * sin(time * (0.015 + 0.004 * f) + f * 2.3));
            float radius = 0.34 + 0.1 * sin(f * 3.1);
            float light = exp(-dot(p - center, p - center) / (radius * radius));
            float3 tint = field == 1 ? float3(0.56, 0.62, 1.0) : (field == 3 ? float3(0.30, 0.82, 0.86) : u.bright.rgb);
            color += tint * light * (field == 1 ? 0.11 : 0.15);
        }
        color += u.bright.rgb * 0.24 * exp(-2.3 * length(float2((uv.x - 0.86) * aspect, uv.y + 0.12)));
        for (int streak = 0; streak < 2; streak++) {
            float s = float(streak);
            float along = uv.x * aspect * 0.55 + uv.y;
            float d = along - (0.62 + 0.62 * s + 0.05 * sin(time * 0.045 + s * 2.0));
            float band = exp(-d * d * (70.0 + 50.0 * s));
            float rim = exp(-(d - 0.03) * (d - 0.03) * 900.0);
            float fade = smoothstep(1.05, 0.2, uv.y);
            color += float3(0.80, 0.93, 1.0) * band * (0.085 - 0.03 * s) * fade;
            color += float3(0.45, 0.88, 1.0) * rim * 0.06 * fade;
        }
        // Crystals: the distance to the second nearest point less the nearest draws their edges.
        float2 grid = p * 7.0;
        float2 cell = floor(grid);
        float nearest = 8.0, second = 8.0;
        for (int y = -1; y <= 1; y++) for (int x = -1; x <= 1; x++) {
            float2 here = cell + float2(x, y);
            float2 site = here + hash2(here + 5.0);
            float distance = length(grid - site);
            if (distance < nearest) { second = nearest; nearest = distance; } else if (distance < second) { second = distance; }
        }
        float edge = smoothstep(0.09, 0.0, second - nearest);
        float corner = smoothstep(0.62, 1.2, length((uv - 0.5) * float2(aspect, 1.0)));
        float frost = fbm(p * 5.0 + 3.0);
        color += float3(0.72, 0.87, 1.0) * corner * (0.13 * frost + 0.07 * edge);
        color += (hash(floor(pixel)) - 0.5) * 0.03;
        return color;
    }

    fragment float4 background_fragment(Varyings in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
        float aspect = u.size.x / max(u.size.y, 1.0);
        float2 uv = in.uv;
        float time = u.time;
        float3 color = u.theme == 1 ? aurora(uv, aspect, time, u) : u.theme == 2 ? sunset(uv, aspect, time, u) : u.theme == 3 ? glass(uv, aspect, time, u, in.position.xy) : cosmic(uv, aspect, time, u);
        float2 centered = (uv - 0.5) * float2(aspect, 1.0);
        color *= 1.0 - (u.theme == 3 ? 0.3 : 0.45) * smoothstep(0.35, 1.25, length(centered));
        color = color / (1.0 + color * 0.35);
        color += (hash(in.position.xy + fract(time) * 91.0) - 0.5) / 255.0 * 2.0;
        return float4(color, 1.0);
    }
    """
}
