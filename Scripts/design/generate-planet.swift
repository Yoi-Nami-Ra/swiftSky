// SKY-43: generates the planet sprite proposals procedurally.
//
// Writes design/proposal/43-planet-<variant>.png for the variants dunes, cratered and mesa:
// 1024 x 1024, sRGB, transparent. Then it reads each file back and prints the disc's measured width.
//
// The look (from .tickets/43.yaml): a warm orange-brown rocky or desert planet, top-down, lit from
// the upper left with a soft terminator and no fully black side, a thin atmosphere glow inside the
// disc edge, no ring, no moons, no text. The disc spans the whole image, the corners are transparent
// and the edge is anti-aliased (analytic coverage, one pixel wide).
//
// Usage (from the repository root):
//   swiftc -O Scripts/design/generate-planet.swift -o /tmp/generate-planet && /tmp/generate-planet
//   swift Scripts/design/generate-planet.swift [variant ...]     (slower: unoptimised)
//
// Output is deterministic: every variant uses a fixed seed.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Small vector maths

struct V3 {
    var x, y, z: Double
    init(_ x: Double, _ y: Double, _ z: Double) { self.x = x; self.y = y; self.z = z }
    static func + (a: V3, b: V3) -> V3 { V3(a.x + b.x, a.y + b.y, a.z + b.z) }
    static func - (a: V3, b: V3) -> V3 { V3(a.x - b.x, a.y - b.y, a.z - b.z) }
    static func * (a: V3, s: Double) -> V3 { V3(a.x * s, a.y * s, a.z * s) }
    func dot(_ b: V3) -> Double { x * b.x + y * b.y + z * b.z }
    func cross(_ b: V3) -> V3 { V3(y * b.z - z * b.y, z * b.x - x * b.z, x * b.y - y * b.x) }
    var length: Double { dot(self).squareRoot() }
    var normalized: V3 { self * (1 / length) }
}

func mix(_ a: V3, _ b: V3, _ t: Double) -> V3 { a + (b - a) * t }
func clamp01(_ v: Double) -> Double { min(1, max(0, v)) }
func smoothstep(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
    let t = clamp01((x - e0) / (e1 - e0))
    return t * t * (3 - 2 * t)
}

/// sRGB-encoded colour (0...255) to linear light.
func srgb(_ r: Double, _ g: Double, _ b: Double) -> V3 {
    func lin(_ c: Double) -> Double {
        let v = c / 255
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }
    return V3(lin(r), lin(g), lin(b))
}

func encode(_ v: Double) -> Double {
    let c = clamp01(v)
    return c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055
}

// MARK: - 3D value noise

struct Noise {
    let seed: UInt32

    private func hash(_ x: Int32, _ y: Int32, _ z: Int32) -> Double {
        var h = UInt32(bitPattern: x) &* 0x8DA6_B343
        h ^= UInt32(bitPattern: y) &* 0xD816_3841
        h ^= UInt32(bitPattern: z) &* 0xCB1A_B31F
        h ^= seed &* 0x2545_F491
        h ^= h >> 13
        h &*= 0x5BD1_E995
        h ^= h >> 15
        return Double(h) / Double(UInt32.max)
    }

    func value(_ p: V3) -> Double {
        let fx = floor(p.x), fy = floor(p.y), fz = floor(p.z)
        let ix = Int32(fx), iy = Int32(fy), iz = Int32(fz)
        func fade(_ t: Double) -> Double { t * t * t * (t * (t * 6 - 15) + 10) }
        let u = fade(p.x - fx), v = fade(p.y - fy), w = fade(p.z - fz)
        func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
        let c000 = hash(ix, iy, iz), c100 = hash(ix + 1, iy, iz)
        let c010 = hash(ix, iy + 1, iz), c110 = hash(ix + 1, iy + 1, iz)
        let c001 = hash(ix, iy, iz + 1), c101 = hash(ix + 1, iy, iz + 1)
        let c011 = hash(ix, iy + 1, iz + 1), c111 = hash(ix + 1, iy + 1, iz + 1)
        return lerp(
            lerp(lerp(c000, c100, u), lerp(c010, c110, u), v),
            lerp(lerp(c001, c101, u), lerp(c011, c111, u), v), w)
    }

