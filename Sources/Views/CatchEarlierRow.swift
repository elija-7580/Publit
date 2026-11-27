// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich
import SwiftUI

/// Under "Change at … no longer works": leave earlier and still catch the same connection
/// (`CatchEarlier`). Opens that route, a route like any other: start it, save it, change it.
struct CatchEarlierRow: View {
    let rescue: CatchEarlier.Rescue
    let open: () -> Void

    private var title: String {
        L10n.f("Still catch %@", rescue.connection.lineName)
    }

    private var detail: String {
        let route = rescue.route
        let leave = Fmt.time(route.startTime, tz: route.legs.first?.from.tz)
        var parts = [rescue.minutesEarlier > 0
                     ? L10n.f("Leave %@ earlier, at %@", Fmt.duration(seconds: rescue.minutesEarlier * 60), leave)
                     : L10n.f("Leave at %@", leave)]
        if let first = route.firstTransitLeg {
            parts.append(L10n.f("%@ at %@", first.lineName, Fmt.time(first.startTime, tz: first.from.tz)))
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        Button(action: open) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.live)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.ink)
                    Text(detail).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
        .listRowBackground(NoticeBackground(tint: .live))
        .accessibilityIdentifier("catchEarlier")
    }
}
