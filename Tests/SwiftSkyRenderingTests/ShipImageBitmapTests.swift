import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import SwiftSkyRendering

/// The bundled ship image, decoded on the CPU (007 contract C11–C13). ImageIO and Core Graphics only —
/// no graphics device.
@Suite("ShipImageBitmap")
struct ShipImageBitmapTests {
    private func bundledBitmap() throws -> ShipImageBitmap {
        let url = try #require(ShipImageBitmap.bundledURL, "ship.png is missing from the rendering bundle")
        return try ShipImageBitmap(contentsOf: url)
    }

    // MARK: - The bundled image (C11, C12)

    @Test("The bundled image decodes to 80 × 80 RGBA pixels")
    func bundledImageDecodes() throws {
        let bitmap = try bundledBitmap()
        #expect(bitmap.widthPixels == 80)
        #expect(bitmap.heightPixels == 80)
        #expect(bitmap.bytes.count == 80 * 80 * 4)
    }

    @Test("Colours are premultiplied, with transparent and opaque pixels both present")
    func premultiplied() throws {
        let bytes = try bundledBitmap().bytes
        var transparent = 0
        var opaque = 0
        var notPremultiplied = 0
        for pixel in stride(from: 0, to: bytes.count, by: 4) {
            let alpha = bytes[pixel + 3]
            if alpha == 0 { transparent += 1 }
            if alpha == 255 { opaque += 1 }
            if bytes[pixel] > alpha || bytes[pixel + 1] > alpha || bytes[pixel + 2] > alpha {
                notPremultiplied += 1
            }
        }
        #expect(notPremultiplied == 0)
        #expect(transparent > 0)
        #expect(opaque > 0)
    }

    // MARK: - Failures (US4, C13)

    private func temporaryURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("swiftSky-\(UUID().uuidString)-\(name)")
    }

    @Test("No file at the URL is `missing`")
    func missingFile() {
        #expect(throws: ShipImageError.missing) {
            try ShipImageBitmap(contentsOf: temporaryURL("absent.png"))
        }
    }

    @Test("A file that is not an image is `undecodable`")
    func notAnImage() throws {
        let url = temporaryURL("text.png")
        try Data("not a png".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: ShipImageError.undecodable) {
            try ShipImageBitmap(contentsOf: url)
        }
    }

    @Test("An image that is not 80 × 80 is `wrongSize`")
    func wrongSize() throws {
        let url = temporaryURL("small.png")
        let context = try #require(
            CGContext(
                data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        let image = try #require(context.makeImage())
        let destination = try #require(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, image, nil)
        try #require(CGImageDestinationFinalize(destination))
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: ShipImageError.wrongSize(width: 16, height: 16)) {
            try ShipImageBitmap(contentsOf: url)
        }
    }
}
