# Feature Specification: Ship Cargo Hold

**Feature Branch**: `sky-52-cargo-hold` (spec number 022)

**Created**: 2026-11-04

**Status**: Draft

**Input**: User description: "SKY-52 — Add a cargo hold to the ship" (`.tickets/52.yaml`, parent SKY-48).
The ship gets a cargo capacity (tons) and a hold of commodity amounts; the commodity list (name, id, base
price) comes from a bundled data file. Logic layer only. Done when: headless tests cover adding and
removing cargo, the capacity limit and rejecting negative amounts; the debug overlay (SKY-29) shows the
used and free capacity.

## Overview

SKY-48 turns the single flying ship into a trading game: buy cargo cheap, jump, sell it dear. Every
later step of that loop (the market, docking, the docked screen, save and load) needs somewhere to put
what the ship carries. This feature gives the ship that place: a hold with a fixed capacity in whole
tons, holding whole tons of each of a fixed list of commodities, and the rules for putting cargo in and
taking it out.

The commodity list (a stable id, a display name and a base price for each commodity) is data, not code:
it is read from a data file that ships inside the logic layer's own resources, so later tickets can add or
retune commodities by editing the file.

Nothing in the game adds or removes cargo yet (the market is SKY-53, docking SKY-50). The player cannot
change the hold in this feature; what can be done is to read it and to see it on the debug overlay, and
the rules are proved by headless tests.

Out of scope: buying, selling and prices changing with supply (SKY-53), docking and the docked screen
(SKY-50, SKY-51), saving and loading the hold (SKY-57), any player-facing display of the hold, cargo
that affects the ship's mass or thrust, and a keyed lookup of ship data with the cargo inside it (a
separate, later ticket; see FR-011).

### Relationship to earlier specs

- **Extended**: 004's `Ship` gains a hold. 015's debug overlay gains cargo lines.
- **Unchanged and still absolute**: 004's per-tick motion rule and 006's autopilot are not affected by the
  hold; 003/015's overlay rules (absent from plain Release, 4 Hz refresh, no per-frame allocation,
  `--no-debug-overlay` hides everything) still hold for the new lines; the logic layer declares no
  dependencies (001) and stays free of rendering and platform code.

## Decisions

Decisions given by the user for this ticket (not assumptions):

- **D1**: The commodity data file lives in the logic target (`SwiftSkySimulation`) resources.
- **D2**: Cargo amounts and the capacity are whole tons (integers).
- **D3**: The default capacity is 20 tons.
- **D4**: The debug overlay is in scope: it shows the current ship's cargo (used and free), behind a toggle
  that switches it on and off.
- **D5**: A keyed lookup of ship data with the cargo inside it is wanted eventually but is another ticket,
  out of scope here. The hold stays simple and is not shaped so as to block such a lookup later.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Load and unload cargo within the capacity (Priority: P1)

A developer (and, later, the market and docking code) can put a whole number of tons of a commodity into
the ship's hold and take it out again. The hold never holds more than its capacity and never holds a
negative amount of anything.

**Why this priority**: This is the whole point of the hold; every trade step builds on it.

**Independent Test**: Headless tests on a launch ship (capacity 20 t): add 5 t of one commodity and read
it back, remove 2 t, fill to exactly 20 t, then fail to add 1 more.

**Acceptance Scenarios**:

1. **Given** an empty launch hold, **When** 5 t of a commodity is added, **Then** the hold contains 5 t of
   it, 5 t are used and 15 t are free.
2. **Given** a hold with 5 t of a commodity, **When** 2 t of it is removed, **Then** it contains 3 t.
3. **Given** a hold with 19 t used, **When** 2 t is added, **Then** the add is rejected and the hold is
   unchanged (nothing is partly loaded).
4. **Given** a hold with 3 t of a commodity, **When** 4 t of it is removed, **Then** the removal is
   rejected and the hold is unchanged.
5. **Given** a hold, **When** 0 t is added or removed, **Then** the hold is unchanged (not an error).

---

### User Story 2 - Reject bad amounts and unknown commodities (Priority: P1)

An add or remove with a negative amount, or for a commodity that is not in the commodity list, is
rejected with a reason and changes nothing.

**Why this priority**: Required by the ticket; a hold that can be driven negative or over capacity breaks
every later rule.

**Independent Test**: Headless tests: add −1 t, remove −1 t, and add to an unknown commodity id; each is
rejected and the hold is bit-for-bit unchanged.

**Acceptance Scenarios**:

1. **Given** any hold, **When** a negative amount is added or removed, **Then** it is rejected and the hold
   is unchanged.
2. **Given** any hold, **When** a commodity id that is not in the list is used, **Then** it is rejected and
   the hold is unchanged.

---

### User Story 3 - Commodities come from a bundled data file (Priority: P2)

The list of commodities (id, name, base price) is read from a data file bundled with the logic layer. A
developer adds a commodity by adding an entry to the file, with no code change.

**Why this priority**: The hold needs the list to exist, but a short fixed starter list is enough to prove
the rest; tuning the list is later work.

**Independent Test**: A headless test loads the bundled file and checks the list: not empty, ids unique,
every price positive. Tests on a malformed file check that it is rejected clearly.

**Acceptance Scenarios**:

1. **Given** the bundled file, **When** the list is loaded, **Then** every commodity has a unique id, a
   non-empty name and a positive base price.
2. **Given** a file with a duplicate id, an empty name or a non-positive price, **When** it is loaded,
   **Then** loading fails with an error that names the problem, and no partial list is used.

---

### User Story 4 - See the hold on the debug overlay (Priority: P2)

On a Debug or instrumented Release build, the debug overlay shows the used and free capacity of the
ship's hold, and the amount of each commodity held. A toggle switches these cargo lines on and off.

