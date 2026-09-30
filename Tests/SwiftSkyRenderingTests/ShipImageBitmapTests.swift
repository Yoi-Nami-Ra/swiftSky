import Foundation
import Testing

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
}
