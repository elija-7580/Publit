import SwiftUI

/// A map as the picture at the top of a screen, like the route of a workout in a fitness app:
/// it reaches up under the navigation bar, fades into the background at its lower edge, and the
/// list scrolls up over it. A tap on the map or on the expand key opens the full map.
///
/// The list's first section is `MapHeroSpace` (it keeps the map free and catches the tap);
/// the list itself gets `.inkList(hero:map:)` instead of `.inkList()`.
enum MapHero {
    /// Visible map below the navigation bar.
    static let height: CGFloat = 290
    /// Lower part of the map that fades into the background (under the first card).
    static let fade: CGFloat = 70
    static let space = "mapHero"
}

/// Where the hero row is in the list (its top edge); nil while it is scrolled out of the list.
struct MapHeroOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        if let next = nextValue() { value = next }
    }
}

/// The list's first section: the free space over the map, with the expand key in its corner.
struct MapHeroSpace: View {
    let onExpand: () -> Void

    var body: some View {
        Section {
            Color.clear
                .frame(height: MapHero.height)
                .contentShape(Rectangle())
                .onTapGesture(perform: onExpand)
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
                    .padding(.bottom, 18)
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

/// The map behind the list: moves up with the first row, so it scrolls away with the content.
private struct MapHeroBackground<M: View>: ViewModifier {
    /// Builds the map for the part of the screen it covers; the insets are the hidden top (under
    /// the bar) and the faded bottom, so the map frames its content in the part that shows.
    let map: (EdgeInsets) -> M
    @State private var rest: CGFloat?
    @State private var shift: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 0, for: .scrollContent)
            .coordinateSpace(name: MapHero.space)
            .onPreferenceChange(MapHeroOffsetKey.self) { y in
                guard let y else {
                    // The row left the list: the map is gone with it.
                    if rest != nil { shift = -(MapHero.height + MapHero.fade + 200) }
                    return
                }
                if rest == nil { rest = y }
                // Pulled down (refresh) the map stays put; scrolled up it goes along.
                shift = min(0, y - (rest ?? y))
            }
            .background {
                GeometryReader { g in
                    let top = g.safeAreaInsets.top
                    ZStack(alignment: .top) {
                        Color.ground
                        map(EdgeInsets(top: top, leading: 0, bottom: MapHero.fade, trailing: 0))
                            .frame(height: top + MapHero.height + MapHero.fade)
                            .mask {
                                LinearGradient(stops: [
                                    .init(color: .black, location: 0),
                                    .init(color: .black, location: (top + MapHero.height - 30) / (top + MapHero.height + MapHero.fade)),
                                    .init(color: .clear, location: 1),
                                ], startPoint: .top, endPoint: .bottom)
                            }
                            .offset(y: shift)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
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
