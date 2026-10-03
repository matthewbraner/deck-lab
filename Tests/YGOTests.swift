import Foundation
@main struct Tests {
    static func main() async throws {
        func check(_ value: @autoclosure () -> Bool, _ message: String) { if !value() { fatalError(message) } }
        let db = try await YGO.shared.cardDatabase()
        check(db.cards.count > 10000,"Full card database")
        let index = db.index
        check(index["14558127"]?.name == "Ash Blossom & Joyous Spring", "Passcode lookup")
        check(index["ash blossom & joyous spring"]?.id == "14558127", "Cross-provider name lookup")
        let genesys = try await YGO.shared.cardDatabase(genesys:true)
        check(genesys.index["14558127"]?.genesysPoints != nil,"Genesys points")
        let archetypes = try await YGO.archetypes()
        check(archetypes.count > 500,"Archetype catalogue")
        let darklord = archetypes.first { $0.name == "Darklord" }!
        let decks = try await YGO.fetch(type:darklord,format:.genesys,from:"2026-09-01",through:"2026-10-03",tier:.any,cards:index) { _ in }
        check(!decks.isEmpty,"Live Genesys submissions")
        check(decks.allSatisfy { $0.format == "Genesys" && $0.provider == "YGOPRODeck" }, "Format isolation")
        check(decks.allSatisfy { $0.main.allSatisfy { !$0.card.name.hasPrefix("Unknown card") } },"Passcodes resolved")
        let stats = aggregate(decks)
        check(stats.reduce(0) { $0 + $1.total } == decks.reduce(0) { $0 + $1.total }, "All zones conserved")
        check(decks.allSatisfy { $0.sourceURL?.host == "ygoprodeck.com" }, "Provider source links")
        let purrely = archetypes.first { $0.name == "Purrely" }!
        let tournaments = try await YGO.fetch(type:purrely,format:.genesys,from:"2026-09-01",through:"2026-10-03",tier:.competitive,cards:index) { _ in }
        check(!tournaments.isEmpty && tournaments.allSatisfy(\.isTournament),"Tier 2+ Genesys tournament results")
        let premier = try await YGO.fetch(type:purrely,format:.genesys,from:"2026-09-01",through:"2026-10-03",tier:.premier,cards:index) { _ in }
        check(Set(premier.map(\.id)).isSubset(of:Set(tournaments.map(\.id))),"Tier 3 subset of Tier 2+")
        print("YGOPRODeck: \(db.cards.count) cards; \(genesys.cards.count) Genesys cards; \(archetypes.count) archetypes; \(decks.count) Genesys Darklord decks; \(tournaments.count) Tier 2+ Purrely decks; \(premier.count) Tier 3 Purrely decks.")
        for format in [GameFormat.tcg,.ocg,.goat,.edison] {
            let start = (format == .ocg || format == .edison) ? "2026-09-01" : "2026-10-01"
            let sample=try await YGO.fetch(type:DeckType(id:"all",name:"All deck types"),format:format,from:start,through:"2026-10-03",tier:.any,cards:index) { _ in }
            check(!sample.isEmpty,"Known populated \(format.rawValue) sample")
            check(sample.allSatisfy{$0.format==format.rawValue && $0.provider=="YGOPRODeck"},"\(format.rawValue) provider and format isolation")
            check(Set(sample.map(\.id)).count==sample.count,"\(format.rawValue) deduplication")
            print("Live format \(format.rawValue): \(sample.count) lists")
        }
        let cancelled=Task {try await YGO.fetch(type:darklord,format:.genesys,from:"2026-09-01",through:"2026-10-03",tier:.any,cards:index){_ in}}
        cancelled.cancel()
        do {_=try await cancelled.value;fatalError("Cancelled fetch completed")}catch is CancellationError {} catch {fatalError("Unexpected cancellation error: \(error)")}
        print("YGOPRODeck live integration checks passed, including all formats and cancellation.")
    }
}
