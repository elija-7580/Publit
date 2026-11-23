// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich

import SwiftUI

/// Where to ride and which way out, under a ride that ends in a station: "Board at the front ·
/// Closest to exit B2" and "Take exit B2". In the route the exit can be changed: Publit then
/// remembers it for this station and destination.
struct ExitAdviceRow: View {
    let advice: ExitAdvice
    /// The exits of the station to choose from (signed ones); empty: no choice offered.
    var choices: [StationEntrance] = []
    /// Picks an exit (nil: back to the automatic one).
    var onPick: ((StationEntrance?) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let board = advice.boardText, let part = advice.part {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    TrainPartGlyph(part: part)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: board).font(.subheadline.weight(.semibold))
                        if let reason = advice.reason {
                            Text(verbatim: reason).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("boardingPart")
            }
            if let door = advice.door {
                HStack(spacing: 8) {
                    Image(systemName: "door.left.hand.open").font(.subheadline).frame(width: TrainPartGlyph.width)
                        .accessibilityHidden(true)
                    Text(L10n.f("Take exit %@", door)).font(.subheadline.weight(.semibold))
                    if advice.doorSaved {
                        Text("Your exit").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.inkFill, in: Capsule())
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("stationExit")
            }
            if let onPick, !choices.isEmpty {
                Menu {
                    Section("Publit remembers this exit for this station and destination.") {
                        Button("Choose automatically") { onPick(nil) }
                        ForEach(choices, id: \.id) { e in
                            Button {
                                onPick(e)
                            } label: {
                                if e.label == advice.door, advice.doorSaved {
                                    Label(L10n.f("Exit %@", e.label ?? ""), systemImage: "checkmark")
                                } else {
                                    Text(L10n.f("Exit %@", e.label ?? ""))
                                }
                            }
                        }
                    }
                } label: {
                    Label(advice.door == nil ? LocalizedStringKey("Choose exit") : LocalizedStringKey("Change exit"),
                          systemImage: "arrow.triangle.branch")
                        .font(.footnote.weight(.semibold))
                }
                .accessibilityIdentifier("chooseStationExit")
            }
        }
    }
}

/// On board: "Front of the train · Exit B2", so you are at the right door when it stops.
struct ExitAdviceLine: View {
    let advice: ExitAdvice

    var body: some View {
        if let text = advice.short {
            HStack(spacing: 8) {
                if let part = advice.part {
                    TrainPartGlyph(part: part)
                } else {
                    Image(systemName: "door.left.hand.open").frame(width: TrainPartGlyph.width)
                }
                Text(verbatim: text).font(.subheadline.weight(.semibold))
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("exitAdviceOnBoard")
        }
    }
}

/// Three cars with the one to board filled in: front on the right, as the train drives to the right.
struct TrainPartGlyph: View {
    let part: ExitAdvice.Part
    static let width: CGFloat = 36

    var body: some View {
        HStack(spacing: 2) {
            ForEach([ExitAdvice.Part.back, .middle, .front], id: \.self) { p in
                RoundedRectangle(cornerRadius: 2)
                    .fill(p == part ? Color.ink : Color.inkFill)
                    .frame(width: 8, height: 9)
            }
            Image(systemName: "chevron.right").font(.system(size: 7, weight: .bold)).foregroundStyle(.secondary)
        }
        .frame(width: Self.width, alignment: .leading)
        .accessibilityHidden(true)
    }
}
