import SwiftUI

struct PlanView: View {
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false
    @Environment(LocationManager.self) private var location
    @State private var picking: PickTarget?
    @State private var showMap = false
    @State private var selectedId: String?

    /// Live refresh interval while planning for "now".
    static let refreshInterval: Duration = .seconds(60)

    enum PickTarget: String, Identifiable { case from, to; var id: String { rawValue } }

    var body: some View {
        @Bindable var plan = app.plan
        List {
            Section {
                // From and To with the swap button between them on the right.
                HStack(spacing: 8) {
                    VStack(spacing: 0) {
                        endpointButton(label: "From", endpoint: plan.from, target: .from)
                        Divider()
                        endpointButton(label: "To", endpoint: plan.to, target: .to)
                    }
                    Button { app.plan.swap() } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.body.weight(.semibold))
                            .frame(width: 40, height: 40)
                            .background(Color(.tertiarySystemFill), in: Circle())
                    }
                    .disabled(plan.to == nil)
                    .accessibilityLabel(Text("Swap"))
                    .accessibilityIdentifier("swapEndpoints")
                }
                .buttonStyle(.borderless)
                // Plan is for later (tonight, next week). "From here, now" lives in Nearby.
                Picker("When", selection: $plan.timeMode) {
                    Text("Depart").tag(TimeMode.departAt)
                    Text("Arrive").tag(TimeMode.arriveBy)
                }
                .pickerStyle(.segmented)
                DatePicker(plan.timeMode == .arriveBy ? L10n.t("Arrive by") : L10n.t("Depart at"), selection: $plan.date)
                RouteOptionsButton(compact: true)
            }

