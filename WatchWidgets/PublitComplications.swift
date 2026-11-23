// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich

import SwiftUI
import WidgetKit

/// Apple Watch complications (#18): the next departures at the stop nearest to the watch, and one
/// tap into Publit. The trip under way shows in the Smart Stack as the iPhone's Live Activity.
@main
struct PublitComplications: WidgetBundle {
    var body: some Widget {
        NextDepartureComplication()
        OpenPublitComplication()
    }
}

struct NextDepartureEntry: TimelineEntry {
    let date: Date
    let stop: NearbyBoardStop?
    var noLocation = false

    /// Departures still ahead at this entry's time.
    var upcoming: [WidgetDeparture] { stop?.departures.filter { $0.time > date.addingTimeInterval(-30) } ?? [] }
}

struct NextDepartureProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextDepartureEntry { NextDepartureEntry(date: .now, stop: nil) }

    func getSnapshot(in context: Context, completion: @escaping (NextDepartureEntry) -> Void) {
        Task { completion(await load(now: .now)) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextDepartureEntry>) -> Void) {
        Task {
            let now = Date()
            let first = await load(now: now)
            // One entry per departure, so the next one moves up without a new request; asked again after 15 min.
            var entries = [first]
            for d in first.upcoming.prefix(3) where d.time > now {
                entries.append(NextDepartureEntry(date: d.time.addingTimeInterval(30), stop: first.stop))
            }
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(15 * 60))))
        }
    }

    private func load(now: Date) async -> NextDepartureEntry {
        guard let here = await OneShotLocator.locate() else { return NextDepartureEntry(date: now, stop: nil, noLocation: true) }
        let stops = (try? await NearbyBoard.load(at: here, favorites: [], limit: 1, now: now)) ?? []
        return NextDepartureEntry(date: now, stop: stops.first)
    }
}

struct NextDepartureComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "nextDeparture", provider: NextDepartureProvider()) { entry in
            NextDepartureView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(entry.stop?.deepLink)
        }
        .configurationDisplayName("Next departure")
        .description("The next departures at the stop nearest to you.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryCorner, .accessoryInline])
    }
}

struct NextDepartureView: View {
    let entry: NextDepartureEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let next = entry.upcoming.first
        switch family {
        case .accessoryCircular:
            VStack(spacing: 0) {
                Text(verbatim: next?.lineName ?? "–").font(.system(size: 13, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
                if let next { Text(next.time, style: .timer).font(.system(size: 12).monospacedDigit()).multilineTextAlignment(.center) }
            }
            .widgetAccentable()
        case .accessoryCorner:
            Image(systemName: "tram.fill")
                .font(.title3)
                .widgetLabel {
                    if let next { Text(verbatim: "\(next.lineName) \(Fmt.time(next.time, tz: next.tz))") } else { Text("Publit") }
                }
        case .accessoryInline:
            if let next {
                Text(verbatim: "\(next.lineName) \(Fmt.time(next.time, tz: next.tz)) · \(entry.stop?.name ?? "")")
            } else {
                Text("No departures soon")
            }
        default:
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: entry.stop?.name ?? "Publit").font(.headline).lineLimit(1).widgetAccentable()
                if entry.noLocation {
                    Text("Location needed").font(.caption).foregroundStyle(.secondary)
                } else if entry.upcoming.isEmpty {
                    Text("No departures soon").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(entry.upcoming.prefix(2)) { d in
                    HStack(spacing: 4) {
                        Text(verbatim: d.lineName).font(.caption.weight(.bold)).lineLimit(1)
                        Text(verbatim: TransitLabels.clean(d.headsign) ?? "").font(.caption).lineLimit(1)
                        Spacer(minLength: 2)
                        Text(Fmt.time(d.time, tz: d.tz)).font(.caption.monospacedDigit()).strikethrough(d.cancelled)
                    }
                }
            }
        }
    }
}

/// The Publit logo on the watch face: one tap opens the app (the trip under way opens by itself).
struct OpenPublitComplication: Widget {
    struct Entry: TimelineEntry { let date: Date }

    struct Provider: TimelineProvider {
        func placeholder(in context: Context) -> Entry { Entry(date: .now) }
        func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) { completion(Entry(date: .now)) }
        func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
            completion(Timeline(entries: [Entry(date: .now)], policy: .never))
        }
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "openPublit", provider: Provider()) { _ in
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "tram.fill").font(.title3.weight(.semibold)).widgetAccentable()
            }
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Publit")
        .description("Opens Publit.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner])
    }
}
