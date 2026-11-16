import SwiftUI

/// A map as the picture at the top of a screen, like the route of a workout in a fitness app:
/// it reaches up under the navigation bar, fades into the background at its lower edge, and the
/// list scrolls up over it. The map is live where it is: move it, zoom it, tap what is on it
/// (feedback 2026-11-16: "everywhere, also in the small state"). The expand key opens the full map.
///
/// The list's first section is `MapHeroSpace`, which draws the map in its row (a map behind the
/// list never gets a touch: the list takes them all). The list gets `.inkList(hero:map:)`, which
/// hands the map to that row.
enum MapHero {
    /// Map below the navigation bar, its faded lower part included.
    static let height: CGFloat = 320
    /// Lower part of the map that fades into the background.
    static let fade: CGFloat = 56
    static let space = "mapHero"
}

/// Where the hero row is in the list (its top edge); nil while it is scrolled out of the list.
struct MapHeroOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        if let next = nextValue() { value = next }
    }
}

/// The map of `inkList(hero:map:)`, handed to its `MapHeroSpace` row.
struct MapHeroContent {
    /// Height of the bar above the list: the map reaches up under it.
    var top: CGFloat = 0
    var map: ((EdgeInsets) -> AnyView)? = nil
}

private struct MapHeroContentKey: EnvironmentKey {
    static let defaultValue = MapHeroContent()
}

extension EnvironmentValues {
    var mapHero: MapHeroContent {
        get { self[MapHeroContentKey.self] }
        set { self[MapHeroContentKey.self] = newValue }
    }
}

/// The list's first section: the map, with the expand key in its corner.
struct MapHeroSpace: View {
    let onExpand: () -> Void
    @Environment(\.mapHero) private var hero

    var body: some View {
        Section {
            ZStack(alignment: .top) {
                if let map = hero.map {
                    let full = hero.top + MapHero.height
                    // The insets keep the content in the part that shows: not under the bar, not in the fade.
                    map(EdgeInsets(top: hero.top, leading: 0, bottom: MapHero.fade, trailing: 0))
                        .frame(height: full)
                        .mask {
                            LinearGradient(stops: [
                                .init(color: .black, location: 0),
                                .init(color: .black, location: (full - MapHero.fade) / full),
                                .init(color: .clear, location: 1),
                            ], startPoint: .top, endPoint: .bottom)
                        }
                        // Up under the bar; where the row is clipped it simply starts below it.
                        .padding(.top, -hero.top)
                }
            }
            .frame(height: MapHero.height, alignment: .bottom)
            .frame(maxWidth: .infinity)
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
                .padding(.trailing, 4)
                .padding(.bottom, MapHero.fade - 22)
                .accessibilityLabel(Text("Map"))
                .accessibilityIdentifier("mapHeroExpand")
            }
            .background {
                GeometryReader { g in
                    Color.clear.preference(key: MapHeroOffsetKey.self, value: g.frame(in: .named(MapHero.space)).minY)
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }
}

/// The ground behind the list and the map for its first row; the bar is see-through while the map shows.
private struct MapHeroBackground<M: View>: ViewModifier {
    /// Builds the map for the part of the screen it covers; the insets are the hidden top (under
    /// the bar) and the faded bottom, so the map frames its content in the part that shows.
    let map: (EdgeInsets) -> M
    @State private var rest: CGFloat?
    @State private var shift: CGFloat = 0
    @State private var top: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .environment(\.mapHero, MapHeroContent(top: top, map: { AnyView(map($0)) }))
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 0, for: .scrollContent)
            .coordinateSpace(name: MapHero.space)
            .onPreferenceChange(MapHeroOffsetKey.self) { y in
                guard let y else {
                    if rest != nil { shift = -(MapHero.height + 200) }
                    return
                }
                if rest == nil { rest = y }
                shift = min(0, y - (rest ?? y))
            }
            .background {
                GeometryReader { g in
                    Color.ground
                        .onAppear { top = g.safeAreaInsets.top }
                        .onChange(of: g.safeAreaInsets.top) { _, t in top = t }
                        .ignoresSafeArea()
                }
            }
            // Over the map the bar is see-through; once the map has scrolled away it is solid again.
            .toolbarBackground(shift < -MapHero.height * 0.6 ? .automatic : .hidden, for: .navigationBar)
    }
}

extension View {
    /// `inkList()` with a map behind its top (see `MapHero`). With `hero` false it is the plain `inkList()`.
    @ViewBuilder
    func inkList<M: View>(hero: Bool, @ViewBuilder map: @escaping (EdgeInsets) -> M) -> some View {
        if hero {
            modifier(MapHeroBackground(map: map))
                .listSectionSpacing(12)
                .liveBarPadding()
        } else {
            inkList()
        }
    }
}
