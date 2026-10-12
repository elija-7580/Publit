import SwiftUI

struct FavoritesView: View {
    @Environment(FavoritesStore.self) private var favorites
    @Environment(AppState.self) private var app
    @State private var adding = false
    @State private var settingRole: PlaceRole?

    var body: some View {
        List {
            Section("Home and Work") {
                ForEach(PlaceRole.allCases, id: \.self) { role in
                    if let p = favorites.place(for: role) {
                        Button { app.route(to: p) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: role.symbol).foregroundStyle(.blue).frame(width: 24)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(role.title).foregroundStyle(.primary)
                                    Text(p.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) { favorites.clear(role) } label: { Label("Remove", systemImage: "trash") }
                            Button { settingRole = role } label: { Label("Change", systemImage: "pencil") }
                        }
                        .accessibilityHint("Plans a route to \(role.title)")
                    } else {
                        Button { settingRole = role } label: {
                            Label("Set \(role.title)", systemImage: role.symbol)
                        }
                    }
                }
            }

            if !favorites.lines.isEmpty {
                Section("Lines") {
                    ForEach(favorites.lines) { line in
                        NavigationLink {
                            LineDeparturesView(line: line)
                        } label: {
                            HStack(spacing: 10) {
                                LineBadge(line)
                                Text("at \(line.stopName)").lineLimit(1)
                            }
                        }
                    }
                    .onDelete { idx in favorites.removeLines(idx.map { favorites.lines[$0].id }) }
                }
            }
            if favorites.stops.isEmpty && favorites.places.isEmpty && favorites.lines.isEmpty {
                Section {
                    ContentUnavailableView("Nothing else saved yet", systemImage: "star",
                                           description: Text("Save stops from their departure board, lines from a trip, or add places with +."))
                }
            }
            if !favorites.stops.isEmpty {
                Section("Stops") {
                    ForEach(favorites.stops) { s in
                        NavigationLink {
                            StopDeparturesView(stopId: s.stopId ?? s.id, name: s.name, coordinate: s.coordinate)
                        } label: {
                            PlaceLabel(name: s.name, subtitle: s.subtitle, isStop: true)
                        }
                    }
                    .onDelete { idx in favorites.remove(idx.map { favorites.stops[$0].id }) }
                }
            }
            if !favorites.places.isEmpty {
                Section("Places") {
                    ForEach(favorites.places) { p in
                        Button { app.route(to: p) } label: {
                            PlaceLabel(name: p.name, subtitle: p.subtitle, isStop: false)
                        }
                        .swipeActions(edge: .leading) {
                            Button { favorites.set(p, as: .home) } label: { Label("Home", systemImage: "house") }.tint(.blue)
                            Button { favorites.set(p, as: .work) } label: { Label("Work", systemImage: "briefcase") }.tint(.indigo)
                        }
                    }
                    .onDelete { idx in favorites.remove(idx.map { favorites.places[$0].id }) }
                }
            }
        }
        .navigationTitle("Saved")
        .withSettingsButton()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { adding = true } label: { Label("Add", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $adding) {
            PlaceSearchView(title: "Save a place", allowCurrentLocation: false) { endpoint in
                if case .place(let p) = endpoint, !favorites.contains(p) { favorites.toggle(p) }
            }
        }
        .sheet(item: $settingRole) { role in
            PlaceSearchView(title: "Set \(role.title)", allowCurrentLocation: false) { endpoint in
                if case .place(let p) = endpoint { favorites.set(p, as: role) }
            }
        }
    }
}
