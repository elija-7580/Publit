import Foundation

/// Shared line styling data for legs and departures. Colour types live in RouteStyle.swift (SwiftUI).
protocol RouteStyled {
    var mode: String { get }
    var routeColor: String? { get }
    var routeTextColor: String? { get }
    var routeShortName: String? { get }
    var displayName: String? { get }
    /// Long route name; some feeds keep the train category only there ("rjx 66").
    var routeLongName: String? { get }
}

extension RouteStyled {
    /// The compact, operator-defined line identifier. Never use a destination as a line name.
    var routeLongName: String? { nil }

    var lineName: String {
        if VehicleKind.railModes.contains(mode),
           let train = TransitLabels.trainName(short: routeShortName, display: displayName, longName: routeLongName) {
            return train
        }
        return TransitLabels.lineName(TransitLabels.clean(routeShortName) ?? TransitLabels.clean(displayName), mode: mode)
            ?? ModeStyle.label(mode)
    }

    /// Additional service identity (e.g. ICE 615), retained separately from the line badge.
    var serviceDetail: String? {
        guard let display = TransitLabels.clean(displayName),
              TransitLabels.identity(display) != TransitLabels.identity(lineName) else { return nil }
        // "xpress 66" under "RJX 66": the same train, written worse.
        if let n = TransitLabels.trainNumber(display), n == TransitLabels.trainNumber(lineName) { return nil }
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

    /// The line name as riders know it. Paris publishes its two short metro lines as "3B" and "7B";
    /// on the platforms and maps they are "3bis" and "7bis".
    static func lineName(_ raw: String?, mode: String) -> String? {
        guard let raw else { return nil }
        if mode == "SUBWAY" || mode == "METRO", raw.count >= 2, raw.hasSuffix("B"),
           raw.dropLast().allSatisfy(\.isNumber) {
            return raw.dropLast() + "bis"
        }
        return raw
    }

    /// A train's name as on the departure board, from feeds that each fill the fields differently:
    /// - DB puts an internal line number in the short name ("29") and the train in the display name ("ICE 1006");
    /// - MÁV leaves the short name empty and writes "xpress 66" with the category in the long name ("rjx 66").
    /// Nil when the short name is already right ("RJX 161", "RE1", "S26").
    static func trainName(short: String?, display: String?, longName: String?) -> String? {
        let short = clean(short), display = clean(display)
        guard let display else { return nil }
        let number = trainNumber(display)
        // The category from the long name when the display name's own word is not a category.
        if let number, VehicleKind.categoryName(display) == nil,
           let code = clean(longName)?.split(separator: " ").first.map({ String($0).uppercased() }),
           VehicleKind.categories[code] != nil {
            return "\(code) \(number)"
        }
        guard let short else { return display }
        // "29" next to "ICE 1006": an internal number, not what is written on the train. The badge
        // shows the category like other feeds ("ICE"), the train itself stays beside it.
        if short.allSatisfy(\.isNumber), display.contains(where: \.isLetter), number != nil, short != number {
            let code = String(display.prefix { $0.isLetter }).uppercased()
            return VehicleKind.categories[code] != nil ? code : display
        }
        return nil
    }

    /// The train number at the end of a name ("ICE 1006" → "1006"); nil without one.
    static func trainNumber(_ value: String) -> String? {
        let last = value.split(separator: " ").last.map(String.init) ?? value
        let digits = String(last.reversed().prefix { $0.isNumber }.reversed())
        return digits.count >= 2 ? digits : nil
    }

    /// The direction to show. Some feeds put an internal service code in the headsign instead of a
    /// destination (Paris RER: "ZEMA", "NEGE", "PEZZ"); then the trip's last stop says where it goes.
    static func direction(headsign: String?, tripEnd: String?) -> String? {
        // No headsign stays no direction: guessing one has misled before (see TransitEnhancementTests).
        guard let h = clean(headsign), let end = clean(tripEnd) else { return clean(headsign) }
        return isServiceCode(h) && identity(h) != identity(end) ? end : h
    }

    /// Three to five capital letters and nothing else: a mission code, not a place name.
    static func isServiceCode(_ value: String) -> Bool {
        (3...5).contains(value.count) && value.allSatisfy { $0.isASCII && $0.isUppercase && $0.isLetter }
    }
}

/// What kind of vehicle a ride is. For someone in a wheelchair a Railjet and an old regional train
/// are different trips, so the category and the vehicle's own step-free flag are shown with the ride.
struct VehicleKind: Equatable, Sendable {
    enum Access: Equatable, Sendable { case accessible, notAccessible, unknown }

