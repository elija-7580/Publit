import SwiftUI

/// A map as the picture at the top of a screen, like the route of a workout in a fitness app:
/// edge to edge, up under the navigation bar, fading into the background right above the first card,
/// and the list scrolls up over it (feedback 2026-11-17: "the part in red is so well done" — the
/// Nearby look of build 87; build 88 put the map into an inset, rounded list row, which looked like
/// a frame around it). The map stays live: move it, zoom it, tap what is on it (feedback
/// 2026-11-16: "everywhere, also in the small state"). The expand key opens the full map.
///
/// How: the list's first section is `MapHeroSpace`, an empty row that only says where it is. The
/// map lies over the list (`MapHeroLayer`), moved along with that row, so it gets its touches
/// (a map behind a list never does). It ends at the first card, so the card stays tappable.
/// The same on every screen with a map at the top: Nearby, a route, Go now, a trip and a line.
enum MapHero {
    /// Map below the navigation bar down to the first card.
    static let height: CGFloat = 300
    /// Lower part of the map that fades into the background, above the first card.
    static let fade: CGFloat = 64
    /// Gap between the hero row and the first card (`listSectionSpacing`).
    static let gap: CGFloat = 12
    static let space = "mapHero"
    /// A map whose screen is covered (another tab, a screen pushed over it) is let go after this
    /// long, and at once in the background or when iOS warns about memory. Each live map holds
    /// tiles and a render surface; several of them, kept under other screens, cost memory and froze
    /// the app for seconds when iOS brought them all back at once (diagnostics of build 96:
    /// 5.8 s in the map renderer on the way back from Tickets to Nearby). Coming back builds a
    /// fresh map; a quick look at another tab keeps it.
    static let releaseDelay: Duration = .seconds(20)
}

/// Where the hero row is in the list; nil while it is scrolled out of the list.
struct MapHeroFrameKey: PreferenceKey {
    static var defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        if let next = nextValue() { value = next }
    }
}

/// Where the hero row is on screen, written by the row itself and read by the map over the list.
/// An observed object handed down through the environment, not a preference: preferences from a
/// List row did not reach the list while scrolling (UI test F31: the list moved 121 pt, the map 0).
@Observable
final class MapHeroTrack {
    /// The row's top in global (screen) coordinates; nil while it is out of the list.
    var globalY: CGFloat?
    var restGlobalY: CGFloat?
}

/// The list's first section: the free space the map shows through.
struct MapHeroSpace: View {
    @Environment(MapHeroTrack.self) private var track: MapHeroTrack?

    var body: some View {
        Section {
            Color.clear
                .frame(height: MapHero.height)
                .frame(maxWidth: .infinity)
                .background {
                    GeometryReader { g in
                        Color.clear.preference(key: MapHeroFrameKey.self, value: g.frame(in: .named(MapHero.space)))
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { y in
                    guard let track else { return }
                    if track.restGlobalY == nil { track.restGlobalY = y }
                    track.globalY = y
                }
                .onDisappear { track?.globalY = nil }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .accessibilityHidden(true)
        }
    }
}

/// The map over the list, placed after `MapHeroSpace`'s row. It ends at the first card's top edge:
/// MapKit's map is a UIKit view, and a shape cut out of it does not stop it taking touches, so it
/// must not lie over the card at all (a cut-out version swallowed taps on "Where to now?").
private struct MapHeroLayer<M: View>: View {
    /// How far the list has moved from its rest: negative scrolled up, positive pulled down.
    let moved: CGFloat
    /// The hero row's top on screen (global), when the row reports it: then the map is placed from
    /// it directly, not from a rest remembered once (on Route that rest was caught mid-push and
    /// the map lay over "Leave now", feedback 2026-11-17).
    var rowTop: CGFloat? = nil
    let map: (EdgeInsets) -> M
    let onExpand: () -> Void

    var body: some View {
        GeometryReader { g in
            // Placed from the bar's lower edge, where the hero row sits at rest (as in build 87), and
            // moved exactly as far as the list.
            let bar = g.safeAreaInsets.top
            // The row's distance below the bar's lower edge (the top of this reader).
            let moved = rowTop.map { $0 - g.frame(in: .global).minY } ?? self.moved
            // Scrolled up the map goes along; pulled down (refresh) it stays and stretches.
            let top = min(0, moved)
            // The first card moves with the list both ways (the bug of builds 91–93: it was held at
            // its rest, so scrolling up made the map taller by as much as it moved up, and its lower
            // edge with the cards under it stood still).
            let cardTop = bar + MapHero.height + moved
            let height = max(1, cardTop - top)

            // Read in the safe area, drawn from the top of the screen (like build 87's map).
            ZStack(alignment: .top) {
                // The insets keep the content in the part that shows: not under the bar, not in the fade.
                map(EdgeInsets(top: bar, leading: 0, bottom: MapHero.fade, trailing: 0))
                    .frame(width: g.size.width, height: height)
                    .mask {
                        LinearGradient(stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: max(0, (height - MapHero.fade) / height)),
                            .init(color: .clear, location: 1),
                        ], startPoint: .top, endPoint: .bottom)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Button(action: onExpand) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Color.ink)
                                .frame(width: 44, height: 44)
                                .matteSurface(in: Circle())
                                .mapShadow()
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Map"))
                        .accessibilityIdentifier("mapHeroExpand")
                        .padding(.trailing, 20)
                        .padding(.bottom, 10)
                    }
                    .offset(y: top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea()
        }
    }
}

/// The ground behind the list and the map over its first row; the bar is see-through while the map shows.
///
/// The map follows the list's own scroll offset (iOS 18+), read every frame, so it goes up exactly
/// with the content (feedback 2026-11-17: with the hero row's reported place it lagged or stood
/// still, and the cards slid under the map). On iOS 17 the hero row's movement is the fallback.
private struct MapHeroOverList<M: View>: ViewModifier {
    let map: (EdgeInsets) -> M
    let onExpand: () -> Void
    /// iOS 18+: the list's offset from its rest (negative = scrolled up).
    @State private var offset: CGFloat?
    /// iOS 17: the hero row's place now and when the screen opened; nil while it is out of the list.
    @State private var row: CGRect?
    @State private var restY: CGFloat?
    @State private var rowGone = false
    @State private var track = MapHeroTrack()
    /// This screen is the one on show (not covered by a pushed screen, not in another tab).
    @State private var onScreen = true
    /// False once a covered screen's map was let go (see `MapHero.releaseDelay`).
    @State private var keepsMap = true
    @Environment(\.scenePhase) private var scenePhase

