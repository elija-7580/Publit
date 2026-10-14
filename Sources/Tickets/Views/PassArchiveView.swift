import SwiftUI

/// Tickets that ended a day ago or longer, and ones archived by hand: by month, newest first,
/// searchable (for refunds, expense reports or a late check). Nothing is deleted automatically.
struct PassArchiveView: View {
    @Environment(PassStore.self) private var store
    @State private var query = ""
    @State private var confirmingDelete = false
    var now: Date = .now

    var body: some View {
        let all = store.archived(at: now)
        let shown = all.filter { PassArchive.matches($0, query) }
        Group {
            if all.isEmpty {
                ContentUnavailableView(L10n.t("No archived tickets"), systemImage: "archivebox")
            } else if shown.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(PassArchive.months(shown), id: \.month) { section in
                            Text(verbatim: section.month.formatted(.dateTime.month(.wide).year()))
                                .font(.headline).padding(.top, 8)
                                .accessibilityAddTraits(.isHeader)
                            PassCards(passes: section.passes, now: now)
                        }
                        Text("Expired tickets move here a day after they end. They stay on this iPhone until you delete them.")
                            .font(.footnote).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 8)
                    }
                    .padding()
                }
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(L10n.t("Archive"))
        .screenTrail("Ticket archive")
        .searchable(text: $query)
        .toolbar {
            if !all.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(role: .destructive) { confirmingDelete = true } label: {
                            Label(L10n.t("Delete archived tickets"), systemImage: "trash")
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                    .accessibilityIdentifier("archiveMenu")
                }
            }
        }
        .confirmationDialog(L10n.t("Delete all archived tickets?"), isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button(L10n.t("Delete archived tickets"), role: .destructive) { withAnimation { store.removeArchived(at: now) } }
        } message: {
            Text("Their copies and originals are removed from this iPhone.")
        }
    }
}
