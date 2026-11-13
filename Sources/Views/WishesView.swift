import SwiftUI

/// Suggest features and vote for them, right in the app: the same wish list as publit.eu/wuensche.
/// No account; a random ID kept on this device marks your votes.
struct WishesView: View {
    @State private var sort: WishesClient.Sort = .top
    @State private var wishes: [Wish] = []
    @State private var loaded = false
    @State private var failed = false
    @State private var busy: Set<Int> = []
    @State private var title = ""
    @State private var details = ""
    @State private var sending = false
    @State private var message: (text: String, isError: Bool)?
    @FocusState private var focused: Bool
    private let client = WishesClient()

    var body: some View {
        List {
            Section {
                TextField(L10n.t("What should Publit do?"), text: $title)
                    .focused($focused)
                    .submitLabel(.next)
                    .accessibilityIdentifier("wishTitle")
                TextField(L10n.t("Details (optional)"), text: $details, axis: .vertical)
                    .lineLimit(2...6)
                    .accessibilityIdentifier("wishBody")
                Button {
                    Task { await send() }
                } label: {
                    HStack {
                        Text("Send wish")
                        if sending { Spacer(); ProgressView() }
                    }
                }
                .disabled(sending || title.trimmingCharacters(in: .whitespacesAndNewlines).count < WishesClient.minTitle)
                .accessibilityIdentifier("wishSend")
                if let message {
                    Text(verbatim: message.text)
                        .font(.subheadline)
                        .foregroundStyle(message.isError ? Color.delay : Color.secondary)
                }
            } header: {
                Text("Suggest a feature")
            } footer: {
                Text("Check the list first: if your idea is there, vote for it instead.")
            }

            Section {
                Picker(L10n.t("Sort"), selection: $sort) {
                    Text("Most votes").tag(WishesClient.Sort.top)
                    Text("Newest").tag(WishesClient.Sort.new)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                if failed {
                    EmptyState(title: L10n.t("Wishes not reachable"), systemImage: "wifi.slash",
                               message: L10n.t("The wish list is not reachable right now. Please try again later.")) {
                        Button("Try again") { Task { await load() } }.buttonStyle(.soft)
                    }
                } else if !loaded {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if wishes.isEmpty {
                    EmptyState(title: L10n.t("No wishes yet"), systemImage: "lightbulb", message: L10n.t("Be the first!"))
                }
                ForEach(wishes) { w in row(w) }
            } header: {
                Text("Wishes")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No account and no tracking: a random ID on this device marks your votes. The wish list does not store addresses.")
                    Link(destination: WishesClient.pageURL) {
                        Text("Also on publit.eu")
                    }
                }
            }
        }
        .readableWidth()
        .inkList()
        .navigationTitle("Wishes")
        .screenTrail("Wishes")
        .task(id: sort) { await load() }
        .refreshable { await load() }
    }

    private func row(_ w: Wish) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button { Task { await vote(w) } } label: {
                VStack(spacing: 2) {
                    Image(systemName: w.mine ? "arrowtriangle.up.fill" : "arrowtriangle.up")
                    Text(verbatim: "\(w.votes)").font(.subheadline.weight(.bold)).monospacedDigit()
                }
                .frame(width: 44, height: 44)
                .foregroundStyle(w.mine ? Color.inkAction : Color.primary)
            }
            .buttonStyle(.borderless)
            .disabled(busy.contains(w.id))
            .accessibilityLabel(L10n.f("Vote for %@", w.title))
            .accessibilityValue(Text(verbatim: "\(w.votes)"))
            .accessibilityAddTraits(w.mine ? .isSelected : [])
            .accessibilityIdentifier("wishVote")
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: w.title).font(.headline)
                if !w.body.isEmpty {
                    Text(verbatim: w.body).font(.subheadline).foregroundStyle(.secondary).lineLimit(6)
                }
                if let state = statusTitle(w.status) {
                    Text(state)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Capsule().fill(Color.inkAction.opacity(0.15)))
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func statusTitle(_ s: Wish.Status) -> String? {
        switch s {
        case .open: return nil
        case .planned: return L10n.t("Planned")
        case .doing: return L10n.t("In progress")
        case .done: return L10n.t("Done")
        }
    }

    private func load() async {
        do {
            wishes = try await client.list(sort: sort)
            failed = false
        } catch {
            failed = wishes.isEmpty
        }
        loaded = true
    }

    private func vote(_ w: Wish) async {
        busy.insert(w.id)
        defer { busy.remove(w.id) }
        do {
            let r = try await client.toggleVote(w.id)
            if let i = wishes.firstIndex(where: { $0.id == w.id }) {
                wishes[i].votes = r.votes
                wishes[i].mine = r.mine
            }
        } catch {
            message = (text(for: error), true)
        }
    }

    private func send() async {
        sending = true
        defer { sending = false }
        do {
            try await client.suggest(title: title, body: details)
            title = ""; details = ""; focused = false
            message = (L10n.t("Thanks! Your wish is in."), false)
            if sort == .new { await load() } else { sort = .new }
        } catch {
            message = (text(for: error), true)
        }
    }

    private func text(for error: Error) -> String {
        switch error as? WishesClient.Failure {
        case .tooShort: return L10n.t("Please describe the wish in at least 6 characters.")
        case .links: return L10n.t("At most two links, please.")
        case .exists: return L10n.t("This wish already exists – just vote for it.")
        case .slowDown: return L10n.t("Too many requests. Please wait a moment.")
        default: return L10n.t("The wish list is not reachable right now. Please try again later.")
        }
    }
}

/// Shown once after the update that brought the wish list: where to suggest and vote.
struct WishesHint: ViewModifier {
    static let shownKey = "wishesHintShown"
    @AppStorage(WishesHint.shownKey) private var shown = false
    /// Not over the first-run onboarding: there the app is new anyway.
    let ready: Bool
    @State private var presented = false
    @State private var openList = false

    func body(content: Content) -> some View {
        content
            .task(id: ready) {
                guard ready, !shown else { return }
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled, !shown else { return }
                presented = true
            }
            .sheet(isPresented: $presented, onDismiss: { shown = true }) {
                NavigationStack {
                    if openList {
                        WishesView()
                            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { presented = false } } }
                    } else {
                        VStack(spacing: 18) {
                            Spacer(minLength: 0)
                            Image(systemName: "lightbulb.max")
                                .font(.system(size: 44)).foregroundStyle(Color.inkAction)
                                .accessibilityHidden(true)
                            Text("New: suggest features and vote").font(.title2.weight(.bold)).multilineTextAlignment(.center)
                            Text("Missing something in Publit? Suggest it or vote for other ideas. The most wanted ones come first. You find the list any time in Settings.")
                                .multilineTextAlignment(.center).foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                            Button { shown = true; openList = true } label: {
                                Text("Show the wishes").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.ink)
                            .accessibilityIdentifier("wishesHintOpen")
                            Button("Later") { shown = true; presented = false }
                                .accessibilityIdentifier("wishesHintLater")
                        }
                        .padding(24)
                    }
                }
                .presentationDetents(openList ? [.large] : [.medium, .large])
            }
    }
}

extension View {
    /// The one-time note about the wish list, once `ready` (onboarding done).
    func wishesHint(ready: Bool) -> some View { modifier(WishesHint(ready: ready)) }
}