    private var moved: CGFloat? {
        if let y = track.globalY, let rest = track.restGlobalY { return y - rest }
        if let offset { return offset }
        guard let row, let restY else { return nil }
        return row.minY - restY
    }

    /// The map is fully out of sight: hidden, and the bar is solid again.
    private var gone: Bool {
        if track.restGlobalY != nil, track.globalY == nil { return true }
        if track.restGlobalY == nil, offset == nil, rowGone { return true }
        guard let moved else { return false }
        return moved < -(MapHero.height + 120)
    }

    private var scrolledAway: Bool {
        gone || (moved ?? 0) < -MapHero.height * 0.6
    }

    func body(content: Content) -> some View {
        content
            .environment(track)
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 0, for: .scrollContent)
            .background(Color.ground.ignoresSafeArea())
            .modifier(ListOffset(offset: $offset))
            .overlay {
                // Kept while scrolled away (only hidden), so the map keeps where you moved it.
                if let moved, keepsMap {
                    MapHeroLayer(moved: max(moved, -(MapHero.height + 400)),
                                 rowTop: track.globalY.map { max($0, -(MapHero.height + 1000)) },
                                 map: map, onExpand: onExpand)
                        .opacity(gone ? 0 : 1)
                        .allowsHitTesting(!gone)
                        .accessibilityHidden(gone)
                }
            }
            .coordinateSpace(name: MapHero.space)
            .onAppear { onScreen = true; keepsMap = true }
            .onDisappear { onScreen = false }
            .task(id: onScreen) {
                guard !onScreen else { return }
                try? await Task.sleep(for: MapHero.releaseDelay)
                if !Task.isCancelled, !onScreen { keepsMap = false }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background, !onScreen { keepsMap = false }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                if !onScreen { keepsMap = false }
            }
            .onPreferenceChange(MapHeroFrameKey.self) { frame in
                guard let frame else {
                    // The row left the list: the map is gone with it.
                    if row != nil { rowGone = true }
                    return
                }
                rowGone = false
                if restY == nil { restY = frame.minY }
                row = frame
            }
            // Over the map the bar is see-through; once the map has scrolled away it is solid again.
            .toolbarBackground(scrolledAway ? .automatic : .hidden, for: .navigationBar)
    }
}

/// The list's scroll offset from its rest (0 at rest, negative scrolled up, positive pulled down), iOS 18+.
private struct ListOffset: ViewModifier {
    @Binding var offset: CGFloat?

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { geo in
                -(geo.contentOffset.y + geo.contentInsets.top)
            } action: { _, now in
                offset = now
            }
        } else {
            content
        }
    }
}

extension View {
    /// `inkList()` with a map at its top (see `MapHero`); its first section must be `MapHeroSpace()`.
    /// With `hero` false it is the plain `inkList()`.
    @ViewBuilder
    func inkList<M: View>(hero: Bool, onExpand: @escaping () -> Void, @ViewBuilder map: @escaping (EdgeInsets) -> M) -> some View {
        if hero {
            modifier(MapHeroOverList(map: map, onExpand: onExpand))
                .listSectionSpacing(MapHero.gap)
                .liveBarPadding()
        } else {
            inkList()
        }
    }
}
