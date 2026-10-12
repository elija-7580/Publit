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
        case "WALK": return "Walk"
        case "BIKE": return "Bike"
        case "RENTAL": return "Rental"
        case "CAR": return "Car"
        case "BUS": return "Bus"
        case "COACH": return "Coach"
        case "TRAM": return "Tram"
        case "SUBWAY", "METRO": return "Metro"
        case "FERRY": return "Ferry"
        case "AIRPLANE": return "Flight"
        case "SUBURBAN": return "S-Bahn"
        case "HIGHSPEED_RAIL": return "High-speed"
        case "NIGHT_RAIL": return "Night train"
        case "FUNICULAR": return "Funicular"
        case "AERIAL_LIFT", "AREAL_LIFT", "CABLE_CAR": return "Cable car"
        default: return "Train"
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
