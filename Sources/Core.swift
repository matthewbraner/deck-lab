import Foundation

func normalizedCardName(_ name: String) -> String {
    name.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:Locale(identifier:"en_US_POSIX")).unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
}

struct DeckType: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String

}
struct Card: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let rarity: String
}
struct Entry: Codable, Sendable { let card: Card; let amount: Int }
struct Deck: Identifiable, Codable, Sendable {
    let id: String
    let typeID: String
    let typeName: String
    let created: String
    let rank: String
    let tournament: String
    let placement: String
    let author: String
    let path: String
    let engines: [String]
    let flagged: Bool
    let main: [Entry]
    let extra: [Entry]
    let side: [Entry]
    var provider: String? = nil
    var format: String? = nil
    var dateLabel: String? = nil
    var title: String? = nil
    var day: String { dateLabel ?? String(created.prefix(10)) }
    var isTournament: Bool { !tournament.isEmpty }
    var isRanked: Bool {
        ["Rookie", "Bronze", "Silver", "Gold", "Platinum", "Diamond", "Master"].contains { rank.hasPrefix($0 + " ") }
        || rank == "Rating Duels" || rank.hasPrefix("Top ") && rank.contains("Rating")
    }
    var isMasterPlus: Bool { rank.hasPrefix("Master ") || rank == "Rating Duels" || rank.hasPrefix("Top ") && rank.contains("Rating") }
    var total: Int { (main + extra + side).reduce(0) { $0 + $1.amount } }
    var sourceURL: URL? {
        guard path.hasPrefix("/"), !path.hasPrefix("//") else { return nil }
        return URL(string: (provider == "YGOPRODeck" ? "https://ygoprodeck.com" : "https://www.masterduelmeta.com/top-decks") + path)
    }
}
enum CardRole: String, CaseIterable, Codable, Sendable { case unclassified = "Unclassified", engine = "Engine", nonEngine = "Non-engine" }
enum DeckSource: String, CaseIterable, Codable { case all = "All submissions", ranked = "Ranked ladder", tournaments = "Tournaments", other = "Events & other" }
enum RankFloor: String, CaseIterable, Codable { case all = "All ranks", master = "Master + Rating", diamond = "Diamond and up", platinum = "Platinum and up" }
enum AverageMode: String, CaseIterable { case all = "All matching decks", included = "Decks running card" }
struct Filters: Codable {
    var source: DeckSource = .all
    var rank: RankFloor = .all
    var exactRank = "All"
    var tournament = "All"
    var excludeFlagged = false
    var requiredCards: [String] = []
    var excludedCards: [String] = []
    func matches(_ d: Deck) -> Bool {
        if excludeFlagged && d.flagged { return false }
        if !requiredCards.isEmpty || !excludedCards.isEmpty {
            let names = Set((d.main + d.extra + d.side).filter { $0.amount > 0 }.map { normalizedCardName($0.card.name) })
            if !requiredCards.allSatisfy({ names.contains(normalizedCardName($0)) }) || excludedCards.contains(where:{ names.contains(normalizedCardName($0)) }) { return false }
        }
        switch source {
        case .all: break
        case .ranked: if !d.isRanked || d.isTournament { return false }
        case .tournaments: if !d.isTournament { return false }
        case .other: if d.isRanked || d.isTournament { return false }
        }
        switch rank {
        case .all: break
        case .master: if !d.isMasterPlus { return false }
        case .diamond: if !d.isMasterPlus && !d.rank.hasPrefix("Diamond ") { return false }
        case .platinum: if !d.isMasterPlus && !d.rank.hasPrefix("Diamond ") && !d.rank.hasPrefix("Platinum ") { return false }
        }
        return (exactRank == "All" || d.rank == exactRank) && (tournament == "All" || d.tournament == tournament)
    }
}
struct CardStats: Identifiable {
    var id: String { card.id }
    let card: Card
    var main = 0
    var extra = 0
    var side = 0
    var included = 0
    var mainIncluded = 0
    var extraIncluded = 0
    var sideIncluded = 0
    var distribution: [Int: Int] = [:]
    var total: Int { main + extra + side }
    func average(_ count: Int, sample: Int, mode: AverageMode) -> Double {
        let denominator = mode == .all ? sample : included
        return denominator == 0 ? 0 : Double(count) / Double(denominator)
    }
}
func aggregate(_ decks: [Deck]) -> [CardStats] {
    var result: [String: CardStats] = [:]
    for deck in decks {
        var counts: [String: (Card, Int, Int, Int)] = [:]
        for (zone, entries) in [deck.main, deck.extra, deck.side].enumerated() {
            for e in entries where e.amount > 0 {
                var v = counts[e.card.id] ?? (e.card, 0, 0, 0)
                if zone == 0 { v.1 += e.amount }; if zone == 1 { v.2 += e.amount }; if zone == 2 { v.3 += e.amount }
                counts[e.card.id] = v
            }
        }
        for (id, v) in counts {
            var s = result[id] ?? CardStats(card: v.0)
            s.main += v.1; s.extra += v.2; s.side += v.3; s.included += 1
            s.mainIncluded += v.1 > 0 ? 1 : 0; s.extraIncluded += v.2 > 0 ? 1 : 0; s.sideIncluded += v.3 > 0 ? 1 : 0
            s.distribution[v.1 + v.2 + v.3, default: 0] += 1
            result[id] = s
        }
    }
    return result.values.sorted { $0.included == $1.included ? $0.card.name < $1.card.name : $0.included > $1.included }
}
enum DataError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let s) = self { return s }; return nil }
}
enum MDM {
    static func array(_ data: Data) throws -> [[String: Any]] {
        let raw = try JSONSerialization.jsonObject(with: data)
        if let a = raw as? [[String: Any]] { return a }
        if let d = raw as? [String: Any], d["_id"] != nil { return [d] }
        throw DataError.message("Master Duel Meta returned an unexpected response. Please try again later.")
    }
    static func types(_ data: Data) throws -> [DeckType] {
        try array(data).map { d in
            guard let id = d["_id"] as? String, let name = d["name"] as? String else { throw DataError.message("A deck type could not be read.") }
            return DeckType(id: id, name: name)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    static func decks(_ data: Data) throws -> [Deck] {
        try array(data).map { d in
            func object(_ key: String) -> [String: Any] { d[key] as? [String: Any] ?? [:] }
            func entries(_ key: String) throws -> [Entry] {
                guard let a = d[key] as? [[String: Any]] else {
                    if d[key] == nil || d[key] is NSNull { return [] }
                    throw DataError.message("The \(key) deck could not be read.")
                }
                return try a.map { e in
                    guard let c = e["card"] as? [String: Any], let id = c["_id"] as? String,
                          let name = c["name"] as? String, let amount = e["amount"] as? Int, amount >= 0 else {
                        throw DataError.message("A card entry could not be read. No partial statistics were loaded.")
                    }
                    return Entry(card: Card(id: id, name: name, rarity: c["rarity"] as? String ?? ""), amount: amount)
                }
            }
            guard let id = d["_id"] as? String, let created = d["created"] as? String,
                  let typeID = object("deckType")["_id"] as? String, let typeName = object("deckType")["name"] as? String else {
                throw DataError.message("A submitted deck could not be read. No partial statistics were loaded.")
            }
            let tournamentType = object("tournamentType")["name"] as? String ?? ""
            return try Deck(id: id, typeID: typeID, typeName: typeName, created: created,
                rank: object("rankedType")["name"] as? String ?? "",
                tournament: d["customTournamentName"] as? String ?? tournamentType,
                placement: d["tournamentPlacement"] as? String ?? "",
                author: d["author"] as? String ?? object("author")["username"] as? String ?? "Unknown",
                path: d["url"] as? String ?? "", engines: (d["engines"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String },
                flagged: d["illegal"] as? Bool ?? false, main: entries("main"), extra: entries("extra"), side: entries("side"))
        }
    }
    static func request(_ path: String, items: [URLQueryItem]) async throws -> Data {
        var url = URLComponents(string: "https://www.masterduelmeta.com/api/v1/" + path)!
        url.queryItems = items
        var req = URLRequest(url: url.url!); req.timeoutInterval = 60
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let r = response as? HTTPURLResponse, r.statusCode == 200 else {
            throw DataError.message("Master Duel Meta is unavailable (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)). Try again shortly.")
        }
        return data
    }
    static func catalogue() async throws -> [DeckType] {
        try types(await request("deck-types", items: [.init(name: "limit", value: "0"), .init(name: "fields", value: "name")]))
    }
    static func fetch(type: DeckType, from: String, before: String, progress: @escaping @Sendable (Int) async -> Void) async throws -> [Deck] {
        var results: [Deck] = []; var seen = Set<String>(); var offset = 0
        // A fixed cutoff prevents newly submitted decks shifting subsequent pages.
        let cutoff = min(before, ISO8601DateFormatter().string(from: Date()))
        while true {
            try Task.checkCancellation()
            let data = try await request("top-decks", items: [
                .init(name: "deckType", value: type.id == "all" ? nil : type.id), .init(name: "created[$gte]", value: from),
                .init(name: "created[$lt]", value: cutoff), .init(name: "sort", value: "-created"),
                .init(name: "limit", value: "200"), .init(name: "skip", value: String(offset)),
                .init(name: "fields", value: "-notes")].filter { $0.value != nil })
            let page = try decks(data)
            if page.isEmpty { break }
            guard page.allSatisfy({ (type.id == "all" || $0.typeID == type.id) && $0.day >= from && $0.created < cutoff }) else {
                throw DataError.message("The source did not honor the selected deck/date filters. Statistics were not loaded.")
            }
            let fresh = page.filter { seen.insert($0.id).inserted }
            guard !fresh.isEmpty else { throw DataError.message("The source repeated a page. Reload to avoid incomplete statistics.") }
            results += fresh; offset += page.count
            await progress(results.count)
            // Continue until an empty page, even if the source applies a lower page limit.
        }
        return results
    }
}
struct Snapshot: Codable { let type: DeckType; let from: String; let through: String; let fetched: Date; let decks: [Deck]; var format: String? = nil; var eventTier: String? = nil }
struct LocalStore {
    let directory: URL
    init(directory: URL? = nil) throws {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DeckLab", isDirectory: true)
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }
    func read<T: Decodable>(_ name: String, as: T.Type) throws -> T? {
        let url = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }
    func write<T: Encodable>(_ value: T, name: String) throws {
        try JSONEncoder().encode(value).write(to: directory.appendingPathComponent(name), options: .atomic)
    }
}
