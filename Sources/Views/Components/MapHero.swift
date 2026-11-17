import SwiftUI

/// A map as the picture at the top of a screen, like the route of a workout in a fitness app:
/// edge to edge, up under the navigation bar, fading into the background behind the first card,
/// and the list scrolls up over it (feedback 2026-11-17: "the part in red is so well done" — the
/// Nearby look of build 87; build 88 put the map into an inset, rounded list row, which looked like
/// a frame around it). The map stays live: move it, zoom it, tap what is on it (feedback
/// 2026-11-16: "everywhere, also in the small state"). The expand key opens the full map.
///
/// How: the list's first section is `MapHeroSpace`, an empty row that only says where it is. The
/// map lies over the list (`MapHeroLayer`), moved along with that row, so it gets its touches
/// (a map behind a list never does). Where it fades out behind the first card it is cut away
/// (drawn and touched), so the card stays on top and tappable; beside the card the fade shows.
/// The same on every screen with a map at the top: Nearby, a route, Go now, a trip and a line.
enum MapHero {
    /// Map below the navigation bar down to the first card.
    static let height: CGFloat = 290
    /// How far the map fades on behind the first card.
    static let fade: CGFloat = 70
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

/// The map over the list, placed after `MapHeroSpace`'s row.
private struct MapHeroLayer<M: View>: View {
    let row: CGRect
    /// The row's place when the screen opened: further up it has scrolled, further down it is pulled.
    let restY: CGFloat
    let map: (EdgeInsets) -> M
    let onExpand: () -> Void

    var body: some View {
        GeometryReader { g in
            // From the space's coordinates (the list) to this layer's (from the top of the screen).
            let origin = g.frame(in: .named(MapHero.space)).origin
            let rowTop = row.minY - origin.y
            let restTop = restY - origin.y
            let moved = row.minY - restY
            // Scrolled up the map goes along; pulled down (refresh) it stays and stretches.
            let top = min(0, moved)
            let cardTop = rowTop + row.height + MapHero.gap
            let bottom = cardTop + MapHero.fade
            let height = max(0, bottom - top)
            let card = CGRect(x: row.minX - origin.x, y: cardTop - top - 1,
                              width: row.width, height: height)
            let cut = HeroCut(card: card)

            // The insets keep the content in the part that shows: not under the bar, not behind the card.
            map(EdgeInsets(top: max(0, restTop), leading: 0, bottom: MapHero.fade + MapHero.gap, trailing: 0))
                .frame(width: g.size.width, height: height)
                .mask {
                    LinearGradient(stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: max(0, (cardTop - 30 - top) / max(height, 1))),
                        .init(color: .clear, location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                    .mask { cut.fill(style: FillStyle(eoFill: true)) }
                }
                .contentShape(cut, eoFill: true)
                .overlay(alignment: .topLeading) {
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
                    .offset(x: card.maxX - 44, y: card.minY - 44 - 10)
                }
                .offset(y: top)
        }
        .ignoresSafeArea(edges: .top)
    }
}

/// The map's whole frame minus the first card (filled even-odd): drawn and touched only around it.
private struct HeroCut: Shape {
    let card: CGRect

    func path(in rect: CGRect) -> Path {
        var p = Path(rect)
        p.addRoundedRect(in: card, cornerSize: CGSize(width: 12, height: 12), style: .continuous)
        return p
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
