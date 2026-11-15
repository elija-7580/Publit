import SwiftUI

enum TripPanelMetrics {
    /// How much of the panel shows when it is down: the stage strip and one stage card.
    static let peek: CGFloat = 206
}

/// The panel over the trip map: down (stages only), half way or up (all details).
/// It keeps one size and only moves, so dragging it does not lay the list out again.
/// Down and half way the whole panel drags (the list does not scroll); up, the list scrolls and
/// the handle and stage cards pull it down again.
struct TripPanel<Header: View, Content: View>: View {
    enum Detent: CaseIterable { case peek, half, full }

    /// One drag: the direction is decided once at the start, so the panel does not jump
    /// between following the finger and standing still when the finger drifts sideways.
    struct Drag: Equatable {
        var vertical: Bool?
        var dy: CGFloat = 0
    }

    let header: Header
    let content: Content
    /// How much shows when it is down.
    let peek: CGFloat
    /// Room left above it when it is all the way up (a strip of the map stays visible).
    let topGap: CGFloat
    /// Where its top edge is, from the top of its area: for screens that frame their map above it.
    var onTop: ((CGFloat) -> Void)?
    /// Down and half way, pulling the panel wins over the taps of its rows (Nearby: the rows are
    /// buttons and move along under the finger). Off for the live trip, whose stage cards swipe sideways.
    let dragWins: Bool
    @State private var detent: Detent
    @GestureState(resetTransaction: Transaction(animation: .spring(response: 0.34, dampingFraction: 0.88)))
    private var drag = Drag()

    init(peek: CGFloat = TripPanelMetrics.peek, topGap: CGFloat = 0, start: Detent = .peek,
         onTop: ((CGFloat) -> Void)? = nil, dragWins: Bool = false,
         @ViewBuilder header: () -> Header, @ViewBuilder content: () -> Content) {
        self.peek = peek
        self.topGap = topGap
        self.onTop = onTop
        self.dragWins = dragWins
        _detent = State(initialValue: start)
        self.header = header()
        self.content = content()
    }

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let y = offset(detent, height: height)
            let lowest = offset(.peek, height: height)
            // Past the top or the bottom it gives a little, then stops.
            let moved = Self.rubberBand(y + drag.dy, min: topGap, max: lowest)
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.45))
                        .frame(width: 36, height: 5)
                        .frame(maxWidth: .infinity, minHeight: 18)
                        .contentShape(Rectangle())
                        .onTapGesture { move(to: detent == .full ? .half : .full) }
                        .accessibilityHidden(true)
                    header
                }
                .padding(.bottom, 10)
                .contentShape(Rectangle())
                content
                    .frame(maxHeight: .infinity, alignment: .top)
                    .scrollDisabled(detent != .full)
            }
            .frame(width: geo.size.width, height: max(height - topGap, 0), alignment: .top)
            .background {
                UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22, style: .continuous)
                    .fill(Color.ground)
                    .shadow(color: .black.opacity(0.12), radius: 12, y: -2)
                    // Down to the bottom edge of the screen, under the home indicator.
                    .padding(.bottom, -120)
            }
            .offset(y: moved)
            .onChange(of: y, initial: true) { _, top in onTop?(top) }
            // Measured on the screen, not on the panel: the panel moves under the finger, and
            // a translation in its own space would feed back into itself (the jitter).
            .simultaneousGesture(dragGesture(height: height), including: detent == .full || dragWins ? .subviews : .all)
            .highPriorityGesture(dragGesture(height: height), including: detent != .full && dragWins ? .all : .subviews)
            .overlay(alignment: .top) {
                // Up, the list scrolls: the top strip (handle and stage cards) still pulls the panel down.
                if detent == .full {
                    Color.clear
                        .frame(height: 40)
                        .contentShape(Rectangle())
                        .offset(y: moved)
                        .gesture(dragGesture(height: height))
                }
            }
        }
    }

    private func offset(_ detent: Detent, height: CGFloat) -> CGFloat {
        switch detent {
        case .full: return topGap
        case .half: return height * 0.45
        case .peek: return max(height - peek, 0)
        }
    }

    /// Beyond the ends the panel follows the finger at a third of the distance, at most 40 pt.
    private static func rubberBand(_ value: CGFloat, min lo: CGFloat, max hi: CGFloat) -> CGFloat {
        if value < lo { return lo - Swift.min((lo - value) / 3, 40) }
        if value > hi { return hi + Swift.min((value - hi) / 3, 40) }
        return value
    }

    private func move(to new: Detent) {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) { detent = new }
    }

    private func dragGesture(height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .updating($drag) { value, state, _ in
                if state.vertical == nil {
                    state.vertical = abs(value.translation.height) > abs(value.translation.width)
                }
                if state.vertical == true { state.dy = value.translation.height }
            }
            .onEnded { value in
                guard abs(value.translation.height) > abs(value.translation.width) else { return }
                let start = offset(detent, height: height)
                // Where a flick would carry it, but at most one step beyond the nearest.
                let target = start + value.translation.height
                    + (value.predictedEndTranslation.height - value.translation.height) * 0.5
                let nearest = Detent.allCases.min {
                    abs(offset($0, height: height) - target) < abs(offset($1, height: height) - target)
                } ?? detent
                move(to: nearest)
            }
    }
}
