import Foundation
import Darwin
import CryptoKit

/// The app and widget share one saved quote. A file lock also deduplicates requests
/// when their separate processes refresh at the same time.
actor DailyQuoteService {
    static let shared = DailyQuoteService()
    private let network: URLSession
    private let cacheURL: URL
    private let retryInterval: TimeInterval = 30 * 60

    init(network: URLSession = .shared, directory: URL = SharedStorage.directory) {
        self.network = network
        // Keep the provider cache separate so an old Quotable result/failure cannot
        // prevent the first ZenQuotes request or carry the wrong attribution.
        cacheURL = directory.appendingPathComponent("daily-quote-zenquotes.json")
    }

    nonisolated func cachedQuote() -> DailyQuote? { loadCache().quote }

    func quote(at date: Date = Date(), calendar: Calendar = .current) async -> DailyQuote? {
        var cache = loadCache()
        if cache.quote?.isCurrent(at: date, calendar: calendar) == true { return cache.quote }
        do { try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true) }
        catch { return cache.quote }

        let descriptor = open(cacheURL.path + ".lock", O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { return cache.quote }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { return loadCache().quote }
        defer { flock(descriptor, LOCK_UN) }

        cache = loadCache()
        if cache.quote?.isCurrent(at: date, calendar: calendar) == true { return cache.quote }
        if let attempt = cache.lastAttempt, (0..<retryInterval).contains(date.timeIntervalSince(attempt)) { return cache.quote }
        cache.lastAttempt = date
        // Persist the attempt before starting so failed requests/relaunches are throttled too.
        do { try save(cache) } catch { return cache.quote }

        do {
            var request = URLRequest(url: URL(string: "https://zenquotes.io/api/today")!)
            request.timeoutInterval = 12
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await network.data(for: request)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                  data.count <= 32_768,
                  let result = try JSONDecoder().decode([ZenQuote].self, from: data).first else { return cache.quote }
            let content = result.q.trimmingCharacters(in: .whitespacesAndNewlines)
            let author = result.a.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty, content.count <= 2000, !author.isEmpty, author.count <= 100,
                  !["zenquotes.io", "zenquotes", "zenquotes api"].contains(author.lowercased()) else { return cache.quote }
            let id = SHA256.hash(data: Data("\(content)\n\(author)".utf8)).map { String(format: "%02x", $0) }.joined()
            let quote = DailyQuote(id: id, content: content, author: author, fetchedAt: date)
            cache.quote = quote
            try save(cache)
            return quote
        } catch {
            // A network, certificate, or decoding failure keeps the last real quote available.
            return loadCache().quote
        }
    }

    private nonisolated func loadCache() -> Cache {
        guard let data = try? Data(contentsOf: cacheURL),
              let cache = try? JSONDecoder().decode(Cache.self, from: data) else { return Cache() }
        return cache
    }
    private func save(_ cache: Cache) throws {
        try JSONEncoder().encode(cache).write(to: cacheURL, options: .atomic)
    }
    private struct Cache: Codable {
        var quote: DailyQuote?
        var lastAttempt: Date?
    }
    private struct ZenQuote: Decodable {
        var q: String
        var a: String
    }
}
