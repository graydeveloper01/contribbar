import AppKit
import CoreGraphics
import Foundation
import SwiftUI

/// A solid panel finish: a rendered plate (metal, gem or matte), ink engraved into it, and its own
/// ramp of contribution levels.
///
/// The plate is a static CPU port of an environment-mapped metal shader: a rounded plate with a
/// beveled rim, a gentle pillow curvature and a low-frequency "swell" in the face, reflecting a studio
/// of soft-box lights. Reflection brightness drives the colour (shadows → `deep`, body → `mid`, hot
/// highlights → `highlight`). `roughness` blurs the lights from mirror metal to matte; `gem` makes the
/// colour glow from within, with reflections only glossing the top.
struct Finish: Hashable, Sendable {
    typealias RGB = SIMD3<Double>

    let name: String
    // Plate
    let deep: RGB
    let mid: RGB
    let highlight: RGB
    let fresnel: RGB
    var faceBurn = 0.3
    var roughness = 0.0
    var gem = false
    // Content
    /// none … fourth, opaque: translucent fills would pick up the reflections behind them.
    let levels: [UInt32]
    let ink: UInt32
    /// Primary, secondary and tertiary ink opacity.
    var inkOpacity: (Double, Double, Double) = (0.92, 0.66, 0.45)
    /// Light ink (engraved with a dark edge above, tinted by `shadow`) or dark ink (light edge above).
    var darkInk = false
    var shadow: UInt32 = 0x000A3C

    static func == (a: Finish, b: Finish) -> Bool { a.name == b.name }
    func hash(into hasher: inout Hasher) { hasher.combine(name) }
}

extension Finish {
    private static let cobaltTint = rgb(0x2458FF)

    /// Anodized cobalt metal with fire-opal levels.
    static let cobalt = Finish(
        name: "Cobalt",
        deep: cobaltTint * RGB(0.18, 0.22, 0.42), mid: cobaltTint * 1.15, highlight: RGB(0.86, 0.92, 1),
        fresnel: RGB(0.75, 0.85, 1),
        levels: [0x2E4BC4, 0xB4492A, 0xDC5E2C, 0xF7853C, 0xFFBE7D],
        ink: 0xECF2FF
    )

    /// A glowing gem: warm core, glossy top, cobalt levels.
    static let fireOpal = Finish(
        name: "Fire Opal",
        deep: rgb(0x8A200E), mid: rgb(0xEC5A26), highlight: rgb(0xFFB85E), fresnel: RGB(1, 0.86, 0.72),
        gem: true,
        levels: [0xB9441F, 0x9DB2FF, 0x6383FF, 0x3359EE, 0x1733B0],
        ink: 0xFFF6EC, inkOpacity: (0.96, 0.80, 0.60), shadow: 0x3C0A00
    )

    /// Jewel-tone metal with marigold levels.
    static let emerald = Finish(
        name: "Emerald",
        deep: rgb(0x032A20), mid: rgb(0x0E8F6A) * 1.1, highlight: RGB(0.82, 1, 0.92), fresnel: RGB(0.75, 1, 0.9),
        levels: [0x14684F, 0x8A6E14, 0xC48E12, 0xF0AC1C, 0xFFD666],
        ink: 0xEAFFF6, shadow: 0x00281A
    )

    /// Matte warm powder coat, terracotta levels, dark ink. Colours are pre-compensated for the
    /// tonemap, which would otherwise pull cream (#E2CFAC → #F4EAD6 → #FFFCF6) down to khaki.
    static let sand = Finish(
        name: "Sand",
        deep: RGB(1.169, 1.036, 0.811), mid: RGB(1.303, 1.227, 1.084), highlight: RGB(1.389, 1.365, 1.318),
        fresnel: RGB(1.389, 1.373, 1.334),
        faceBurn: 0.6, roughness: 0.9,
        levels: [0xD6BF98, 0xE8B08A, 0xD98458, 0xC0603A, 0x8E3B22],
        ink: 0x3A2A1E, inkOpacity: (0.90, 0.68, 0.50), darkInk: true
    )

