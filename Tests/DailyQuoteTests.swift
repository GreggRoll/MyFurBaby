import XCTest
@testable import MyFurBaby

private final class QuoteURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    static var delay: TimeInterval = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler!(request)
            let deliver = {
                let response = HTTPURLResponse(url: self.request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                self.client?.urlProtocol(self, didLoad: data)
                self.client?.urlProtocolDidFinishLoading(self)
            }
            if Self.delay > 0 { DispatchQueue.global().asyncAfter(deadline: .now() + Self.delay, execute: deliver) }
            else { deliver() }
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@MainActor final class DailyQuoteTests: XCTestCase {
    private var directory: URL!
    private var network: URLSession!
    private var service: DailyQuoteService!
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }
    private func date(day: Int, hour: Int = 8, month: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }
    private func payload(content: String = "A short quote for testing.", author: String = "Test author") throws -> Data {
        try JSONSerialization.data(withJSONObject: [["q": content, "a": author]])
    }
    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("quote-tests-\(UUID().uuidString)")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [QuoteURLProtocol.self]
        network = URLSession(configuration: configuration)
        service = DailyQuoteService(network: network, directory: directory)
        QuoteURLProtocol.delay = 0
    }
    override func tearDown() async throws {
        network.invalidateAndCancel()
        QuoteURLProtocol.handler = nil
        QuoteURLProtocol.delay = 0
        try? FileManager.default.removeItem(at: directory)
    }

    func testFetchesOneQuoteWithAuthorAndReusesItAllDayAndAfterRelaunch() async throws {
        var calls = 0
        let data = try payload()
        QuoteURLProtocol.handler = { request in
            calls += 1
            XCTAssertEqual(request.url?.host, "zenquotes.io")
            XCTAssertEqual(request.url?.path, "/api/today")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertNil(request.url?.query)
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            return (200, data)
        }
        let first = await service.quote(at: date(day: 9), calendar: calendar)
        XCTAssertEqual(first?.author, "Test author")
        XCTAssertEqual(first?.content, "A short quote for testing.")
        let evening = await service.quote(at: date(day: 9, hour: 23), calendar: calendar)
        let relaunched = DailyQuoteService(network: network, directory: directory)
        let restored = await relaunched.quote(at: date(day: 9, hour: 23), calendar: calendar)
        XCTAssertEqual(evening, first); XCTAssertEqual(restored, first)
        XCTAssertEqual(calls, 1)
    }

    func testFetchesAnotherQuoteAfterLocalMidnightIncludingDaylightSavingChange() async throws {
        var calls = 0
        let firstData = try payload(), secondData = try payload(content: "Another quote.")
        QuoteURLProtocol.handler = { _ in calls += 1; return (200, calls == 1 ? firstData : secondData) }
        let first = await service.quote(at: date(day: 1, hour: 0, month: 11), calendar: calendar)
        let sameDay = await service.quote(at: date(day: 1, hour: 23, month: 11), calendar: calendar)
        let nextDay = await service.quote(at: date(day: 2, hour: 0, month: 11), calendar: calendar)
        XCTAssertEqual(first, sameDay); XCTAssertEqual(nextDay?.content, "Another quote.")
        XCTAssertEqual(calls, 2)
    }

    func testCertificateFailurePreservesLastQuoteThrottlesRetriesAndRecovers() async throws {
        var calls = 0
        let data = try payload()
        QuoteURLProtocol.handler = { _ in calls += 1; return (200, data) }
        let saved = await service.quote(at: date(day: 9), calendar: calendar)
        QuoteURLProtocol.handler = { _ in calls += 1; throw URLError(.serverCertificateUntrusted) }
        let failed = await service.quote(at: date(day: 10), calendar: calendar)
        let relaunched = DailyQuoteService(network: network, directory: directory)
        let throttled = await relaunched.quote(at: date(day: 10).addingTimeInterval(60), calendar: calendar)
        XCTAssertEqual(failed, saved); XCTAssertEqual(throttled, saved)
        XCTAssertEqual(calls, 2)
        let newData = try payload(content: "Recovered quote.")
        QuoteURLProtocol.handler = { _ in calls += 1; return (200, newData) }
        let recovered = await service.quote(at: date(day: 10).addingTimeInterval(1800), calendar: calendar)
        XCTAssertEqual(recovered?.content, "Recovered quote."); XCTAssertEqual(calls, 3)
    }

    func testSeparateAppAndWidgetClientsDeduplicateConcurrentRequests() async throws {
        var calls = 0
        let started = expectation(description: "Quote request started"), data = try payload()
        QuoteURLProtocol.delay = 0.3
        QuoteURLProtocol.handler = { _ in calls += 1; started.fulfill(); return (200, data) }
        let widget = DailyQuoteService(network: network, directory: directory)
        let day = date(day: 9), calendar = calendar
        async let first = service.quote(at: day, calendar: calendar)
        await fulfillment(of: [started], timeout: 2)
        let concurrent = await widget.quote(at: day, calendar: calendar)
        XCTAssertNil(concurrent)
        let saved = await first
        let shared = await widget.quote(at: day, calendar: calendar)
        XCTAssertEqual(saved, shared); XCTAssertEqual(calls, 1)
    }

    func testUnavailableAndInvalidResponsesNeverBecomeQuotes() async throws {
        let invalid = [Data("[]".utf8), Data("not JSON".utf8), try payload(content: " "),
                       try payload(content: String(repeating: "a", count: 2001)), try payload(author: " "), try payload(content: "Too many requests", author: "zenquotes.io")]
        for (index, data) in invalid.enumerated() {
            QuoteURLProtocol.handler = { _ in (200, data) }
            let result = await service.quote(at: date(day: 9 + index), calendar: calendar)
            XCTAssertNil(result)
        }
        let valid = try payload()
        QuoteURLProtocol.handler = { _ in (503, valid) }
        let unavailable = await service.quote(at: date(day: 20), calendar: calendar)
        XCTAssertNil(unavailable); XCTAssertNil(service.cachedQuote())
    }

    func testDailyEndpointQuotesLongerThanQuotablesOldLimitKeepTheirFullText() async throws {
        let content = String(repeating: "A longer daily quote. ", count: 10)
        let data = try payload(content: content)
        QuoteURLProtocol.handler = { _ in (200, data) }
        let quote = await service.quote(at: date(day: 9), calendar: calendar)
        XCTAssertEqual(quote?.content, content.trimmingCharacters(in: .whitespacesAndNewlines))
        XCTAssertEqual(quote?.author, "Test author")
    }

    func testWidgetSnapshotCarriesQuoteAndOldSnapshotsStillDecode() throws {
        let quote = DailyQuote(id: "one", content: "A short quote.", author: "Test author", fetchedAt: date(day: 9))
        let snapshot = WidgetSnapshot(rightSide: .dailyQuote, dailyQuote: quote)
        let restored = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(restored.dailyQuote, quote)
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        old.removeValue(forKey: "dailyQuote")
        let legacy = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertNil(legacy.dailyQuote); XCTAssertEqual(legacy.resolvedRightSide, .dailyQuote)
    }
}