    /// Train category as printed on timetables ("Railjet Xpress", "Intercity"), nil when not known.
    let category: String?
    /// The mode in words ("Regional train", "Metro").
    let modeLabel: String
    let access: Access

    /// Category codes at the start of a train number ("RJX 161", "REX 9563", "ICE615").
    static let categories: [String: String] = [
        "RJX": "Railjet Xpress", "RJ": "Railjet", "ICE": "ICE", "ECE": "EuroCity-Express", "IC": "Intercity",
        "EC": "EuroCity", "EN": "EuroNight", "NJ": "Nightjet", "CJX": "Cityjet Xpress", "REX": "Regionalexpress",
        "RE": "Regional-Express", "RB": "Regionalbahn", "WB": "Westbahn", "FLX": "Flixtrain", "TGV": "TGV",
        "OUIGO": "OUIGO", "IRE": "Interregio-Express", "IR": "InterRegio", "FR": "Frecciarossa", "FA": "Frecciargento",
        "FB": "Frecciabianca", "RV": "Regionale Veloce", "AVE": "AVE", "ALVIA": "Alvia", "EST": "Eurostar",
        "TER": "TER", "INTERCITY": "Intercity", "INOUI": "TGV INOUI", "TL": "Transilien", "SC": "SuperCity", "EX": "Express", "RR": "Rychlík", "OS": "Osobní vlak",
    ]

    static let railModes: Set<String> = ["HIGHSPEED_RAIL", "LONG_DISTANCE", "REGIONAL_RAIL", "REGIONAL_FAST_RAIL",
                                         "NIGHT_RAIL", "RAIL", "SUBURBAN"]

    static func of(_ leg: Leg) -> VehicleKind {
        let access: Access
        switch leg.wheelchairAccessible {
        case "ACCESSIBLE": access = .accessible
        case "NOT_ACCESSIBLE": access = .notAccessible
        default: access = .unknown
        }
        let category = railModes.contains(leg.mode)
            ? [leg.lineName, leg.tripShortName, leg.displayName, leg.routeShortName].lazy.compactMap(categoryName).first
            : nil
        return VehicleKind(category: category, modeLabel: label(leg.mode), access: access)
    }

    /// "RJX 161" → "Railjet Xpress"; nil for plain numbers, line names ("S7" stays a line) and unknown codes.
    static func categoryName(_ value: String?) -> String? {
        guard let value = TransitLabels.clean(value) else { return nil }
        let code = String(value.prefix { $0.isLetter }).uppercased()
        guard !code.isEmpty, code.count < value.count || categories[code] != nil else { return nil }
        return categories[code]
    }

    static func label(_ mode: String) -> String {
        switch mode {
        case "HIGHSPEED_RAIL": return L10n.t("High-speed train")
        case "LONG_DISTANCE": return L10n.t("Long-distance train")
        case "REGIONAL_RAIL", "REGIONAL_FAST_RAIL": return L10n.t("Regional train")
        default: return ModeStyle.label(mode)
        }
    }

    /// "Railjet Xpress · High-speed train", or just the mode.
    var summary: String {
        guard let category, TransitLabels.identity(category) != TransitLabels.identity(modeLabel) else { return modeLabel }
        return "\(category) · \(modeLabel)"
    }

    var accessText: String? {
        switch access {
        case .accessible: return L10n.t("Wheelchair accessible")
        case .notAccessible: return L10n.t("Not wheelchair accessible")
        case .unknown: return nil
        }
    }
}
