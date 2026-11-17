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
}

/// Where the hero row is in the list; nil while it is scrolled out of the list.
struct MapHeroFrameKey: PreferenceKey {
    static var defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        if let next = nextValue() { value = next }
    }
}

/// The list's first section: the free space the map shows through.
struct MapHeroSpace: View {
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
    let row: CGRect
    /// The row's place when the screen opened: further up it has scrolled, further down it is pulled.
    let restY: CGFloat
    let map: (EdgeInsets) -> M
    let onExpand: () -> Void

    var body: some View {
        GeometryReader { g in
            // Only how far the row has moved is reliable (a list row's absolute place in the space is
            // not), so the map is placed from the bar's lower edge, where the row sits at rest (as in
            // build 87).
            let bar = g.safeAreaInsets.top
            let moved = row.minY - restY
            // Scrolled up the map goes along; pulled down (refresh) it stays and stretches.
            let top = min(0, moved)
            let cardTop = bar + MapHero.height + max(0, moved)
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
private struct MapHeroOverList<M: View>: ViewModifier {
    let map: (EdgeInsets) -> M
    let onExpand: () -> Void
    @State private var row: CGRect?
    @State private var restY: CGFloat?
    /// The row has scrolled out of the list.
    @State private var gone = false

    private var scrolledAway: Bool {
        guard !gone, let row, let restY else { return gone }
        return row.minY - restY < -MapHero.height * 0.6
    }

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 0, for: .scrollContent)
            .background(Color.ground.ignoresSafeArea())
            .overlay {
                // Kept while scrolled away (only hidden), so the map keeps where you moved it.
                if let row, let restY {
                    MapHeroLayer(row: row, restY: restY, map: map, onExpand: onExpand)
                        .opacity(gone ? 0 : 1)
                        .allowsHitTesting(!gone)
                        .accessibilityHidden(gone)
                }
            }
            .coordinateSpace(name: MapHero.space)
            .onPreferenceChange(MapHeroFrameKey.self) { frame in
                guard let frame else {
                    // The row left the list: the map is gone with it.
                    if row != nil { gone = true }
                    return
                }
                gone = false
                if restY == nil { restY = frame.minY }
                row = frame
            }
            // Over the map the bar is see-through; once the map has scrolled away it is solid again.
            .toolbarBackground(scrolledAway ? .automatic : .hidden, for: .navigationBar)
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