    /// Fractal sum in 0...1. Every octave is rotated off the lattice axes, so value noise's
    /// straight cube-aligned edges don't show up as straight lines on the planet.
    func fbm(_ p: V3, octaves: Int, gain: Double = 0.5) -> Double {
        var sum = 0.0, amp = 1.0, norm = 0.0, q = skew(p)
        for _ in 0..<octaves {
            sum += value(q) * amp
            norm += amp
            amp *= gain
            q = skew(q) * 2.03 + V3(17.1, -9.7, 4.3)
        }
        return sum / norm
    }

    /// A fixed rotation with no axis-aligned component (rows of an orthonormal matrix).
    private func skew(_ p: V3) -> V3 {
        V3(
            0.00 * p.x + 0.80 * p.y + 0.60 * p.z,
            -0.80 * p.x + 0.36 * p.y - 0.48 * p.z,
            -0.60 * p.x - 0.48 * p.y + 0.64 * p.z)
    }
}

// MARK: - Variants

/// A surface: height (for bump shading) and albedo (linear) at a point on the unit sphere.
protocol Surface {
    func height(_ p: V3) -> Double
    func albedo(_ p: V3, height: Double) -> V3
    var bumpStrength: Double { get }
}

/// Wind-swept dune seas: sinuous bands of sand over a darker rocky floor.
struct Dunes: Surface {
    let n = Noise(seed: 4301)
    let bumpStrength = 0.9
    let sandLight = srgb(236, 168, 98), sand = srgb(206, 124, 62), rock = srgb(132, 72, 40)

    private func band(_ p: V3) -> Double {
        let warp = n.fbm(p * 2.2, octaves: 4)
        // Asymmetric ridge: a gentle windward slope and a steep slip face, like real dunes.
        let phase = (p.y * 1.0 + p.x * 0.35) * 42 + warp * 12
        let t = phase / (2 * Double.pi) - floor(phase / (2 * Double.pi))
        return t < 0.8 ? t / 0.8 : (1 - t) / 0.2
    }
    func height(_ p: V3) -> Double {
        let dunes = smoothstep(0.38, 0.62, n.fbm(p * 1.6 + V3(3, 1, 7), octaves: 5))
        return band(p) * 0.012 * dunes + n.fbm(p * 5, octaves: 4) * 0.03
    }
    func albedo(_ p: V3, height: Double) -> V3 {
        let field = n.fbm(p * 1.6 + V3(3, 1, 7), octaves: 5)
        let base = mix(rock, sand, smoothstep(0.35, 0.6, field))
        let c = mix(base, sandLight, band(p) * 0.6 * smoothstep(0.4, 0.65, field))
        let grain = 0.92 + 0.16 * n.value(p * 90)
        return c * grain
    }
}

/// An old, cratered rocky world.
struct Cratered: Surface {
    let n = Noise(seed: 4302)
    let bumpStrength = 1.4
    let craters: [(centre: V3, radius: Double)]
    let dust = srgb(214, 140, 84), rockA = srgb(170, 96, 56), rockB = srgb(118, 66, 42)

