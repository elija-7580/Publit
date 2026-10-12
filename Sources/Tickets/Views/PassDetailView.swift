import SwiftUI

/// One pass: the card with its code, then the original, Wallet, edit and delete.
struct PassDetailView: View {
    let passId: String
    @Environment(PassStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showingCode = false
    @State private var showingOriginal = false
    @State private var editing = false
    @State private var confirmingDelete = false

    var body: some View {
        if let pass = store.pass(passId) {
            content(pass)
        } else {
            ContentUnavailableView(L10n.t("Ticket deleted"), systemImage: "ticket")
        }
    }

    private func content(_ pass: TicketPass) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PassCardView(pass: pass, onCodeTap: pass.barcode == nil ? nil : { showingCode = true })
                    .accessibilityElement(children: .contain)

                if case .expired(let date) = pass.validity() {
                    Label(L10n.f("Expired on %@", PassFormat.date(date, end: true)), systemImage: "exclamationmark.circle")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Color.danger)
                }

                VStack(spacing: 10) {
                    if pass.document != nil {
                        Button { showingOriginal = true } label: {
                            Label(L10n.t("Show original"), systemImage: "doc.text.magnifyingglass").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered).controlSize(.large)
                        .accessibilityIdentifier("showOriginal")
                    }
                    if WalletPassConfig.current != nil, pass.barcode?.walletMessage != nil {
                        AddToWalletButton(pass: pass)
                    }
                }

                if let notes = pass.notes, !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notes").font(.subheadline.weight(.semibold))
                        Text(verbatim: notes).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }

                Text("A copy of your ticket for quick access. Only the ticket the operator issued is valid. Inspectors may ask for it or for the operator's app.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(pass.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .brightnessBoost(pass.barcode != nil)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { editing = true } label: { Label("Edit", systemImage: "pencil") }
                    Button(role: .destructive) { confirmingDelete = true } label: { Label("Delete", systemImage: "trash") }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .accessibilityIdentifier("passMenu")
            }
        }
        .fullScreenCover(isPresented: $showingCode) { FullScreenCodeView(pass: pass) }
        .sheet(isPresented: $showingOriginal) {
            NavigationStack {
                Group {
                    if let url = store.documentURL(pass), let document = pass.document {
                        ZoomableDocumentView(url: url, kind: document.kind, page: document.page)
                    } else {
                        ContentUnavailableView(L10n.t("Ticket image unavailable"), systemImage: "doc")
                    }
                }
                .navigationTitle(L10n.t("Original ticket"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingOriginal = false } } }
            }
            .brightnessBoost()
        }
        .sheet(isPresented: $editing) {
            NavigationStack { PassEditorView(mode: .edit(pass)) }
        }
        .confirmationDialog(L10n.t("Delete this ticket?"), isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button(L10n.t("Delete ticket"), role: .destructive) {
                store.remove(pass.id)
                dismiss()
            }
        } message: {
            Text("The copy and its original are removed from this iPhone.")
        }
    }
}

/// The code alone on white, as large as possible, at full brightness.
struct FullScreenCodeView: View {
    let pass: TicketPass
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text(verbatim: pass.displayTitle).font(.title2.bold()).multilineTextAlignment(.center)
            if let code = pass.barcode {
                BarcodeView(code: code)
                    .aspectRatio(code.format.isSquare ? 1 : 3, contentMode: .fit)
                    .padding(.horizontal, 24)
                    .accessibilityLabel(L10n.f("%@ code", code.format.title))
                if let text = pass.reference ?? code.altText {
                    Text(verbatim: text).font(.body.monospaced())
                }
            }
            if let passenger = pass.passenger { Text(verbatim: passenger).font(.headline) }
            Spacer()
            Button { dismiss() } label: { Text("Done").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).controlSize(.large).tint(.black)
                .padding(.horizontal)
                .accessibilityIdentifier("closeCode")
        }
        .padding(.vertical)
        .foregroundStyle(.black)
        .background(Color.white.ignoresSafeArea())
        .environment(\.colorScheme, .light)
        .brightnessBoost()
        .onTapGesture(count: 2) { dismiss() }
    }
}
