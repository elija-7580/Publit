// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich

import SwiftUI

/// Changes on the live trip screen (layout A): the next change as a card under the stage card, and each change
/// as its own row in the trip's timeline, with platforms, time to spare, how sure it is and the exit to take.
enum LiveChanges {
    /// The transit leg whose change matters from this stage on: while waiting at a change the change itself,
    /// otherwise the next change after the stage. Nil when no change is left.
    static func target(for step: GuideStep, in it: Itinerary) -> Int? {
        guard step.kind != .arrive else { return nil }
        if step.kind == .wait, TransferInfo(before: step.legIndex, in: it) != nil { return step.legIndex }
        return it.legs.indices.first { $0 > step.legIndex && it.legs[$0].isTransit && TransferInfo(before: $0, in: it) != nil }
    }

    /// How sure the change into the leg at `index` is (smart routing), if it can be told.
    static func chance(into index: Int, in it: Itinerary) -> SmartRouting.Change? {
        SmartRouting.changes(it).first { $0.outgoingIndex == index }
    }

    /// The exit advice of the ride that ends at this change ("Board at the front · Exit B2").
    static func exit(before index: Int, in it: Itinerary) -> ExitAdvice? {
        guard let ride = it.legs[..<index].lastIndex(where: \.isTransit) else { return nil }
        return ExitAdvice.forRide(ride, in: it.legs)
    }

    /// "Pl. 2 → Pl. 3 · R 1990 · Safe change · Front of the train · Exit B2", the facts after the stop's name.
    static func detail(_ info: TransferInfo, chance: SmartRouting.Change?, exit: ExitAdvice?) -> String {
        var parts: [String] = []
        let from = TransitLabels.clean(info.fromTrack).map { L10n.f("Pl. %@", $0) }
        let to = TransitLabels.clean(info.toTrack).map { L10n.f("Pl. %@", $0) }
        switch (from, to) {
        case let (f?, t?): parts.append("\(f) → \(t)")
        case let (nil, t?): parts.append("→ \(t)")
        case let (f?, nil): parts.append(f)
        default: break
        }
        parts.append(info.toLine)
        if let chance, chance.source != .throughRun { parts.append(verdict(chance)) }
        if let short = exit?.short { parts.append(short) }
        return parts.joined(separator: " · ")
    }

    static func verdict(_ c: SmartRouting.Change) -> String {
        if c.source == .throughRun { return L10n.t("Stay on board") }
        switch c.level {
        case .safe: return L10n.t("Safe change")
        case .likely: return L10n.t("Change should work")
        case .risky: return L10n.t("Risky change")
        }
    }

    /// Green, orange or red only when it means something (docs/design §1.4): sure, tight, broken.
    static func tint(_ info: TransferInfo, chance: SmartRouting.Change?) -> Color {
        if info.isCancelled || info.isMissed || chance?.level == .risky { return .danger }
        if info.isTight || chance?.level == .likely { return .delay }
        return chance?.level == .safe ? .live : .secondary
    }

    static func spare(_ info: TransferInfo) -> String {
        info.isCancelled ? L10n.t("Connection cancelled")
            : info.isMissed ? L10n.f("Change at %@ no longer works", info.arrivalStop.name)
            : info.spareSeconds >= 60 ? L10n.f("%@ to spare", Fmt.duration(seconds: info.spareSeconds))
            : L10n.t("Very tight change")
    }
}

/// The next change, always under the stage card: where, the minutes to spare, platforms, how sure, which exit.
/// A tap opens the change (the wait for the next vehicle) with the change guide.
struct NextChangeCard: View {
    let info: TransferInfo
    let chance: SmartRouting.Change?
    let exit: ExitAdvice?
    let onTap: () -> Void

    static let height: CGFloat = 68

    var body: some View {
        let tint = LiveChanges.tint(info, chance: chance)
        HStack(spacing: 12) {
            Image(systemName: tint == .danger ? "exclamationmark.triangle.fill" : "arrow.triangle.swap")
                .font(.title3.weight(.semibold)).foregroundStyle(tint == .secondary ? Color.ink : tint)
                .frame(width: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.f("Change at %@", info.arrivalStop.name)).font(.headline).lineLimit(1)
                Text(verbatim: LiveChanges.detail(info, chance: chance, exit: exit))
                    .font(.footnote).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 8)
            if !info.isCancelled && !info.isMissed {
                // Numbers first: the minutes to spare, large and tabular, the unit small.
                VStack(alignment: .trailing, spacing: 0) {
                    Text(verbatim: "\(max(0, info.spareSeconds / 60))").font(.title2.weight(.heavy).monospacedDigit())
                        .foregroundStyle(tint == .secondary ? Color.ink : tint)
                    Text(verbatim: "min").font(.footnote.weight(.bold)).foregroundStyle(.secondary)
                }
                .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: Self.height, maxHeight: Self.height, alignment: .leading)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: [L10n.f("Change at %@", info.arrivalStop.name), LiveChanges.spare(info),
                                            LiveChanges.detail(info, chance: chance, exit: exit)].joined(separator: ", ")))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("liveNextChange")
    }
}

/// A change as its own row in the trip's timeline, between the ride that ends there and the next one.
struct LiveChangeRow: View {
    let info: TransferInfo
    let chance: SmartRouting.Change?
    let exit: ExitAdvice?
    let done: Bool

    var body: some View {
        let tint = LiveChanges.tint(info, chance: chance)
        HStack(spacing: 12) {
            Image(systemName: tint == .danger ? "exclamationmark.triangle.fill" : "arrow.triangle.swap")
                .font(.body.weight(.semibold)).foregroundStyle(tint == .secondary ? Color.ink : tint)
                .frame(minWidth: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.f("Change at %@", info.arrivalStop.name)).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(verbatim: [LiveChanges.spare(info), LiveChanges.detail(info, chance: chance, exit: exit)].joined(separator: " · "))
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .opacity(done ? 0.5 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
