// Tests of the Calculator stores' pure rules (Sources/CalculatorStores.swift): when rates are
// fetched, how a Frankfurter response decodes, and how the result history changes.
import Foundation
import Testing
@testable import DynamicNotchApp   // the CLT harness library and the Xcode test-support library

private let t0 = Date(timeIntervalSince1970: 1_792_400_000)

@Suite("Calculator stores")
struct CalculatorStoreTests {

    private func table(fetched offset: TimeInterval) -> CalculatorRateTable {
        CalculatorRateTable(base: "USD", date: "2026-10-16", rates: ["EUR": 0.9], fetchedAt: t0.addingTimeInterval(offset))
    }

    // MARK: Rates policy

    @Test func staleness() {
        #expect(CalculatorRatesPolicy.isStale(nil, now: t0))
        #expect(!CalculatorRatesPolicy.isStale(table(fetched: -3599), now: t0))
        #expect(!CalculatorRatesPolicy.isStale(table(fetched: -3600), now: t0))
        #expect(CalculatorRatesPolicy.isStale(table(fetched: -3601), now: t0))
        #expect(!CalculatorRatesPolicy.isStale(table(fetched: 600), now: t0))    // clock moved back
    }

    @Test func fetchDecision() {
        let stale = table(fetched: -7200)
        #expect(CalculatorRatesPolicy.shouldFetch(table: stale, now: t0, inFlight: false, lastErrorAt: nil))
        #expect(!CalculatorRatesPolicy.shouldFetch(table: stale, now: t0, inFlight: true, lastErrorAt: nil))
        #expect(!CalculatorRatesPolicy.shouldFetch(table: table(fetched: -60), now: t0, inFlight: false, lastErrorAt: nil))
        // after a failure: wait a minute
        #expect(!CalculatorRatesPolicy.shouldFetch(table: nil, now: t0, inFlight: false, lastErrorAt: t0.addingTimeInterval(-30)))
        #expect(CalculatorRatesPolicy.shouldFetch(table: nil, now: t0, inFlight: false, lastErrorAt: t0.addingTimeInterval(-61)))
    }

    // MARK: Frankfurter

    @Test func decodesFrankfurter() throws {
        let json = #"{"amount":1.0,"base":"usd","date":"2026-10-16","rates":{"EUR":0.9,"JPY":150.5}}"#
        let t = try CalculatorRateTable.decodeFrankfurter(Data(json.utf8), fetchedAt: t0)
        #expect(t.base == "USD")
        #expect(t.date == "2026-10-16")
        #expect(t.rates == ["EUR": 0.9, "JPY": 150.5])
        #expect(t.fetchedAt == t0)
        #expect(t.rate(from: "EUR", to: "JPY")! - 150.5 / 0.9 < 1e-9)
    }

    @Test func rejectsEmptyOrBrokenResponses() {
        #expect(throws: (any Error).self) {
            try CalculatorRateTable.decodeFrankfurter(Data(#"{"base":"USD","date":"x","rates":{}}"#.utf8), fetchedAt: t0)
        }
        #expect(throws: (any Error).self) {
            try CalculatorRateTable.decodeFrankfurter(Data(#"{"message":"not found"}"#.utf8), fetchedAt: t0)
        }
    }

    @Test func rateTableCacheRoundTrip() throws {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        let t = table(fetched: 0)
        #expect(try d.decode(CalculatorRateTable.self, from: e.encode(t)) == t)
    }

    // MARK: History

    @Test func historyAddsOnTopAndDedupesByExpression() throws {
        var items: [CalculatorHistoryItem] = []
        items = try #require(CalculatorHistoryList.adding(expression: "1+1", result: "2", number: 2, date: t0, to: items, limit: 10))
        items = try #require(CalculatorHistoryList.adding(expression: "2*3", result: "6", number: 6, date: t0, to: items, limit: 10))
        items = try #require(CalculatorHistoryList.adding(expression: "  1+1 \n", result: "2", number: 2, date: t0, to: items, limit: 10))
        #expect(items.map(\.expression) == ["1+1", "2*3"])
    }

    @Test func historyRejectsEmpty() {
        #expect(CalculatorHistoryList.adding(expression: "  ", result: "2", number: nil, date: t0, to: [], limit: 10) == nil)
        #expect(CalculatorHistoryList.adding(expression: "1+1", result: "", number: nil, date: t0, to: [], limit: 10) == nil)
    }

    @Test func historyLimit() throws {
        var items: [CalculatorHistoryItem] = []
        for i in 0..<15 {
            items = try #require(CalculatorHistoryList.adding(expression: "\(i)", result: "\(i)", number: Double(i), date: t0, to: items, limit: 10))
        }
        #expect(items.count == 10)
        #expect(items.first?.expression == "14")
        #expect(items.last?.expression == "5")
    }

    @Test func ansIsNewestNumber() throws {
        var items: [CalculatorHistoryItem] = []
        #expect(CalculatorHistoryList.ans(in: items) == nil)
        items = try #require(CalculatorHistoryList.adding(expression: "2*3", result: "6", number: 6, date: t0, to: items, limit: 10))
        items = try #require(CalculatorHistoryList.adding(expression: "15:00 JST in PST", result: "23:00 PDT", number: nil, date: t0, to: items, limit: 10))
        #expect(CalculatorHistoryList.ans(in: items) == 6)
    }
}
