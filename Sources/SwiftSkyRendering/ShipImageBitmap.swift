import CoreGraphics
import Foundation
import ImageIO

/// Why the ship image could not be decoded (007 FR-005). The renderer turns each into
/// `RendererError.shipImageUnavailable(reason:)`.
enum ShipImageError: Error, Equatable, Sendable {
    /// There is no file at the URL.
    case missing

    /// The file exists but is not an image ImageIO can read.
    case undecodable

    /// The image decoded, but it is not 80 × 80 pixels.
    case wrongSize(width: Int, height: Int)
}

/// The ship image, decoded once on the CPU and ready to upload (007 FR-002–FR-004, research R2, R3).
///
/// Separate from the GPU texture it becomes, as `GlyphAtlasBitmap` is, so the headless tests can check
/// the decoding without a graphics device.
///
/// Four bytes per pixel, RGBA, row-major, top row first — the image's top edge is the ship's front
/// (005 FR-010). Colours are sRGB-encoded and **premultiplied**: every colour byte is at most its alpha
/// byte. That is what Core Graphics produces when it draws the file, and what, sampled from an sRGB
/// texture and blended `one` / `oneMinusSourceAlpha`, reproduces Core Graphics' own result over black
/// (research R3).
///
/// Built once at renderer initialisation (007 FR-003): it allocates the byte array and is never called
/// on the frame path.
struct ShipImageBitmap: Sendable {
    /// The image's width and height in pixels: 80, which is 40 points at 2× (005 FR-009).
    static let sizePixels = 80

    /// The copy shipped in the rendering layer's resource bundle, byte-identical to
    /// `design/sprites/ship.png` (research R1). `nil` if the bundle lacks it.
    static var bundledURL: URL? {
        Bundle.module.url(forResource: "ship", withExtension: "png")
    }

    let widthPixels: Int
    let heightPixels: Int
    let bytes: [UInt8]

    /// Decodes the image at `url`, whatever its bit depth and colour space, into 8-bit premultiplied
    /// sRGB.
    init(contentsOf url: URL) throws(ShipImageError) {
        guard FileManager.default.fileExists(atPath: url.path) else { throw .missing }
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw .undecodable }

        let size = Self.sizePixels
        guard image.width == size, image.height == size else {
            throw .wrongSize(width: image.width, height: image.height)
        }

        // Drawing into an 8-bit sRGB context converts depth and colour space in one step (research R2).
        // Same size in and out, so nothing is resampled.
        let bytesPerRow = size * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * size)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let space = CGColorSpace(name: CGColorSpace.sRGB),
                let context = CGContext(
                    data: buffer.baseAddress,
                    width: size,
                    height: size,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
                )
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
            return true
        }
        guard drawn else { throw .undecodable }

        // A bitmap context's memory is laid out top row first, the same as the texture's, so the rows
        // need no flipping.
        self.widthPixels = size
        self.heightPixels = size
        self.bytes = pixels
    }
}
