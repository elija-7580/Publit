import SwiftUI

struct RecentSearchesSection: View {
    var goNow = false
    @Environment(SearchHistoryStore.self) private var history
    @Environment(AppState.self) private var app
    @State private var confirmClear = false

    var body: some View {
        if !history.entries.isEmpty {
            Section {
                ForEach(Array(history.entries.prefix(goNow ? 3 : 5))) { search in
                    Button {
                        if goNow {
                            search.apply(to: app.goNow)
                            app.goNow.timeMode = .now
                            app.showGoNow = true
                        } else {
                            search.apply(to: app.plan)
                            app.plan.searchStarted = true // a past search: run it again
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(search.to.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            Text(L10n.f("from %@", search.from.title)).font(.caption).foregroundStyle(.secondary)
                            Text(search.searchedAt, style: .relative).font(.caption2).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 3)
                    }
                    .accessibilityIdentifier("recentSearch")
                    .swipeActions { Button("Remove", role: .destructive) { history.remove(search.id) } }
                }
                Button("Clear history", role: .destructive) { confirmClear = true }
                    .font(.subheadline)
            } header: { Text("Recently searched") }
            .confirmationDialog("Clear search history?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear history", role: .destructive) { history.clear() }
                Button("Cancel", role: .cancel) { }
            }
        }
    }
}