**Why this priority**: Required by the ticket's "done when"; it is the only way to see the hold before
the market exists.

**Independent Test**: Headless tests on the overlay's cargo text for known holds (empty, partly filled,
full) and on the toggle's state; then, by hand, launch the app and see the lines appear and disappear.

**Acceptance Scenarios**:

1. **Given** an empty launch ship and the cargo lines on, **When** the overlay is drawn, **Then** it shows
   `0 / 20` used and 20 free tons.
2. **Given** a hold with cargo, **When** the overlay refreshes, **Then** the used and free tons and the
   non-zero commodity amounts match the ship's hold as of the latest tick.
3. **Given** the cargo lines are switched off, **When** the overlay is drawn, **Then** no cargo line is
   shown and the other overlay lines are unchanged.
4. **Given** a plain Release build, **Then** none of the cargo overlay's strings are present.

### Edge Cases

- Adding exactly the free capacity succeeds (hold full, 0 t free); adding one ton more fails.
- A hold with capacity 0 accepts no cargo and shows 0 / 0.
- An amount large enough to overflow the integer arithmetic is rejected as over capacity, never wrapping.
- A removal that would leave exactly 0 t of a commodity leaves it with no entry (or an entry of 0; both read
  as 0 t).
- Adding cargo changes nothing about the ship's position, velocity, heading or the autopilot.
- A hold read before any cargo is added shows every commodity at 0 t.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The ship MUST have a hold with a capacity in whole tons. The launch ship's capacity MUST be 20
  tons (D2, D3).
- **FR-002**: The hold MUST record a whole-ton amount for each commodity in the commodity list; a commodity
  never added has 0 t.
- **FR-003**: The hold MUST report its used tons (the sum of all amounts), its free tons (capacity minus
  used) and the amount of any one commodity.
- **FR-004**: Adding cargo MUST succeed only when the amount is not negative, the commodity is in the list,
  and used plus the amount does not exceed the capacity. Otherwise it MUST be rejected with a reason and
  leave the hold unchanged. A rejected add never loads part of the amount.
- **FR-005**: Removing cargo MUST succeed only when the amount is not negative, the commodity is in the
  list, and the hold has at least that amount of it. Otherwise it MUST be rejected with a reason and leave
  the hold unchanged.
- **FR-006**: Adding or removing 0 t MUST succeed and change nothing.
- **FR-007**: The invariants "no amount is negative" and "used never exceeds capacity" MUST hold after every
  operation, including on arithmetic overflow.
- **FR-008**: The commodity list (stable id, display name, base price) MUST be read from a data file bundled
  in the logic layer's resources (D1). Ids MUST be unique, names non-empty and base prices positive; a
  file that breaks this MUST fail to load with an error naming the problem.
- **FR-009**: The cargo hold and its rules MUST live in the logic layer, MUST be plain value types with no
  rendering, platform or Metal dependency, and MUST be testable headlessly.
- **FR-010**: The debug overlay MUST show the ship's hold on lines under the existing ship and order lines:
  used tons, free tons and capacity, and the amount of each commodity held, taken from the latest
  completed tick (as 015's values are, never an interpolated one). It MUST be refreshed at the overlay's
  4 Hz, MUST add no per-frame allocation, MUST be absent from plain Release builds, and MUST NOT be exposed
  to assistive technology (D4).
- **FR-011**: A toggle MUST switch the overlay's cargo lines on and off; the other overlay lines are
  unaffected (D4). The hold MUST NOT depend on how a ship is looked up or stored, so that a later keyed
  lookup of ship data needs no change to the hold's rules (D5).
- **FR-012**: Nothing in the hold MUST change the ship's motion, the autopilot, or the planned path.

### Key Entities

- **Commodity**: a kind of goods; has a stable id, a display name and a base price. Read from the data file
  and never changed while the game runs.
- **Commodity list**: the ordered, validated set of commodities loaded from the data file.
- **Cargo hold**: part of the ship; a capacity in whole tons and an amount in whole tons per commodity.
  Used and free tons derive from these.
- **Cargo rejection**: the reason an add or remove changed nothing (negative amount, unknown commodity,
  over capacity, not enough stock).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Headless tests cover adding, removing, the capacity limit (at, below and above it), 0 t and
  negative amounts, unknown commodities and overflow, and all pass in the checked-in verification command.
- **SC-002**: After any sequence of accepted and rejected operations, used tons never exceeds the capacity
  and no commodity amount is negative (checked by tests over a generated sequence).
- **SC-003**: A rejected operation leaves the hold equal to what it was before, in every rejection case.
- **SC-004**: The bundled commodity file loads with at least one commodity, and every malformed-file case in
  the tests is rejected with a message naming the problem.
- **SC-005**: On a Debug build, the overlay's used and free tons match the ship's hold at the last refresh;
  switching the toggle off removes every cargo line and switching it on restores them.
- **SC-006**: A plain Release build contains none of the cargo overlay's strings, and the instrumented
  Release build's allocation counter still reports zero allocations per frame with the cargo lines on.
- **SC-007**: The ship's motion tests and the autopilot tests pass unchanged.

## Assumptions

- Whole tons only: no fractional cargo, no per-commodity volume or mass.
- The starter commodity list is short (about 5 to 8 commodities with placeholder names and prices); the
  real balance is SKY-53's and later work.
- Prices are whole numbers of credits (no fractions).
- The toggle is a launch argument for Debug and instrumented Release builds, in the same way as the other
  debug arguments (`--no-debug-overlay`, `--no-ship`); the cargo lines are on by default, and the argument
  turns them off. A runtime control is not needed.
- A rejected operation reports a reason value; it does not crash and does not log.
- The hold does not exist for the player yet: there is no way in the running game to change it, so the
  overlay normally shows an empty hold until SKY-53.
