import Foundation

func collectionKey(_ name: String) -> String {
    name.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:Locale(identifier:"en_US_POSIX")).unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
}
struct TCGProduct: Identifiable, Codable, Hashable, Sendable {
    let id: Int
    let name: String
    let rarity: String
    let set: String
    let number: String
    let indicativeLow: Double?
    var label: String { "\(rarity) · \(set)\(number.isEmpty ? "" : " · " + number)" }
    var url: URL { URL(string:"https://www.tcgplayer.com/product/\(id)")! }
}
struct TCGSKU: Codable, Hashable, Sendable { let condition: String; let edition: String }
struct CardVariant: Identifiable, Codable, Hashable, Sendable {
    let cardName: String
    let product: TCGProduct
    let condition: String
    let edition: String
    var id: String { "\(product.id)|\(condition)|\(edition)|English" }
    var cardKey: String { collectionKey(cardName) }
    var label: String { "\(product.rarity) · \(product.set) · \(edition) · \(condition)" }
}
struct PriceQuote: Codable, Sendable {
    let variantID: String
    let cents: Int
    let shippingCents: Int
    let seller: String
    let listingID: String
    let quantity: Int
    let checked: Date
    let condition: String
    let edition: String
    let verified: Bool
    var isFresh: Bool { Date().timeIntervalSince(checked) >= 0 && Date().timeIntervalSince(checked) < 86400 }
    var freshnessLabel: String { isFresh ? "Cached quote · checked within 24 hours" : "Stale quote · refresh needed" }
}
struct Inventory: Codable {
    var displayNames: [String:String]? = nil
    var variants: [String:CardVariant] = [:]
    var quantities: [String:Int] = [:]
    var targets: [String:String] = [:]
    var unassigned: [String:Int] = [:]
    func owned(_ cardName: String) -> Int {
        let key = collectionKey(cardName)
        return (unassigned[key] ?? 0) + variants.values.filter { $0.cardKey == key }.reduce(0) { $0 + (quantities[$1.id] ?? 0) }
    }
    func target(_ cardName: String) -> CardVariant? { targets[collectionKey(cardName)].flatMap { variants[$0] } }
    func holdings(_ cardName: String) -> [CardVariant] {
        variants.values.filter { $0.cardKey == collectionKey(cardName) && (quantities[$0.id] ?? 0) > 0 }.sorted { $0.label < $1.label }
    }
}
struct BuildTotals {
    var targetCopies = 0
    var coveredCopies = 0
    var missingCopies = 0
    var targetCents = 0
    var missingCents = 0
    var builtCents = 0
    var collectionCents = 0
    var unpricedTargetCopies = 0
    var unpricedMissingCopies = 0
    var unpricedBuiltCopies = 0
    var unpricedCollectionCopies = 0
}
func targetCopies(_ stats: CardStats, sample: Int, roundUp: Bool) -> Int {
    guard sample > 0 else { return 0 }
    let mean = Double(stats.total) / Double(sample)
    return Int(roundUp ? ceil(mean) : mean.rounded())
}
func buildTotals(stats: [CardStats], sample: Int, inventory: Inventory, quotes: [String:PriceQuote], roundUp: Bool) -> BuildTotals {
    var result = BuildTotals()
    for row in stats {
        let target = targetCopies(row,sample:sample,roundUp:roundUp)
        let owned = inventory.owned(row.card.name)
        let used = min(target,owned), missing = max(0,target-owned)
        result.targetCopies += target; result.coveredCopies += used; result.missingCopies += missing
        if let variant = inventory.target(row.card.name), let quote = quotes[variant.id], quote.verified {
            result.targetCents += target * quote.cents; result.missingCents += missing * quote.cents
        } else { result.unpricedTargetCopies += target; result.unpricedMissingCopies += missing }
        // Attribute copies in the build to the selected target printing first, then other owned printings.
        let selected = inventory.target(row.card.name)?.id
        let holdings = inventory.holdings(row.card.name).sorted { a,b in
            if a.id == selected { return b.id != selected }; if b.id == selected { return false }; return a.id < b.id
        }
        var remaining = used
        for variant in holdings {
            let count = inventory.quantities[variant.id] ?? 0
            let allocated = min(remaining,count); remaining -= allocated
            if let quote = quotes[variant.id], quote.verified {
                result.collectionCents += count * quote.cents; result.builtCents += allocated * quote.cents
            } else { result.unpricedCollectionCopies += count; result.unpricedBuiltCopies += allocated }
        }
        result.unpricedCollectionCopies += inventory.unassigned[collectionKey(row.card.name)] ?? 0
        result.unpricedBuiltCopies += remaining
    }
    return result
}
struct ProductCache: Codable { let fetched: Date; let products: [TCGProduct] }
struct SKUCache: Codable { let fetched: Date; let skus: [TCGSKU] }
actor TCG {
    static let shared = TCG()
    private var products: [String:ProductCache] = [:]
    private var details: [String:SKUCache] = [:]
    private let transport: TCGTransport
    init(transport: TCGTransport = TCGTransport()) { self.transport = transport }
    static let root = "https://mp-search-api.tcgplayer.com"
    private func request(path: String, query: [URLQueryItem] = [], body: [String:Any]? = nil) async throws -> [String:Any] {
        var url = URLComponents(string:Self.root + path)!; if !query.isEmpty { url.queryItems = query }
        var req = URLRequest(url:url.url!); req.timeoutInterval = 30
        req.setValue("application/json",forHTTPHeaderField:"Accept")
        // Explicit app identification makes packaged and command-line builds use the same headers.
        req.setValue("DeckLab/6.2 (macOS)",forHTTPHeaderField:"User-Agent")
        if let body { req.httpMethod = "POST"; req.setValue("application/json",forHTTPHeaderField:"Content-Type"); req.httpBody = try JSONSerialization.data(withJSONObject:body) }
        let data = try await transport.send(req)
        guard let object = try JSONSerialization.jsonObject(with:data) as? [String:Any], (object["errors"] as? [Any] ?? []).isEmpty else { throw DataError.message("TCGplayer could not return this request. No replacement price was assumed.") }
        return object
    }
    static func matches(_ productName: String, card: String) -> Bool {
        if collectionKey(productName) == collectionKey(card) { return true }
        if let i = productName.range(of:" (") { return collectionKey(String(productName[..<i.lowerBound])) == collectionKey(card) }
        return false
    }
    func search(_ name: String, force: Bool = false) async throws -> [TCGProduct] {
        let key = collectionKey(name); let store = try LocalStore()
        if products.isEmpty { products = try store.read("tcg-products.json",as:[String:ProductCache].self) ?? [:] }
        if let cache = products[key], !force, Date().timeIntervalSince(cache.fetched) < 86400 { return cache.products }
        var found: [TCGProduct] = []; var seen = Set<Int>(); var offset = 0
        while true {
            try Task.checkCancellation()
            let body: [String:Any] = ["algorithm":"revenue_dismax","from":offset,"size":50,
                "filters":["term":["productLineName":["yugioh"]],"range":[:],"match":[:]],
                "listingSearch":["context":["cart":[:]],"filters":["term":["sellerStatus":"Live","channelId":0],"range":["quantity":["gte":1]],"exclude":["channelExclusion":0]]],
                "context":["cart":[:],"shippingCountry":"US"],"settings":["useFuzzySearch":false,"didYouMean":[:]],"sort":[:]]
            let term = "\"" + name.replacingOccurrences(of:"\"",with:"\\\"") + "\""
            let response = try await request(path:"/v1/search/request",query:[.init(name:"q",value:term),.init(name:"isList",value:"false")],body:body)
            guard let group = (response["results"] as? [[String:Any]])?.first, let page = group["results"] as? [[String:Any]], let total = group["totalResults"] as? Int else { throw DataError.message("TCGplayer's product search response changed.") }
            if page.isEmpty { break }
            var fresh = 0
            for d in page {
                guard let id = d["productId"] as? Int else { throw DataError.message("TCGplayer returned a product without an ID.") }
                if !seen.insert(id).inserted { continue }; fresh += 1
                guard let productName = d["productName"] as? String, Self.matches(productName,card:name), d["sealed"] as? Bool != true else { continue }
                let attributes = d["customAttributes"] as? [String:Any] ?? [:]
                found.append(TCGProduct(id:id,name:productName,rarity:d["rarityName"] as? String ?? "Unknown rarity",set:d["setName"] as? String ?? "",number:attributes["number"] as? String ?? "",indicativeLow:d["lowestPrice"] as? Double))
            }
            guard fresh > 0 else { throw DataError.message("TCGplayer repeated a product-search page. Try again.") }
            offset += page.count
            if offset >= total { break }
        }
        found.sort { a,b in a.label == b.label ? a.id < b.id : a.label < b.label }
        products[key] = ProductCache(fetched:Date(),products:found); try store.write(products,name:"tcg-products.json")
        return found
    }
    func skus(_ product: TCGProduct) async throws -> [TCGSKU] {
        let store = try LocalStore(); let key = String(product.id)
        if details.isEmpty { details = try store.read("tcg-skus.json",as:[String:SKUCache].self) ?? [:] }
        if let cache = details[key], Date().timeIntervalSince(cache.fetched) < 86400 { return cache.skus }
        let d = try await request(path:"/v2/product/\(product.id)/details")
        guard let raw = d["skus"] as? [[String:Any]] else { throw DataError.message("No printings or conditions were returned for this product.") }
        let values = Array(Set(raw.compactMap { s -> TCGSKU? in
            guard s["language"] as? String == "English", let condition = s["condition"] as? String, let edition = s["variant"] as? String else { return nil }
            return TCGSKU(condition:condition,edition:edition)
        })).sorted { ($0.condition + $0.edition) < ($1.condition + $1.edition) }
        details[key] = SKUCache(fetched:Date(),skus:values); try store.write(details,name:"tcg-skus.json")
        return values
    }
    static func eligible(_ d: [String:Any], variant: CardVariant) -> Bool {
        (d["productId"] as? Int) == variant.product.id && d["verifiedSeller"] as? Bool == true &&
        d["condition"] as? String == variant.condition && d["printing"] as? String == variant.edition &&
        d["language"] as? String == "English" && (d["quantity"] as? Int ?? 0) > 0 &&
        (d["price"] as? Double ?? -1) >= 0
    }
    func quote(_ variant: CardVariant) async throws -> PriceQuote {
        var offset = 0; var seen = Set<String>(); var best: PriceQuote?
        while true {
            try Task.checkCancellation()
            let body: [String:Any] = ["filters":["term":["sellerStatus":"Live","channelId":0,"language":["English"],"condition":[variant.condition],"printing":[variant.edition]],"range":["quantity":["gte":1]],"exclude":["channelExclusion":0]],"context":["shippingCountry":"US","cart":[:]],"sort":["field":"price","order":"asc"],"from":offset,"size":50,"aggregations":["listingType"]]
            let response = try await request(path:"/v1/product/\(variant.product.id)/listings",body:body)
            guard let group = (response["results"] as? [[String:Any]])?.first, let page = group["results"] as? [[String:Any]], let total = group["totalResults"] as? Int else { throw DataError.message("TCGplayer's listings response changed. No quote was assumed.") }
            if page.isEmpty { break }
            var fresh = 0
            for listing in page {
                guard let id = listing["listingId"] as? Int else { throw DataError.message("A listing ID was missing.") }
                if !seen.insert(String(id)).inserted { continue }; fresh += 1
                guard Self.eligible(listing,variant:variant) else { continue }
                let quote = PriceQuote(variantID:variant.id,cents:Int(((listing["price"] as? Double ?? 0)*100).rounded()),shippingCents:Int(((listing["shippingPrice"] as? Double ?? 0)*100).rounded()),seller:listing["sellerName"] as? String ?? "Verified seller",listingID:String(id),quantity:listing["quantity"] as? Int ?? 0,checked:Date(),condition:variant.condition,edition:variant.edition,verified:true)
                if best == nil || quote.cents < best!.cents || quote.cents == best!.cents && quote.shippingCents < best!.shippingCents { best = quote }
            }
            guard fresh > 0 else { throw DataError.message("TCGplayer repeated a listings page. A low price could not be verified.") }
            offset += page.count
            if offset >= total { break }
        }
        guard let best else { throw DataError.message("No in-stock English \(variant.condition) · \(variant.edition) listings from verified sellers were found.") }
        return best
    }
}

