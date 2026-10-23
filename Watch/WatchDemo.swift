#if DEBUG
import Foundation

/// Screens with made-up data, for screenshots and for checking the layout without an iPhone.
/// Start the app with `PUBLIT_WATCH_DEMO=<screen>` in its environment:
/// `home`, `trip` (a trip before it starts), `leg` (the U6 under way), `leg-s8` (the delayed S8 with a platform change),
/// `tripmap`, `legmap`, `tickets`, `ticket`, `saved`, `plan`, `plan-gap` (the planner with a destination in Carinthia),
/// `nearby`, `gap` (a trip through Carinthia, where data is missing).
/// Nothing is saved and nothing is sent. Debug builds only.
@MainActor
struct WatchDemo {
    let screen: String

    static var current: WatchDemo? {
        guard let name = ProcessInfo.processInfo.environment["PUBLIT_WATCH_DEMO"], !name.isEmpty else { return nil }
        return WatchDemo(screen: name)
    }

    private static let codeFile = "demo-ticket-1700000000-352.png"
    private let now = Date()

    /// The trip under way, started at the time of the app's launch (or 25 minutes before it).
    private var munich: SavedTrip {
        let base = screen == "leg-s8" ? now.addingTimeInterval(-25 * 60) : (screen == "trip" ? now.addingTimeInterval(25 * 60) : now)
        return SavedTrip(id: "demo-munich", itinerary: DesignSampleTrip.itinerary(DesignSampleTrip.munich, base: base),
                         fromName: "Zuhause", toName: "Flughafen München", savedAt: now.addingTimeInterval(-3600))
    }

    /// A trip tomorrow morning through Carinthia.
    private var carinthia: SavedTrip {
        SavedTrip(id: "demo-carinthia",
                  itinerary: DesignSampleTrip.itinerary(DesignSampleTrip.carinthia, base: now.addingTimeInterval(screen == "gap" ? 40 * 60 : 18 * 3600)),
                  fromName: "Zuhause", toName: "Villach", savedAt: now.addingTimeInterval(-7200))
    }

    private var tickets: [WatchTicket] {
        let month = Calendar.current.dateInterval(of: .month, for: now)
        let pass = TicketPass(id: "demo-ticket", title: "Monthly pass (demo)", operatorName: "Publit demo", category: .period, symbol: .train,
                              passenger: "Alex Example", travelClass: "2", reference: "DEMO-0001",
                              validFrom: month?.start, validUntil: month?.end.addingTimeInterval(-1),
                              barcode: TicketPass.Barcode(format: .qr, message: "PUBLIT-DEMO-TICKET-0001 (not a real ticket)"),
                              style: PassStyle(background: "0066D6"), createdAt: now.addingTimeInterval(-86400))
        let single = TicketPass(id: "demo-single", title: "Single ticket (demo)", operatorName: "Publit demo", category: .single, symbol: .metro,
                                origin: "Zuhause", destination: "Flughafen München", reference: "DEMO-0002",
                                validFrom: now.addingTimeInterval(24 * 3600), validUntil: now.addingTimeInterval(27 * 3600),
                                barcode: TicketPass.Barcode(format: .qr, message: "PUBLIT-DEMO-TICKET-0002 (not a real ticket)"),
                                createdAt: now.addingTimeInterval(-3600))
        return [WatchTicket(pass: pass, code: Self.codeFile), WatchTicket(pass: single, code: Self.codeFile)]
    }

    private var places: [SavedPlace] {
        var home = SavedPlace(id: "demo-home", name: "Home", subtitle: "Schwabing", lat: 48.166, lon: 11.589, stopId: nil)
        home.role = .home
        var work = SavedPlace(id: "demo-work", name: "Work", subtitle: "Maxvorstadt", lat: 48.1503, lon: 11.5681, stopId: nil)
        work.role = .work
        return [home, work,
                SavedPlace(id: "demo-stop-1", name: "Marienplatz", subtitle: "Munich", lat: 48.1372, lon: 11.5755, stopId: "d-Marienplatz"),
                SavedPlace(id: "demo-stop-2", name: "Münchner Freiheit", subtitle: "Munich", lat: 48.1617, lon: 11.5866, stopId: "d-Münchner Freiheit"),
                SavedPlace(id: "demo-place-1", name: "Englischer Garten", subtitle: nil, lat: 48.1642, lon: 11.6056, stopId: nil)]
    }

    /// What the watch holds, as if the iPhone had just sent it.
    func library() -> WatchLibrary {
        var trips = [munich, carinthia]
        if screen == "gap" { trips = [carinthia] }
        let started = ["home", "leg", "leg-s8", "tripmap", "legmap"].contains(screen)
        let snapshot = WatchSnapshot(sentAt: now, trips: trips, activeTripId: started ? munich.id : nil, places: places, tickets: tickets)
        let code = Data(base64Encoded: DesignSampleTrip.codeBase64) ?? Data()
        return WatchLibrary(demo: WatchState(received: snapshot), codes: [Self.codeFile: code])
    }

    /// The screens to open first (the back button leads to the home screen).
    func path() -> [WatchRoute] {
        switch screen {
        case "trip", "leg", "leg-s8": return [.trip(munich.id)]
        case "gap": return [.trip(carinthia.id)]
        case "tripmap": return [.map(OpenedRoute(itinerary: munich.itinerary), .overview)]
        case "legmap": return [.map(OpenedRoute(itinerary: munich.itinerary), .leg(1))]
        case "tickets": return [.tickets]
        case "ticket": return [.ticket("demo-ticket")]
        case "saved": return [.saved]
        case "plan": return [.plan]
        case "plan-gap":
            return [.planTo(SavedPlace(id: "demo-villach", name: "Villach", subtitle: "Kärnten", lat: 46.6167, lon: 13.8483, stopId: nil))]
        case "nearby": return [.nearby]
        default: return []
        }
    }
}
#endif
