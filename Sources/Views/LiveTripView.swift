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
    @Environment(\.scenePhase) private var scenePhase
    @State private var now = Date()
    /// A stage picked by hand; nil follows the trip.
    @State private var picked: String?

    /// A recent fix only: an old one would put you at the wrong stop.
    private var fix: LatLon? {
        guard let l = location.location, Date().timeIntervalSince(l.timestamp) < 120, l.horizontalAccuracy >= 0,
              l.horizontalAccuracy < 200 else { return nil }
        return LatLon(lat: l.coordinate.latitude, lon: l.coordinate.longitude)
    }

    var body: some View {
        let it = trip.itinerary
        let steps = TripGuide.steps(it)
        // Reading the fix here redraws on every fix: wanted on this screen (every few metres while walking).
        let here = fix
        let live = TripGuide.current(steps, it, at: now, location: here)
        let index = picked.flatMap { id in steps.firstIndex { $0.id == id } } ?? live
        let step = steps[index]
        let leg = it.legs[step.legIndex]
        let walk = step.kind == .walk ? WalkRoute(leg: leg) : nil
        let walkPos = here.flatMap { walk?.position(of: $0) }
        let ride = step.kind == .ride || step.kind == .wait ? TripGuide.ridePosition(leg, at: now, location: here) : nil
        let check = index == live ? TripGuide.check(step, it, at: now, location: here, accuracy: location.accuracy, walk: walk) : .fine
        List {
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

            if picked != nil {
                Section {
                    Button { picked = nil } label: { Label("Back to now", systemImage: "location.fill") }
                        .font(.subheadline.weight(.semibold))
                }
            }

            switch step.kind {
            case .walk: walkSections(leg, index: step.legIndex, in: it, route: walk!, position: walkPos, check: check)
            case .wait: waitSection(leg, in: it, check: check)
            case .ride: rideSections(leg, progress: ride?.progress ?? .notStarted, fromGPS: ride?.fromGPS ?? false, check: check)
            case .arrive: arriveSection(it)
            }

            Section {
                NavigationLink {
                    ItineraryDetailView(itinerary: it, fromName: trip.fromName, toName: trip.toName,
                                        statusAt: { TripStatus.at($0, it) }, refreshedAt: trip.refreshedAt)
                } label: {
                    Label("Route details", systemImage: "list.bullet")
                }
                Button(role: .destructive) {
                    Task { await TripSession.stop(trip, in: trips) }
                } label: {
                    Label("End trip", systemImage: "stop.circle")
                }
                .accessibilityIdentifier("endTrip")
            } footer: {
                if let refreshedAt = trip.refreshedAt {
                    Text("Updated \(refreshedAt.formatted(date: .omitted, time: .shortened))")
                }
            }
        }
        .ticking(every: 15, now: $now)
        .navigationTitle(trip.toName)
        .navigationBarTitleDisplayMode(.inline)
        .screenTrail("Live trip")
        .onAppear { location.start(); location.setPrecise(scenePhase == .active) }
        .onDisappear { location.setPrecise(false) }
        .onChange(of: scenePhase) { _, phase in location.setPrecise(phase == .active) }
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
                        if let track = TransitLabels.clean(next.from.track) {
                            Text(verbatim: "· " + L10n.f("Platform %@", track)).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    if spare < 60 && next.startTime > now {
                        Label("Walk faster to make it.", systemImage: "hare.fill")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Color.delay)
                    }
                }
            }
            .padding(.vertical, 4)
            if let position, let nextMove = route.maneuvers[safe: position.index + 1] {
                HStack(spacing: 12) {
                    Image(systemName: nextMove.symbol).font(.title2.weight(.bold)).frame(width: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.f("In %@", Fmt.distance(meters: position.toNext ?? 0)))
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(nextMove.instruction(destination: target)).font(.headline)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            if check == .offRoute { replanRow(L10n.t("You seem to be off the route.")) }
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
    private func waitSection(_ leg: Leg, in it: Itinerary, check: TripGuide.Check) -> some View {
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
                if let track = TransitLabels.clean(leg.from.track) {
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
            ServiceAlertsView(alerts: leg.serviceAlerts)
            Label(rideSummary, systemImage: "arrow.right.circle")
                .font(.subheadline).foregroundStyle(.secondary)
            GetOffButton(leg: leg)
            if check == .missed { replanRow(L10n.t("Missed it?")) }
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
                InkProgress(value: value, tint: leg.lineColor).padding(.top, 2)
                Text(fromGPS ? L10n.t("Position from your location.") : leg.realTime
                     ? L10n.t("Position estimated from live stop times.") : L10n.t("Position estimated from the timetable."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            if check == .missed { replanRow(L10n.t("Missed it?")) }
            ServiceAlertsView(alerts: leg.serviceAlerts)
            GetOffButton(leg: leg)
        }
        Section("Stops") {
            ForEach(Array(stops.enumerated()), id: \.offset) { i, stop in
                GuideStopRow(stop: stop, state: Self.stopState(i, progress: progress, count: stops.count),
                             isLast: i == stops.count - 1, color: leg.lineColor)
            }
        }
    }

    // MARK: Arrive

    private func arriveSection(_ it: Itinerary) -> some View {
        let last = it.legs.last
        let arrived = now >= it.endTime
        return Section {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "flag.checkered").font(.title.weight(.semibold))
                Text(arrived ? L10n.t("You have arrived") : L10n.f("Arrive at %@", trip.toName))
                    .font(.title3.weight(.bold))
                Text(verbatim: "\(trip.toName) · \(Fmt.time(it.endTime, tz: last?.to.tz))")
                    .font(.headline.monospacedDigit()).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            if arrived {
                Button {
                    Task { await TripSession.stop(trip, in: trips) }
                } label: {
                    Text("End trip").font(.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

    // MARK: Helpers

    private func replanRow(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold)).foregroundStyle(Color.delay)
            Button { replan() } label: {
                Label("New route from here", systemImage: "arrow.triangle.turn.up.right.diamond")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
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

    var body: some View {
        let current = itinerary.legs[step.legIndex]
        Map(position: $camera) {
            UserAnnotation()
            ForEach(Array(itinerary.legs.enumerated()), id: \.offset) { i, leg in
                let active = i == step.legIndex
                MapPolyline(coordinates: leg.legGeometry.clCoordinates)
                    .stroke((leg.isTransit ? leg.lineColor : Color.gray).opacity(active ? 1 : 0.35),
                            style: StrokeStyle(lineWidth: active ? 6 : 4, lineCap: .round, lineJoin: .round,
                                               dash: leg.isTransit ? [] : [6, 5]))
            }
            if let vehicle {
                Annotation("", coordinate: vehicle.clCoordinate) {
                    Circle().fill(current.lineColor).frame(width: 18, height: 18)
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
        .onAppear { camera = Self.camera(step, itinerary) }
        .onChange(of: step) { _, s in withAnimation { camera = Self.camera(s, itinerary) } }
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

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
