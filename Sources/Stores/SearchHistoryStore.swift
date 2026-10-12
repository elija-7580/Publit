import Foundation
import Observation

struct RecentSearch: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let from: Endpoint
    let to: Endpoint
    let mode: TimeMode
    let date: Date
    let searchedAt: Date

    /// An old query is repeated with current departures, not with stale search results.
    @MainActor
    func apply(to plan: PlanModel, now: Date = .now) {
        plan.from = from
        plan.to = to
        plan.timeMode = mode == .now || date < now ? .now : mode
        plan.date = max(date, now)
    }
}

@MainActor
@Observable
final class SearchHistoryStore {
    static let shared = SearchHistoryStore()
    private(set) var entries: [RecentSearch] = []
    @ObservationIgnored private let file: JSONFile<[RecentSearch]>
    static let limit = 20

    init(directory: URL? = nil) {
        file = JSONFile(name: "search-history.json", directory: directory)
        entries = Array((file.load() ?? []).sorted { $0.searchedAt > $1.searchedAt }.prefix(Self.limit))
    }

    func record(from: Endpoint, to: Endpoint, mode: TimeMode, date: Date, now: Date = .now) {
        guard from.key != to.key else { return }
        // One entry per origin/destination pair; refreshes never fill the history with duplicates.
        entries.removeAll { $0.from.key == from.key && $0.to.key == to.key }
        entries.insert(RecentSearch(id: UUID().uuidString, from: from, to: to, mode: mode, date: date, searchedAt: now), at: 0)
        entries = Array(entries.prefix(Self.limit))
        file.saveInBackground(entries)
    }

    func remove(_ id: String) { entries.removeAll { $0.id == id }; file.saveInBackground(entries) }
    func clear() { entries = []; file.saveInBackground(entries) }
}
