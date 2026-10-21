// Calculator widget (2026-10-20): exchange rates and result history.
//
// Persistence (local only, `~/Library/Application Support/<bundle id>/`):
//   CalculatorRates.json    the last Frankfurter response (all currencies against USD) + fetch time
//   CalculatorHistory.json  the last 10 results ([CalculatorHistoryItem], newest first)
//
// Exchange rates: https://api.frankfurter.app/latest?from=USD (free, no key; ECB reference rates,
// updated on working days ~16:00 CET). One request returns every currency against USD, so any
// pair converts through USD. Cached for 1 h; offline (or on error) the cached table keeps being
// used, however old — the result's detail line shows the rates' date.
//
// The decisions (when to fetch, how a response decodes, how the history list changes) are pure
// functions below the stores (`CalculatorRatesPolicy`, `CalculatorRateTable.decodeFrankfurter`,
// `CalculatorHistoryList`); Tests/EngineTests/CalculatorStoreTests.swift covers them.
import Foundation
import Observation

@MainActor
@Observable
final class CalculatorRatesStore {
    static let shared = CalculatorRatesStore()

    nonisolated static let maxAge: TimeInterval = CalculatorRatesPolicy.maxAge
    nonisolated static let endpoint = URL(string: "https://api.frankfurter.app/latest?from=USD")!

    private(set) var table: CalculatorRateTable?
    private(set) var isFetching = false
    /// The last fetch failed (the cached table, if any, is still used).
    private(set) var lastError: String?

    @ObservationIgnored private var task: Task<Void, Never>?

    private init() {
        table = Self.loadCache()
    }

    var isStale: Bool { CalculatorRatesPolicy.isStale(table, now: Date()) }

    /// Fetches new rates if the cache is older than an hour (or missing). Cheap to call often.
    func refreshIfNeeded() {
        guard CalculatorRatesPolicy.shouldFetch(table: table, now: Date(), inFlight: task != nil,
                                                lastErrorAt: lastErrorAt) else { return }
        isFetching = true
        task = Task { [weak self] in
            let result = await Self.fetch()
            guard let self else { return }
            self.isFetching = false
            self.task = nil
            switch result {
            case .success(let t):
                self.table = t
                self.lastError = nil
                self.lastErrorAt = nil
                Self.saveCache(t)
            case .failure(let e):
                self.lastError = e.localizedDescription
                self.lastErrorAt = Date()
                NSLog("[Calculator] rates fetch failed: %@", "\(e)")
            }
        }
    }

    @ObservationIgnored private var lastErrorAt: Date?

    nonisolated private static func fetch() async -> Result<CalculatorRateTable, Error> {
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return .failure(URLError(.badServerResponse))
            }
            return .success(try CalculatorRateTable.decodeFrankfurter(data, fetchedAt: Date()))
        } catch {
            return .failure(error)
        }
    }

    nonisolated static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "DynamicNotch", isDirectory: true)
    }()
    nonisolated static let cacheURL = directory.appendingPathComponent("CalculatorRates.json")

    nonisolated private static func loadCache() -> CalculatorRateTable? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try? d.decode(CalculatorRateTable.self, from: data)
    }

    nonisolated private static func saveCache(_ t: CalculatorRateTable) {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        guard let data = try? e.encode(t) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: cacheURL, options: .atomic)
    }
}

struct CalculatorHistoryItem: Codable, Identifiable, Equatable, Hashable {
    var id = UUID()
    var expression: String
    var result: String
    /// Numeric value (for `ans` after reusing an item), when there is one.
    var number: Double?
    var date = Date()
}

@MainActor
@Observable
final class CalculatorHistoryStore {
    static let shared = CalculatorHistoryStore()
    static let limit = 10

    private(set) var items: [CalculatorHistoryItem] = []
    /// Previews (DEBUG gallery) never write the history file.
    @ObservationIgnored var persists = true
    /// Serial, so the snapshots reach the disk in the order they were taken (the last one wins).
    @ObservationIgnored private let ioQueue = DispatchQueue(label: "dynamicnotch.calculator-history.io", qos: .utility)