    init() {
        var state: UInt64 = 0x43_2024
        func rand() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 11) / Double(1 << 53)
        }
        var list: [(V3, Double)] = []
        for i in 0..<70 {
            let z = rand() * 2 - 1, a = rand() * 2 * Double.pi
            let r = (1 - z * z).squareRoot()
            let radius = i < 6 ? 0.12 + rand() * 0.1 : 0.025 + pow(rand(), 2) * 0.08
            list.append((V3(r * cos(a), r * sin(a), z), radius))
        }
        craters = list
    }

    func height(_ p: V3) -> Double {
        var h = n.fbm(p * 3, octaves: 5) * 0.06
        for c in craters {
            let d = (p - c.centre).length / c.radius
            if d < 1.8 {  // far enough out that the rim term is ~0: no visible cut-off ring
                let bowl = d < 1 ? (d * d - 1) * 0.6 : 0
                let rim = exp(-pow((d - 1) * 4.5, 2)) * 0.25
                h += (bowl + rim) * c.radius * 0.35
            }
        }
        return h
    }
    func albedo(_ p: V3, height: Double) -> V3 {
        let f = n.fbm(p * 2.4 + V3(5, 2, 9), octaves: 5)
        var c = mix(rockB, rockA, smoothstep(0.3, 0.6, f))
        c = mix(c, dust, smoothstep(0.55, 0.75, n.fbm(p * 1.2, octaves: 3)) * 0.7)
        return c * (0.9 + 0.2 * n.value(p * 70))
    }
}

/// Terraced mesas and canyons: layered plateaus in rust, ochre and pale sandstone.
struct Mesa: Surface {
    let n = Noise(seed: 4303)
    let bumpStrength = 1.1
    let canyon = srgb(120, 52, 30), rust = srgb(178, 86, 44), ochre = srgb(214, 138, 70),
        pale = srgb(238, 192, 136)

    private func raw(_ p: V3) -> Double { n.fbm(p * 2.1, octaves: 5, gain: 0.55) }
    func height(_ p: V3) -> Double {
        let r = raw(p) * 5
        let step = floor(r)
        let terraced = step + smoothstep(0.75, 0.95, r - step)
        return terraced * 0.018 + n.fbm(p * 12, octaves: 3) * 0.006
    }
    func albedo(_ p: V3, height: Double) -> V3 {
        let level = raw(p)
        var c = mix(canyon, rust, smoothstep(0.32, 0.42, level))
        c = mix(c, ochre, smoothstep(0.48, 0.56, level))
        c = mix(c, pale, smoothstep(0.62, 0.7, level) * 0.8)
        let strata = 0.97 + 0.06 * sin(level * 60)
        return c * strata * (0.93 + 0.14 * n.value(p * 80))
    }
}

// MARK: - Rendering

let size = 1024
let radius = Double(size) / 2
/// Towards the light, in image space with +y up and +z towards the viewer: upper left, in front.
let light = V3(-0.68, 0.62, 0.36).normalized
let glowColour = srgb(255, 190, 130)
/// Tilt so the texture isn't centred on the disc in a way that reads as a pattern.
let tiltCos = cos(0.35), tiltSin = sin(0.35)