            if plan.to != nil && !plan.searchStarted {
                Section {
                    Button { app.plan.searchStarted = true } label: {
                        Label("Search routes", systemImage: "magnifyingglass")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .accessibilityIdentifier("searchRoutes")
                }
            }
            if plan.to == nil || !plan.searchStarted {
                RecentSearchesSection()
            } else {
                resultsSection(plan)
                StreetComparisonSection(comparisons: plan.comparisons,
                                        bestTransit: plan.itineraries.filter { !$0.isDirect }.map(\.duration).min(),
                                        fromName: plan.from.title, toName: plan.to?.title ?? "")
            }
        }
        .navigationTitle("Plan")
        .screenTrail("Plan")
        .withSettingsButton()
        .onAppear {
            isVisible = true
            if plan.timeMode == .now { plan.timeMode = .departAt }
            if plan.date < .now.addingTimeInterval(-60) { plan.date = .now }
        }
        .toolbar {
            if plan.to != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { app.plan.to = nil } label: { Label("Clear destination", systemImage: "xmark.circle") }
                }
            }
        }
        .sheet(item: $picking) { target in
            PlaceSearchView(title: target == .from ? "From" : "To", allowCurrentLocation: true) { endpoint in
                if target == .from { app.plan.from = endpoint } else { app.plan.to = endpoint }
            }
        }
        .onDisappear { isVisible = false }
        .task(id: "\(app.plan.queryKey)|\(scenePhase)|\(app.tab)|\(isVisible)|\(app.plan.searchStarted)") {
            guard isVisible, scenePhase == .active, app.tab == .plan, app.plan.searchStarted else { return }
            selectedId = nil
            await app.plan.search(current: location.coordinate, locationDenied: location.isDenied)
            // Keep "now" results live: delays, cancellations and departed trips change by the minute.
            while app.plan.timeMode == .now, app.plan.to != nil, !Task.isCancelled {
                try? await Task.sleep(for: Self.refreshInterval)
                guard !Task.isCancelled else { break }
                await app.plan.search(current: location.coordinate, locationDenied: location.isDenied, silent: true)
            }
        }
        .onChange(of: location.hasFix) { _, hasFix in
            // Retry once the first location fix arrives.
            if hasFix, app.plan.searchStarted, app.plan.itineraries.isEmpty, app.plan.to != nil {
                Task { await app.plan.search(current: location.coordinate) }
            }
        }
    }

    /// Same weekday and time, next time it comes round.
    static func nextOccurrence(of date: Date, after now: Date = .now) -> Date {
        var d = date
        while d < now { d = Calendar.current.date(byAdding: .day, value: 7, to: d) ?? now }
        return d
    }

    private func endpointButton(label: LocalizedStringKey, endpoint: Endpoint?, target: PickTarget) -> some View {
        Button { picking = target } label: {
            HStack {
                Text(label).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                    .frame(minWidth: 56, alignment: .leading)
                if let endpoint {
                    if case .currentLocation = endpoint {
                        Image(systemName: "location.fill").foregroundStyle(.blue)
                    }
                    Text(endpoint.title).foregroundStyle(.primary).lineLimit(1)
                } else {
                    Text("Where to?").foregroundStyle(.secondary)
                }
                Spacer()
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(endpoint?.title ?? L10n.t("not set"))
    }

    private func detail(_ it: Itinerary) -> some View {
        ItineraryDetailView(itinerary: it, fromName: app.plan.from.title, toName: app.plan.to?.title ?? "")
    }

    @ViewBuilder
    private func resultsSection(_ plan: PlanModel) -> some View {
        let its = plan.sortedItineraries
        let windowStart = its.map(\.startTime).min() ?? .now
        let windowEnd = its.map(\.endTime).max() ?? .now
        let zoneNote = its.first.flatMap { Fmt.foreignZoneNote(tz: $0.legs.first?.from.tz, at: $0.startTime) }

        Section {
            OfflineNote()
            if plan.isLoading && its.isEmpty {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if let msg = plan.errorMessage, its.isEmpty {
                Text(msg).foregroundStyle(.secondary)
            }

            // Sort/map controls as a real list row: Menu buttons in Section headers are often
            // non-hittable for UI tests and awkward for VoiceOver.
            if !its.isEmpty {
                // Borderless: two controls in one row, each with its own tap area
                // (otherwise a tap anywhere in the row triggers both).
                HStack {
                    RouteSortMenu()
                        .buttonStyle(.borderless)
                    Spacer()
                    Button(showMap ? L10n.t("List") : L10n.t("Map")) { withAnimation { showMap.toggle() } }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.borderless)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("routeMapToggle")
                }
                .listRowBackground(Color.clear)
            }

            if !showMap && !its.isEmpty {
                ConnectionLegendRow(start: windowStart, end: windowEnd, tz: its.first?.legs.first?.from.tz)
            }
            if showMap && !its.isEmpty {
                CompareMapView(itineraries: its, selectedId: selectedId ?? its.first?.id)
                    .frame(height: 320)
                    .listRowInsets(EdgeInsets())
                if let sel = its.first(where: { $0.id == (selectedId ?? its.first?.id) }) {
                    NavigationLink("Details of selected route") { detail(sel) }
                }
                ForEach(its) { it in
                    Button { selectedId = it.id } label: {
                        ItineraryRow(itinerary: it, windowStart: windowStart, windowEnd: windowEnd)
                            .padding(.leading, 6)
                            .overlay(alignment: .leading) {
                                if it.id == (selectedId ?? its.first?.id) {
                                    Capsule().fill(.blue).frame(width: 3)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(it.id == (selectedId ?? its.first?.id) ? .isSelected : [])
                }
            } else {
                ForEach(its) { it in
                    NavigationLink {
                        detail(it)
                    } label: {
                        ItineraryRow(itinerary: it, windowStart: windowStart, windowEnd: windowEnd)
                    }
                }
            }

            if plan.canLoadMore {
                Button {
                    Task { await plan.loadMore() }
                } label: {
                    HStack {
                        Text(plan.timeMode == .arriveBy ? L10n.t("Earlier connections") : L10n.t("Later connections"))
                        if plan.isLoadingMore { Spacer(); ProgressView() }
                    }
                }
            }
        } header: {
            Text("Routes")
        } footer: {
            if !its.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    if let zoneNote { Label(zoneNote, systemImage: "clock") }
                }
                .padding(.top, 8)
            }
        }
    }
}

/// One route in the comparison list. All rows share one time axis so routes can be compared at a glance.
struct ItineraryRow: View {
    @AppStorage("routeTimelines") private var showTimeline = true
    let itinerary: Itinerary
    let windowStart: Date
    let windowEnd: Date

    private var tz: String? { itinerary.legs.first?.from.tz }

    var body: some View {
        let warnings = TransferRisk.warnings(for: itinerary)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(Fmt.time(itinerary.startTime, tz: tz)) – \(Fmt.time(itinerary.endTime, tz: itinerary.legs.last?.to.tz))")
                    .font(.headline.monospacedDigit())
                if itinerary.hasRealtime {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.caption).foregroundStyle(Color.live)
                        .accessibilityLabel("Live data")
                }
                Spacer()
                Text(Fmt.duration(seconds: itinerary.duration))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
            }
            if showTimeline {
                TimelineBar(itinerary: itinerary, windowStart: windowStart, windowEnd: windowEnd).frame(height: 22)
            }
            HStack(spacing: 8) {
                Text(Fmt.changes(itinerary.transfers))
                if let first = itinerary.firstTransitLeg {
                    Text("· \(first.lineName) from \(first.from.name)").lineLimit(1)
                }
                if itinerary.isCancelled {
                    Text("Cancelled").foregroundStyle(Color.danger)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if itinerary.transitLegs.contains(where: { !$0.serviceAlerts.isEmpty || $0.isReplacementBus }) {
                Label("Service changes on this route", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(Color.delay)
            }
            ForEach(warnings, id: \.self) { w in
                Label(w.message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(w.level == .missed ? Color.danger : Color.delay)
            }
        }
        .padding(.vertical, 4)
    }
}

struct TimelineBar: View {
    let itinerary: Itinerary
    let windowStart: Date
    let windowEnd: Date

    var body: some View {
        GeometryReader { geo in
            let span = max(windowEnd.timeIntervalSince(windowStart), 60)
            let width = geo.size.width
            let height = geo.size.height
            ZStack(alignment: .leading) {
                ForEach(Array(itinerary.legs.enumerated()), id: \.offset) { index, leg in
                    if index > 0, itinerary.legs[index - 1].endTime < leg.startTime {
                        let previous = itinerary.legs[index - 1].endTime
                        let gapStart = max(0, min(width, previous.timeIntervalSince(windowStart) / span * width))
                        let gapEnd = max(gapStart, min(width, leg.startTime.timeIntervalSince(windowStart) / span * width))
                        Path { path in path.move(to: CGPoint(x: gapStart, y: height / 2)); path.addLine(to: CGPoint(x: gapEnd, y: height / 2)) }
                            .stroke(Color.secondary, style: StrokeStyle(lineWidth: 2, lineCap: .butt, dash: [4, 4]))
                    }
                    let x = max(0, min(width, leg.startTime.timeIntervalSince(windowStart) / span * width))
                    let end = max(x, min(width, leg.endTime.timeIntervalSince(windowStart) / span * width))
                    let w = max(0, min(width - x, max(end - x, 2)))
                    if leg.isTransit {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(leg.lineColor)
                            .overlay {
                                if w > 36 {
                                    Text(leg.lineName)
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(leg.lineTextColor)
                                        .lineLimit(1)
                                        .padding(.horizontal, 2)
                                }
                            }
                            .frame(width: w, height: height)
                            .offset(x: x)
                    } else {
                        Capsule()
                            .fill(Color.secondary.opacity(0.35))
                            .frame(width: w, height: 4)
                            .offset(x: x)
                    }
                }
            }
            .frame(width: width, height: height, alignment: .leading).clipped()
        }
        .accessibilityHidden(true)
    }
}

/// Quick switch of the route order in the results header.
struct RouteSortMenu: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let current = app.routeOptions.sort
        Menu {
            Picker("Sort routes by", selection: Binding(get: { current }, set: { s in
                var o = app.routeOptions
                o.sort = s
                app.setRouteOptions(o)
            })) {
                ForEach(RouteSort.allCases) { s in Label(s.title, systemImage: s.symbol).tag(s) }
            }
        } label: {
            Label(current.title, systemImage: "arrow.up.arrow.down")
                .font(.caption.weight(.semibold))
                .textCase(nil)
        }
        .accessibilityIdentifier("routeSortMenu")
        .padding(.trailing, 8)
    }
}
