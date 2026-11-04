import Testing

@testable import SwiftSkySimulation

/// The ship carries a hold (022 FR-001, FR-012, FR-013); motion and autopilot never read it.
@Suite("Ship hold")
struct ShipHoldTests {
    @Test("The launch ship has a 20 t hold, empty")
    func launchHold() {
        let ship = Ship()
        #expect(ship.hold.capacity == CargoHold.defaultCapacity)
        #expect(ship.hold.capacity == 20)
        #expect(ship.hold.used == 0)
        #expect(ship.hold.free == 20)
    }

    @Test("Adding cargo to state.ship.hold mutates in place")
    func mutatesInPlace() {
        var state = SimulationState()
        #expect(state.ship.hold.add(5, of: 0) == nil)
        #expect(state.ship.hold.tons(of: 0) == 5)
        #expect(state.ship.hold.used == 5)
    }

    @Test("Ships differing only in hold are not equal")
    func equalityIncludesHold() {
        let empty = Ship()
        var loaded = Ship()
        #expect(empty == loaded)
        _ = loaded.hold.add(1, of: 0)
        #expect(empty != loaded)
    }

    @Test("Cargo changes no motion, autopilot or path bit after identical ticks")
    func cargoLeavesMotionAlone() {
        var plain = SimulationState()
        var laden = SimulationState()
        _ = laden.ship.hold.add(7, of: 1)
        _ = plain.setOrder(to: Vector2(x: 300, y: -150))
        _ = laden.setOrder(to: Vector2(x: 300, y: -150))
        let a = Simulation.advance(plain, ticks: 240)
        let b = Simulation.advance(laden, ticks: 240)
        #expect(bits(a) == bits(b))
        #expect(a.ship.hold != b.ship.hold)
        #expect(b.ship.hold.tons(of: 1) == 7)
    }
}