    nonisolated static let historyURL = CalculatorRatesStore.directory.appendingPathComponent("CalculatorHistory.json")

    private init() {
        if let data = try? Data(contentsOf: Self.historyURL) {
            let d = JSONDecoder()
            d.dateDecodingStrategy = .iso8601
            items = (try? d.decode([CalculatorHistoryItem].self, from: data)) ?? []
        }
    }

    /// Adds a result at the top; the same expression moves up instead of appearing twice.
    func add(expression: String, result: String, number: Double?) {
        guard let list = CalculatorHistoryList.adding(expression: expression, result: result, number: number,
                                                      date: Date(), to: items, limit: Self.limit) else { return }
        items = list
        save()
    }

    func delete(_ item: CalculatorHistoryItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func clear() {
        items = []
        save()
    }

    #if DEBUG
    func setPreviewItems(_ preview: [CalculatorHistoryItem]) {
        persists = false
        items = preview
    }
    #endif

    private func save() {
        guard persists else { return }
        let snapshot = items
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? e.encode(snapshot) else { return }
        ioQueue.async {
            try? FileManager.default.createDirectory(at: CalculatorRatesStore.directory, withIntermediateDirectories: true)
            try? data.write(to: Self.historyURL, options: .atomic)
        }
    }
}

// MARK: - Pure rules (tested)

/// When the rates store fetches.
enum CalculatorRatesPolicy {
    /// Rates older than this are refreshed (ECB rates change once per working day).
    static let maxAge: TimeInterval = 3600
    /// After a failed fetch, wait this long before trying again.
    static let retryDelay: TimeInterval = 60

    /// Missing, or older than `maxAge` (a `fetchedAt` in the future — clock moved back — is fresh).
    static func isStale(_ table: CalculatorRateTable?, now: Date) -> Bool {
        guard let table else { return true }
        return now.timeIntervalSince(table.fetchedAt) > maxAge
    }

    static func shouldFetch(table: CalculatorRateTable?, now: Date, inFlight: Bool, lastErrorAt: Date?) -> Bool {
        guard isStale(table, now: now), !inFlight else { return false }
        if let lastErrorAt, now.timeIntervalSince(lastErrorAt) < retryDelay { return false }
        return true
    }
}

extension CalculatorRateTable {
    /// Frankfurter's `/latest` response: `{"amount":1.0,"base":"USD","date":"2026-10-16","rates":{"EUR":0.9,…}}`.
    /// The base code is upper-cased; a response without rates is rejected.
    static func decodeFrankfurter(_ data: Data, fetchedAt: Date) throws -> CalculatorRateTable {
        struct Response: Decodable {
            var base: String
            var date: String
            var rates: [String: Double]
        }
        let r = try JSONDecoder().decode(Response.self, from: data)
        guard !r.rates.isEmpty else { throw URLError(.cannotParseResponse) }
        return CalculatorRateTable(base: r.base.uppercased(), date: r.date, rates: r.rates, fetchedAt: fetchedAt)
    }
}

/// How the result history changes (newest first).
enum CalculatorHistoryList {
    /// `items` with a new entry at the top, or nil when there is nothing to keep (empty expression or
    /// result). The expression is trimmed; an entry with the same expression moves up (with the new
    /// result) instead of appearing twice; the list keeps at most `limit` entries.
    static func adding(expression: String, result: String, number: Double?, date: Date,
                       to items: [CalculatorHistoryItem], limit: Int) -> [CalculatorHistoryItem]? {
        let expr = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expr.isEmpty, !result.isEmpty else { return nil }
        var list = items.filter { $0.expression != expr }
        list.insert(CalculatorHistoryItem(expression: expr, result: result, number: number, date: date), at: 0)
        return Array(list.prefix(max(limit, 1)))
    }

    /// The value of `ans`: the newest entry that has a number (a time-zone answer has none).
    static func ans(in items: [CalculatorHistoryItem]) -> Double? {
        items.first(where: { $0.number != nil })?.number
    }
}