    static func rgb(_ hex: UInt32) -> RGB {
        RGB(Double((hex >> 16) & 0xFF), Double((hex >> 8) & 0xFF), Double(hex & 0xFF)) / 255
    }
}

// MARK: - Colours for SwiftUI

extension Finish {
    private static func color(_ hex: UInt32, _ opacity: Double = 1) -> Color {
        let c = rgb(hex)
        return Color(.sRGB, red: c.x, green: c.y, blue: c.z, opacity: opacity)
    }

    var inkPrimary: Color { Self.color(ink, inkOpacity.0) }
    var inkSecondary: Color { Self.color(ink, inkOpacity.1) }
    var inkTertiary: Color { Self.color(ink, inkOpacity.2) }

    /// Engraving: the edge above each glyph is in shadow, the edge below catches light (flipped for dark ink).
    var engraveAbove: Color { darkInk ? Color(.sRGB, white: 1, opacity: 0.38) : Self.color(shadow, 0.40) }
    var engraveBelow: Color { darkInk ? Color(.sRGB, white: 0, opacity: 0.16) : Color(.sRGB, white: 1, opacity: 0.16) }

    func levelColor(_ level: ContributionLevel) -> Color {
        let index = ContributionLevel.allCases.firstIndex(of: level) ?? 0
        return Self.color(levels[index])
    }

    /// Icons and "more than" highlights: the second-busiest level.
    var accent: Color { Self.color(levels[3]) }

    /// Light controls on the dark finishes, dark controls on Sand.
    var appearance: NSAppearance? { NSAppearance(named: darkInk ? .aqua : .darkAqua) }

    /// A menu chip: the plate's body colour with a dot of its busiest level.
    var swatch: NSImage {
        let body = NSColor(srgbRed: min(mid.x, 1), green: min(mid.y, 1), blue: min(mid.z, 1), alpha: 1)
        let dot = Self.rgb(levels[4])
        let image = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            body.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            NSColor(white: 0, alpha: 0.2).setStroke()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).stroke()
            NSColor(srgbRed: dot.x, green: dot.y, blue: dot.z, alpha: 1).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 4.5, dy: 4.5)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}

// MARK: - Plate rendering

enum PlateRender {
    /// Pixel dimensions of a plate.
    struct Geometry: Hashable, Sendable {
        let width: Int, height: Int, radius: Int, scale: Double

        init(size: CGSize, scale: CGFloat, cornerRadius: CGFloat) {
            width = Int((size.width * scale).rounded())
            height = Int((size.height * scale).rounded())
            radius = Int((cornerRadius * scale).rounded())
            self.scale = Double(scale)
        }
    }

    /// How the plate sits under the lights: `tilt` is the card's cursor tilt (-1...1 per axis),
    /// `drift` shifts the swell in the face.
    struct Pose: Sendable {
        var tilt: SIMD2<Double>
        var drift: Double

        /// Within the range the original card idles through, so every pose looks intended.
        static func random() -> Pose {
            Pose(tilt: SIMD2(.random(in: -0.45...0.45), .random(in: -0.3...0.3)), drift: .random(in: 0...200))
        }
    }

    private typealias V2 = SIMD2<Double>
    private typealias V3 = SIMD3<Double>

