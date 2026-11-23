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

    /// Changes when anything that needs a new search changes.
    private var searchKey: String { "\(model.revision)|\(model.isComplete)" }

    var body: some View {
        List {
            Section {
                ForEach(Array(model.stops.enumerated()), id: \.element.id) { index, stop in
                    stopRow(index, stop)
                    if index < model.sections.count {
                        sectionRow(index, model.sections[index])
                    }
                }
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
        .screenTrail("Plan in sections")
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
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(Fmt.time(route.startTime, tz: route.legs.first?.from.tz)) – \(Fmt.time(route.endTime, tz: route.legs.last?.to.tz))")
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                            SectionLines(route: route, mode: section.mode)
                        }
                        Spacer(minLength: 4)
                        Text(verbatim: Fmt.duration(seconds: route.duration)).font(.footnote).foregroundStyle(.secondary)
                        if section.options.count > 1 {
                            Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(section.options.count < 2)
                .accessibilityHint(Text("Choose another departure"))
                .accessibilityIdentifier("sectionRoute")
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

/// The lines of a section, or its way on the street.
private struct SectionLines: View {
    let route: Itinerary
    let mode: SectionMode

    var body: some View {
        let rides = route.legs.filter(\.isTransit)
        if rides.isEmpty {
            Label(mode.title, systemImage: mode.symbol).font(.footnote).foregroundStyle(.secondary)
        } else {
            HStack(spacing: 4) {
                ForEach(Array(rides.prefix(5).enumerated()), id: \.offset) { i, leg in
                    if i > 0 {
                        Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
                    }
                    LineBadge(leg)
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
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(Fmt.time(option.startTime, tz: option.legs.first?.from.tz)) – \(Fmt.time(option.endTime, tz: option.legs.last?.to.tz))")
                                        .font(.headline.monospacedDigit())
                                    SectionLines(route: option, mode: section.mode)
                                }
                                Spacer(minLength: 4)
                                Text(verbatim: Fmt.duration(seconds: option.duration)).font(.footnote).foregroundStyle(.secondary)
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
