import SwiftUI

/// Localized duration with large tabular figures and quiet units, not a hard-coded "min" suffix.
struct DurationFigure: View {
    let seconds: Int
    @ScaledMetric(relativeTo: .title2) private var size: CGFloat

    init(seconds: Int, size: CGFloat = 28) {
        self.seconds = seconds
        _size = ScaledMetric(wrappedValue: size, relativeTo: .title2)
    }

    var body: some View {
        Text(styled)
            .lineLimit(1).minimumScaleFactor(0.7)
            .accessibilityLabel(Text(verbatim: Fmt.duration(seconds: seconds)))
    }

    private var styled: AttributedString {
        var result = AttributedString()
        var group = ""
        var numeric = false
        func append() {
            guard !group.isEmpty else { return }
            var part = AttributedString(group)
            part.font = .system(size: numeric ? size : size * 0.5, weight: numeric ? .bold : .medium,
                                design: numeric ? .monospaced : .default)
            part.foregroundColor = numeric ? Color.ink : Color.secondary
            result += part
        }
        for character in Fmt.duration(seconds: seconds) {
            if character.isNumber != numeric { append(); group = ""; numeric = character.isNumber }
            group.append(character)
        }
        append()
        return result
    }
}
