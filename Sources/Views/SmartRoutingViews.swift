import SwiftUI

/// "✦ Recommended · One change fewer", then the other labels of a route in the list.
struct SmartBadgesRow: View {
    let badges: [SmartRouting.Badge]
    var reason: String? = nil

    var body: some View {
        // Chips never wrap or hyphenate ("Recommend-ed"); when the reason does not fit beside
        // them it goes on its own line below.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { chips; reasonText(fixed: true) }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) { chips }
                reasonText(fixed: false)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("smartBadges")
    }

    private var chips: some View {
        ForEach(badges, id: \.self) { badge in
            Label(badge.title, systemImage: badge.symbol)
                .labelStyle(.titleAndIcon)
                .font(.caption2.weight(.bold))
                .lineLimit(1)
                .fixedSize()
                // The suggestion is a solid ink chip (readable in light and dark), the rest stay quiet.
                .foregroundStyle(badge == .recommended ? Color.onInk : Color.secondary)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(badge == .recommended ? Color.ink : Color.inkFill, in: Capsule())
        }
    }

    /// Fixed beside the chips (so ViewThatFits can tell it does not fit), truncated on its own line.
    @ViewBuilder
    private func reasonText(fixed: Bool) -> some View {
        if let reason {
            Text(verbatim: reason).font(.caption2).foregroundStyle(.secondary)
                .lineLimit(1).fixedSize(horizontal: fixed, vertical: false)
        }
    }
}

/// On a route: each change with how likely it works and the vehicle that takes over if it does not.
struct SmartChangesSection: View {
    let itinerary: Itinerary
    @AppStorage(SmartRouting.enabledKey) private var enabled = true

    var body: some View {
        if enabled, !itinerary.isDirect {
            let changes = SmartRouting.changes(itinerary)
            let lastRide = itinerary.legs.lastIndex(where: \.isTransit)
            Section {
                if changes.isEmpty {
                    Label(L10n.t("No change: nothing to miss"), systemImage: "checkmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(Color.live)
                }
                ForEach(Array(changes.enumerated()), id: \.offset) { _, change in
                    ChangeChanceRow(change: change, isLastRide: change.outgoingIndex == lastRide)
                }
            } header: {
                Text(L10n.t("Smart routing"))
            } footer: {
                Text(L10n.f("Feels like %@: waiting, walking and changes count more than riding.",
                            Fmt.duration(seconds: Int(SmartRouting.feltMinutes(itinerary) * 60))))
            }
        }
    }
}

struct ChangeChanceRow: View {
    let change: SmartRouting.Change
    let isLastRide: Bool

    private var tint: Color {
        switch change.level {
        case .safe: return .live
        case .likely: return .delay
        case .risky: return .danger
        }
    }

    /// Where the chance comes from, in small print under the change.
    static func sourceText(_ source: SmartRouting.Change.Source) -> String {
        switch source {
        case .history(let n): return L10n.f("Based on %lld past trips", n)
        case .estimate: return L10n.t("Estimate")
        case .throughRun: return L10n.t("Same vehicle continues")
        }
    }

    private var verdict: String {
        if change.source == .throughRun { return L10n.t("Stay on board") }
        switch change.level {
        case .safe: return L10n.t("Safe change")
        case .likely: return L10n.t("Change should work")
        case .risky: return L10n.t("Risky change")
        }
    }

