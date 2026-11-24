// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich

import SwiftUI

/// Plan around a ticket you have (#24, #23): from here to where the ticket starts, in time for its
/// ride, the ride itself, then on to where you are going. Built on Plan in sections.
struct TicketRoutePlanView: View {
    let pass: TicketPass
    @Environment(LocationManager.self) private var location
    @State private var model: SectionPlanModel?
    @State private var failed = false

    var body: some View {
        Group {
            if let model {
                SectionPlanView(model: model)
            } else if failed {
                ContentUnavailableView {
                    Label(L10n.t("Stations not found"), systemImage: "magnifyingglass")
                } description: {
                    Text("Publit could not find the stations of this ticket. Check From and To on the ticket, or plan in sections yourself.")
                }
            } else {
                LogoLoader(label: L10n.t("Finding the stations…")).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Plan around this ticket")
        .navigationBarTitleDisplayMode(.inline)
        .screenTrail("Ticket route")
        .task {
            guard model == nil, let origin = pass.origin, let destination = pass.destination else { failed = model == nil; return }
            let near = location.coordinate
            async let a = Self.station(origin, near: near)
            async let b = Self.station(destination, near: near)
            guard let from = await a, let to = await b else { failed = true; return }
            model = SectionPlanModel.aroundTicket(start: .currentLocation, origin: .place(from), destinationOfTicket: .place(to),
                                                  destination: nil, departure: Self.departure(of: pass))
        }
    }

    /// The ride's departure when the ticket names a time of day (not just a day of validity).
    static func departure(of pass: TicketPass, calendar: Calendar = .current) -> Date? {
        guard let from = pass.validFrom else { return nil }
        let c = calendar.dateComponents([.hour, .minute], from: from)
        return c.hour == 0 && c.minute == 0 ? nil : from
    }

    /// The station a ticket names, found by its name (stations first).
    static func station(_ name: String, near: LatLon?) async -> SavedPlace? {
        let found = (try? await TransitousClient.shared.geocode(name, near: near, type: "STOP")) ?? []
        if let m = found.first(where: \.isStop) ?? found.first { return SavedPlace(match: m) }
        return (try? await TransitousClient.shared.geocode(name, near: near))?.first.map(SavedPlace.init(match:))
    }
}
