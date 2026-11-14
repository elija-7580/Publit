import SwiftUI
import MapKit

// The three station views (Settings → Stations): platform map, departures by platform, change guide.

/// Where each platform of a station is. Compact on purpose (the departures come right after it):
/// the map and one row of platform buttons; a tapped platform shows its lines and next stops.
struct PlatformMapSection: View {
    let groups: [PlatformGroup]
    @State private var camera: MapCameraPosition = .automatic
    @State private var selected: String?

    var body: some View {
        Section {
            Map(position: $camera) {
                ForEach(groups) { g in
                    Annotation("", coordinate: g.coordinate.clCoordinate, anchor: .center) {
                        PlatformPin(group: g, selected: selected == g.id)
                            .onTapGesture { select(g) }
                    }
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .frame(height: 220)
            .listRowInsets(EdgeInsets())
            .accessibilityHidden(true)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(groups) { g in
                        Button { select(g) } label: {
                            Text(verbatim: g.pinText)
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .foregroundStyle(selected == g.id ? Color.onInk : Color.primary)
                                .background(selected == g.id ? Color.ink : Color.inkFill, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(verbatim: g.title))
                        .accessibilityAddTraits(selected == g.id ? AccessibilityTraits.isSelected : [])
                        .accessibilityIdentifier("platformChip")
                    }
                }
            }
            if let g = groups.first(where: { $0.id == selected }) {
                PlatformSummaryRow(group: g, selected: true)
            }
        } header: {
            Text("Platform map")
        }
        .onChange(of: groups.map(\.id)) { _, _ in
            if let s = selected, !groups.contains(where: { $0.id == s }) { selected = nil }
        }
    }

    private func select(_ g: PlatformGroup) {
        selected = selected == g.id ? nil : g.id
        withAnimation {
            camera = selected == nil ? .automatic
                : .camera(MapCamera(centerCoordinate: g.coordinate.clCoordinate, distance: 250))
        }
    }
}

/// A platform on the map: its name ("A", "3") in a dark key, the first line's colour as an edge.
private struct PlatformPin: View {
    let group: PlatformGroup
    let selected: Bool

    var body: some View {
        Text(verbatim: group.pinText)
            .font((selected ? Font.headline : .subheadline).weight(.bold))
            .foregroundStyle(Color.onInk)
            .padding(.horizontal, selected ? 10 : 7)
            .padding(.vertical, selected ? 6 : 4)
            .background(Color.ink, in: Capsule())
            .overlay(Capsule().strokeBorder(group.lines.first?.lineColor ?? .white, lineWidth: 3))
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
    }
}

/// "Platform A · 17 18 · Next: Karlovy lázně → Národní divadlo".
struct PlatformSummaryRow: View {
    let group: PlatformGroup
    var selected = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(verbatim: group.title).font(.subheadline.weight(.bold))
                if selected { SignatureDot(size: 8) }
                Spacer(minLength: 0)
            }
            FlowLines(lines: group.lines)
            ForEach(Array(group.ways.enumerated()), id: \.offset) { _, way in
                Label {
                    Text(verbatim: L10n.f("Next: %@", way.joined(separator: " → ")))
                } icon: {
                    Image(systemName: "arrow.turn.down.right")
                }
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("platformSummary")
    }
}

/// The line badges of a platform, wrapping onto more rows when there are many.
private struct FlowLines: View {
    let lines: [StopTime]
    static let shown = 8

    var body: some View {
        HStack(spacing: 4) {
            ForEach(lines.prefix(Self.shown)) { LineBadge($0, compact: true) }
            if lines.count > Self.shown {
                Text(verbatim: "+\(lines.count - Self.shown)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
    }
}

/// The header row of a platform in "Departures by platform".
struct PlatformHeaderRow: View {
    let group: PlatformGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: group.title).font(.headline)
            ForEach(Array(group.ways.enumerated()), id: \.offset) { _, way in
                Text(verbatim: L10n.f("Next: %@", way.joined(separator: " → ")))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 8)
        .listRowSeparator(.hidden)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("platformHeader")
    }
}

/// During a live trip: the change from platform to platform on a small map, with stairs, lifts,
/// levels and exits on the way.
struct ChangeGuideCard: View {
    let guide: ChangeGuide
    @State private var camera: MapCameraPosition = .automatic

    init?(before legIndex: Int, in it: Itinerary) {
        guard let g = ChangeGuide(before: legIndex, in: it) else { return nil }
        guide = g
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(guide.headline, systemImage: "figure.walk.motion")
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            Map(position: $camera, interactionModes: [.pan, .zoom]) {
                if guide.path.count > 1 {
                    MapPolyline(coordinates: guide.path.map(\.clCoordinate))
                        .stroke(Color.routeAhead, style: .leg(false, width: 5))
                }
                Annotation(L10n.t("Get off here"), coordinate: guide.arriving.to.coordinate.clCoordinate, anchor: .center) {
                    end(guide.arriving, track: guide.arriving.to.track)
                }
                Annotation(L10n.t("Board here"), coordinate: guide.departing.from.coordinate.clCoordinate, anchor: .center) {
                    end(guide.departing, track: guide.departing.from.track)
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityHidden(true)
            summary
            ForEach(Array(guide.steps.enumerated()), id: \.offset) { _, m in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: m.symbol).font(.subheadline.weight(.semibold)).frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.instruction(destination: guide.departing.from.name)).font(.subheadline)
                        if let note = m.exitNote { Text(note).font(.caption.weight(.semibold)) }
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.vertical, 6)
        .accessibilityIdentifier("changeGuide")
    }

    @ViewBuilder
    private var summary: some View {
        if guide.isSamePlatform {
            Label("Same platform", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold)).foregroundStyle(Color.live)
        } else {
            HStack(spacing: 6) {
                Text(L10n.f("%@ walk", Fmt.duration(seconds: max(60, guide.walkSeconds))))
                Text(verbatim: "·").accessibilityHidden(true)
                if guide.isStepFree {
                    Label("Step-free", systemImage: "figure.roll")
                } else {
                    Label("With stairs", systemImage: "figure.stairs").foregroundStyle(Color.delay)
                }
            }
            .font(.subheadline.weight(.semibold))
            .accessibilityElement(children: .combine)
        }
    }

    /// A platform on the change map: the line's badge with the platform underneath.
    private func end(_ leg: Leg, track: String?) -> some View {
        VStack(spacing: 2) {
            LineBadge(leg, compact: true)
            if let t = TransitLabels.clean(track) {
                Text(verbatim: t).font(.caption2.weight(.bold))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(.regularMaterial, in: Capsule())
            }
        }
        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
    }
}

extension PlatformGroup {
    /// On the map and the platform buttons: the platform's name, or its first line where the feed
    /// names no platforms (not the first letters of the stop: "Ma", "Ma", "Ma" at Marienplatz).
    var pinText: String { label ?? lines.first?.lineName ?? String(name.prefix(3)) }
}
