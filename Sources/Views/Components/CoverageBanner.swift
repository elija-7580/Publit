import SwiftUI

/// "Not reliable here": says that open timetable data is missing at a place, and which data.
/// Above the routes, the departures and on the map, so nobody trusts a gap in the data.
struct CoverageBanner: View {
    let notices: [CoverageNotice]
    /// Just the facts, without the explanation and the link (a second banner on one screen, a sheet).
    var compact = false

    var body: some View {
        if let first = notices.first {
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text("Not reliable here").font(.subheadline.weight(.bold)).foregroundStyle(Color.ink)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.delay)
                }
                ForEach(notices) { notice in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: notice.heading).font(.footnote.weight(.semibold)).foregroundStyle(Color.ink)
                        Text(verbatim: notice.area.summary).font(.footnote).foregroundStyle(Color.ink)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("coverageNotice")
                }
                if !compact {
                    Text("Publit uses open timetable data (Transitous). Where it is missing, connections can be incomplete or wrong.")
                        .font(.caption).foregroundStyle(.secondary)
                    Link(destination: first.area.mapURL()) {
                        Label("Coverage map", systemImage: "map").font(.caption.weight(.semibold))
                    }
                    .accessibilityIdentifier("coverageMapLink")
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.delay.opacity(0.13), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.delay.opacity(0.55), lineWidth: 1))
            .accessibilityIdentifier("coverageBanner")
        }
    }
}

/// Over the map: the warning for the area in the middle of the map, as a small card.
/// A tap opens the whole explanation (and the link to the coverage map).
struct CoverageMapNote: View {
    let notice: CoverageNotice
    @State private var open = false

    var body: some View {
        Group {
            if open {
                CoverageBanner(notices: [notice])
                    .background(Color.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        Button { open = false } label: {
                            Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                                .frame(width: 40, height: 40)
                        }
                        .accessibilityLabel(Text("Close"))
                        .accessibilityIdentifier("closeCoverageNote")
                    }
            } else {
                Button { open = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.delay)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Not reliable here").font(.footnote.weight(.bold)).foregroundStyle(Color.ink)
                            Text(verbatim: notice.area.summary).font(.caption).foregroundStyle(.secondary)
                                .lineLimit(2).multilineTextAlignment(.leading)
                        }
                        Image(systemName: "chevron.down").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .matteSurface(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.delay.opacity(0.6), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint(Text(verbatim: notice.area.name))
                .accessibilityIdentifier("coverageMapNote")
            }
        }
        .padding(.horizontal, 12)
        .mapShadow()
        .animation(.easeInOut(duration: 0.2), value: open)
        .onChange(of: notice.id) { open = false }
    }
}

/// A small orange triangle for a place in an area with missing data (search results, saved places).
struct CoverageMark: View {
    let point: LatLon?

    var body: some View {
        if let notice = CoverageGuide.notice(at: point) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(Color.delay)
                .accessibilityLabel(Text("Not reliable here"))
                .accessibilityValue(Text(verbatim: notice.area.summary))
                .accessibilityIdentifier("coverageMark")
        }
    }
}

extension View {
    /// The banner as a full-width list row on the list's background.
    func coverageRow() -> some View {
        listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}
