import SwiftUI

/// The tickets for one trip: its own single tickets, then passes valid at the trip's time.
/// Without a trip: the passes valid now.
struct TripPassesView: View {
    var tripId: String? = nil
    var at: Date = .now
    @Environment(PassStore.self) private var store
    @State private var adding = false

    var body: some View {
        let list = store.passes(forTrip: tripId, at: at)
        Group {
            if list.isEmpty {
                ContentUnavailableView {
                    Label(L10n.t("No ticket for this trip"), systemImage: "ticket")
                } description: {
                    Text("Add the ticket from a PDF, a photo or a screenshot. Day, weekly and annual passes show up for every trip while they are valid.")
                } actions: {
                    Button(L10n.t("Add ticket")) { adding = true }.buttonStyle(.ink)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(list) { pass in
                            NavigationLink { PassDetailView(passId: pass.id) } label: {
                                PassCardView(pass: pass, compact: true, now: at, logo: PassLogoCache.image(pass, store: store))
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(pass.accessibilitySummary)
                            .accessibilityAddTraits(.isButton)
                        }
                        Button { adding = true } label: {
                            Label(L10n.t("Add ticket"), systemImage: "plus").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered).controlSize(.large)
                    }
                    .padding()
                }
                .background(Color.ground)
            }
        }
        .navigationTitle(L10n.t("Tickets"))
        .screenTrail("Trip tickets")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $adding) { PassImportView(tripId: tripId) }
    }
}

/// "Show ticket" for a trip: straight to the code when there is exactly one ticket with a code
/// (fast at the gate), otherwise the trip's tickets.
/// The bar item exists only when there is a ticket, and its sheets hang on the screen, not inside
/// the navigation bar: an empty item, or one that presents, can keep the bar laying itself out.
struct ShowPassToolbar: ViewModifier {
    var tripId: String?
    var at: Date
    var enabled = true
    @Environment(PassStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var code: TicketPass?
    @State private var listing = false

    func body(content: Content) -> some View {
        let list = enabled ? store.passes(forTrip: tripId, at: at) : []
        content
            .toolbar {
                if !list.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            if list.count == 1, list[0].barcode != nil { code = list[0] } else { listing = true }
                        } label: {
                            Label(L10n.t("Show ticket"), systemImage: "ticket")
                        }
                        .accessibilityIdentifier("showTicket")
                    }
                }
            }
            .fullScreenCover(item: $code) { pass in
                FullScreenCodeView(pass: pass, source: source(pass)).dynamicTypeSize(dynamicTypeSize)
            }
            .sheet(isPresented: $listing) {
                NavigationStack {
                    TripPassesView(tripId: tripId, at: at)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { listing = false } } }
                }
            }
    }

    private func source(_ pass: TicketPass) -> BarcodeSource? {
        guard let url = store.documentURL(pass), let d = pass.document else { return nil }
        return .file(url, d.kind, page: d.page)
    }
}

extension View {
    func showPassToolbar(tripId: String? = nil, at date: Date, enabled: Bool = true) -> some View {
        modifier(ShowPassToolbar(tripId: tripId, at: date, enabled: enabled))
    }
}

/// The trip section on route and saved-trip screens: the trip's tickets and "Add ticket".
struct TripPassSection: View {
    let tripId: String?
    let at: Date
    /// Saves the trip first, so a single ticket can belong to it; returns its ID.
    let ensureTrip: () -> String
    @Environment(PassStore.self) private var store
    @State private var adding: String?
    @State private var listing = false

    var body: some View {
        let list = store.passes(forTrip: tripId, at: at)
        Section {
            ForEach(list) { pass in
                Button { listing = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: pass.symbol.systemImage)
                            .frame(width: 30, height: 30)
                            .foregroundStyle(Color(hex: pass.style.foreground) ?? .white)
                            .background(Color(hex: pass.style.background) ?? .black, in: RoundedRectangle(cornerRadius: 7))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: pass.displayTitle).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
                            if let op = pass.operatorName { Text(verbatim: op).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                }
                .accessibilityLabel(pass.accessibilitySummary)
            }
            Button { adding = ensureTrip() } label: {
                Label(L10n.t("Add ticket for this trip"), systemImage: "plus.rectangle.on.rectangle")
            }
            .id("trip-ticket-import-row")
            .accessibilityIdentifier("addTripTicket")
            // On one row only: presentation modifiers on a Section are copied onto every row.
            .sheet(item: Binding(get: { adding.map(TripRef.init) }, set: { adding = $0?.id })) { ref in
                PassImportView(tripId: ref.id)
            }
            .sheet(isPresented: $listing) {
                NavigationStack {
                    TripPassesView(tripId: tripId, at: at)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { listing = false } } }
                }
            }
        } header: {
            Text("Tickets")
        }
    }

    private struct TripRef: Identifiable { let id: String }
}