/// One queue for manual, batch and background requests. Access denials are never retried.
struct TCGServiceError: LocalizedError {
    let status: Int
    let retryAt: Date?
    var stopsBatch: Bool { status == 403 || status == 429 }
    var errorDescription: String? {
        let reason = status == 403 ? "TCGplayer denied access (HTTP 403)." : "TCGplayer returned HTTP \(status)."
        let next = retryAt.map { " Next attempt available after \($0.formatted(date:.omitted,time:.standard))." } ?? ""
        return reason + next + " Last verified prices are preserved; no new price was assumed."
    }
}
actor TCGTransport {
    typealias Loader = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private let loader: Loader
    private let pause: @Sendable (TimeInterval) async throws -> Void
    private var busy = false
    private var lastFinished = Date.distantPast
    private var blocked: TCGServiceError?
    init(loader: Loader? = nil, pause: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for:.seconds($0)) }) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 90
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration:configuration)
        self.loader = loader ?? { try await session.data(for:$0) }
        self.pause = pause
    }
    static func retryDelay(_ value: String?, now: Date = Date()) -> TimeInterval? {
        guard let value else { return nil }
        if let seconds = Double(value), seconds.isFinite { return max(0,seconds) }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier:"en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT:0); formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from:value).map { max(0,$0.timeIntervalSince(now)) }
    }
    func send(_ request: URLRequest) async throws -> Data {
        while busy { try await Task.sleep(for:.milliseconds(50)); try Task.checkCancellation() }
        try Task.checkCancellation()
        busy = true
        defer { busy = false; lastFinished = Date() }
        if let blocked, let date = blocked.retryAt, date > Date() { throw blocked }
        blocked = nil
        let spacing = 0.35 - Date().timeIntervalSince(lastFinished)
        if spacing > 0 { try await pause(spacing) }
        for attempt in 0..<3 {
            try Task.checkCancellation()
            do {
                let (data,response) = try await loader(request)
                try Task.checkCancellation()
                guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                if http.statusCode == 200 { return data }
                let status = http.statusCode
                let delay = Self.retryDelay(http.value(forHTTPHeaderField:"Retry-After")) ?? pow(2,Double(attempt))
                if status == 403 {
                    let failure = TCGServiceError(status:status,retryAt:Date().addingTimeInterval(300))
                    blocked = failure; throw failure
                }
                if status == 429 && (delay > 8 || attempt == 2) {
                    let failure = TCGServiceError(status:status,retryAt:Date().addingTimeInterval(max(60,delay)))
                    blocked = failure; throw failure
                }
                if (status == 429 || [500,502,503,504].contains(status)) && attempt < 2 && delay <= 8 {
                    try await pause(max(0.35,delay)); continue
                }
                throw TCGServiceError(status:status,retryAt:nil)
            } catch let error as URLError {
                if Task.isCancelled || error.code == .cancelled { throw CancellationError() }
                guard attempt < 2, [.timedOut,.networkConnectionLost,.cannotConnectToHost,.dnsLookupFailed].contains(error.code) else { throw error }
                try await pause(pow(2,Double(attempt)))
            }
        }
        throw URLError(.badServerResponse)
    }
}
