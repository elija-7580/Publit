import MapKit
import SwiftUI

/// The interactive "What's new" (`ReleaseStory`): an intro, one card per feature with a small live
/// demo and "Try it", the fixes, and the community card last. Swipe or use the buttons; nothing
/// moves on by itself. Shown full screen after an update, and again from Settings.
struct ReleaseStoryView: View {
    let story: ReleaseStory
    /// Called with a target when "Try it" is tapped; nil hides the button (e.g. from Settings).
    var onTry: ((ReleaseStory.Target) -> Void)? = nil
    let onClose: () -> Void

    @State private var page = 0
    @State private var openWishes = false
    @State private var openSupport = false

    init(story: ReleaseStory, onTry: ((ReleaseStory.Target) -> Void)? = nil, onClose: @escaping () -> Void) {
        self.story = story
        self.onTry = onTry
        self.onClose = onClose
    }

    private enum Page: Hashable {
        case intro, card(ReleaseStory.Card), fixes, community
    }

    private var pages: [Page] {
        [.intro] + story.cards.map { .card($0) } + [.fixes, .community]
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                        ScrollView {
                            content(item, active: index == page)
                                .padding(.horizontal, 24)
                                .padding(.top, 12)
                                .padding(.bottom, 24)
                                .frame(maxWidth: 560, alignment: .leading)
                                .frame(maxWidth: .infinity)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.25), value: page)
                footer
            }
            .background(Color.ground.ignoresSafeArea())
            .navigationDestination(isPresented: $openWishes) { WishesView() }
            .navigationDestination(isPresented: $openSupport) { SupportView() }
            .toolbar(.hidden, for: .navigationBar)
        }
        .accessibilityIdentifier("releaseStory")
    }

    // MARK: Chrome

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 4) {
                ForEach(pages.indices, id: \.self) { i in
                    Capsule()
                        .fill(i <= page ? Color.ink : Color.ink.opacity(0.15))
                        .frame(height: 3)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(L10n.f("Page %lld of %lld", page + 1, pages.count))
            HStack {
                Circle().fill(Color.signature).frame(width: 9, height: 9).accessibilityHidden(true)
                Text(L10n.f("What's new in %@", story.version))
                    .font(.subheadline.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.bold))
                        .frame(width: 32, height: 32)
                        .background(Color.inkFill, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("Close"))
                .accessibilityIdentifier("storyClose")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    private var footer: some View {
        let item = pages[page]
        let last = page == pages.count - 1
        return HStack(spacing: 10) {
            Button { page = max(0, page - 1) } label: {
                Image(systemName: "chevron.left").frame(width: 24)
            }
            .buttonStyle(.soft)
            .opacity(page == 0 ? 0 : 1)
            .disabled(page == 0)
            .accessibilityLabel(L10n.t("Back"))
            if case .card(let card) = item, let target = card.target, let onTry {
                Button { onTry(target) } label: { Text("Try it").frame(maxWidth: .infinity) }
                    .buttonStyle(.soft)
                    .accessibilityIdentifier("storyTry")
            }
            Button {
                if last { onClose() } else { page += 1 }
            } label: {
                Text(last ? L10n.t("Continue") : (page == 0 ? L10n.t("Let's go") : L10n.t("Next")))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.ink)
            .accessibilityIdentifier(last ? "storyDone" : "storyNext")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    // MARK: Pages

    @ViewBuilder
    private func content(_ item: Page, active: Bool) -> some View {
        switch item {
        case .intro: intro
        case .card(let card): cardPage(card, active: active)
        case .fixes: fixes
        case .community: community
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 18) {
            StoryChip(text: L10n.t("The first update"), highlighted: true)
            Text(L10n.t(story.headline))
                .font(.system(size: 54, weight: .heavy))
                .fixedSize(horizontal: false, vertical: true)
            Text(L10n.t(story.thanks))
                .font(.title3).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                StoryStat(value: story.cards.count, label: L10n.t("new things"))
                StoryStat(value: story.fixCount, label: L10n.t("bugs fixed"))
                StoryStat(value: story.requestedCount, label: L10n.t("asked by you"))
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func cardPage(_ card: ReleaseStory.Card, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            StoryChip(text: chip(card.credit), highlighted: card.credit != .new)
            Text(L10n.t(card.title))
                .font(.largeTitle.weight(.heavy))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(L10n.t(card.text))
                .font(.body).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            StoryDemo(demo: card.demo, active: active)
                .padding(16)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .padding(.top, 6)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("storyCard-\(card.id)")
    }

    private var fixes: some View {
        VStack(alignment: .leading, spacing: 14) {
            StoryChip(text: L10n.f("%lld bugs fixed", story.fixCount), highlighted: false)
            Text("Also fixed")
                .font(.largeTitle.weight(.heavy))
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(story.fixes, id: \.self) { fix in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Circle().fill(Color.signature).frame(width: 8, height: 8).accessibilityHidden(true)
                        Text(L10n.t(fix)).font(.body).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            Text("And many smaller ones. Thanks to everyone who reported them.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("storyFixes")
    }

    private var community: some View {
        VStack(alignment: .leading, spacing: 14) {
            StoryChip(text: L10n.t("Publit is a community project"), highlighted: true)
            Text("What should come next?")
                .font(.largeTitle.weight(.heavy))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            CommunityCard(open: { openWishes = true }, support: { openSupport = true })
        }
        .accessibilityIdentifier("storyCommunity")
    }

    private func chip(_ credit: ReleaseStory.Credit) -> String {
        switch credit {
        case .community: return L10n.t("You asked")
        case .testers: return L10n.t("Testers asked")
        case .new: return L10n.t("New")
        }
    }
}

private struct StoryChip: View {
    let text: String
    let highlighted: Bool

    var body: some View {
        Text(verbatim: text)
            .font(.caption.weight(.bold))
            .foregroundStyle(highlighted ? Color(white: 0.07) : Color.ink)
            .padding(.horizontal, 11).padding(.vertical, 5)
            .background(highlighted ? Color.signature : Color.inkFill, in: Capsule())
    }
}

private struct StoryStat: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: "\(value)").font(.title.weight(.heavy)).monospacedDigit()
            Text(verbatim: label).font(.footnote).foregroundStyle(.secondary)
                .lineLimit(2).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Demos

/// The live demo of one card. `active` is true while its page is on screen; demos that move
/// start then and stop when the page is left. With Reduce Motion they show their end state.
private struct StoryDemo: View {
    let demo: ReleaseStory.Demo
    let active: Bool

    var body: some View {
        switch demo {
        case .typing(let query, let result, let detail): TypingDemo(query: query, result: result, detail: detail, active: active)
        case .beforeAfter: BeforeAfterDemo()
        case .compass: NearbyMapDemo(active: active)
        case .tickets: TicketsDemo()
        case .getOff: GetOffDemo(active: active)
        case .places(let names): PlacesDemo(names: names, active: active)
        }
    }
}

private struct TypingDemo: View {
    let query: String
    let result: String
    let detail: String
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var typed = ""
    @State private var showResults = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                Text(verbatim: typed.isEmpty ? " " : typed)
                Rectangle().fill(Color.routeAhead).frame(width: 2, height: 18)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            .background(Color.inkFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 0) {
                row(symbol: "house.fill", title: result, subtitle: detail, highlighted: true)
                Divider()
                row(symbol: "tram.fill", title: "Mariahilfer Straße", subtitle: "U3 · 13A", highlighted: false)
            }
            .opacity(showResults ? 1 : 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("Your address, found."))
        .task(id: active) { await run() }
    }

    private func row(symbol: String, title: String, subtitle: String, highlighted: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.footnote)
                .frame(width: 28, height: 28)
                .background(Color.inkFill, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: title).font(.subheadline.weight(.semibold))
                    .padding(.horizontal, highlighted ? 4 : 0)
                    .background(highlighted ? Color.signature.opacity(0.85) : .clear, in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(highlighted ? Color(white: 0.07) : Color.ink)
                Text(verbatim: subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }

    private func run() async {
        guard active, !reduceMotion else {
            typed = query; showResults = true
            return
        }
        typed = ""; showResults = false
        try? await Task.sleep(for: .milliseconds(400))
        for ch in query {
            guard !Task.isCancelled else { return }
            typed.append(ch)
            try? await Task.sleep(for: .milliseconds(70))
        }
        try? await Task.sleep(for: .milliseconds(250))
        withAnimation(.easeOut(duration: 0.3)) { showResults = true }
    }
}

/// Clips to the part right of `fraction` (0…1) of the width.
private struct TrailingClip: Shape {
    var fraction: CGFloat
    var animatableData: CGFloat {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX + rect.width * fraction, y: rect.minY,
                    width: rect.width * (1 - fraction), height: rect.height))
    }
}

private struct BeforeAfterDemo: View {
    @State private var fraction: CGFloat = 0.5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                pane(after: false)
                pane(after: true).clipShape(TrailingClip(fraction: fraction))
                Rectangle().fill(Color.ink).frame(width: 2)
                    .overlay {
                        Image(systemName: "arrow.left.and.right")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(Color.onInk)
                            .frame(width: 34, height: 34)
                            .background(Color.ink, in: Circle())
                    }
                    .offset(x: geo.size.width * fraction - 1)
            }
            .contentShape(Rectangle())
            // Above the page swipe of the story, so dragging moves the handle instead of the page.
            .highPriorityGesture(DragGesture(minimumDistance: 0).onChanged { value in
                fraction = min(0.95, max(0.05, value.location.x / max(geo.size.width, 1)))
            })
        }
        .frame(height: 230)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("Search where your thumb is."))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: fraction = min(0.95, fraction + 0.2)
            case .decrement: fraction = max(0.05, fraction - 0.2)
            @unknown default: break
            }
        }
    }

    private func pane(after: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(after ? L10n.t("Now") : L10n.t("Before"))
                    .font(.caption2.weight(.bold)).textCase(.uppercase).foregroundStyle(.secondary)
                Spacer()
            }
            field("Marienplatz", button: false)
            field("Flughafen München", button: !after)
            Spacer(minLength: 0)
            if after {
                Label(L10n.t("Search routes"), systemImage: "magnifyingglass")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.onInk)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.surface)
    }

    private func field(_ name: String, button: Bool) -> some View {
        HStack {
            Text(verbatim: name).font(.footnote).foregroundStyle(.secondary)
            Spacer()
            if button {
                Image(systemName: "magnifyingglass").font(.caption.weight(.bold))
                    .foregroundStyle(Color.onInk)
                    .frame(width: 26, height: 26)
                    .background(Color.ink, in: Circle())
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(Color.inkFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

/// A view cone pointing up from its bottom centre.
private struct Beam: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

/// The real Nearby map, as in the Nearby tab: you with the arrow the way you face, the stations
/// around you from the last board (or a fresh query), movable and zoomable, a tap on a station
/// opens its departures. Without a location it falls back to `CompassDemo`.
private struct NearbyMapDemo: View {
    let active: Bool
    @Environment(LocationManager.self) private var location
    @State private var groups: [StopGroup] = []
    @State private var station: StopGroup?
    @State private var showStation = false

    var body: some View {
        Group {
            if let here = location.coordinate {
                NearbyMap(here: here, groups: groups,
                          onOpenStation: { g in station = g; showStation = true },
                          heading: location.heading)
                    .frame(height: 340)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                CompassDemo()
            }
        }
        .navigationDestination(isPresented: $showStation) {
            if let g = station {
                StopDeparturesView(stopId: g.id, name: g.name, coordinate: g.coordinate, exact: g.isPole)
            }
        }
        .task(id: "\(active)-\(location.coordinate != nil)") { await load() }
        .onChange(of: active, initial: true) { _, on in location.setHeading(on, for: "story") }
        .onDisappear { location.setHeading(false, for: "story") }
    }

    private func load() async {
        guard active, groups.isEmpty, let here = location.coordinate else { return }
        if let last = await TransitousClient.shared.lastNearby(maxAge: 1800), here.distance(to: last.center) < 400 {
            groups = StopGrouping.group(StopTime.upcoming(last.response.stopTimes), around: here)
        }
        for radius in Reach.nearbyRadii where groups.isEmpty {
            guard let res = try? await TransitousClient.shared.departures(near: here, radius: radius, count: 40),
                  !Task.isCancelled else { return }
            groups = StopGrouping.group(StopTime.upcoming(res.stopTimes), around: here)
        }
    }
}

/// Without a location: Apple Maps around Marienplatz in Munich with five stations; you can move
/// the map, and the beam turns with Left / Ahead / Right.
private struct CompassDemo: View {
    private struct Station: Identifiable {
        let id: String
        let coordinate: CLLocationCoordinate2D
    }

    @State private var heading: Double = 0
    private let me = CLLocationCoordinate2D(latitude: 48.13695, longitude: 11.57290)
    private let stations = [
        Station(id: "Marienplatz", coordinate: CLLocationCoordinate2D(latitude: 48.13718, longitude: 11.57555)),
        Station(id: "Karlsplatz (Stachus)", coordinate: CLLocationCoordinate2D(latitude: 48.13915, longitude: 11.56540)),
        Station(id: "Odeonsplatz", coordinate: CLLocationCoordinate2D(latitude: 48.14260, longitude: 11.57700)),
        Station(id: "Sendlinger Tor", coordinate: CLLocationCoordinate2D(latitude: 48.13405, longitude: 11.56700)),
        Station(id: "Isartor", coordinate: CLLocationCoordinate2D(latitude: 48.13395, longitude: 11.58260)),
    ]

    var body: some View {
        VStack(spacing: 10) {
            Map(initialPosition: .region(MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: 48.13800, longitude: 11.57350),
                    span: MKCoordinateSpan(latitudeDelta: 0.0125, longitudeDelta: 0.0125))),
                interactionModes: [.pan, .zoom]) {
                ForEach(stations) { station in
                    Annotation(station.id, coordinate: station.coordinate, anchor: .center) {
                        Circle().fill(Color(white: 0.07))
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                            .frame(width: 13, height: 13)
                    }
                }
                Annotation("", coordinate: me, anchor: .center) {
                    ZStack {
                        Beam()
                            .fill(Color.routeAhead.opacity(0.25))
                            .frame(width: 60, height: 70)
                            .offset(y: -35)
                            .frame(width: 150, height: 150)
                            .rotationEffect(.degrees(heading))
                            .animation(.spring(duration: 0.5), value: heading)
                        Circle().fill(Color.routeAhead)
                            .overlay(Circle().stroke(Color.white, lineWidth: 3))
                            .frame(width: 22, height: 22)
                            .shadow(color: .black.opacity(0.2), radius: 3)
                    }
                }
                .annotationTitles(.hidden)
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .frame(height: 280)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityHidden(true)
            Picker(L10n.t("Direction"), selection: $heading) {
                Text("Left").tag(-60.0)
                Text("Ahead").tag(0.0)
                Text("Right").tag(60.0)
            }
            .pickerStyle(.segmented)
        }
    }
}

private struct TicketsDemo: View {
    private struct Ride: Identifiable {
        let id: Int
        let line: String
        let color: Color
        let route: String
        let time: String
        /// The pass that does not cover this ride.
        let notWith: String?
    }

    private let passes = ["Deutschlandticket", "KlimaTicket Ö", "GA"]
    private let rides = [
        Ride(id: 0, line: "ICE 26", color: Color(red: 0.77, green: 0.09, blue: 0.11), route: "München → Nürnberg", time: "1 h 05", notWith: "Deutschlandticket"),
        Ride(id: 1, line: "RE 1", color: Color(white: 0.33), route: "München → Nürnberg", time: "1 h 42", notWith: nil),
        Ride(id: 2, line: "CAT", color: Color(red: 0.16, green: 0.49, blue: 0.88), route: "Flughafen → Wien Mitte", time: "16 min", notWith: "KlimaTicket Ö"),
        Ride(id: 3, line: "S7", color: Color(red: 0.24, green: 0.6, blue: 0.24), route: "Flughafen → Wien Mitte", time: "25 min", notWith: nil),
    ]
    @State private var chosen: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FlowChips(items: passes, chosen: $chosen)
            VStack(spacing: 0) {
                ForEach(rides.filter { r in r.notWith.map { !chosen.contains($0) } ?? true }) { r in
                    HStack(spacing: 8) {
                        Text(verbatim: r.line)
                            .font(.caption2.weight(.heavy)).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(r.color, in: RoundedRectangle(cornerRadius: 5))
                        Text(verbatim: r.route).font(.subheadline).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(verbatim: r.time).font(.footnote).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 9)
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                    Divider()
                }
            }
            .animation(.easeInOut(duration: 0.3), value: chosen)
        }
    }
}

private struct FlowChips: View {
    let items: [String]
    @Binding var chosen: Set<String>

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { chips }
            VStack(alignment: .leading, spacing: 6) { chips }
        }
    }

    @ViewBuilder private var chips: some View {
        ForEach(items, id: \.self) { item in
            let on = chosen.contains(item)
            Button {
                if on { chosen.remove(item) } else { chosen.insert(item) }
            } label: {
                Text(verbatim: item)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(on ? Color.onInk : Color.ink)
                    .padding(.horizontal, 11).padding(.vertical, 7)
                    .background(on ? Color.ink : Color.inkFill, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(on ? .isSelected : [])
        }
    }
}

private struct GetOffDemo: View {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0
    private let stops = ["Sendlinger Tor", "Goetheplatz", "Poccistraße", "Implerstraße"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(stops.indices, id: \.self) { i in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().stroke(Color.routeAhead, lineWidth: 3).frame(width: 12, height: 12)
                            if i == step {
                                Circle().fill(Color.signature)
                                    .overlay(Circle().stroke(Color(white: 0.07), lineWidth: 2))
                                    .frame(width: 18, height: 18)
                                    .transition(.scale)
                            }
                        }
                        .frame(width: 20)
                        Text(verbatim: stops[i])
                            .font(i == stops.count - 1 ? .subheadline.weight(.heavy) : .subheadline)
                        Spacer()
                        if i == stops.count - 2 {
                            Image(systemName: "bell.fill")
                                .foregroundStyle(step == i ? Color.signature : Color.secondary.opacity(0.4))
                                .symbolEffect(.bounce, value: step == i)
                        }
                    }
                    .frame(height: 34)
                }
            }
            .animation(.easeInOut(duration: 0.4), value: step)
            Text(L10n.f("Next stop: %@. Get ready to get off.", stops[stops.count - 1]))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.onInk)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .opacity(step == stops.count - 2 ? 1 : 0)
                .animation(.easeInOut(duration: 0.3), value: step)
        }
        .task(id: active) { await run() }
    }

    private func run() async {
        guard active, !reduceMotion else {
            step = stops.count - 2
            return
        }
        step = 0
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(1300))
            guard !Task.isCancelled else { return }
            step = (step + 1) % stops.count
        }
    }
}

private struct PlacesDemo: View {
    let names: [String]
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // One name at a time: the old one slides up and out, the new one comes in from below.
            ZStack(alignment: .leading) {
                Text(verbatim: names.isEmpty ? "" : names[index % names.count])
                    .font(.system(size: 40, weight: .heavy))
                    .id(index)
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                            removal: .move(edge: .top).combined(with: .opacity)))
            }
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .clipped()
            .animation(.easeInOut(duration: 0.45), value: index)
            .accessibilityHidden(true)
            HStack(spacing: 6) {
                tile("location.fill", L10n.t("Nearby"))
                tile("magnifyingglass", L10n.t("Search"))
                tile("tram.fill", L10n.t("Live trip"))
            }
        }
        .task(id: active) { await run() }
    }

    private func tile(_ symbol: String, _ title: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
            Text(verbatim: title).font(.caption).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(Color.inkFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func run() async {
        guard active, !reduceMotion, names.count > 1 else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(1400))
            guard !Task.isCancelled else { return }
            index += 1
        }
    }
}
