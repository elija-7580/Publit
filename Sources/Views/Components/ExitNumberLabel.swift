import SwiftUI

/// "Use exit 3": the number of the station exit a walk comes up through, from OpenStreetMap.
/// Shows nothing until (and unless) a number is found, so the row does not jump for stations
/// without numbered exits.
struct ExitNumberLabel: View {
    let coordinate: LatLon
    var font: Font = .caption.weight(.semibold)
    @State private var ref: String?

    var body: some View {
        ZStack(alignment: .leading) {
            if let ref {
                Label(L10n.f("Use exit %@", ref), systemImage: "door.right.hand.open")
                    .font(font)
                    .accessibilityIdentifier("exitNumber")
            }
        }
        .task(id: coordinate) {
            ref = await StationExits.shared.ref(at: coordinate)
        }
    }
}
