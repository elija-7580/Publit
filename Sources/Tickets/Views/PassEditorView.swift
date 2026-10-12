import SwiftUI

/// Check and adjust what was read from the ticket, with a live preview of the pass.
struct PassEditorView: View {
    enum Mode {
        /// A freshly recognised ticket with its document and every code found on the page.
        case new(TicketPass, document: Data?, kind: TicketPass.Document.Kind?, page: Int, codes: [TicketPass.Barcode], colorFromTicket: String?)
        case edit(TicketPass)
    }

    let mode: Mode
    var onFinish: (() -> Void)? = nil

    @Environment(PassStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var pass: TicketPass
    @State private var codeIndex: Int
    @State private var saving = false
    @State private var error: String?

    init(mode: Mode, onFinish: (() -> Void)? = nil) {
        self.mode = mode
        self.onFinish = onFinish
        switch mode {
        case .new(let pass, _, _, _, let codes, _):
            _pass = State(initialValue: pass)
            _codeIndex = State(initialValue: codes.firstIndex { $0 == pass.barcode } ?? (codes.isEmpty ? -1 : 0))
        case .edit(let pass):
            _pass = State(initialValue: pass)
            _codeIndex = State(initialValue: 0)
        }
    }

    private var isNew: Bool { if case .new = mode { return true }; return false }

    private var codes: [TicketPass.Barcode] {
        switch mode {
        case .new(_, _, _, _, let codes, _): return codes
        case .edit(let pass): return pass.barcode.map { [$0] } ?? []
        }
    }

    private var colorFromTicket: String? {
        if case .new(_, _, _, _, _, let color) = mode { return color }
        return nil
    }

    var body: some View {
        Form {
            Section {
                PassCardView(pass: pass)
                    .padding(.vertical, 6)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    .listRowBackground(Color.clear)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L10n.f("Preview: %@", pass.accessibilitySummary))
            } footer: {
                if isNew { Text("Read on your iPhone. Check every detail before you save.") }
            }

            Section(L10n.t("Ticket")) {
                TextField(L10n.t("Title"), text: $pass.title, prompt: Text(verbatim: pass.category.title))
                TextField(L10n.t("Operator"), text: text(\.operatorName))
                Picker(L10n.t("Type"), selection: $pass.category) {
                    ForEach(TicketPass.Category.allCases, id: \.self) { Text(verbatim: $0.title).tag($0) }
                }
            }

            Section(L10n.t("Route")) {
                TextField(L10n.t("From"), text: text(\.origin))
                TextField(L10n.t("To"), text: text(\.destination))
            }

            Section(L10n.t("Validity")) {
                dateRow(L10n.t("Valid from"), \.validFrom, end: false)
                dateRow(L10n.t("Valid until"), \.validUntil, end: true)
            }

            Section(L10n.t("Details")) {
                TextField(L10n.t("Passenger"), text: text(\.passenger))
                    .textContentType(.name)
                Picker(L10n.t("Class"), selection: $pass.travelClass) {
                    Text("None").tag(String?.none)
                    Text(verbatim: L10n.f("Class %@", "1")).tag(String?.some("1"))
                    Text(verbatim: L10n.f("Class %@", "2")).tag(String?.some("2"))
                }
                TextField(L10n.t("Price"), text: text(\.price))
                TextField(L10n.t("Ticket number"), text: text(\.reference))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            }

            codeSection

            Section(L10n.t("Look")) {
                swatches
                Picker(L10n.t("Symbol"), selection: $pass.symbol) {
                    ForEach(TicketPass.Symbol.allCases, id: \.self) { symbol in
                        Label(symbol.title, systemImage: symbol.systemImage).tag(symbol)
                    }
                }
            }

            Section(L10n.t("Notes")) {
                TextField(L10n.t("Notes"), text: text(\.notes), axis: .vertical)
                    .lineLimit(2...6)
            }
        }
        .navigationTitle(isNew ? L10n.t("Check ticket") : L10n.t("Edit ticket"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { finish() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
                    .disabled(saving)
                    .accessibilityIdentifier("savePass")
            }
        }
        .alert(L10n.t("Ticket could not be saved"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: error ?? "")
        }
        .interactiveDismissDisabled(isNew)
    }

    @ViewBuilder
    private var codeSection: some View {
        Section {
            if codes.count > 1 {
                Picker(L10n.t("Code"), selection: $codeIndex) {
                    ForEach(codes.indices, id: \.self) { i in
                        Text(verbatim: "\(codes[i].format.title) \(i + 1)").tag(i)
                    }
                    Text("No code").tag(-1)
                }
                .onChange(of: codeIndex) { _, i in pass.barcode = codes.indices.contains(i) ? codes[i] : nil }
            } else if let code = pass.barcode {
                LabeledContent(L10n.t("Code"), value: code.format.title)
                Button(L10n.t("Remove code"), role: .destructive) { pass.barcode = nil; codeIndex = -1 }
            } else if let only = codes.first {
                Button(L10n.f("Use the %@ code", only.format.title)) { pass.barcode = only; codeIndex = 0 }
            } else {
                Text("No code found on this page. Publit shows the original instead.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Code")
        } footer: {
            Text("Only codes that stay the same work here. Codes that change every few seconds only work in the operator's app.")
        }
    }

    private var swatches: some View {
        let presets = PassStyle.presets
        let extra = colorFromTicket.map { PassStyle.Preset(style: PassStyle(background: $0), name: L10n.t("From ticket")) }
        let all = (extra.map { [$0] } ?? []) + presets.filter { $0.style != extra?.style }
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 12)], spacing: 12) {
            ForEach(all) { preset in
                Button { pass.style = preset.style } label: {
                    Circle()
                        .fill(Color(hex: preset.style.background) ?? .black)
                        .overlay(Circle().stroke(Color.primary.opacity(0.15), lineWidth: 1))
                        .overlay {
                            if pass.style == preset.style {
                                Image(systemName: "checkmark").font(.headline)
                                    .foregroundStyle(Color(hex: preset.style.foreground) ?? .white)
                            }
                        }
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(preset.name)
                .accessibilityAddTraits(pass.style == preset.style ? .isSelected : [])
            }
        }
        .padding(.vertical, 6)
    }

    private func text(_ path: WritableKeyPath<TicketPass, String?>) -> Binding<String> {
        Binding(get: { pass[keyPath: path] ?? "" },
                set: { pass[keyPath: path] = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 })
    }

    @ViewBuilder
    private func dateRow(_ title: String, _ path: WritableKeyPath<TicketPass, Date?>, end: Bool) -> some View {
        Toggle(title, isOn: Binding(get: { pass[keyPath: path] != nil }, set: { on in
            let calendar = Calendar.current
            let start = calendar.startOfDay(for: .now)
            pass[keyPath: path] = on ? (end ? calendar.date(byAdding: .second, value: 86_399, to: start) : start) : nil
        }))
        if let value = pass[keyPath: path] {
            DatePicker(title, selection: Binding(get: { value }, set: { pass[keyPath: path] = $0 }))
                .labelsHidden()
        }
    }

    private func save() async {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        if let from = pass.validFrom, let until = pass.validUntil, from > until {
            (pass.validFrom, pass.validUntil) = (until, from)
        }
        switch mode {
        case .new(_, let document, let kind, let page, _, _):
            do {
                try await store.add(pass, document: document, kind: kind, page: page)
                finish()
            } catch {
                self.error = error.localizedDescription
            }
        case .edit:
            store.update(pass)
            finish()
        }
    }

    private func finish() {
        if let onFinish { onFinish() } else { dismiss() }
    }
}
