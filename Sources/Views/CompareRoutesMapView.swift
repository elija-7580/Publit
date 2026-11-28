// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich
import SwiftUI

/// iPhone: all routes found in Plan on one map, like the big map next to the list on iPad
/// (`WideRoutesMap`). Opened with the map key in Plan's bar, built only while it is open (one map
/// at a time, see `MapHero.releaseDelay`). The routes below the map pick which one is drawn
/// strong; "Show route" opens it.
struct CompareRoutesMapView: View {
    let itineraries: [Itinerary]
    let title: String
    var onOpen: (Itinerary) -> Void
    @State private var selected: String?
    @Environment(\.dismiss) private var dismiss

    init(itineraries: [Itinerary], selected: String?, title: String, onOpen: @escaping (Itinerary) -> Void) {
        self.itineraries = itineraries
        self.title = title
        self.onOpen = onOpen
        _selected = State(initialValue: selected ?? itineraries.first?.routeKey)
    }

    private var current: Itinerary? { itineraries.first { $0.routeKey == selected } ?? itineraries.first }

    var body: some View {
        NavigationStack {
            CompareMapView(itineraries: itineraries, selectedId: current?.routeKey)
                .equatable()
                .ignoresSafeArea(edges: .bottom)
                .safeAreaInset(edge: .bottom, spacing: 0) { picker }
                .navigationTitle(Text(verbatim: title))
                .navigationBarTitleDisplayMode(.inline)
                .screenTrail("Routes map")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
        }
    }

    private var picker: some View {
        VStack(spacing: 10) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(itineraries, id: \.routeKey) { it in
                            chip(it).id(it.routeKey)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .onAppear { if let selected { proxy.scrollTo(selected, anchor: .center) } }
            }
            if let current {
                Button { dismiss(); onOpen(current) } label: {
                    Label("Show route", systemImage: "arrow.right")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.ink)
                .padding(.horizontal, 16)
                .accessibilityIdentifier("compareShowRoute")
            }
        }
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func chip(_ it: Itinerary) -> some View {
        let isSelected = it.routeKey == current?.routeKey
        return Button { withAnimation(.snappy) { selected = it.routeKey } } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(Fmt.time(it.startTime, tz: it.legs.first?.from.tz)) – \(Fmt.time(it.endTime, tz: it.legs.last?.to.tz))")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(verbatim: Fmt.duration(seconds: it.duration))
                    Text(verbatim: "·")
                    Text(verbatim: Fmt.changes(it.transfers))
                }
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .fixedSize()
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.inkFill : Color.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? Color.ink : Color.ink.opacity(0.09), lineWidth: isSelected ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("compareRoute")
    }
}
