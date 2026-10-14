import SwiftUI
import MapKit

/// A started trip, stage by stage, as the trip screen: walk (with directions), wait for the
/// vehicle, ride (where you are, stops left), arrive. It follows the live times and, while it is
/// open, the phone's position. A stage can be tapped to look ahead; "Now" goes back.
struct LiveTripView: View {
    let trip: SavedTrip
    @Environment(TripStore.self) private var trips
    @Environment(LocationManager.self) private var location
    @Environment(AppState.self) private var app
    @Environment(PassStore.self) private var passes
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("guideVoice") private var voice = false
    @State private var now = Date()
    /// Cues already given (each turn, platform change, "get off next" once).
    @State private var announced: Set<String> = []
    @State private var feedback = 0
    @State private var feedbackKind: GuideCue.Kind = .stage
    @State private var showTickets = false
    /// A stage picked by hand; nil follows the trip.
    @State private var picked: String?

    /// A recent fix only: an old one would put you at the wrong stop.
    private var fix: LatLon? {
        guard let l = location.location, Date().timeIntervalSince(l.timestamp) < 120, l.horizontalAccuracy >= 0,
              l.horizontalAccuracy < 200 else { return nil }
        return LatLon(lat: l.coordinate.latitude, lon: l.coordinate.longitude)
    }

    var body: some View {
        Group {
            if trip.itinerary.legs.isEmpty {
                ItineraryDetailView(itinerary: trip.itinerary, fromName: trip.fromName, toName: trip.toName)
            } else {
                guide
            }
        }
    }

