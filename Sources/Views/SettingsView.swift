import SwiftUI

/// Settings and credits, behind the gear in the top-left corner of every tab.
/// Credits for the data sources live here once instead of under every list.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(TicketStore.self) private var tickets
    @AppStorage("mapLines") private var mapLines = true
    @AppStorage("mapVehicles") private var mapVehicles = true
    @AppStorage("mapSharing") private var mapSharing = false
    @AppStorage("routeTimelines") private var routeTimelines = true
    @AppStorage(LineAlertMonitor.enabledKey) private var lineAlerts = false
    @State private var hasFreezeLog = HangLog.shared.hasEntries

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        PublitAppIcon(size: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: "Publit").font(.title2.bold())
                            Text("Public transport, without the noise.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                }
                Section(L10n.t("Travel preferences")) {
                    RouteOptionsButton()
                    Toggle(L10n.t("Show connection timelines"), isOn: $routeTimelines)
                    NavigationLink { ConnectionGuideView() } label: { Label(L10n.t("How to read connections"), systemImage: "questionmark.circle") }
                }
                Section(L10n.t("Map layers")) {
                    Toggle(L10n.t("Lines"), isOn: $mapLines)
                    Toggle(L10n.t("Vehicles"), isOn: $mapVehicles)
                    Toggle(L10n.t("Bikes and scooters"), isOn: $mapSharing)
                }
                if Features.tickets {
                    Section("Tickets") {
                        NavigationLink {
                            TicketsView()
                        } label: {
                            LabeledContent {
                                Text("\(tickets.tickets.count)")
                            } label: {
                                Label("My tickets", systemImage: "ticket")
                            }
                        }
                        NavigationLink {
                            LinkedTicketAppsView()
                        } label: {
                            LabeledContent {
                                Text("\(tickets.linkedApps.count)")
                            } label: {
                                Label("Ticket apps per operator", systemImage: "arrow.up.forward.app")
                            }
                        }
                    }
                }
                Section {
                    Toggle(isOn: Binding(get: { lineAlerts }, set: { on in
                        lineAlerts = on
                        if on { Task { if !(await LineAlertMonitor.requestPermission()) { lineAlerts = false } } }
                    })) {
                        Label("Disruptions on saved lines", systemImage: "exclamationmark.bubble")
                    }
                    .accessibilityIdentifier("lineAlertsToggle")
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Publit checks your saved lines when you open it and from time to time in the background (iOS decides when), and tells you about alerts and cancelled departures.")
                }
                Section {
                    Link("Routing and timetables: Transitous and its data sources", destination: AppInfo.sourcesURL)
                    Link("Map data © OpenStreetMap contributors", destination: AppInfo.osmCopyrightURL)
                } header: {
                    Text("Data")
                } footer: {
                    Text("Times marked live come from the operator's real-time feed; all others are timetable times.")
                }
                Section {
                    if hasFreezeLog {
                        ShareLink(item: HangLog.shared.fileURL) {
                            Label("Share freeze log", systemImage: "square.and.arrow.up")
                        }
                        .accessibilityIdentifier("shareFreezeLog")
                        Button(role: .destructive) {
                            HangLog.shared.clear()
                            hasFreezeLog = false
                        } label: {
                            Label("Delete freeze log", systemImage: "trash")
                        }
                    } else {
                        Text("No freezes recorded").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Diagnostics")
                } footer: {
                    Text("If Publit stops responding for 2 seconds or more, the time and the screens opened just before are noted here. Nothing else is recorded, and nothing leaves this device unless you share it.")
                }
                Section {
                    Link("Source code and feedback", destination: AppInfo.repositoryURL)
                    LabeledContent("Version", value: AppInfo.version)
                } header: {
                    Text("About")
                } footer: {
                    if Features.tickets {
                        Text("Publit is open source (MIT). No account, no ads, no tracking. Saved places, trips and tickets stay on this device.")
                    } else {
                        Text("Publit is open source (MIT). No account, no ads, no tracking. Saved places and trips stay on this device.")
                    }
                }
            }
            .navigationTitle("Settings")
            .screenTrail("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

/// Gear button for the navigation bar of each tab.
struct SettingsButton: View {
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: { Label("Settings", systemImage: "gearshape") }
            .sheet(isPresented: $showing) { SettingsView() }
    }
}

extension View {
    func withSettingsButton() -> some View {
        toolbar {
            ToolbarItem(placement: .topBarLeading) { SettingsButton() }
        }
    }
}
