import SwiftUI

struct PassRoute: Hashable {
    let id: String
}

/// All tickets as passes: valid now first, then upcoming, without dates and (folded) expired.
/// Expects a NavigationStack around it and a PassStore in the environment.
struct PassWalletView: View {
    @Environment(PassStore.self) private var store
    @State private var importing = false
    @State private var showingExpired = false
    var now: Date = .now

    var body: some View {
        Group {
            if store.passes.isEmpty {
                empty
            } else {
                list
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(L10n.t("Tickets"))
        .navigationDestination(for: PassRoute.self) { PassDetailView(passId: $0.id) }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { importing = true } label: { Label(L10n.t("Add ticket"), systemImage: "plus") }
                    .accessibilityIdentifier("addPass")
            }
        }
        .sheet(isPresented: $importing) { PassImportView() }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(store.grouped(at: now), id: \.group) { section in
                    if section.group == .expired {
                        Button {
                            withAnimation { showingExpired.toggle() }
                        } label: {
                            HStack {
                                Text(verbatim: "\(section.group.title) (\(section.passes.count))").font(.headline)
                                Spacer()
                                Image(systemName: showingExpired ? "chevron.up" : "chevron.down").accessibilityHidden(true)
                            }
                            .foregroundStyle(.secondary)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 8)
                        .accessibilityValue(showingExpired ? L10n.t("Shown") : L10n.t("Hidden"))
                        if showingExpired { cards(section.passes) }
                    } else {
                        Text(verbatim: section.group.title).font(.headline).padding(.top, 8)
                            .accessibilityAddTraits(.isHeader)
                        cards(section.passes)
                    }
                }
            }
            .padding()
        }
    }

    private func cards(_ passes: [TicketPass]) -> some View {
        ForEach(passes) { pass in
            NavigationLink(value: PassRoute(id: pass.id)) {
                PassCardView(pass: pass, compact: true, now: now)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(pass.accessibilitySummary)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("passCard")
        }
    }

    private var empty: some View {
        ContentUnavailableView {
            Label(L10n.t("No tickets yet"), systemImage: "ticket")
        } description: {
            Text("Add a ticket from a PDF, a photo or a screenshot. Publit reads the details on your iPhone and keeps the code ready for the gate.")
        } actions: {
            Button { importing = true } label: { Text("Add ticket") }
                .buttonStyle(.borderedProminent)
        }
    }
}
