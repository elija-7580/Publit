import SwiftUI
import MapKit

// The iPad layout (also iPad Split View at half width and the inner display of iPhone Duo): the map
// fills the screen and the content floats over it in a panel on the left, like Apple Maps on iPad.
// The views in the panel are the iPhone views; they tell the big map what to show (`wideMapScene`).

enum WideLayout {
    /// Wide enough for a panel next to a useful map. Below this (iPhone, Slide Over, the folded
    /// iPhone Duo, narrow Split View) the iPhone layout is used.
    static let minWidth: CGFloat = 680

    /// The unfolded iPhone Duo reports a compact width like every iPhone, so a window that is big
    /// in both directions counts as well. An iPhone in landscape is never tall enough for that.
    static let minSquare: CGFloat = 580

    static func isWide(size: CGSize, sizeClass: UserInterfaceSizeClass?) -> Bool {
        if sizeClass == .regular, size.width >= minWidth { return true }
        return size.width >= minSquare && size.height >= minSquare
    }

    /// The panel: a phone-like column, a bit wider on the big screens. About 40 % in portrait,
    /// about a third in landscape, so the map always keeps the larger part.
    static func panelWidth(for width: CGFloat) -> CGFloat {
        min(max((width * 0.4).rounded(), 340), 420)
    }

    static let margin: CGFloat = 12
}

/// What the big map shows next to the panel.
enum WideMapScene {
    /// The live transit map: stations, lines and vehicles around you.
    case explore
    /// Several routes at once; the selected one strong, the others pale.
    case routes([Itinerary], selected: String?)
    /// One route with where it starts, changes and ends.
    case route(Itinerary)

    var key: String {
        switch self {
        case .explore: return "explore"
        case .routes(let its, let selected): return "routes|\(selected ?? "")|" + its.map(\.routeKey).joined(separator: ",")
        case .route(let it): return "route|\(it.routeKey)"
        }
    }
}

/// The scenes asked for by the screens in the panel; the topmost one (the screen on top of the
/// panel's navigation stack) is shown. A screen leaves when it disappears (popped or covered).
@MainActor
@Observable
final class WideMapState {
    private struct Entry { let owner: String; var scene: WideMapScene }
    private var entries: [Entry] = []

    var scene: WideMapScene { entries.last?.scene ?? .explore }

    func show(_ scene: WideMapScene, for owner: String) {
        if let i = entries.firstIndex(where: { $0.owner == owner }) {
            entries[i].scene = scene
        } else {
            entries.append(Entry(owner: owner, scene: scene))
        }
    }

    func remove(_ owner: String) { entries.removeAll { $0.owner == owner } }
}

private struct WideMapSceneModifier: ViewModifier {
    let scene: WideMapScene
    @Environment(WideMapState.self) private var state: WideMapState?
    @State private var owner = UUID().uuidString

    func body(content: Content) -> some View {
        content
            .onAppear { state?.show(scene, for: owner) }
            .onDisappear { state?.remove(owner) }
            .onChange(of: scene.key) { _, _ in state?.show(scene, for: owner) }
    }
}

extension View {
    /// What the big map should show while this screen is on top of the panel (iPad layout only;
    /// on iPhone it does nothing).
    func wideMapScene(_ scene: WideMapScene) -> some View {
        modifier(WideMapSceneModifier(scene: scene))
    }
}

/// A tab in the iPad layout: the map over the whole screen, the tab's screens in a floating panel.
struct WideMapScreen<Panel: View>: View {
    @ViewBuilder var panel: Panel
    @State private var state = WideMapState()

    var body: some View {
        GeometryReader { geo in
            let width = WideLayout.panelWidth(for: geo.size.width)
            ZStack(alignment: .topLeading) {
                WideMapCanvas(leadingInset: width + WideLayout.margin * 2)
                    .ignoresSafeArea()
                NavigationStack { panel }
                    .liveTripBar()
                    // The panel is a phone-sized column: its screens lay out as on iPhone.
                    .environment(\.horizontalSizeClass, .compact)
                    .frame(width: width)
                    .frame(maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .shadow(color: .black.opacity(0.16), radius: 18, y: 4)
                    .padding(WideLayout.margin)
            }
        }
        .environment(state)
    }
}

/// The big map behind the panel.
struct WideMapCanvas: View {
    let leadingInset: CGFloat
    @Environment(WideMapState.self) private var state

