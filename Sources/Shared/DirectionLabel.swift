import SwiftUI

/// Same wording in departure boards, itinerary legs and widgets. Missing headsigns are explicit.
struct DirectionLabel: View {
    let direction: String?
    var font: Font = .subheadline

    var body: some View {
        Group {
            if let direction = TransitLabels.clean(direction) {
                (Text(L10n.t("Towards") + " ").foregroundColor(.secondary)
                 + Text(verbatim: direction).foregroundColor(.primary).bold())
            } else {
                Text("Direction unavailable").foregroundColor(.secondary)
            }
        }
        .font(font)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("vehicleDirection")
    }
}
