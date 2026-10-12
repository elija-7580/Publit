import Foundation

/// Shared line styling data for legs and departures. Colour types live in RouteStyle.swift (SwiftUI).
protocol RouteStyled {
    var mode: String { get }
    var routeColor: String? { get }
    var routeTextColor: String? { get }
    var routeShortName: String? { get }
    var displayName: String? { get }
}

extension RouteStyled {
    var lineName: String {
        let name = (displayName?.isEmpty == false ? displayName : routeShortName) ?? ""
        return name.isEmpty ? ModeStyle.label(mode) : name
    }

    /// Background and text colour as hex, with the text colour corrected for legibility.
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
        case "WALK", "BIKE", "RENTAL", "CAR": return "8E8E93"
        default: return "4D4D59"
        }
    }
}