    var body: some View {
        let scene = state.scene
        ZStack {
            switch scene {
            case .explore:
                StationMapView(embedded: true, leadingInset: leadingInset)
                    .transition(.opacity)
            case .routes(let its, let selected):
                WideRoutesMap(itineraries: its, selectedId: selected ?? its.first?.routeKey, leadingInset: leadingInset)
                    .id(scene.key)
                    .transition(.opacity)
            case .route(let it):
                WideRoutesMap(itineraries: [it], selectedId: it.routeKey, leadingInset: leadingInset)
                    .id(scene.key)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: scene.key)
    }
}

/// Routes on the big map, framed in the part the panel leaves free: the selected one in its line
/// colours with line badges, start, changes and destination; the others pale underneath.
struct WideRoutesMap: View {
    let itineraries: [Itinerary]
    let selectedId: String?
    let leadingInset: CGFloat

    private var selected: Itinerary? { itineraries.first { $0.routeKey == selectedId } ?? itineraries.first }

    /// The selected route drawn last, on top.
    private var ordered: [Itinerary] {
        itineraries.filter { $0.routeKey != selected?.routeKey } + itineraries.filter { $0.routeKey == selected?.routeKey }
    }

    /// All routes in view; around the selected one when they spread far apart.
    private var frame: MKMapRect? {
        let rects = itineraries.compactMap { RouteMap.frame($0, margin: 0.12) }
        guard var all = rects.first else { return nil }
        for r in rects.dropFirst() { all = all.union(r) }
        return all
    }

    var body: some View {
        Map(initialPosition: frame.map { MapCameraPosition.rect($0) } ?? .automatic) {
            UserAnnotation()
            ForEach(ordered, id: \.routeKey) { it in
                let isSelected = it.routeKey == selected?.routeKey
                ForEach(Array(it.legs.enumerated()), id: \.offset) { _, leg in
                    MapPolyline(coordinates: leg.overviewPath.map(\.clCoordinate))
                        .stroke(isSelected ? (leg.isTransit ? leg.lineStroke : Color.routeAhead) : Color.gray.opacity(0.45),
                                style: .leg(leg.isTransit, width: isSelected ? 6 : 4))
                }
            }
            if let it = selected {
                let rides = it.legs.filter(\.isTransit)
                ForEach(Array(rides.dropFirst().enumerated()), id: \.offset) { _, leg in
                    Annotation("", coordinate: leg.from.coordinate.clCoordinate, anchor: .center) { RouteMark(kind: .change) }
                }
                // Each ride's line where you board it: the map reads like the route's line chain.
                ForEach(Array(rides.enumerated()), id: \.offset) { _, leg in
                    Annotation(leg.from.name, coordinate: leg.from.coordinate.clCoordinate, anchor: .bottom) {
                        LineBadge(leg, compact: true)
                            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                            .padding(.bottom, 8)
                    }
                }
                if let first = it.legs.first {
                    Annotation("", coordinate: first.from.coordinate.clCoordinate, anchor: .center) { RouteMark(kind: .start) }
                }
                if let last = it.legs.last {
                    Annotation(ItineraryDetailView.placeName(last.to), coordinate: last.to.coordinate.clCoordinate, anchor: .center) {
                        RouteMark(kind: .destination)
                    }
                }
            }
        }
        .publitMapStyle()
        .mapControls { MapUserLocationButton(); MapCompass(); MapScaleView() }
        // Frame the routes beside the panel, not under it.
        .safeAreaPadding(.leading, leadingInset)
        .safeAreaPadding(.vertical, 16)
    }
}

/// Tickets and Saved in the iPad layout: the list on the left, what you open on the right.
struct WideSplitScreen<Sidebar: View>: View {
    @ViewBuilder var list: Sidebar
    let placeholder: LocalizedStringKey
    let symbol: String

    var body: some View {
        NavigationSplitView {
            list
                .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 440)
        } detail: {
            ContentUnavailableView(placeholder, systemImage: symbol)
        }
        .navigationSplitViewStyle(.balanced)
        .liveTripBar()
    }
}