    var body: some View {
        let spare = change.spareMinutes >= 1 ? L10n.f("%@ to spare", Fmt.duration(seconds: Int(change.spareMinutes * 60)))
            : L10n.t("Very tight change")
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: change.level == .risky ? "exclamationmark.triangle.fill" : "arrow.triangle.swap")
                    .foregroundStyle(tint)
                Text(L10n.f("Change at %@", change.stopName)).font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                if !change.isEstimate {
                    Text(verbatim: "\(change.percent) %")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(tint)
                }
            }
            Text(verbatim: "\(verdict) · \(spare)")
                .font(.caption).foregroundStyle(.secondary)
            Text(Self.sourceText(change.source))
                .font(.caption2).foregroundStyle(.tertiary)
            if let backup = SmartRouting.backup(for: change.outgoing) {
                let then = isLastRide ? L10n.f("Arrive %@", Fmt.time(backup.arrival, tz: change.outgoing.to.tz))
                    : L10n.t("still makes the next change")
                Label(L10n.f("If missed: %@ at %@", backup.leg.lineName, Fmt.time(backup.leg.startTime, tz: backup.leg.from.tz)) + " · " + then,
                      systemImage: "arrow.uturn.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.ink)
            } else if change.level != .safe {
                Text(L10n.t("No backup found if you miss it.")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// Settings → Smart routing.
struct SmartRoutingSettingsSection: View {
    @AppStorage(SmartRouting.enabledKey) private var enabled = true
    @AppStorage(SmartRouting.transferMinutesKey) private var transferMinutes = SmartRouting.defaultTransferMinutes
    @AppStorage(SmartRouting.walkWeightKey) private var walkWeight = SmartRouting.defaultWalkWeight
    @AppStorage(SmartRouting.extraTransferKey) private var extraTransfer = 0
    @AppStorage(SmartRouting.ownSpeedKey) private var ownSpeed = false
    @AppStorage(SmartRouting.measuredSpeedKey) private var measuredSpeed = 0.0
    @AppStorage(SmartRouting.flatWalksKey) private var flatWalks = false
    @AppStorage(SmartRouting.learnKey) private var learn = true
    @AppStorage(SmartRouting.learnTripsKey) private var learnTrips = false
    @AppStorage(ChangeWatch.enabledKey) private var changeAlerts = true
    @State private var measuring = false
    @State private var learnedChanges = TripLearning.observations.count

    private var learnedSomething: Bool {
        transferMinutes != SmartRouting.defaultTransferMinutes || walkWeight != SmartRouting.defaultWalkWeight || learnedChanges > 0
    }

    var body: some View {
        Section {
            Toggle(isOn: $enabled) {
                Label(L10n.t("Smart routing"), systemImage: "sparkles")
            }
            .accessibilityIdentifier("smartRouting")
            if enabled {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.t("Changes")).font(.subheadline)
                    Slider(value: $transferMinutes, in: SmartRouting.transferMinutesRange, step: 1) {
                        Text(L10n.t("Changes"))
                    } minimumValueLabel: {
                        Text(L10n.t("Faster")).font(.caption)
                    } maximumValueLabel: {
                        Text(L10n.t("Fewer changes")).font(.caption)
                    }
                    .accessibilityIdentifier("smartTransferSlider")
                    Text(L10n.f("A change counts like %lld extra minutes.", Int(transferMinutes)))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Picker(L10n.t("Extra time for changes"), selection: $extraTransfer) {
                    ForEach(SmartRouting.extraTransferChoices, id: \.self) { m in
                        Text(m == 0 ? L10n.t("None") : L10n.f("+%lld min", m)).tag(m)
                    }
                }
                if WalkingPace.isAvailable {
                    Toggle(isOn: $ownSpeed) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.t("Use my walking speed"))
                                if WalkingPace.healthAvailable {
                                    Text(L10n.t("From Apple Health"))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            Image(systemName: WalkingPace.healthAvailable ? "heart.fill" : "figure.walk")
                                .foregroundStyle(WalkingPace.healthAvailable ? Color.pink : Color.ink)
                        }
                    }
                    .accessibilityIdentifier("walkingSpeedHealth")
                    .onChange(of: ownSpeed) { _, on in if on { Task { await measure() } } }
                    if ownSpeed {
                        if measuring {
                            ProgressView()
                        } else if measuredSpeed > 0 {
                            LabeledContent(L10n.t("Your walking speed"), value: Self.speedText(measuredSpeed))
                            if let source = WalkingPace.source {
                                Label(source == .health ? L10n.t("From Apple Health") : L10n.t("From the step counter"),
                                      systemImage: source == .health ? "heart.fill" : "figure.walk")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } else {
                            Text(L10n.t("Not enough walking measured yet.")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Toggle(L10n.t("Avoid steep walks"), isOn: $flatWalks)
                Toggle(L10n.t("Learn from my choices"), isOn: $learn)
                Toggle(isOn: $learnTrips) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("Learn from my trips"))
                        Text(learnedChanges > 0 ? L10n.f("Learned from %lld changes. Stays on this iPhone.", learnedChanges)
                             : L10n.t("How long your changes take, from your started trips. Stays on this iPhone."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("learnFromTrips")
                Toggle(L10n.t("Change alerts"), isOn: $changeAlerts)
                    .accessibilityIdentifier("changeAlerts")
                if learnedSomething {
                    Button(L10n.t("Reset learned preferences")) {
                        SmartRouting.resetLearning()
                        transferMinutes = SmartRouting.defaultTransferMinutes
                        walkWeight = SmartRouting.defaultWalkWeight
                        learnedChanges = 0
                    }
                }
            }
        } header: {
            Text(L10n.t("Smart routing"))
        } footer: {
            Text(L10n.t(enabled
                ? "Routes stay in time order. The one that feels shortest is marked “Recommended”: waiting, walking and changes count more than riding. Each change shows how likely it works and what to take if you miss it. Your choices tune this on your iPhone only."
                : "Routes are listed by departure, as the planner returns them."))
        }
        .task { if enabled && ownSpeed { await measure() } }
    }

    private func measure() async {
        measuring = true
        if let v = await WalkingPace.measure() { measuredSpeed = v }
        measuring = false
    }

    static func speedText(_ metersPerSecond: Double) -> String {
        Measurement(value: metersPerSecond * 3.6, unit: UnitSpeed.kilometersPerHour)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(1))))
    }
}
