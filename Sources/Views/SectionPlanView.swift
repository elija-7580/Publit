// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich
import SwiftUI

/// Build your own connection, part 5 (#144): a journey laid out section by section. Places in
/// order, between each two how to travel (public transport, on foot, by bike, by car) and which
/// departure, and how long to stay at the places in between. The result is one route that can be
/// started and saved like any other.
struct SectionPlanView: View {
    @Environment(LocationManager.self) private var location
    @State private var model: SectionPlanModel
    /// The place being chosen, by its position.
    @State private var picking: StopIndex?
    /// The section whose ways are listed.
    @State private var choosing: StopIndex?
    @State private var shown: BuiltRoute?

    private struct StopIndex: Identifiable { let id: Int }

    init(from: Endpoint?, to: Endpoint?, date: Date = .now) {
        _model = State(initialValue: SectionPlanModel(from: from, to: to, date: date))
    }

    /// A plan laid out beforehand, e.g. around a ticket (#24).
    init(model: SectionPlanModel) {
        _model = State(initialValue: model)
    }

    /// Changes when anything that needs a new search changes.
    private var searchKey: String { "\(model.revision)|\(model.isComplete)" }

    var body: some View {
        List {
            Section {
                // One row per place with the section that leaves it, so a place can be held and
                // dragged to another position (or moved with the handles after "Edit").
                ForEach(Array(model.stops.enumerated()), id: \.element.id) { index, stop in
                    VStack(alignment: .leading, spacing: 6) {
                        stopRow(index, stop)
                        if index < model.sections.count {
                            sectionRow(index, model.sections[index])
                        }
                    }
                    .listRowSeparator(.hidden)
                    .deleteDisabled(index == 0 || index == model.stops.count - 1)
                }
                .onMove { model.moveStops(from: $0, to: $1) }
                .onDelete { offsets in offsets.sorted(by: >).forEach { model.removeStop(at: $0) } }
                if model.canAddStop {
                    Button { model.addStop(); picking = StopIndex(id: model.stops.count - 2) } label: {
                        Label("Add a stop in between", systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("addSectionStop")
                }
            } footer: {
                Text("Each section starts when the one before has arrived, plus the time you stay.")
                    + Text(verbatim: " ") + Text("Hold a place and drag it to change the order.")
            }
            .inkCard()

            Section {
                HStack(spacing: 10) {
                    DatePicker(L10n.t("Depart at"), selection: Binding(get: { model.date }, set: { model.setDate($0) }))
                        .labelsHidden()
                        .datePickerStyle(.compact)
                    Spacer(minLength: 0)
                    Button { model.leavesNow = true; model.setDate(.now) } label: {
                        Label("Now", systemImage: "clock.arrow.circlepath").lineLimit(1).fixedSize()
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.soft)
                    .disabled(model.leavesNow)
                }
            } header: {
                Text("Depart")
            }
            .inkCard()
        }
        .inkList()
        .safeAreaInset(edge: .bottom, spacing: 0) { summary }
        .navigationTitle("Plan in sections")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { EditButton().accessibilityIdentifier("sectionReorder") } }
        .screenTrail("Plan in sections")
        .task {
            // Laid out around a ticket: the final destination is the one place still missing.
            if let missing = model.stops.lastIndex(where: { $0.place == nil }), model.anchor != nil {
                picking = StopIndex(id: missing)
            }
        }
        .task(id: searchKey) {
            guard model.isComplete else { return }
            await model.plan(current: location.coordinate)
        }
        .sheet(item: $picking) { target in
            PlaceSearchView(title: target.id == 0 ? "From" : target.id == model.stops.count - 1 ? "To" : "Stop in between",
                            allowCurrentLocation: true, chooseOnMap: true) { endpoint in
                model.setPlace(endpoint, at: target.id)
            }
        }
        .sheet(item: $choosing) { target in
            NavigationStack {
                SectionChoiceView(section: model.sections[safe: target.id],
                                  from: model.stops[safe: target.id]?.place?.title ?? "",
                                  to: model.stops[safe: target.id + 1]?.place?.title ?? "") { option in
                    model.choose(option, at: target.id)
                }
            }
        }
        .navigationDestination(item: $shown) { route in
            // Changing a ride there would plan through to the destination and drop the places in between.
            ItineraryDetailView(itinerary: route.itinerary, fromName: model.stops.first?.place?.title ?? "",
                                toName: model.stops.last?.place?.title ?? "", allowsLegChange: false)
        }
    }

    // MARK: Rows

    private func stopRow(_ index: Int, _ stop: SectionPlanModel.Stop) -> some View {
        let between = index > 0 && index < model.stops.count - 1
        return HStack(spacing: 10) {
            Image(systemName: index == 0 ? "circle" : between ? "smallcircle.filled.circle" : "mappin.circle.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(between ? Color.secondary : Color.ink)
                .frame(width: 24)
                .accessibilityHidden(true)
            Button { picking = StopIndex(id: index) } label: {
                HStack(spacing: 6) {
                    if let place = stop.place {
                        if case .currentLocation = place { SignatureDot(size: 9) }
                        Text(place.title).font(.body.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                    } else {
                        Text(between ? "Where do you stop?" : "Where to?").foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("sectionStop")
            if between {
                Menu {
                    Picker("Stay", selection: Binding(get: { stop.stay }, set: { model.setStay($0, at: index) })) {
                        ForEach(SectionPlanModel.stays, id: \.self) { minutes in
                            Text(minutes == 0 ? L10n.t("No stay") : Fmt.duration(seconds: minutes * 60)).tag(minutes)
                        }
                    }
                    Button(role: .destructive) { model.removeStop(at: index) } label: {
                        Label("Remove stop", systemImage: "trash")
                    }
                } label: {
                    Label(stop.stay == 0 ? L10n.t("No stay") : Fmt.duration(seconds: stop.stay * 60), systemImage: "hourglass")
                        .font(.footnote.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                        .fixedSize()
                }
                .accessibilityLabel(Text(L10n.f("Stay: %@", Fmt.duration(seconds: stop.stay * 60))))
                .accessibilityIdentifier("sectionStay")
            }
        }
        .listRowSeparator(.hidden)
    }

    private func sectionRow(_ index: Int, _ section: SectionPlanModel.Section) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // The stroke between two places.
            Capsule().fill(Color.inkFill).frame(width: 3).frame(width: 24).padding(.vertical, 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Picker("How", selection: Binding(get: { section.mode }, set: { model.setMode($0, at: index) })) {
                    ForEach(SectionMode.allCases) { mode in
                        Image(systemName: mode.symbol).accessibilityLabel(Text(verbatim: mode.title)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("sectionMode")
                sectionResult(index, section)
            }
        }
        .padding(.vertical, 4)
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private func sectionResult(_ index: Int, _ section: SectionPlanModel.Section) -> some View {
        switch section.state {
        case .idle:
            Text(verbatim: section.mode.title).font(.footnote).foregroundStyle(.secondary)
        case .loading:
            HStack(spacing: 8) { ProgressView(); Text(verbatim: section.mode.title).font(.footnote).foregroundStyle(.secondary) }
        case .failed:
            HStack {
                Text("This section could not be loaded.").font(.footnote).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Button("Try again") { Task { await model.plan(current: location.coordinate) } }
                    .font(.footnote.weight(.semibold)).buttonStyle(.borderless)
            }
        case .empty:
            Text("No way found for this section. Try another way to travel or another time.")
                .font(.footnote).foregroundStyle(Color.delay)
        case .found:
            if let route = section.route {
                Button { choosing = StopIndex(id: index) } label: {
                    SectionSummary(route: route, mode: section.mode, canChoose: section.options.count > 1)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(section.options.count < 2)
                .accessibilityHint(Text("Choose another departure"))
                .accessibilityIdentifier("sectionRoute")
                if model.anchor?.index == index {
                    Label("The ride on your ticket", systemImage: "ticket").font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                // Choose the change point yourself (#10): split the section at a stop of this way.
                let points = model.changePoints(of: index)
                if !points.isEmpty, model.canAddStop {
                    Menu {
                        ForEach(Array(points.prefix(30).enumerated()), id: \.offset) { _, p in
                            Button(p.name) { model.split(index, at: p) }
                        }
                    } label: {
                        Label("Change at…", systemImage: "arrow.triangle.branch").font(.footnote.weight(.semibold))
                    }
                    .accessibilityIdentifier("sectionChangeAt")
                }
            }
        }
    }

    @ViewBuilder
    private var summary: some View {
        if let route = model.route {
            Button { shown = BuiltRoute(itinerary: route) } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Fmt.time(route.startTime, tz: route.legs.first?.from.tz)) – \(Fmt.time(route.endTime, tz: route.legs.last?.to.tz))")
                            .font(.headline.monospacedDigit())
                        Text(verbatim: Fmt.duration(seconds: route.duration)).font(.footnote).opacity(0.8)
                    }
                    Spacer()
                    Label("Show route", systemImage: "arrow.right").labelStyle(.titleAndIcon).font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar)
            .accessibilityIdentifier("showSectionRoute")
        }
    }
}

/// One section's way: times and duration on one line, its lines below. The times and the
/// duration never get cut off, and the lines wrap onto a second row instead of being squeezed
/// into narrow badges one letter wide (feedback on build 98: "F E", "12 h 51 mi").
private struct SectionSummary: View {
    let route: Itinerary
    let mode: SectionMode
    var canChoose = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Fmt.time(route.startTime, tz: route.legs.first?.from.tz)) – \(Fmt.time(route.endTime, tz: route.legs.last?.to.tz))")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .layoutPriority(1)
                Spacer(minLength: 4)
                Text(verbatim: Fmt.duration(seconds: route.duration))
                    .font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                if canChoose {
                    Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            SectionLines(route: route, mode: mode)
        }
    }
}

/// The lines of a section, or its way on the street. Every ride, wrapping onto more rows.
private struct SectionLines: View {
    let route: Itinerary
    let mode: SectionMode

    var body: some View {
        let rides = route.legs.filter(\.isTransit)
        if rides.isEmpty {
            Label(mode.title, systemImage: mode.symbol).font(.footnote).foregroundStyle(.secondary)
        } else {
            FlowRow(spacing: 4) {
                ForEach(Array(rides.enumerated()), id: \.offset) { i, leg in
                    HStack(spacing: 4) {
                        if i > 0 {
                            Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        LineBadge(leg, compact: true).fixedSize()
                    }
                }
            }
        }
    }
}

/// The ways to travel one section, earliest arrival first.
private struct SectionChoiceView: View {
    let section: SectionPlanModel.Section?
    let from: String
    let to: String
    var onChoose: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if let section {
                Section {
                    ForEach(Array(section.options.enumerated()), id: \.offset) { index, option in
                        Button { onChoose(index); dismiss() } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                SectionSummary(route: option, mode: section.mode)
                                if index == section.chosen {
                                    Image(systemName: "checkmark").font(.subheadline.weight(.bold)).foregroundStyle(Color.ink)
                                        .accessibilityLabel(Text("Selected"))
                                }
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("sectionChoice")
                    }
                } header: {
                    Text(verbatim: "\(from) → \(to)")
                } footer: {
                    Text("The sections after this one are planned again from when you arrive.")
                }
                .inkCard()
            }
        }
        .inkList()
        .navigationTitle("Choose a departure")
        .navigationBarTitleDisplayMode(.inline)
        .screenTrail("Section choice")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        }
    }
}