    /// The plate with transparent rounded corners. Takes ~50 ms (release) at 2x; safe off the main thread.
    /// All lengths below are in plate-height units (height = 1), centred on the plate, y up.
    static func render(_ geometry: Geometry, finish: Finish, pose: Pose) -> CGImage? {
        let (width, height) = (geometry.width, geometry.height)
        guard width > 0, height > 0 else { return nil }
        let h = Double(height)
        let aspect = Double(width) / h
        let plate = Plate(
            half: V2(aspect / 2, 0.5),
            radius: Double(geometry.radius) / h,
            bevel: 16 * geometry.scale / h,
            px: 1.5 / h,
            finish: finish,
            pose: pose
        )

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBufferPointer { buffer in
            let base = buffer.baseAddress!
            DispatchQueue.concurrentPerform(iterations: height) { row in
                for col in 0..<width {
                    let uv = V2((Double(col) + 0.5) / Double(width), 1 - (Double(row) + 0.5) / h)
                    let (rgb, alpha) = plate.shade((uv - 0.5) * V2(aspect, 1))
                    let o = (row * width + col) * 4
                    // Premultiplied RGBA.
                    base[o] = byte(rgb.x * alpha)
                    base[o + 1] = byte(rgb.y * alpha)
                    base[o + 2] = byte(rgb.z * alpha)
                    base[o + 3] = byte(alpha)
                }
            }
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }

    private struct Plate {
        let half: V2, radius: Double, bevel: Double, px: Double
        let m: Finish
        let soften: Double
        let view: V3, swellOffset: V2, cosY: Double, sinY: Double, cosX: Double, sinX: Double

        init(half: V2, radius: Double, bevel: Double, px: Double, finish: Finish, pose: Pose) {
            (self.half, self.radius, self.bevel, self.px, self.m) = (half, radius, bevel, px, finish)
            soften = finish.roughness * 0.45
            let t = pose.tilt
            view = normalize(V3(-t.x * 0.35, -t.y * 0.35, 1))
            swellOffset = V2(pose.drift * 0.04, -pose.drift * 0.03) + t * 0.25
            // The studio turns with the tilt: yaw by tilt.x, pitch by -0.7 tilt.y.
            (cosY, sinY) = (cos(t.x), sin(t.x))
            (cosX, sinX) = (cos(-t.y * 0.7), sin(-t.y * 0.7))
        }

        /// rotY(yaw) * rotX(pitch) * r
        func turn(_ r: V3) -> V3 {
            let x = V3(r.x, cosX * r.y - sinX * r.z, sinX * r.y + cosX * r.z)
            return V3(cosY * x.x + sinY * x.z, x.y, -sinY * x.x + cosY * x.z)
        }

        func shade(_ p: V2) -> (V3, Double) {
            let d = sdRoundRect(p, half, radius)
            let alpha = clamp(-d / px)
            guard alpha > 0 else { return (.zero, 0) }

            // Outward direction of the edge, for the rim's normal.
            let e = 0.0015
            let gD = normalize(V2(
                sdRoundRect(p + V2(e, 0), half, radius) - sdRoundRect(p - V2(e, 0), half, radius),
                sdRoundRect(p + V2(0, e), half, radius) - sdRoundRect(p - V2(0, e), half, radius)
            ) + 1e-6)

            // Rounded rim profile: steep at the edge, flat on the face.
            let t = clamp(-d / bevel)
            let u = 1 - t
            let slope = min(max(u / (max(1 - u * u, 1e-3)).squareRoot(), 0), 6)
            let rim = smoothstep(1, 0, t)
            var nxy = gD * slope * 0.9

            // Low-frequency swell across the face, plus a pillow curvature so highlights sweep across it.
            let q = p * 1.1 + swellOffset
            let h0 = swell(q)
            let gW = V2(swell(q + V2(0.03, 0)) - h0, swell(q + V2(0, 0.03)) - h0) / 0.03
            nxy += gW * 0.30 * (1 - rim) * (1 - 0.5 * m.roughness)
            nxy += p * V2(0.32, 0.42) * (1 - rim)
            let n = normalize(V3(nxy.x, nxy.y, 1))

            // Slight dispersion, strongest on the rim; none on rough surfaces.
            let incident = -view
            let disp = (0.025 + 0.09 * rim) * (1 - m.roughness)
            let nR = normalize(V3(n.x * (1 - disp), n.y * (1 - disp), n.z))
            let nB = normalize(V3(n.x * (1 + disp), n.y * (1 + disp), n.z))
            var col = V3(
                env(turn(reflect(incident, nR)), soften).x,
                env(turn(reflect(incident, n)), soften).y,
                env(turn(reflect(incident, nB)), soften).z
            )
            let lum = dot(col, V3(0.3, 0.5, 0.2))
            let fres = pow(1 - max(dot(n, view), 0), 5)

            if m.gem {
                // The body glows from within (a slow depth field and a warm core); reflections only gloss the top.
                let depth = swell(p * 1.4 + swellOffset * 0.6 + 5.3) / 1.3
                let core = 1 - smoothstep(0, 1.0, length((p - V2(0.08, -0.12)) * V2(0.7, 1.1)))
                var body = mix(m.deep, m.mid, smoothstep(0.05, 0.75, depth * 0.55 + core * 0.55))
                body = mix(body, m.highlight, smoothstep(0.55, 1.2, depth * 0.4 + core * 0.9) * 0.9)
                body *= 0.88 + 0.24 * smoothstep(0.2, 1.2, lum)
                body += V3(1, 0.95, 0.88) * smoothstep(1.05, 1.9, lum) * mix(0.16, 0.9, rim)
                col = body
            } else {
                // Anodize: reflection luminance drives the colour. Hot highlights burn fully on the rim but
                // only partly on the face, so the panel's text stays readable wherever a reflection lands.
                var a = mix(m.deep, m.mid, smoothstep(0.15, 0.85, lum))
                a = mix(a, m.highlight, smoothstep(0.95, 1.9, lum) * mix(m.faceBurn, 1, rim))
                a += (col - V3(repeating: lum)) * 0.45 * (1 - m.roughness)
                col = a
            }
            col = mix(col, m.fresnel, fres * 0.35)

            // Fine outer lip highlight, and an inner shade just under it.
            col += V3(repeating: 0.55 * (1 - 0.6 * m.roughness) * (1 - smoothstep(0, px * 2.5, Swift.abs(d + px * 1.2))))
            col *= 1 - 0.18 * smoothstep(0, 0.25, t) * (1 - smoothstep(0.25, 0.6, t))

            // Filmic-ish tonemap.
            col = pointwiseMax(col, .zero)  // colour fringes can dip below zero; pow() would give NaN
            col = col / (1 + col * 0.28)
            col = V3(pow(col.x, 0.95), pow(col.y, 0.95), pow(col.z, 0.95))
            return (col, alpha)
        }
    }

    /// The studio the plate reflects: a grey gradient, a horizon band and seven soft boxes.
    /// `soften` widens each light's falloff (and spreads its energy) for rougher surfaces.
    private static func env(_ r: V3, _ soften: Double) -> V3 {
        let sp = V2(atan2(r.x, r.z), asin(min(max(r.y, -1), 1)))
        let spread = 1 - 0.6 * soften
        func box(_ c: V2, _ hs: V2, _ soft: Double) -> Double { softbox(sp, c, hs, soft + soften) * spread }
        var col = mix(V3(0.30, 0.305, 0.32), V3(0.58, 0.59, 0.61), smoothstep(0, 1, r.y * 0.5 + 0.5))
        col += V3(repeating: 0.10 * exp(-pow((r.y + 0.02) * 9, 2)))
        col += V3(repeating: 1.7) * box(V2(-0.42, 0.30), V2(0.30, 0.24), 0.07)  // key, upper left
        col += V3(repeating: 1.5) * box(V2(0.55, 0.38), V2(0.16, 0.08), 0.04)   // hot panel, upper right
        col += V3(repeating: 1.2) * box(V2(0.30, -0.25), V2(0.07, 0.30), 0.05)  // strip, lower right
        col += V3(repeating: 1.3) * box(V2(-1.05, 0.05), V2(0.20, 0.45), 0.06)  // side panel, far left
        col += V3(repeating: 1.2) * box(V2(1.10, 0.10), V2(0.12, 0.50), 0.05)   // strip, far right
        col += V3(0.75, 0.80, 0.90) * box(V2(0.10, 0.95), V2(0.70, 0.10), 0.20) // ceiling
        col += V3(repeating: 0.25) * box(V2(-0.10, -0.60), V2(0.80, 0.18), 0.30) // floor bounce
        return col
    }

    private static func softbox(_ sp: V2, _ c: V2, _ hs: V2, _ soft: Double) -> Double {
        let q = abs(sp - c) - hs
        let d = length(pointwiseMax(q, .zero)) + min(max(q.x, q.y), 0)
        return 1 - smoothstep(-soft, soft, d)
    }

    private static func sdRoundRect(_ p: V2, _ b: V2, _ r: Double) -> Double {
        let q = abs(p) - b + r
        return length(pointwiseMax(q, .zero)) + min(max(q.x, q.y), 0) - r
    }

    // Two broad octaves of value noise; more would make the face look like lumpy foil.
    private static func swell(_ p: V2) -> Double { noise(p) + 0.3 * noise(p * 1.9 + 17.1) }

    private static func noise(_ p: V2) -> Double {
        let i = V2(p.x.rounded(.down), p.y.rounded(.down))
        let f = p - i
        let u = f * f * (3 - 2 * f)
        let a = hash(i), b = hash(i + V2(1, 0)), c = hash(i + V2(0, 1)), d = hash(i + V2(1, 1))
        return mix(mix(a, b, u.x), mix(c, d, u.x), u.y)
    }

    private static func hash(_ p: V2) -> Double { fract(sin(dot(p, V2(127.1, 311.7))) * 43758.5453) }

    // MARK: GLSL-style helpers

    private static func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
    private static func fract(_ x: Double) -> Double { x - x.rounded(.down) }
    private static func smoothstep(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
        let t = clamp((x - e0) / (e1 - e0))
        return t * t * (3 - 2 * t)
    }
    private static func mix(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
    private static func mix(_ a: V3, _ b: V3, _ t: Double) -> V3 { a + (b - a) * t }
    private static func dot(_ a: V2, _ b: V2) -> Double { (a * b).sum() }
    private static func dot(_ a: V3, _ b: V3) -> Double { (a * b).sum() }
    private static func length(_ v: V2) -> Double { dot(v, v).squareRoot() }
    private static func normalize(_ v: V2) -> V2 { v / length(v) }
    private static func normalize(_ v: V3) -> V3 { v / dot(v, v).squareRoot() }
    private static func abs(_ v: V2) -> V2 { V2(Swift.abs(v.x), Swift.abs(v.y)) }
    private static func reflect(_ i: V3, _ n: V3) -> V3 { i - 2 * dot(n, i) * n }
    private static func byte(_ x: Double) -> UInt8 { UInt8(clamp(x) * 255 + 0.5) }
}

/// Holds the plate on show and renders the next pose in the background, so each opening of the
/// panel reflects the lights differently without any work (or visible change) while it's open.
@MainActor
final class PlateRenderer: ObservableObject {
    static let shared = PlateRenderer()

    private struct Key: Equatable { let geometry: PlateRender.Geometry, finish: Finish }

    @Published private(set) var image: CGImage?
    private var key: Key?
    private var upcoming: CGImage?
    private var rendering: Task<Void, Never>?

    /// The plate to show. The first call, and any change of size, display scale or finish, renders synchronously.
    func use(_ geometry: PlateRender.Geometry, finish: Finish) {
        let key = Key(geometry: geometry, finish: finish)
        guard key != self.key else { return }
        self.key = key
        image = PlateRender.render(geometry, finish: finish, pose: .random())
        prepareNext()
    }

    /// Swap in the pre-rendered pose. Call while the panel is hidden.
    func advance() {
        guard let upcoming else { return }  // still rendering (very quick reopen): keep the current pose
        image = upcoming
        self.upcoming = nil
        prepareNext()
    }

    private func prepareNext() {
        rendering?.cancel()
        upcoming = nil
        guard let key else { return }
        rendering = Task {
            let next = await Task.detached(priority: .utility) {
                PlateRender.render(key.geometry, finish: key.finish, pose: .random())
            }.value
            guard !Task.isCancelled, key == self.key else { return }
            upcoming = next
        }
    }
}

/// A finish's plate, sized to whatever it sits behind.
struct FinishPlate: View {
    let finish: Finish
    let cornerRadius: CGFloat
    @Environment(\.displayScale) private var scale
    @ObservedObject private var renderer = PlateRenderer.shared

    var body: some View {
        GeometryReader { proxy in
            let geometry = PlateRender.Geometry(size: proxy.size, scale: scale, cornerRadius: cornerRadius)
            Group {
                if let image = renderer.image {
                    Image(decorative: image, scale: scale).resizable()
                }
            }
            .onAppear { renderer.use(geometry, finish: finish) }
            .onChange(of: geometry) { renderer.use(geometry, finish: finish) }
            .onChange(of: finish) { renderer.use(geometry, finish: finish) }
        }
    }
}
