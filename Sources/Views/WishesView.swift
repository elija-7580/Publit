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

/// After every update: the interactive story (`ReleaseStory`) when one covers the new builds,
/// otherwise a short "What's new" (WhatsNew.entries) with the wish list right below,
/// because Publit is a community project and what comes next is voted on there.
/// Not on a fresh install (the onboarding introduces the app) and never over the onboarding.
struct WhatsNewSheet: ViewModifier {
    @Environment(AppState.self) private var app
    /// Old one-time hint about the wish list; still set so it never comes back.
    static let wishesHintKey = "wishesHintShown"
    /// Captured at launch: true when this start shows the onboarding (fresh install).
    let freshInstall: Bool
    let ready: Bool
    @State private var items: [WhatsNewItem] = []
    @State private var story: ReleaseStory?
    @State private var presented = false
    @State private var openList = false
    @State private var openSupport = false

    func body(content: Content) -> some View {
        content
            .task(id: ready) {
                guard ready else { return }
                let defaults = UserDefaults.standard
                let current = Int(AppInfo.build) ?? 0
                if freshInstall {
                    defaults.set(current, forKey: WhatsNew.seenKey)
                    return
                }
                let seen = defaults.integer(forKey: WhatsNew.seenKey)
                if let found = ReleaseStory.story(seen: seen, current: current) {
                    try? await Task.sleep(for: .seconds(1.2))
                    guard !Task.isCancelled else { return }
                    story = found
                    return
                }
                let new = WhatsNew.items(seen: seen, current: current)
                guard !new.isEmpty else {
                    if current > seen { defaults.set(current, forKey: WhatsNew.seenKey) }
                    return
                }
                try? await Task.sleep(for: .seconds(1.2))
                guard !Task.isCancelled else { return }
                items = new
                presented = true
            }
            .sheet(isPresented: $presented, onDismiss: markSeen) {
                NavigationStack {
                    if openList || openSupport {
                        Group { if openSupport { SupportView() } else { WishesView() } }
                            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { presented = false } } }
                    } else {
                        note
                    }
                }
                .presentationDetents(openList || openSupport ? [.large] : [.medium, .large])
            }
            .fullScreenCover(item: $story, onDismiss: markSeen) { story in
                ReleaseStoryView(story: story, onTry: { target in
                    markSeen()
                    self.story = nil
                    app.tab = target == .plan ? .plan : .nearby
                }, onClose: { self.story = nil })
            }
    }

    private var note: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("What's new in Publit").font(.title2.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: item.symbol)
                            .font(.title3).foregroundStyle(Color.inkAction)
                            .frame(width: 30)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.t(item.title)).font(.headline)
                            Text(L10n.t(item.text)).font(.subheadline).foregroundStyle(.secondary)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
                CommunityCard(open: { markSeen(); openList = true }, support: { markSeen(); openSupport = true })
                Button { presented = false } label: { Text("Continue").frame(maxWidth: .infinity) }
                    .buttonStyle(.soft)
                    .accessibilityIdentifier("whatsNewContinue")
            }
            .padding(24)
        }
        .accessibilityIdentifier("whatsNew")
    }

    private func markSeen() {
        UserDefaults.standard.set(Int(AppInfo.build) ?? 0, forKey: WhatsNew.seenKey)
        UserDefaults.standard.set(true, forKey: Self.wishesHintKey)
    }
}

/// "Publit is a community project": the way to the wish list, used at the top of Settings and
/// in the What's new note.
struct CommunityCard: View {
    let open: () -> Void
    /// Support Publit (monthly or one-time); nil hides the button.
    var support: (() -> Void)? = nil
    /// Its own rounded box; off inside a List row, which already draws one (in Settings the box
    /// sat apart from the "What's new" row below it).
    var boxed = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Not a Label: in a List, Label puts the icon in a fixed narrow column, and the wide
            // three-person symbol stuck out to the left of the text.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "person.3.fill")
                Text("Publit is a community project")
            }
            .font(.headline)
            .accessibilityElement(children: .combine)
            Text("Vote for what comes next, or suggest your own idea. No account needed.")
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: open) {
                Label("Suggest features and vote", systemImage: "lightbulb").frame(maxWidth: .infinity)
            }
            .buttonStyle(.ink)
            .accessibilityIdentifier("wishesOpen")
            if let support {
                Button(action: support) {
                    Label("Support Publit", systemImage: "heart").frame(maxWidth: .infinity)
                }
                .buttonStyle(.soft)
                .accessibilityIdentifier("supportOpen")
            }
        }
        .padding(boxed ? 16 : 0)
        .background(boxed ? Color.inkFill : .clear, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

extension View {
    /// The note after an update, once `ready` (onboarding done, splash gone).
    func whatsNew(freshInstall: Bool, ready: Bool) -> some View {
        modifier(WhatsNewSheet(freshInstall: freshInstall, ready: ready))
    }
}
