// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich

import AppIntents
import SwiftUI
import WidgetKit

/// Widget settings: up to four destinations. Nothing chosen: Home and Work.
struct ShortcutsWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Shortcuts"
    static var description = IntentDescription("Routes to Home, Work or your own places with one tap.")

    @Parameter(title: "First")
    var first: ShortcutEntity?
    @Parameter(title: "Second")
    var second: ShortcutEntity?
    @Parameter(title: "Third")
    var third: ShortcutEntity?
    @Parameter(title: "Fourth")
    var fourth: ShortcutEntity?

    var chosen: [ShortcutEntity] {
        let list = [first, second, third, fourth].compactMap { $0 }
        return list.isEmpty ? PlaceRole.allCases.map(ShortcutEntity.init(role:)) : list
    }
}

struct ShortcutsEntry: TimelineEntry {
    let date: Date
    let targets: [ShortcutEntity]
}

struct ShortcutsProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ShortcutsEntry {
        ShortcutsEntry(date: .now, targets: PlaceRole.allCases.map(ShortcutEntity.init(role:)))
    }

    func snapshot(for configuration: ShortcutsWidgetIntent, in context: Context) async -> ShortcutsEntry {
        ShortcutsEntry(date: .now, targets: configuration.chosen)
    }

    /// Nothing changes by itself: one entry until the user edits the widget.
    func timeline(for configuration: ShortcutsWidgetIntent, in context: Context) async -> Timeline<ShortcutsEntry> {
        Timeline(entries: [ShortcutsEntry(date: .now, targets: configuration.chosen)], policy: .never)
    }
}

