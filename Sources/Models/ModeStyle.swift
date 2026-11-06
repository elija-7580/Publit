import Foundation

/// Shared line styling data for legs and departures. Colour types live in RouteStyle.swift (SwiftUI).
protocol RouteStyled {
    var mode: String { get }
    var routeColor: String? { get }
    var routeTextColor: String? { get }
    var routeShortName: String? { get }
    var displayName: String? { get }
    /// GTFS route ID; some feeds encode the public line only there (see `TransitLabels.line(fromRouteId:)`).
    var routeId: String? { get }
}

extension RouteStyled {
    var routeId: String? { nil }
}

extension RouteStyled {
    /// The compact, operator-defined line identifier. Never use a destination as a line name.
    var lineName: String {
        TransitLabels.line(fromRouteId: routeId)
            ?? TransitLabels.clean(routeShortName) ?? TransitLabels.clean(displayName) ?? ModeStyle.label(mode)
    }

    /// Additional service identity (e.g. ICE 615), retained separately from the line badge.
    var serviceDetail: String? {
        guard let display = TransitLabels.clean(displayName),
              TransitLabels.identity(display) != TransitLabels.identity(lineName) else { return nil }
        return display
    }

    /// Feeds without route colours (e.g. many Italian operators) still get a clear colour per mode.
    var lineColors: LineColors.Pair {
        LineColors.resolve(routeColor: routeColor, routeTextColor: routeTextColor,
                           fallback: ModeStyle.defaultHex(mode))
    }

}

enum ModeStyle {
    private static let streetModes: Set<String> = [
        "WALK", "BIKE", "RENTAL", "CAR", "HGV", "CAR_PARKING", "CAR_DROPOFF"
    ]

    static func isTransit(_ mode: String) -> Bool { !streetModes.contains(mode) }

    static func symbol(_ mode: String) -> String {
        switch mode {
        case "WALK": return "figure.walk"
        case "BIKE", "RENTAL": return "bicycle"
        case "CAR", "CAR_PARKING", "CAR_DROPOFF", "ODM", "RIDE_SHARING", "HGV": return "car.fill"
        case "BUS", "COACH", "FLEX": return "bus.fill"
        case "TRAM": return "tram.fill"
        case "SUBWAY", "METRO": return "tram.fill.tunnel"
        case "FERRY": return "ferry.fill"
        case "AIRPLANE": return "airplane"
        case "FUNICULAR", "AERIAL_LIFT", "AREAL_LIFT", "CABLE_CAR": return "cablecar.fill"
        default: return "train.side.front.car"
        }
    }

    static func label(_ mode: String) -> String {
        switch mode {
        case "WALK": return L10n.t("Walk")
        case "BIKE": return L10n.t("Bike")
        case "RENTAL": return L10n.t("Rental")
        case "CAR": return L10n.t("Car")
        case "BUS": return L10n.t("Bus")
        case "COACH": return L10n.t("Coach")
        case "TRAM": return L10n.t("Tram")
        case "SUBWAY", "METRO": return L10n.t("Metro")
        case "FERRY": return L10n.t("Ferry")
        case "AIRPLANE": return L10n.t("Flight")
        case "SUBURBAN": return L10n.t("S-Bahn")
        case "HIGHSPEED_RAIL": return L10n.t("High-speed")
        case "NIGHT_RAIL": return L10n.t("Night train")
        case "FUNICULAR": return L10n.t("Funicular")
        case "AERIAL_LIFT", "AREAL_LIFT", "CABLE_CAR": return L10n.t("Cable car")
        default: return L10n.t("Train")
        }
    }

    /// Fallback line colour when the feed has none.
    static func defaultHex(_ mode: String) -> String {
        switch mode {
        case "BUS", "COACH", "FLEX": return "2973CC"
        case "TRAM": return "CC2633"
        case "SUBWAY", "METRO": return "5940B3"
        case "FERRY": return "0D8CA6"
        case "SUBURBAN": return "1A8C4D"
        case "HIGHSPEED_RAIL", "LONG_DISTANCE": return "9E1B32"
        case "NIGHT_RAIL": return "33308C"
        case "FUNICULAR", "AERIAL_LIFT", "AREAL_LIFT", "CABLE_CAR": return "A15C0F"
        case "AIRPLANE": return "1F6FA8"
        case "ODM", "RIDE_SHARING": return "7A3DB8"
        case "WALK", "BIKE", "RENTAL", "CAR", "CAR_PARKING", "CAR_DROPOFF", "HGV": return "8E8E93"
        default: return "D0571B" // regional and other rail
        }
    }
}

/// A headsign describes the vehicle's actual advertised direction, not the passenger's alighting stop.
enum TransitLabels {
    static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
    }

    static func identity(_ value: String) -> String {
        value.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    /// The Austrian rail feed puts the train number in `route_short_name` ("R 6046", "REX 2248"),
    /// while the public line ("R 44", "REX 3", as on station boards and in the ÖBB app) is only
    /// part of the route ID: `at-Railway-…_3-R44-N-j26-1…`, `…_2-RX3-W-j26-1…`.
    /// S-Bahn routes already have the line as short name; long-distance codes (A13, WB1) are internal.
    static func line(fromRouteId routeId: String?) -> String? {
        guard let routeId, routeId.hasPrefix("at-Railway-"),
              let underscore = routeId.firstIndex(of: "_") else { return nil }
        let parts = routeId[routeId.index(after: underscore)...].split(separator: "-", maxSplits: 2)
        guard parts.count == 3, parts[0].allSatisfy(\.isNumber) else { return nil }
        let token = parts[1]
        for (code, label) in [("RX", "REX"), ("R", "R")] where token.hasPrefix(code) {
            let number = token.dropFirst(code.count)
            guard !number.isEmpty, number.count <= 3, number.allSatisfy(\.isNumber) else { return nil }
            return "\(label) \(number)"
        }
        return nil
    }
}
