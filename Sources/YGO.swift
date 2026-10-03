import Foundation

enum GameFormat: String, CaseIterable, Codable, Sendable {
    case masterDuel = "Master Duel", genesys = "Genesys", tcg = "TCG", ocg = "OCG", goat = "GOAT", edison = "Edison"
    var categories: [String] {
        switch self {
        case .masterDuel: return ["Master Duel Decks"]
        case .genesys: return ["Genesys Decks", "Tournament Meta Decks (Genesys)"]
        case .tcg: return ["Meta Decks", "Non-Meta Decks", "Fun/Casual Decks", "Tournament Meta Decks"]
        case .ocg: return ["Tournament Meta Decks OCG"]
        case .goat: return ["Goat Format Decks"]
        case .edison: return ["Edison Format Decks"]
        }
    }
    var provider: String { self == .masterDuel ? "Master Duel Meta" : "YGOPRODeck" }
}
enum EventTier: String, CaseIterable, Codable, Sendable {
    case any = "All events", competitive = "Tier 2+ · Competitive", premier = "Tier 3 · Premier"
    var parameter: String { switch self { case .any: return "any"; case .competitive: return "tier-2"; case .premier: return "tier-3" } }
}
struct CardInfo: Identifiable, Codable, Sendable {
    let id: String
    let name: String
    let type: String
    let description: String
    let race: String
    let attribute: String
    let archetype: String
    let atk: Int?
    let def: Int?
    let level: Int?
    let formats: [String]
    let genesysPoints: Int?
    let mdRarity: String
    let link: String
    let aliases: [String]
    var imageURL: String? = nil
    var banlist: [String:String]? = nil
}
struct CardDatabase: Codable, Sendable {
    let fetched: Date
    let cards: [CardInfo]
    var index: [String: CardInfo] {
        var result: [String: CardInfo] = [:]
        for c in cards { result[c.id] = c; result[c.name.lowercased()] = c; for alias in c.aliases { result[alias] = c } }
        return result
    }
}
actor YGO {
    static let shared = YGO()
    private var database: CardDatabase?
    private var pointsDatabase: CardDatabase?
    static func request(_ address: String, items: [URLQueryItem] = []) async throws -> Data {
        var url = URLComponents(string: address)!; if !items.isEmpty { url.queryItems = items }
        var req = URLRequest(url: url.url!); req.timeoutInterval = 90; req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status != 200 {
            let message = ((try? JSONSerialization.jsonObject(with:data)) as? [String:Any])?["error"] as? String
            if address == "https://ygoprodeck.com/api/decks/getDecks.php", status == 400, message == "No decks matching your query were found in the database." { return data }
            throw DataError.message("YGOPRODeck is unavailable (HTTP \(status)). \(message ?? "Try again later.")")
        }
        return data
    }
    static func parseCards(_ data: Data) throws -> CardDatabase {
        guard let object = try JSONSerialization.jsonObject(with:data) as? [String:Any], let a = object["data"] as? [[String:Any]] else { throw DataError.message("YGOPRODeck returned unexpected card data.") }
        let cards: [CardInfo] = try a.map { d in
            guard let id = d["id"] as? Int, let name = d["name"] as? String else { throw DataError.message("YGOPRODeck returned an invalid card.") }
            let misc = (d["misc_info"] as? [[String:Any]])?.first ?? [:]
            let images = d["card_images"] as? [[String:Any]] ?? []
            return CardInfo(id:String(id), name:name, type:d["type"] as? String ?? "", description:d["desc"] as? String ?? "", race:d["race"] as? String ?? "", attribute:d["attribute"] as? String ?? "", archetype:d["archetype"] as? String ?? "", atk:d["atk"] as? Int, def:d["def"] as? Int, level:d["level"] as? Int, formats:misc["formats"] as? [String] ?? [], genesysPoints:(misc["genesys_points"] as? Int) ?? (misc["genesys_points"] as? String).flatMap(Int.init), mdRarity:misc["md_rarity"] as? String ?? "", link:d["ygoprodeck_url"] as? String ?? "", aliases: images.compactMap { ($0["id"] as? Int).map(String.init) }, imageURL: images.first?["image_url"] as? String, banlist:d["banlist_info"] as? [String:String] ?? [:])
        }
        return CardDatabase(fetched:Date(),cards:cards)
    }
    func cardDatabase(genesys: Bool = false, force: Bool = false) async throws -> CardDatabase {
        let name = genesys ? "ygo-genesys-cards.json" : "ygo-cards.json"
        let store = try LocalStore()
        let memory = genesys ? pointsDatabase : database
        let cached = try memory ?? store.read(name,as:CardDatabase.self)
        if !force, let cached, cached.cards.first?.banlist != nil, Date().timeIntervalSince(cached.fetched) < 172800 {
            if genesys { pointsDatabase = cached } else { database = cached }; return cached
        }
        do {
            var items = [URLQueryItem(name:"misc",value:"yes")]
            if genesys { items.append(.init(name:"format",value:"genesys")) }
            let loaded = try Self.parseCards(await Self.request("https://db.ygoprodeck.com/api/v7/cardinfo.php",items:items))
            try store.write(loaded,name:name)
            if genesys { pointsDatabase = loaded } else { database = loaded }
            return loaded
        } catch { if let cached, !force { return cached }; throw error }
    }
    static func archetypes() async throws -> [DeckType] {
        let data = try await request("https://db.ygoprodeck.com/api/v7/archetypes.php")
        guard let a = try JSONSerialization.jsonObject(with:data) as? [[String:String]] else { throw DataError.message("YGOPRODeck's archetype catalogue could not be read.") }
        return a.compactMap { $0["archetype_name"] }.map { DeckType(id:"ygo:" + $0,name:$0) }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    static func parseDecks(_ data: Data, type: DeckType, format: GameFormat, cards: [String:CardInfo]) throws -> [Deck] {
        let raw = try JSONSerialization.jsonObject(with:data)
        if let error = (raw as? [String:Any])?["error"] as? String {
            if error == "No decks matching your query were found in the database." { return [] }
            throw DataError.message(error)
        }
        guard let a = raw as? [[String:Any]] else { throw DataError.message("YGOPRODeck returned unexpected deck data. No partial dataset was loaded.") }
        return try a.map { d in
            guard let id = d["deckNum"] as? Int, let category = d["format"] as? String,
                  format.categories.contains(where: { $0.caseInsensitiveCompare(category) == .orderedSame }),
                  let slug = d["pretty_url"] as? String, let date = d["submit_date"] as? String else { throw DataError.message("YGOPRODeck returned a deck outside the selected format or with missing metadata.") }
            func entries(_ key: String) throws -> [Entry] {
                guard let text = d[key] as? String else { if d[key] == nil || d[key] is NSNull { return [] }; throw DataError.message("Unexpected \(key) data.") }
                guard let rawCards = try JSONSerialization.jsonObject(with:Data(text.utf8)) as? [Any] else { throw DataError.message("Could not read \(key).") }
                var counts: [String:Int] = [:]
                for v in rawCards {
                    guard let id = (v as? String).flatMap(Int.init) ?? v as? Int else { throw DataError.message("A card passcode could not be read.") }
                    let canonical = cards[String(id)]?.id ?? String(id)
                    counts[canonical,default:0] += 1
                }
                return counts.map { id, count in
                    Entry(card:Card(id:"ygo:" + id,name:cards[id]?.name ?? "Unknown card #\(id)",rarity:""),amount:count)
                }.sorted { $0.card.name < $1.card.name }
            }
            let tournament = d["tournamentName"] as? String ?? (category.hasPrefix("Tournament") ? category : "")
            return try Deck(id:"ygo:\(id)",typeID:type.id,typeName:type.id == "all" ? d["deck_name"] as? String ?? "Submitted deck" : type.name,created:"",rank:"",tournament:tournament,placement:d["tournamentPlacement"] as? String ?? "",author:d["tournamentPlayerName"] as? String ?? d["username"] as? String ?? "Unknown",path:"/deck/" + slug,engines:[],flagged:false,main:entries("main_deck"),extra:entries("extra_deck"),side:entries("side_deck"),provider:"YGOPRODeck",format:format.rawValue,dateLabel:date,title:d["deck_name"] as? String)
        }
    }
    static func fetch(type: DeckType, format: GameFormat, from: String, through: String, tier: EventTier, cards: [String:CardInfo], progress: @escaping @Sendable (Int) async -> Void) async throws -> [Deck] {
        var results: [Deck] = []; var seen = Set<String>()
        for category in format.categories {
            var offset = 0
            while true {
                try Task.checkCancellation()
                var items: [URLQueryItem] = [.init(name:"_sft_category",value:category),.init(name:"_sft_post_tag",value:type.id == "all" ? nil : type.name),.init(name:"from",value:from),.init(name:"to",value:through),.init(name:"offset",value:String(offset))]
                if tier != .any { items.append(.init(name:"tournament",value:tier.parameter)) }
                let page = try parseDecks(await request("https://ygoprodeck.com/api/decks/getDecks.php",items:items.filter { $0.value != nil }),type:type,format:format,cards:cards)
                if page.isEmpty { break }
                let fresh = page.filter { seen.insert($0.id).inserted }
                guard !fresh.isEmpty else { throw DataError.message("YGOPRODeck repeated a page. Try again to avoid an incomplete dataset.") }
                results += fresh; offset += page.count; await progress(results.count)
                if page.count < 20 { break }
                try await Task.sleep(for:.milliseconds(150))
            }
        }
        return results
    }
}
