// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich

import Foundation

/// "Board at the front · Take exit B2": worked out per trip from where the walk after the ride leaves
/// the platform (stairs, lift, the station door it uses) or, at a change, where the next train leaves.
/// The door can also be one the user picked, which Publit remembers for that station and destination.
extension ExitAdvice {
    /// "Board at the front": before the ride (route, waiting at the platform, watch).
    var boardText: String? {
        switch part {
        case .front: return L10n.t("Board at the front")
        case .middle: return L10n.t("Board in the middle")
        case .back: return L10n.t("Board at the back")
        case nil: return nil
        }
    }

    /// "Front of the train", for a line that already names the ride.
    var partText: String? {
        switch part {
        case .front: return L10n.t("Front of the train")
        case .middle: return L10n.t("Middle of the train")
        case .back: return L10n.t("Back of the train")
        case nil: return nil
        }
    }

    /// Why that part: "Closest to exit B2", "Closest to your next train", "Closest to the way out".
    var reason: String? {
        guard part != nil else { return nil }
        if forChange { return L10n.t("Closest to your next train") }
        if let door { return L10n.f("Closest to exit %@", door) }
        return L10n.t("Closest to the way out")
    }

    /// One short line for on board and the Live Activity: "Front of the train · Exit B2".
    var short: String? {
        let parts = [partText, door.map { L10n.f("Exit %@", $0) }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: Working it out

    /// Only rides that stop at a platform in a station: metro and trains.
    static func applies(to ride: Leg) -> Bool { ride.isTransit && StationExits.stationModes.contains(ride.mode) }

    /// How far (metres, along the direction of travel) the way out must be from where the train stops
    /// to be "front" or "back"; within `middleBand` it is the middle, in between it is not said.
    static let endBand = 25.0
    static let middleBand = 10.0
    /// Further than this from the stop, a point is not on this platform.
    static let maxReach = 400.0
    /// The walk leaves the platform within this distance, else it is not the platform's stairs.
    static let platformReach = 250.0

    /// The advice for the ride at `index`, or nil when there is nothing to say.
    static func forRide(_ index: Int, in legs: [Leg], exits: StationExits = .shared) -> ExitAdvice? {
        guard let ride = legs[safe: index], applies(to: ride) else { return nil }
        // Worked out on the iPhone and sent along (the watch gets no walking directions).
        if let sent = ride.exitAdvice { return sent.isEmpty ? nil : sent }
        var advice = ExitAdvice(part: nil)
        var target: LatLon?
        if let walk = legs[safe: index + 1], !walk.isTransit {
            let route = WalkRoute(leg: walk, exits: exits)
            if StationExits.leavesStation(legs, at: index + 1) {
                if let door = route.exitDoor {
                    advice.door = door.label
                    advice.doorSaved = door.label != nil && exits.preferred(for: walk)?.label == door.label
                }
            } else {
                advice.forChange = legs[safe: index + 2]?.isTransit ?? false
            }
            target = leavesPlatform(route) ?? route.exitDoor?.point
            if target == nil, advice.forChange, let next = legs[safe: index + 2] { target = next.from.coordinate }
        } else if let next = legs[safe: index + 1], next.isTransit {
            // Same platform or across it: the next train's stop.
            advice.forChange = true
            target = next.from.coordinate
        }
        if let target { advice.part = part(arriving: ride, towards: target) }
        return advice.isEmpty ? nil : advice
    }

    /// Advice for every ride of the trip, by leg index.
    static func all(_ legs: [Leg], exits: StationExits = .shared) -> [Int: ExitAdvice] {
        var out: [Int: ExitAdvice] = [:]
        for i in legs.indices { if let a = forRide(i, in: legs, exits: exits) { out[i] = a } }
        return out
    }

    /// Where the walk leaves the platform: its first stairs, escalator or lift; failing that, which way
    /// it heads along the platform (the point 60 m into it).
    static func leavesPlatform(_ route: WalkRoute) -> LatLon? {
        let levelKinds: Set<WalkManeuver.Kind> = [.stairsUp, .stairsDown, .stairs, .elevator, .levelUp, .levelDown]
        if let m = route.maneuvers.first(where: { levelKinds.contains($0.kind) }), m.along <= platformReach {
            return m.coordinate
        }
        guard route.length >= 30 else { return nil }
        return PathGeometry.point(at: min(60, route.length), on: route.path)
    }

    /// Which part of the train stops nearest `target`: the direction of travel comes from the last
    /// stretch of the ride's shape, and `target` is measured along it from where the train stops.
    static func part(arriving ride: Leg, towards target: LatLon) -> Part? {
        let stop = ride.to.coordinate
        let path = ride.legGeometry.coordinates
        let length = PathGeometry.length(path)
        guard path.count >= 2, length > 20,
              let before = PathGeometry.point(at: max(0, length - 120), on: path), let end = path.last,
              before.distance(to: end) > 10 else { return nil }
        let heading = PathGeometry.bearing(before, end)
        let d = stop.distance(to: target)
        guard d <= maxReach else { return nil }
        // Right where the train stops (or no shape to tell): nothing worth saying.
        guard d >= middleBand else { return nil }
        let ahead = d * cos(PathGeometry.turn(from: heading, to: PathGeometry.bearing(stop, target)) * .pi / 180)
        if ahead >= endBand { return .front }
        if ahead <= -endBand { return .back }
        if abs(ahead) <= middleBand { return .middle }
        return nil
    }
}

extension Itinerary {
    /// The trip with each ride's advice worked out (for the watch, which gets no walking directions).
    func withExitAdvice(exits: StationExits = .shared) -> Itinerary {
        var it = self
        for i in legs.indices where ExitAdvice.applies(to: legs[i]) {
            // Empty: worked out, nothing to say (the watch does not try again without directions).
            it.legs[i].exitAdvice = ExitAdvice.forRide(i, in: legs, exits: exits) ?? ExitAdvice(part: nil)
        }
        return it
    }
}
