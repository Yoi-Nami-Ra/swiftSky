#if SWIFTSKY_INSTRUMENTATION
import Testing

@testable import SwiftSkyRendering
@testable import SwiftSkySimulation

@Suite("Debug overlay cargo lines")
struct DebugOverlayCargoTests {
    private let surface = RenderSurface(
        widthPixels: 2560, heightPixels: 1440, backingScale: 2,
        safeAreaInsets: SurfaceInsets(top: 24, left: 44, bottom: 0, right: 0)
    )
    private let statistics = DebugOverlayStatistics(
        meanFrameSeconds: 0.000_41, worstFrameSeconds: 0.000_97, budgetSeconds: 1.0 / 120.0,
        droppedFrames: 0, skippedFrames: 0, tickCount: 61
    )
    private let names = ["Ore", "Grain", "Fuel", "Alloys", "Spice", "Gems", "Water", "Tools"]

    private func lines(in buffer: TextBuffer) -> [String] {
        var lines: [String] = []
        var current = ""
        var lastY: UInt16?
        for instance in buffer.instances {
            if let lastY, instance.y != lastY {
                lines.append(current)
                current = ""
            }
            current.append(Character(Unicode.Scalar(UInt8(instance.cell) + GlyphAtlasBitmap.firstCode)))
            lastY = instance.y
        }
        lines.append(current)
        return lines
    }

    private func written(
        _ state: SimulationState, names: [String]? = nil, showsCargo: Bool = true
    ) -> (lines: [String], buffer: TextBuffer) {
        let overlay = DebugOverlay(commodityNames: names ?? self.names)
        overlay.showsCargo = showsCargo
        overlay.statistics = statistics
        overlay.ship = DebugOverlayShip(state)
        let buffer = TextBuffer(metrics: syntheticMetrics(scale: 2))
        buffer.clear()
        overlay.write(into: buffer, surface: surface)
        return (lines(in: buffer), buffer)
    }

    private func state(_ fill: (inout CargoHold) -> Void) -> SimulationState {
        var ship = Ship(limits: .default)
        fill(&ship.hold)
        return SimulationState(tickCount: 3, ship: ship)
    }

    @Test("An empty hold shows 0 / 20 and free 20, and no commodity line")
    func emptyHold() {
        let result = written(state { _ in })
        let tail = Array(result.lines.drop { !$0.hasPrefix("hold") })
        #expect(tail == ["hold    0 / 20 t  free 20"])
    }

    @Test("A partial hold lists only the non-zero commodities")
    func partialHold() {
        let result = written(state { hold in
            _ = hold.add(5, of: 0)
            _ = hold.add(7, of: 2)
        })
        let tail = Array(result.lines.drop { !$0.hasPrefix("hold") })
        #expect(tail == ["hold    12 / 20 t  free 8", "  Ore 5", "  Fuel 7"])
    }

    @Test("A full hold shows free 0")
    func fullHold() {
        let result = written(state { hold in _ = hold.add(20, of: 3) })
        let tail = Array(result.lines.drop { !$0.hasPrefix("hold") })
        #expect(tail == ["hold    20 / 20 t  free 0", "  Alloys 20"])
    }

    @Test("Non-ASCII names write ?, long names are cut to ten columns, missing names write ?")
    func nameEncoding() {
        let result = written(state { hold in
            _ = hold.add(1, of: 0)
            _ = hold.add(1, of: 1)
            _ = hold.add(1, of: 2)
        }, names: ["Zażółć", "Extraordinarily long", ])
        let tail = Array(result.lines.drop { !$0.hasPrefix("hold") })
        #expect(tail == ["hold    3 / 20 t  free 17", "  Za???? 1", "  Extraordin 1", "  ? 1"])
    }

    @Test("The worst case, 16 commodities held, fits the text capacity: 17 cargo lines, no overflow")
    func worstCase() {
        let longNames = (0..<16).map { _ in "NNNNNNNNNN" }
        var ship = Ship(limits: .default)
        ship.hold = CargoHold(capacity: 100_000_000, commodityCount: 16)
        var index = 0
        while index < 16 {
            _ = ship.hold.add(1_000_000, of: index)
            index += 1
        }
        let result = written(SimulationState(tickCount: 99, ship: ship), names: longNames)
        #expect(!result.buffer.didOverflow)
        let tail = Array(result.lines.drop { !$0.hasPrefix("hold") })
        #expect(tail.count == 17)
        #expect(result.buffer.count <= TextBuffer.capacity)
    }

    @Test("showsCargo == false removes every cargo line and changes nothing else")
    func cargoOff() {
        let held = state { hold in _ = hold.add(5, of: 0) }
        let on = written(held)
        let off = written(held, showsCargo: false)
        #expect(!off.lines.contains { $0.hasPrefix("hold") || $0.hasPrefix("  ") })
        #expect(Array(on.lines.prefix(off.lines.count)) == off.lines)
        #expect(on.lines.count > off.lines.count)
    }

    @Test("The snapshot reads the hold of the state it is taken from")
    func snapshot() {
        let held = state { hold in _ = hold.add(4, of: 1) }
        let cargo = try! #require(DebugOverlayShip(held).cargo)
        #expect(cargo.capacity == 20 && cargo.used == 4 && cargo.free == 16 && cargo.count == 16)
        #expect(cargo.amounts[1] == 4 && cargo.amounts[0] == 0)
    }
}
#endif