/// Home, Work and own shortcuts on the Home Screen and Lock Screen (#6, #22): one tap opens the
/// routes from where you are, leaving now.
struct ShortcutsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "shortcuts", intent: ShortcutsWidgetIntent.self, provider: ShortcutsProvider()) { entry in
            ShortcutsWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Shortcuts")
        .description("Routes to Home, Work or your own places with one tap.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct ShortcutsWidgetView: View {
    let entry: ShortcutsEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            if let t = entry.targets.first {
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: t.symbol).font(.title3.weight(.semibold))
                }
                .widgetURL(t.deepLink)
                .accessibilityLabel(Text(L10n.f("Route to %@", t.title)))
            }
        case .accessoryInline:
            if let t = entry.targets.first {
                Label(t.title, systemImage: t.symbol).widgetURL(t.deepLink)
            }
        case .accessoryRectangular:
            if let t = entry.targets.first {
                VStack(alignment: .leading, spacing: 2) {
                    Label(t.title, systemImage: t.symbol).font(.headline).lineLimit(1)
                    Text("Routes from here").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .widgetURL(t.deepLink)
            }
        case .systemSmall:
            // A small widget has one tap target: the first destination, with the second below it
            // only when they fit as one (Home and Work open the same "Where to" list in the app).
            if let t = entry.targets.first {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: t.symbol)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Color(Palette.ink))
                        .frame(width: 44, height: 44)
                        .background(Color(Palette.fill), in: Circle())
                    Spacer(minLength: 0)
                    Text(verbatim: t.title).font(.headline).lineLimit(2)
                    Text("Routes from here").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .widgetURL(t.deepLink)
            }
        default:
            let shown = Array(entry.targets.prefix(4))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(shown, id: \.id) { t in
                    Link(destination: t.deepLink) {
                        HStack(spacing: 8) {
                            Image(systemName: t.symbol)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color(Palette.ink))
                                .frame(width: 30, height: 30)
                                .background(Color(Palette.fill), in: Circle())
                            Text(verbatim: t.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                                .minimumScaleFactor(0.8)
                            Spacer(minLength: 0)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, minHeight: shown.count > 2 ? 52 : 110, alignment: .leading)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Departures near you (#19)

/// Widget settings: saved stops that go first when you are close to them.
struct NearbyWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Departures nearby"
    static var description = IntentDescription("Departures at the stops closest to you.")

    @Parameter(title: "Favourite stops")
    var favorites: [StopEntity]?
}

struct NearbyEntry: TimelineEntry {
    enum State { case ok, noLocation, failed }
    let date: Date
    let stops: [NearbyBoardStop]
    var state: State = .ok
}

struct NearbyProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> NearbyEntry { NearbyEntry(date: .now, stops: []) }

    func snapshot(for configuration: NearbyWidgetIntent, in context: Context) async -> NearbyEntry {
        await load(configuration, family: context.family)
    }

    func timeline(for configuration: NearbyWidgetIntent, in context: Context) async -> Timeline<NearbyEntry> {
        let entry = await load(configuration, family: context.family)
        // On the move the nearest stop changes: ask again soon (WidgetKit decides the real interval).
        let wait: TimeInterval = entry.state == .ok ? 10 * 60 : 15 * 60
        // One entry after each departure, so a train that has left drops off the list without a new
        // load (WidgetKit often waits much longer than asked).
        let now = entry.date
        let times = Set(entry.stops.flatMap { $0.departures.map(\.time) }).filter { $0 > now }.sorted().prefix(24)
        let later = times.map { NearbyEntry(date: $0.addingTimeInterval(30), stops: entry.stops, state: entry.state) }
        return Timeline(entries: [entry] + later, policy: .after(now.addingTimeInterval(wait)))
    }

    private func load(_ configuration: NearbyWidgetIntent, family: WidgetFamily) async -> NearbyEntry {
        let now = Date()
        guard let here = await OneShotLocator.locate() else { return NearbyEntry(date: now, stops: [], state: .noLocation) }
        let favorites = (configuration.favorites ?? []).map {
            NearbyFavorite(stopId: $0.stopId, name: $0.name, coordinate: LatLon(lat: $0.lat, lon: $0.lon))
        }
        let limit = family == .systemLarge ? 3 : family == .systemMedium ? 2 : 1
        do {
            let stops = try await NearbyBoard.load(at: here, favorites: favorites, limit: limit, now: now)
            return NearbyEntry(date: now, stops: stops)
        } catch {
            return NearbyEntry(date: now, stops: [], state: .failed)
        }
    }
}

struct NearbyWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "nearby", intent: NearbyWidgetIntent.self, provider: NearbyProvider()) { entry in
            NearbyWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(entry.stops.first?.deepLink)
        }
        .configurationDisplayName("Departures nearby")
        .description("Departures at the stops closest to you. Favourite stops go first when you are near them.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

struct NearbyWidgetView: View {
    let entry: NearbyEntry
    @Environment(\.widgetFamily) private var family

    private var perStop: Int {
        switch family {
        case .systemSmall: return 2
        case .systemMedium: return 2
        case .systemLarge: return 3
        default: return 1
        }
    }

    /// Departures still ahead at this entry's time (the timeline has an entry after each one).
    private func ahead(_ stop: NearbyBoardStop) -> [WidgetDeparture] {
        stop.departures.filter { $0.time > entry.date.addingTimeInterval(-30) }
    }

    var body: some View {
        switch entry.state {
        case .noLocation:
            message(L10n.t("Location needed"), detail: "Allow location for Publit's widgets in Settings.", symbol: "location.slash")
        case .failed:
            message(L10n.t("Departures nearby"), detail: "Departures unavailable", symbol: "wifi.slash")
        case .ok:
            if entry.stops.isEmpty {
                message(L10n.t("Departures nearby"), detail: "No departures soon", symbol: "tram")
            } else if family == .accessoryRectangular, let stop = entry.stops.first {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: stop.name).font(.caption.weight(.semibold)).lineLimit(1)
                    if let d = ahead(stop).first {
                        HStack(spacing: 4) {
                            Text(verbatim: d.serviceDetail ?? d.lineName).font(.caption.weight(.bold))
                            Text(Fmt.time(d.time, tz: d.tz)).font(.caption.monospacedDigit()).strikethrough(d.cancelled)
                        }
                        DirectionLabel(direction: d.headsign, circular: d.circular, font: .caption2).lineLimit(1)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(entry.stops) { stop in
                        Link(destination: stop.deepLink) { stopBlock(stop) }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private func stopBlock(_ stop: NearbyBoardStop) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                if stop.favorite { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow) }
                Text(verbatim: stop.name).font(.caption.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 2)
                if let d = stop.distance {
                    Text(verbatim: Fmt.distance(meters: d)).font(.caption2).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                }
            }
            ForEach(ahead(stop).prefix(perStop)) { d in
                HStack(spacing: 6) {
                    LineBadge(d, compact: true)
                    DirectionLabel(direction: d.headsign, circular: d.circular, font: .caption).lineLimit(1)
                    Spacer(minLength: 2)
                    Text(Fmt.time(d.time, tz: d.tz))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .strikethrough(d.cancelled)
                        .foregroundStyle(d.cancelled ? Color.danger : d.realTime ? Color.live : Color.primary)
                        .lineLimit(1).fixedSize()
                }
            }
        }
    }

    private func message(_ title: String, detail: LocalizedStringKey, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol).font(.title3).foregroundStyle(.secondary)
            Text(title).font(.subheadline.weight(.semibold)).lineLimit(2)
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
