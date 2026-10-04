import Foundation
import Testing

@testable import SwiftSkySimulation

/// The ship-pose blend (013 FR-002, FR-003, SC-001, SC-002). Exactness is asserted with `bits(_:)`.
@Suite("Ship pose")
struct ShipPoseTests {
    static let tau = 2 * Double.pi

    /// Signed angle from `a` to `b`, the short way, in [−π, π].
    static func arc(_ a: Double, _ b: Double) -> Double {
        (b - a).remainder(dividingBy: tau)
    }

    // MARK: - Exact endpoints (SC-001)

    @Test("Fraction 0 returns the previous pose bit for bit, signed zeros included")
    func fractionZero() {
        let previous = ShipPose(position: Vector2(x: -0.0, y: 12.5), heading: -0.0)
        let current = ShipPose(position: Vector2(x: 40, y: -7), heading: 1.2)
        #expect(bits(ShipPose.blended(from: previous, to: current, fraction: 0)) == bits(previous))
    }

    @Test("An equal pair blends to itself bit for bit at every fraction", arguments: [0.0, 0.25, 0.5, 0.999, 1.0.nextDown])
    func equalPair(fraction: Double) {
        let pose = ShipPose(position: Vector2(x: -0.0, y: 3.75), heading: -0.0)
        #expect(bits(ShipPose.blended(from: pose, to: pose, fraction: fraction)) == bits(pose))
    }

    @Test("A component equal in both poses keeps the previous pose's bits")
    func equalComponent() {
        let previous = ShipPose(position: Vector2(x: -0.0, y: 1), heading: 2)
        let current = ShipPose(position: Vector2(x: -0.0, y: 9), heading: 2)
        let blended = ShipPose.blended(from: previous, to: current, fraction: 0.5)
        #expect(blended.position.x.bitPattern == (-0.0).bitPattern)
        #expect(blended.heading.bitPattern == 2.0.bitPattern)
        #expect(blended.position.y == 5)
    }

    @Test("Out-of-range fractions are clamped into [0, 1)")
    func clampedFraction() {
        let previous = ShipPose(position: Vector2(x: 0, y: 0), heading: 0)
        let current = ShipPose(position: Vector2(x: 100, y: -50), heading: 1)
        #expect(bits(ShipPose.blended(from: previous, to: current, fraction: -1)) == bits(previous))
        #expect(
            bits(ShipPose.blended(from: previous, to: current, fraction: 2))
                == bits(ShipPose.blended(from: previous, to: current, fraction: 1.0.nextDown))
        )
    }

    // MARK: - Linear position, short-arc heading (SC-001, SC-002)

    /// SC-001: at least 1,000 pairs and fractions, each blended position within 1e-9 units of the point
    /// at that fraction along the segment, computed by the other lerp formula; and the heading on the
    /// short arc, in (−π, π].
    @Test("Seeded pairs blend onto the segment and the short arc")
    func seededPairs() {
        var generator = SplitMix64(seed: 0x013)
        for _ in 0..<2_000 {
            let previous = ShipPose(
                position: Vector2(x: generator.next(in: -10_000...10_000), y: generator.next(in: -10_000...10_000)),
                heading: generator.next(in: -Double.pi...Double.pi)
            )
            let current = ShipPose(
                position: Vector2(x: generator.next(in: -10_000...10_000), y: generator.next(in: -10_000...10_000)),
                heading: generator.next(in: -Double.pi...Double.pi)
            )
            let t = generator.next(in: 0...1.0.nextDown)
            let blended = ShipPose.blended(from: previous, to: current, fraction: t)

            let expectedX = previous.position.x * (1 - t) + current.position.x * t
            let expectedY = previous.position.y * (1 - t) + current.position.y * t
            #expect(abs(blended.position.x - expectedX) <= 1e-9)
            #expect(abs(blended.position.y - expectedY) <= 1e-9)

            let expectedHeading = previous.heading + Self.arc(previous.heading, current.heading) * t
            #expect(abs(Self.arc(expectedHeading, blended.heading)) <= 1e-12)
            #expect(abs(Self.arc(previous.heading, blended.heading)) <= abs(Self.arc(previous.heading, current.heading)) + 1e-12)
            #expect(blended.heading > -Double.pi && blended.heading <= Double.pi)
        }
    }

    @Test("Fractions approaching 1 approach the current pose")
    func approachesCurrent() {
        let previous = ShipPose(position: Vector2(x: -300, y: 20), heading: 3.0)
        let current = ShipPose(position: Vector2(x: 500, y: -80), heading: -3.0)
        let blended = ShipPose.blended(from: previous, to: current, fraction: 1.0.nextDown)
        #expect(abs(blended.position.x - current.position.x) <= 1e-9)
        #expect(abs(blended.position.y - current.position.y) <= 1e-9)
        #expect(abs(Self.arc(current.heading, blended.heading)) <= 1e-9)
    }

    @Test("Headings blend the short way across ±π, in both directions", arguments: [(3.1, -3.1), (-3.1, 3.1)])
    func acrossTheSeam(from: Double, to: Double) {
        let previous = ShipPose(position: .zero, heading: from)
        let current = ShipPose(position: .zero, heading: to)

        let halfway = ShipPose.blended(from: previous, to: current, fraction: 0.5).heading
        #expect(abs(Self.arc(.pi, halfway)) <= 1e-12)

        let quarter = ShipPose.blended(from: previous, to: current, fraction: 0.25).heading
        #expect(quarter.sign == from.sign)
        #expect(abs(quarter) > abs(from))
        for step in 1..<100 {
            let heading = ShipPose.blended(from: previous, to: current, fraction: Double(step) / 100).heading
            #expect(heading > -Double.pi && heading <= Double.pi)
            #expect(abs(heading) >= 3.1 - 1e-12)
        }
    }

    @Test("Exactly opposite headings blend counter-clockwise", arguments: [0.0, Double.pi / 2, -Double.pi / 2, 1.0])
    func oppositeHeadings(from: Double) {
        let to = Ship.wrapped(from + .pi)
        let previous = ShipPose(position: .zero, heading: from)
        let current = ShipPose(position: .zero, heading: to)
        let blended = ShipPose.blended(from: previous, to: current, fraction: 0.5).heading
        #expect(abs(Self.arc(from + .pi / 2, blended)) <= 1e-12)
        #expect(blended > -Double.pi && blended <= Double.pi)
    }

    @Test("A pose built from a ship carries its position and heading bit for bit")
    func fromShip() {
        let ship = Ship(position: Vector2(x: -0.0, y: 7), velocity: Vector2(x: 1, y: 2), heading: -2.5, angularVelocity: 0.3)
        let pose = ShipPose(ship)
        #expect(bits(pose) == [ship.position.x, ship.position.y, ship.heading].map(\.bitPattern))
    }
}

/// A pose's exact bits: x, y, heading.
func bits(_ pose: ShipPose) -> [UInt64] {
    [pose.position.x, pose.position.y, pose.heading].map(\.bitPattern)
}

/// A fixed-seed generator, so the seeded tests are deterministic (013 SC-006).
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func next(in range: ClosedRange<Double>) -> Double {
        Double.random(in: range, using: &self)
    }
}