func render(_ s: Surface) -> [UInt8] {
    var pixels = [UInt8](repeating: 0, count: size * size * 4)
    let eps = 0.004
    for row in 0..<size {
        for col in 0..<size {
            let px = Double(col) + 0.5 - radius
            let py = radius - (Double(row) + 0.5)
            let dist = (px * px + py * py).squareRoot()
            // Analytic edge coverage: 1 inside, 0 outside, linear over one pixel at the rim.
            let coverage = clamp01(radius - dist + 0.5)
            if coverage <= 0 { continue }

            // Sphere normal (clamped just inside the rim for the edge pixels).
            let d = min(dist, radius - 0.5) / radius
            let scale = dist > 0 ? d / (dist / radius) : 0
            let nx = px / radius * scale, ny = py / radius * scale
            let nz = max(0, 1 - nx * nx - ny * ny).squareRoot()
            let normal = V3(nx, ny, nz)
            // Texture coordinates: the sphere point rotated by a fixed tilt.
            let p = V3(nx, ny * tiltCos - nz * tiltSin, ny * tiltSin + nz * tiltCos)

            // Bump shading from the height field's tangential gradient.
            let h = s.height(p)
            // A 3D gradient projected onto the tangent plane: no tangent frame, so no seams.
            let grad = V3(
                s.height(p + V3(eps, 0, 0)) - h,
                s.height(p + V3(0, eps, 0)) - h,
                s.height(p + V3(0, 0, eps)) - h) * (1 / eps)
            let tangential = grad - p * grad.dot(p)
            var bumpedTex = (p - tangential * s.bumpStrength).normalized
            // Back into image space (inverse tilt).
            bumpedTex = V3(
                bumpedTex.x,
                bumpedTex.y * tiltCos + bumpedTex.z * tiltSin,
                -bumpedTex.y * tiltSin + bumpedTex.z * tiltCos)
            let shadingNormal = mix(normal, bumpedTex, smoothstep(0, 0.25, nz)).normalized

            // Wrapped diffuse for a soft terminator; a cool ambient so no side goes black.
            let wrap = 0.25
            let geo = clamp01((normal.dot(light) + wrap) / (1 + wrap))
            let detail = clamp01((shadingNormal.dot(light) + wrap) / (1 + wrap))
            let diffuse = pow(geo * 0.4 + detail * 0.6, 1.25)
            let ambient = 0.06 + 0.04 * detail
            let albedo = s.albedo(p, height: h)
            var c = albedo * (min(diffuse, 1.4) * 1.05 + ambient)
            c = c + V3(0.012, 0.010, 0.016)  // faint sky fill, keeps the night side readable

            // Thin atmosphere inside the edge: a rim term, brighter on the lit limb.
            let rim = pow(1 - nz, 2.6)
            let litLimb = 0.25 + 0.75 * clamp01((normal.dot(light) + 0.4) / 1.4)
            c = c + glowColour * (rim * 1.1 * litLimb)

            let i = (row * size + col) * 4
            pixels[i + 0] = UInt8((encode(c.x) * coverage * 255).rounded())
            pixels[i + 1] = UInt8((encode(c.y) * coverage * 255).rounded())
            pixels[i + 2] = UInt8((encode(c.z) * coverage * 255).rounded())
            pixels[i + 3] = UInt8((coverage * 255).rounded())
        }
    }
    return pixels
}

func writePNG(_ pixels: [UInt8], to url: URL) throws {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let data = Data(pixels) as CFData
    let image = CGImage(
        width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
        space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: CGDataProvider(data: data)!, decode: nil, shouldInterpolate: false,
        intent: .defaultIntent)!
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw CocoaError(.fileWriteUnknown) }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
}

/// Reads the PNG back and measures the disc: the bounding box of pixels with non-zero alpha.
func measure(_ url: URL) -> (width: Int, height: Int, cornersClear: Bool, minLitAlphaRGB: Int)? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
    let w = image.width, h = image.height
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(
        data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    var minX = w, maxX = -1, minY = h, maxY = -1, darkest = 255
    for y in 0..<h {
        for x in 0..<w {
            let i = (y * w + x) * 4
            let a = buf[i + 3]
            if a == 0 { continue }
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            if a == 255 { darkest = min(darkest, Int(max(buf[i], buf[i + 1], buf[i + 2]))) }
        }
    }
    let corners = [0, w - 1, (h - 1) * w, h * w - 1].allSatisfy { buf[$0 * 4 + 3] == 0 }
    return (maxX - minX + 1, maxY - minY + 1, corners, darkest)
}

// MARK: - Main

let variants: [(String, Surface)] = [("dunes", Dunes()), ("cratered", Cratered()), ("mesa", Mesa())]
let wanted = Set(CommandLine.arguments.dropFirst())
let outDir = URL(fileURLWithPath: "design/proposal", isDirectory: true)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

for (name, surface) in variants where wanted.isEmpty || wanted.contains(name) {
    let url = outDir.appendingPathComponent("43-planet-\(name).png")
    try writePNG(render(surface), to: url)
    guard let m = measure(url) else { fatalError("could not read back \(url.path)") }
    print("\(url.path): disc \(m.width) x \(m.height) px, corners transparent: \(m.cornersClear), "
        + "darkest opaque pixel max channel: \(m.minLitAlphaRGB)")
}