    private var guide: some View {
        let it = trip.itinerary
        let steps = TripGuide.steps(it)
        // Reading the fix here redraws on every fix: wanted on this screen (every few metres while walking).
        let here = fix
        let live = TripGuide.current(steps, it, at: now, location: here)
        let index = picked.flatMap { id in steps.firstIndex { $0.id == id } } ?? live
        let step = steps[index]
        let leg = it.legs[step.legIndex]
        let walk = step.kind == .walk ? WalkRoute(leg: leg) : nil
        // Your position counts only on the walk you are on and near its path. A walk picked in the
        // strip (a later change, the last metres) or one starting somewhere else shows its own length,
        // not the way from where you stand.
        let walkPos = walk?.livePosition(of: here, isActive: index == live)
        let ride = step.kind == .ride || step.kind == .wait ? TripGuide.ridePosition(leg, at: now, location: here) : nil
        let check = index == live ? TripGuide.check(step, it, at: now, location: here, accuracy: location.accuracy, walk: walk) : .fine
        let cue = index == live ? GuideCues.current(step, it, at: now, walk: walk, position: walkPos, progress: ride?.progress) : nil
        let wrong = index == live && TripAlternative.needed(check, it, at: now)
        let wrongMessage: String = check == .offRoute ? L10n.t("You seem to be off the route.")
            : check == .missed ? L10n.t("Missed it?") : L10n.t("Connection cancelled")
        List {
            Section {
                TripArrivalCard(trip: trip, now: now)
            }
            .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            Section {
                TripTimelineView(itinerary: it, fromName: trip.fromName, toName: trip.toName, now: now) { legIndex in
                    if let selected = steps.first(where: { $0.legIndex == legIndex && $0.kind != .arrive }) {
                        picked = selected.id
                    }
                }
            }
            .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            TripActionsSection(itinerary: it, fromName: trip.fromName, toName: trip.toName)

            if wrong {
                Section {
                    AlternativeRow(trip: trip, from: here, message: wrongMessage, onMore: replan)
                }
            }

            if picked != nil {
                Section {
                    Button { picked = nil } label: { Label("Back to now", systemImage: "location.fill") }
                        .font(.subheadline.weight(.semibold))
                }
            }

            switch step.kind {
            case .walk: walkSections(leg, index: step.legIndex, in: it, route: walk!, position: walkPos, check: check)
            case .wait: waitSection(leg, index: step.legIndex, in: it)
            case .ride: rideSections(leg, progress: ride?.progress ?? .notStarted, fromGPS: ride?.fromGPS ?? false, check: check)
            case .arrive: arriveSection(it, here: here)
            }

            Section {
                GuideMap(itinerary: it, step: step,
                         vehicle: step.kind == .ride ? ride.flatMap { TripProgress.position($0.progress, stops: leg.allStops) } : nil,
                         focus: walkPos.flatMap { p in walk?.maneuvers[safe: p.index + 1]?.coordinate })
                    .frame(height: 250)
                    .listRowInsets(EdgeInsets())
                StageStrip(steps: steps, itinerary: it, live: live, shown: index) { tapped in
                    picked = tapped == live ? nil : steps[tapped].id
                }
                .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
            }

            Section {
                NavigationLink {
                    ItineraryDetailView(itinerary: it, fromName: trip.fromName, toName: trip.toName,
                                        statusAt: { TripStatus.at($0, it) }, refreshedAt: trip.refreshedAt)
                } label: {
                    Label("Route details", systemImage: "list.bullet")
                }

            } footer: {
                if let refreshedAt = trip.refreshedAt {
                    Text("Updated \(refreshedAt.formatted(date: .omitted, time: .shortened))")
                }
            }
        }
        .inkList()
        .ticking(every: 15, now: $now)
        .navigationTitle(trip.toName)
        .navigationBarTitleDisplayMode(.inline)
        .screenTrail("Live trip")
        .toolbar { ToolbarItem(placement: .primaryAction) { voiceButton } }
        .sheet(isPresented: $showTickets) {
            NavigationStack {
                TripPassesView(tripId: trip.id, at: now)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showTickets = false } } }
            }
            .environment(\.liveBarInset, 0)
        }
        .sensoryFeedback(trigger: feedback) { _, _ in
            feedbackKind == .platform ? SensoryFeedback.warning : SensoryFeedback.impact(weight: .heavy, intensity: 1)
        }
        .onChange(of: cue) { _, new in announce(new) }
        .onAppear {
            // What is on screen when it opens needs no announcement.
            if let cue { announced.insert(cue.key) }
            location.start()
            location.setPrecise(scenePhase == .active)
            location.setHeading(scenePhase == .active)
        }
        .onDisappear {
            location.setPrecise(false)
            location.setHeading(false)
            GuideVoice.shared.stop()
        }
        .onChange(of: scenePhase) { _, phase in
            location.setPrecise(phase == .active)
            location.setHeading(phase == .active)
        }
        .onChange(of: live) { _, _ in
            // The trip moved on: a stage picked earlier is over or now current.
            if let picked, let i = steps.firstIndex(where: { $0.id == picked }), i <= live { self.picked = nil }
        }
    }

    // MARK: Walk

    @ViewBuilder
    private func walkSections(_ leg: Leg, index: Int, in it: Itinerary, route: WalkRoute,
                              position: WalkRoute.Position?, check: TripGuide.Check) -> some View {
        let next = it.legs[(index + 1)...].first(where: \.isTransit)
        let target = next?.from.name ?? ItineraryDetailView.placeName(leg.to)
        let remaining = position?.remaining ?? leg.distance ?? route.length * route.scale
        let pace = (leg.distance ?? 0) > 0 ? Double(leg.duration) / (leg.distance ?? 1) : 1 / 1.3
        let walkSeconds = Int(remaining * pace)
        let nextIndex = it.legs[(index + 1)...].firstIndex(where: \.isTransit)
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: leg.rental.map { $0.kind.symbol } ?? ModeStyle.symbol(leg.mode))
                        .font(.title3.weight(.semibold)).frame(width: 30)
                    Text(L10n.f("Walk to %@", target)).font(.title3.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(verbatim: "\(Fmt.distance(meters: remaining)) · \(Fmt.duration(seconds: max(60, walkSeconds)))")
                    .font(.headline.monospacedDigit()).foregroundStyle(.secondary)
                if now < leg.startTime {
                    Text(TripStatus.at(now, it).headline).font(.subheadline.weight(.semibold)).foregroundStyle(Color.live)
                }
                if let next {
                    let spare = Int(next.startTime.timeIntervalSince(now)) - walkSeconds
                    HStack(spacing: 6) {
                        LineBadge(next, compact: true)
                        Text(Self.departure(next, now: now)).font(.subheadline)
                        if let change = next.from.platformChange {
                            Text(verbatim: "· " + L10n.f("Platform %@", change.now)).font(.subheadline.weight(.bold)).foregroundStyle(Color.delay)
                        } else if let track = TransitLabels.clean(next.from.track) {
                            Text(verbatim: "· " + L10n.f("Platform %@", track)).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    if let change = next.from.platformChange { PlatformChangeLabel(change: change) }
                    if spare < 60 && next.startTime > now {
                        Label("Walk faster to make it.", systemImage: "hare.fill")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Color.delay)
                    }
                }
            }
            .padding(.vertical, 4)
            if let b = route.bearing(at: position?.along ?? 0) {
                HeadingRow(bearing: b, title: Compass.head(Compass.point(b)))
            }
            if let position, let nextMove = route.maneuvers[safe: position.index + 1] {
                HStack(spacing: 12) {
                    Image(systemName: nextMove.symbol).font(.title2.weight(.bold)).frame(width: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.f("In %@", Fmt.distance(meters: position.toNext ?? 0)))
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(nextMove.instruction(destination: target)).font(.headline)
                        if let note = nextMove.exitNote {
                            Text(note).font(.subheadline.weight(.semibold))
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
            if let nextIndex, let transfer = TransferInfo(before: nextIndex, in: it) { TransferCard(info: transfer) }
            Button { Self.openInMaps(leg.to, name: target) } label: {
                Label("Open in Apple Maps", systemImage: "map")
            }
        }
        Section("Directions") {
            ForEach(Array(route.maneuvers.enumerated()), id: \.offset) { i, m in
                let isNow = position?.index == i
                let isPast = (position?.index ?? -1) > i
                HStack(spacing: 12) {
                    Image(systemName: m.symbol).font(.body.weight(.semibold)).frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.instruction(destination: target))
                            .font(.subheadline.weight(isNow ? .bold : .regular))
                        if let note = m.exitNote {
                            Text(note).font(.caption.weight(.semibold))
                        }
                        if m.kind != .arrive, m.distance >= 1 {
                            Text(Fmt.distance(meters: m.distance)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    if isNow { SignatureDot(size: 10) }
                }
                .foregroundStyle(isPast ? Color.secondary : Color.primary)
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: Wait

    @ViewBuilder
    private func waitSection(_ leg: Leg, index legIndex: Int, in it: Itinerary) -> some View {
        let warnings = TransferRisk.warnings(for: it).filter { $0.stopName == leg.from.name }
        let rideSummary: String = [Fmt.stops(max(leg.allStops.count - 1, 1)), Fmt.duration(seconds: leg.duration),
                                   L10n.f("Get off at %@", leg.to.name)].joined(separator: " · ")
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    LineBadge(leg)
                    DirectionLabel(direction: leg.directionName)
                }
                Text(Self.departure(leg, now: now)).font(.title2.weight(.bold).monospacedDigit())
                HStack(spacing: 8) {
                    Text(Fmt.time(leg.startTime, tz: leg.from.tz)).font(.headline.monospacedDigit())
                    if leg.delayMinutes > 0 {
                        Text(L10n.f("+%lld min", leg.delayMinutes)).font(.subheadline.weight(.semibold)).foregroundStyle(Color.delay)
                    } else if leg.realTime {
                        Text("On time").font(.subheadline.weight(.semibold)).foregroundStyle(Color.live)
                    }
                }
                Text(verbatim: leg.from.name).font(.subheadline)
                if let change = leg.from.platformChange {
                    Text(L10n.f("Platform %@", change.now)).font(.title3.weight(.bold))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .foregroundStyle(Color.delay)
                        .background(Color.delay.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                    PlatformChangeLabel(change: change)
                } else if let track = TransitLabels.clean(leg.from.track) {
                    Text(L10n.f("Platform %@", track)).font(.title3.weight(.bold))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.inkFill, in: RoundedRectangle(cornerRadius: 8))
                }
                if leg.isReplacementBus {
                    Label("Rail replacement bus", systemImage: "bus.fill").font(.subheadline.weight(.semibold)).foregroundStyle(Color.delay)
                }
                if leg.cancelled == true {
                    Text("This trip is cancelled.").font(.subheadline.weight(.semibold)).foregroundStyle(Color.danger)
                }
            }
            .padding(.vertical, 4)
            ForEach(warnings, id: \.self) { w in
                Label(w.message, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(w.level == .missed ? Color.danger : Color.delay)
            }
            if let transfer = TransferInfo(before: legIndex, in: it) { TransferCard(info: transfer) }
            ServiceAlertsView(alerts: leg.serviceAlerts)
            Label(rideSummary, systemImage: "arrow.right.circle")
                .font(.subheadline).foregroundStyle(.secondary)
            ticketRow
            GetOffButton(leg: leg)
        }
    }

    // MARK: Ride

    @ViewBuilder
    private func rideSections(_ leg: Leg, progress: TripProgress, fromGPS: Bool, check: TripGuide.Check) -> some View {
        let stops = leg.allStops
        let left = TripGuide.stopsLeft(progress, count: stops.count)
        let arrivalDelay = Int((leg.endTime.timeIntervalSince(leg.scheduledEndTime) / 60).rounded())
        let value = progress.stopValue(count: stops.count) / Double(max(stops.count - 1, 1))
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    LineBadge(leg)
                    DirectionLabel(direction: leg.directionName)
                }
                Text(L10n.f("Get off at %@", leg.to.name)).font(.title3.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Text(left == 0 ? L10n.t("Next stop") : L10n.f("in %@", Fmt.stops(left)))
                        .font(.headline)
                    Text(verbatim: "· \(Fmt.time(leg.endTime, tz: leg.to.tz))").font(.headline.monospacedDigit())
                    if arrivalDelay > 0 {
                        Text(L10n.f("+%lld min", arrivalDelay)).font(.subheadline.weight(.semibold)).foregroundStyle(Color.delay)
                    }
                }
                if let line = Self.whereNow(progress, stops: stops) {
                    Text(line).font(.subheadline).foregroundStyle(.secondary)
                }
                InkProgress(value: value, tint: leg.lineStroke).padding(.top, 2)
                Text(fromGPS ? L10n.t("Position from your location.") : leg.realTime
                     ? L10n.t("Position estimated from live stop times.") : L10n.t("Position estimated from the timetable."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            ServiceAlertsView(alerts: leg.serviceAlerts)
            ticketRow
            GetOffButton(leg: leg)
        }
        Section("Stops") {
            ForEach(Array(stops.enumerated()), id: \.offset) { i, stop in
                GuideStopRow(stop: stop, state: Self.stopState(i, progress: progress, count: stops.count),
                             isLast: i == stops.count - 1, color: leg.lineStroke)
            }
        }
    }

    // MARK: Arrive

    private func arriveSection(_ it: Itinerary, here: LatLon?) -> some View {
        let last = it.legs.last
        let arrived = now >= it.endTime
        let dest = last?.to.coordinate
        let away = here.flatMap { h in dest.map { h.distance(to: $0) } }
        return Section {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "flag.checkered").font(.title.weight(.semibold))
                Text(arrived ? L10n.t("You have arrived") : L10n.f("Arrive at %@", trip.toName))
                    .font(.title3.weight(.bold))
                Text(verbatim: "\(trip.toName) · \(Fmt.time(it.endTime, tz: last?.to.tz))")
                    .font(.headline.monospacedDigit()).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            // The last metres: how far and which way to the door, after the last stop.
            if let here, let dest, let away, away > 15, away < 3000 {
                HeadingRow(bearing: PathGeometry.bearing(here, dest), title: L10n.f("Destination in %@", Fmt.distance(meters: away)))
            }
            if arrived {
                Button {
                    Task { await TripSession.stop(trip, in: trips) }
                } label: {
                    Text("End trip").font(.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(.ink)
                .controlSize(.large)
            }
        }
    }

    // MARK: Helpers

    /// Opens the tickets valid for this trip (from the wallet), right where you board.
    @ViewBuilder
    private var ticketRow: some View {
        if Features.passes, !passes.passes(forTrip: trip.id, at: now).isEmpty {
            Button { showTickets = true } label: {
                Label("Show ticket", systemImage: "ticket")
            }
            .accessibilityIdentifier("guideShowTicket")
        }
    }

    private var voiceButton: some View {
        Button {
            voice.toggle()
            if !voice { GuideVoice.shared.stop() }
        } label: {
            Label(voice ? L10n.t("Turn off spoken directions") : L10n.t("Turn on spoken directions"),
                  systemImage: voice ? "speaker.wave.2.fill" : "speaker.slash")
        }
        .accessibilityIdentifier("guideVoice")
    }

    /// A vibration for each new cue, and the words when spoken directions are on.
    private func announce(_ cue: GuideCue?) {
        guard let cue, !announced.contains(cue.key) else { return }
        announced.insert(cue.key)
        feedbackKind = cue.kind
        feedback += 1
        if voice { GuideVoice.shared.say(cue.text) }
    }

    /// Routes from the current position to the trip's destination, leaving now.
    private func replan() {
        guard let dest = trip.itinerary.legs.last?.to else { return }
        let place = SavedPlace(id: "trip-\(trip.id)", name: trip.toName, subtitle: nil, lat: dest.lat, lon: dest.lon, stopId: nil)
        app.deepLink = nil
        app.goNow(to: place)
    }

    static func departure(_ leg: Leg, now: Date) -> String {
        let secs = leg.startTime.timeIntervalSince(now)
        if secs > 60 { return L10n.f("Departs in %lld min", Int(ceil(secs / 60))) }
        if secs > -60 { return L10n.t("Departs now") }
        return L10n.f("Departed %@", Fmt.time(leg.startTime, tz: leg.from.tz))
    }

    static func whereNow(_ progress: TripProgress, stops: [Place]) -> String? {
        switch progress {
        case .notStarted: return stops.first.map { L10n.f("Board at %@", $0.name) }
        case .atStop(let i): return L10n.f("Now at %@", stops[i].name)
        case .between(let i, _): return stops.indices.contains(i + 1) ? L10n.f("Next: %@", stops[i + 1].name) : nil
        case .finished: return nil
        }
    }

    static func stopState(_ i: Int, progress: TripProgress, count: Int) -> GuideStopRow.Mark {
        switch progress {
        case .notStarted: return i == 0 ? .here : .ahead
        case .finished: return i == count - 1 ? .here : .past
        case .atStop(let s): return i < s ? .past : i == s ? .here : .ahead
        case .between(let s, _): return i <= s ? .past : i == s + 1 ? .next : .ahead
        }
    }

    static func openInMaps(_ place: Place, name: String) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate.clCoordinate))
        item.name = name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }
}

/// The stages as a row of chips: done, now (yellow dot), ahead. Tap one to look at it.
private struct StageStrip: View {
    let steps: [GuideStep]
    let itinerary: Itinerary
    let live: Int
    let shown: Int
    let onTap: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { i, step in
                        if i > 0 {
                            Image(systemName: "chevron.compact.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        Button { onTap(i) } label: { chip(step, index: i) }
                            .buttonStyle(.plain)
                            .id(step.id)
                    }
                }
                .padding(.vertical, 2)
            }
            .onAppear { if let id = steps[safe: shown]?.id { proxy.scrollTo(id, anchor: .center) } }
            .onChange(of: shown) { _, s in
                guard let id = steps[safe: s]?.id else { return }
                withAnimation { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    @ViewBuilder
    private func chip(_ step: GuideStep, index: Int) -> some View {
        let leg = itinerary.legs[step.legIndex]
        let selected = index == shown
        HStack(spacing: 4) {
            switch step.kind {
            case .walk:
                Image(systemName: leg.rental.map { $0.kind.symbol } ?? ModeStyle.symbol(leg.mode))
                Text(verbatim: "\(max(1, leg.duration / 60))")
            case .wait:
                Image(systemName: "clock")
                Text(Fmt.time(leg.startTime, tz: leg.from.tz)).monospacedDigit()
            case .ride:
                LineBadge(leg, compact: true)
            case .arrive:
                Image(systemName: "flag.checkered")
            }
            if index == live { SignatureDot(size: 7) }
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(selected ? Color.inkFill : Color.clear, in: Capsule())
        .overlay(Capsule().strokeBorder(selected ? Color.ink.opacity(0.5) : Color.primary.opacity(0.1)))
        .opacity(index < live ? 0.5 : 1)
        .accessibilityLabel(Text(Self.label(step, leg)))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private static func label(_ step: GuideStep, _ leg: Leg) -> String {
        switch step.kind {
        case .walk: return L10n.f("Walk to %@", leg.to.name)
        case .wait: return L10n.f("%@ departs %@", leg.lineName, Fmt.time(leg.startTime, tz: leg.from.tz))
        case .ride: return L10n.f("Get off at %@", leg.to.name)
        case .arrive: return L10n.t("Arrived")
        }
    }
}

/// One stop of the ride on a line in the line's colour; the yellow dot is where you are.
struct GuideStopRow: View {
    enum Mark { case past, here, next, ahead }
    let stop: Place
    let state: Mark
    let isLast: Bool
    let color: Color

    var body: some View {
        let time = stop.arrival ?? stop.departure
        let scheduled = stop.scheduledArrival ?? stop.scheduledDeparture
        let delay = time.flatMap { t in scheduled.map { Int((t.timeIntervalSince($0) / 60).rounded()) } } ?? 0
        HStack(spacing: 12) {
            ZStack {
                Rectangle().fill(state == .past ? color.opacity(0.35) : color).frame(width: 4)
                if state == .here || state == .next {
                    Circle().fill(Color.signature).frame(width: 14, height: 14)
                        .overlay(Circle().strokeBorder(Color.surface, lineWidth: 2.5))
                } else {
                    Circle().fill(Color.surface).frame(width: 10, height: 10)
                        .overlay(Circle().strokeBorder(state == .past ? color.opacity(0.35) : color, lineWidth: 2.5))
                }
            }
            .frame(width: 16)
            .frame(maxHeight: .infinity)
            .accessibilityHidden(true)
            Text(time.map { Fmt.time($0, tz: stop.tz) } ?? "–")
                .font(.subheadline.monospacedDigit().weight(isLast ? .bold : .regular))
                .lineLimit(1).fixedSize()
            if delay > 0 {
                Text(verbatim: "+\(delay)").font(.caption.monospacedDigit()).foregroundStyle(Color.delay)
            }
            Text(verbatim: stop.name)
                .font(.subheadline.weight(isLast || state == .here || state == .next ? .bold : .regular))
                .lineLimit(2)
                .strikethrough(stop.cancelled == true)
            Spacer(minLength: 4)
            if isLast { Image(systemName: "figure.walk.departure").foregroundStyle(.secondary).accessibilityLabel(Text("Get off here")) }
            else if let track = TransitLabels.clean(stop.track) {
                Text(L10n.f("Pl. %@", track)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(state == .past ? Color.secondary : Color.primary)
        .listRowSeparator(.hidden)
    }
}

/// The map of the stage: its leg in full colour, the rest faded; you, the vehicle and the next turn.
private struct GuideMap: View {
    let itinerary: Itinerary
    let step: GuideStep
    let vehicle: LatLon?
    let focus: LatLon?
    @State private var camera: MapCameraPosition = .automatic
    /// The map turns with the phone (like a compass) and follows you.
    @State private var followHeading = false

    var body: some View {
        let current = itinerary.legs[step.legIndex]
        Map(position: $camera) {
            UserAnnotation()
            ForEach(Array(itinerary.legs.enumerated()), id: \.offset) { i, leg in
                let active = i == step.legIndex
                MapPolyline(coordinates: leg.legGeometry.clCoordinates)
                    .stroke((leg.isTransit ? leg.lineStroke : Color.gray).opacity(active ? 1 : 0.35),
                            style: StrokeStyle(lineWidth: active ? 6 : 4, lineCap: .round, lineJoin: .round,
                                               dash: leg.isTransit ? [] : [6, 5]))
            }
            if let vehicle {
                Annotation("", coordinate: vehicle.clCoordinate) {
                    Circle().fill(current.lineStroke).frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                        .shadow(radius: 2)
                }
            }
            if let focus {
                Annotation("", coordinate: focus.clCoordinate) {
                    Circle().fill(Color.signature).frame(width: 14, height: 14)
                        .overlay(Circle().strokeBorder(.black.opacity(0.6), lineWidth: 2))
                }
            }
            Marker(current.isTransit && step.kind == .wait ? current.from.name : current.to.name,
                   systemImage: step.kind == .arrive ? "flag.fill" : "mappin",
                   coordinate: (step.kind == .wait ? current.from : current.to).coordinate.clCoordinate)
                .tint(step.kind == .arrive ? Color.danger : Color.ink)
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls { MapUserLocationButton(); MapCompass() }
        .overlay(alignment: .topLeading) {
            Button {
                followHeading.toggle()
                withAnimation {
                    camera = followHeading ? .userLocation(followsHeading: true, fallback: Self.camera(step, itinerary))
                        : Self.camera(step, itinerary)
                }
            } label: {
                Image(systemName: followHeading ? "location.north.line.fill" : "location.north.line")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .matteSurface(in: Circle())
            }
            .buttonStyle(.plain)
            .padding(8)
            .accessibilityLabel(Text(followHeading ? L10n.t("Stop turning the map") : L10n.t("Turn the map with you")))
            .accessibilityIdentifier("guideFollowHeading")
        }
        .onAppear { camera = Self.camera(step, itinerary) }
        .onChange(of: step) { _, s in
            guard !followHeading else { return }
            withAnimation { camera = Self.camera(s, itinerary) }
        }
    }

    static func camera(_ step: GuideStep, _ it: Itinerary) -> MapCameraPosition {
        let leg = it.legs[step.legIndex]
        switch step.kind {
        case .walk:
            return .userLocation(fallback: .rect(rect(leg.legGeometry.mapPoints + [leg.from.coordinate, leg.to.coordinate])))
        case .wait:
            return .camera(MapCamera(centerCoordinate: leg.from.coordinate.clCoordinate, distance: 900))
        case .ride:
            return .rect(rect(leg.legGeometry.mapPoints + leg.allStops.map(\.coordinate)))
        case .arrive:
            return .camera(MapCamera(centerCoordinate: leg.to.coordinate.clCoordinate, distance: 900))
        }
    }

    static func rect(_ points: [LatLon]) -> MKMapRect {
        let r = points.reduce(MKMapRect.null) { $0.union(MKMapRect(origin: MKMapPoint($1.clCoordinate), size: MKMapSize(width: 1, height: 1))) }
        let pad = max(max(r.width, r.height) * 0.15, 400)
        return r.insetBy(dx: -pad, dy: -pad)
    }
}

/// "Head north-east" with an arrow that points the way: turned by the compass while it works,
/// otherwise drawn with north at the top.
private struct HeadingRow: View {
    let bearing: Double
    let title: String
    @Environment(LocationManager.self) private var location

    var body: some View {
        // Only this row reads the compass, so only it redraws when the phone turns.
        let heading = location.heading
        HStack(spacing: 12) {
            Image(systemName: "location.north.fill")
                .font(.title2.weight(.bold))
                .rotationEffect(.degrees(heading.map { Compass.relative(bearing, heading: $0) } ?? bearing))
                .foregroundStyle(heading == nil ? Color.secondary : Color.ink)
                .frame(width: 36, height: 36)
                .animation(.easeOut(duration: 0.25), value: heading)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if heading == nil {
                    Text("No compass: the arrow has north at the top.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// "Platform changed (was 3)".
private struct PlatformChangeLabel: View {
    let change: PlatformChange
    var body: some View {
        Label(L10n.f("Platform changed (was %@)", change.scheduled), systemImage: "exclamationmark.triangle.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.delay)
    }
}

/// The change between two vehicles: platforms, levels, walk and time to spare.
private struct TransferCard: View {
    let info: TransferInfo

    var body: some View {
        let walk = info.walkSeconds >= 30 ? L10n.f("%@ walk", Fmt.duration(seconds: max(60, info.walkSeconds))) : nil
        let spare = info.spareSeconds >= 60 ? L10n.f("%@ to spare", Fmt.duration(seconds: info.spareSeconds)) : L10n.t("Very tight change")
        VStack(alignment: .leading, spacing: 4) {
            Label(L10n.f("Change from %@", info.fromLine), systemImage: "arrow.triangle.swap")
                .font(.subheadline.weight(.semibold))
            if let p = info.platforms { Text(p).font(.subheadline) }
            if let l = info.levels { Text(l).font(.caption).foregroundStyle(.secondary) }
            Text(verbatim: [walk, spare].compactMap { $0 }.joined(separator: " · "))
                .font(.caption.weight(.semibold))
                .foregroundStyle(info.isTight ? Color.delay : Color.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// Missed, off the path or cancelled: the next connection from where you are, to switch to in
/// one tap (the guide goes on with it), or all options.
private struct AlternativeRow: View {
    let trip: SavedTrip
    let from: LatLon?
    let message: String
    let onMore: () -> Void
    @Environment(TripStore.self) private var trips
    @Environment(AppState.self) private var app
    @State private var option: Itinerary?
    @State private var searching = false
    @State private var switching = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold)).foregroundStyle(Color.delay)
            if let option, let first = option.firstTransitLeg {
                HStack(spacing: 8) {
                    LineBadge(first, compact: true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(LiveTripView.departure(first, now: .now)).font(.subheadline.weight(.semibold))
                        Text(verbatim: "\(first.from.name) · " + L10n.f("Arrive %@", Fmt.time(option.endTime, tz: option.legs.last?.to.tz)))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                Button {
                    switching = true
                    Task {
                        await TripSession.reroute(trip, to: option, in: trips)
                        switching = false
                    }
                } label: {
                    Label("Switch to this connection", systemImage: "arrow.triangle.branch")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.ink)
                .disabled(switching)
                .accessibilityIdentifier("guideSwitchConnection")
            } else if searching {
                LogoLoader(label: L10n.t("Looking for the next connection…"), size: 40)
            }
            Button { onMore() } label: {
                Label("New route from here", systemImage: "arrow.triangle.turn.up.right.diamond")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
        .task(id: trip.itinerary.id) { await search() }
    }

    private func search() async {
        guard let from, let dest = trip.itinerary.legs.last?.to else { return }
        searching = true
        defer { searching = false }
        guard let res = try? await TransitousClient.shared.plan(from: from, to: dest.coordinate, time: nil, arriveBy: false,
                                                                 options: app.routeOptions) else { return }
        option = TripAlternative.pick(res.itineraries, at: .now)
    }
}
