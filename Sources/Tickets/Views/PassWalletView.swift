import SwiftUI

struct PassRoute: Hashable {
    let id: String
}

/// All tickets as passes: valid now first, then upcoming, without dates and just expired;
/// older ones in the archive.
/// Expects a NavigationStack around it and a PassStore in the environment.
struct PassWalletView: View {
    @Environment(PassStore.self) private var store
    @State private var importing = false
    @State private var showSettings = false
    var now: Date = .now

    var body: some View {
        VStack(spacing: 0) {
            InkPageHeader("Tickets", identifier: "heading-tickets") {
                Button { importing = true } label: { Label("Add ticket", systemImage: "plus").frame(width: 44, height: 44) }
                    .accessibilityIdentifier("addPass")
                Button { showSettings = true } label: { Label("Settings", systemImage: "gearshape").frame(width: 44, height: 44) }
            }
            .padding(.horizontal, 16)
            if store.passes.isEmpty { empty } else { list }
        }
        .liveBarPadding().background(Color.ground)
        .navigationTitle("").toolbar(.hidden, for: .navigationBar)
        .screenTrail("Tickets")
        .navigationDestination(for: PassRoute.self) { PassDetailView(passId: $0.id) }
        .sheet(isPresented: $showSettings) {
            SettingsView().environment(\.liveBarInset, 0)
        }
        .sheet(isPresented: $importing) { PassImportView() }
    }

    private var list: some View {
        let groups = store.grouped(at: now)
        let archived = store.archived(at: now).count
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if groups.isEmpty {
                    Text("No current tickets").font(.subheadline).foregroundStyle(.secondary).padding(.top, 8)
                }
                ForEach(groups, id: \.group) { section in
                    InkSectionLabel(title: section.group.title)
                    ForEach(section.passes.filter { $0.category.isPass }) { pass in
                        NavigationLink(value: PassRoute(id: pass.id)) {
                            WalletPassTile(pass: pass, now: now, source: source(pass))
                        }
                        .buttonStyle(.plain).accessibilityElement(children: .ignore)
                        .accessibilityLabel(pass.accessibilitySummary).accessibilityIdentifier("passCard")
                        .contextMenu { PassArchiveButton(pass: pass, now: now) }
                        .accessibilityActions { PassArchiveButton(pass: pass, now: now) }
                    }
                    let singles = section.passes.filter { !$0.category.isPass }
                    if !singles.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(Array(singles.enumerated()), id: \.element.id) { index, pass in
                                if index > 0 { Divider().padding(.leading, 16) }
                                NavigationLink(value: PassRoute(id: pass.id)) {
                                    WalletTicketRow(pass: pass, logo: PassLogoCache.image(pass, store: store))
                                }
                                .buttonStyle(.plain).accessibilityElement(children: .ignore)
                                .accessibilityLabel(pass.accessibilitySummary).accessibilityIdentifier("passCard")
                                .contextMenu { PassArchiveButton(pass: pass, now: now) }
                                .accessibilityActions { PassArchiveButton(pass: pass, now: now) }
                            }
                        }
                        .background(Color.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                }
                Button { importing = true } label: {
                    Label("Add ticket", systemImage: "plus").font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.inkFill, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                if archived > 0 {
                    NavigationLink {
                        PassArchiveView(now: now)
                    } label: {
                        HStack {
                            Label(L10n.t("Archive"), systemImage: "archivebox")
                            Spacer()
                            Text(verbatim: "\(archived)").foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        .padding(14)
                        .background(Color.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                    .accessibilityIdentifier("passArchive")
                }
            }
            .padding()
        }
    }

    private func source(_ pass: TicketPass) -> BarcodeSource? {
        guard let document = pass.document, let url = store.documentURL(pass) else { return nil }
        return .file(url, document.kind, page: document.page)
    }

    private var empty: some View {
        ContentUnavailableView {
            Label(L10n.t("No tickets yet"), systemImage: "ticket")
        } description: {
            Text("Add a ticket from a PDF, a photo or a screenshot. Publit reads the details on your iPhone and keeps the code ready for the gate.")
        } actions: {
            Button { importing = true } label: { Text("Add ticket") }
                .buttonStyle(.ink)
        }
    }
}

/// Compact cards that open the pass; long press to move a ticket to the archive or back.
struct PassCards: View {
    @Environment(PassStore.self) private var store
    let passes: [TicketPass]
    var now: Date = .now

    var body: some View {
        ForEach(passes) { pass in
            NavigationLink(value: PassRoute(id: pass.id)) {
                PassCardView(pass: pass, compact: true, now: now, logo: PassLogoCache.image(pass, store: store))
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(pass.accessibilitySummary)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("passCard")
            .contextMenu { PassArchiveButton(pass: pass, now: now) }
            .accessibilityActions { PassArchiveButton(pass: pass, now: now) }
        }
    }
}

struct PassArchiveButton: View {
    @Environment(PassStore.self) private var store
    let pass: TicketPass
    var now: Date = .now

    var body: some View {
        if pass.isArchived(at: now) {
            Button { withAnimation { store.unarchive(pass.id) } } label: {
                Label(L10n.t("Move back to tickets"), systemImage: "tray.and.arrow.up")
            }
        } else {
            Button { withAnimation { store.archive(pass.id) } } label: {
                Label(L10n.t("Move to archive"), systemImage: "archivebox")
            }
        }
    }
}
