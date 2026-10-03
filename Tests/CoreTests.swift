import Foundation

@main struct Tests {
    static func main() async throws {
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() { fatalError(message) }
        }
        let a = Card(id: "a", name: "Card A", rarity: "UR")
        let b = Card(id: "b", name: "Card B", rarity: "R")
        func deck(_ id: String, _ rank: String, _ tournament: String = "", main: [Entry] = [], extra: [Entry] = [], side: [Entry] = []) -> Deck {
            Deck(id: id, typeID: "test", typeName: "Test", created: "2026-10-01T00:00:00Z", rank: rank, tournament: tournament, placement: "", author: "Test", path: "/test/", engines: [], flagged: false, main: main, extra: extra, side: side)
        }
        let d1 = deck("1", "Master I", main: [Entry(card:a,amount:2), Entry(card:a,amount:1)], extra: [Entry(card:b,amount:1)])
        let d2 = deck("2", "Diamond I", main: [Entry(card:b,amount:3)], side: [Entry(card:a,amount:2)])
        let d3 = deck("3", "", "Tournament", main: [Entry(card:b,amount:1)])
        let stats = aggregate([d1,d2,d3])
        let s = stats.first { $0.id == "a" }!
        check(s.main == 3 && s.side == 2 && s.extra == 0, "Zone totals")
        check(s.included == 2 && s.mainIncluded == 1 && s.sideIncluded == 1, "Per-deck inclusion not per-entry")
        check(s.average(s.main, sample:3, mode:.all) == 1, "Zeros included in all-decks denominator")
        check(s.average(s.main, sample:3, mode:.included) == 1.5, "Running-card denominator")
        check(s.distribution == [3:1, 2:1], "Copy distribution")
        check(aggregate([]).isEmpty, "Empty sample")
        var filter = Filters(); filter.rank = .master
        check(filter.matches(d1) && !filter.matches(d2) && !filter.matches(d3), "Master rank floor excludes unranked tournaments")
        check(filter.matches(deck("4", "Rating Duels")), "Rating Duels included")
        check(!filter.matches(deck("5", "Win Streaks")), "Do not infer unknown rank")
        filter = Filters(); filter.source = .tournaments
        check(filter.matches(d3) && !filter.matches(d1), "Tournament source")
        filter.source = .ranked
        check(filter.matches(d1) && filter.matches(d2) && !filter.matches(d3), "Ranked source")
        filter = Filters(); filter.requiredCards = ["cArD a"]
        check(filter.matches(d1) && filter.matches(d2) && !filter.matches(d3), "Required card includes side decks and ignores case")
        filter.requiredCards = ["Card A", "Card B"]
        check(filter.matches(d1) && filter.matches(d2) && !filter.matches(d3), "All required cards including extra zone")
        filter.excludedCards = ["Card A"]
        check(!filter.matches(d1) && !filter.matches(d2), "Excluded card overrides inclusion")
        filter.requiredCards = []; filter.excludedCards = ["Card A"]
        check(filter.matches(d3) && !filter.matches(d2), "Exclusion across side zone")
        filter.requiredCards = ["Card"]
        check(!filter.matches(d3), "No partial card-name matches")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try LocalStore(directory: dir)
        try store.write([normalizedCardName("Zubaba")],name:"hidden-deck-types.json")
        check(try! store.read("hidden-deck-types.json",as:[String].self) == ["zubaba"], "Hidden deck preference survives reload")
        let roles = ["deck1:a": CardRole.engine, "deck2:a": CardRole.nonEngine]
        try store.write(roles, name:"classifications.json")
        let saved = try store.read("classifications.json", as:[String:CardRole].self)
        check(saved == roles, "Persistent deck-specific roles")
        let snapshot = Snapshot(type:DeckType(id:"test",name:"Test"),from:"2026-10-01",through:"2026-10-02",fetched:Date(),decks:[d1,d2,d3])
        try store.write(snapshot,name:"snapshot.json")
        let restored = try store.read("snapshot.json",as:Snapshot.self)!
        check(restored.decks.count == 3 && aggregate(restored.decks).first { $0.id == "a" }!.side == 2, "Offline snapshot roundtrip")
        if let fixture = CommandLine.arguments.dropFirst().first(where: { !$0.hasPrefix("--") }) {
            let decks = try MDM.decks(Data(contentsOf:URL(fileURLWithPath:fixture)))
            check(!decks.isEmpty, "Live fixture parsed")
            let sums = aggregate(decks)
            check(sums.reduce(0) { $0 + $1.total } == decks.reduce(0) { $0 + $1.total }, "Live card totals conserved")
            print("Live fixture: \(decks.count) decks, \(sums.count) distinct cards")
        }
        if CommandLine.arguments.contains("--live") {
            let catalogue = try await MDM.catalogue()
            check(catalogue.count > 100, "Full deck catalogue")
            let type = catalogue.first { $0.name == "Sky Striker" }!
            let decks = try await MDM.fetch(type:type,from:"2026-09-01",before:"2026-10-04") { _ in }
            check(!decks.isEmpty && Set(decks.map(\.id)).count == decks.count, "Complete deduplicated live dataset")
            check(decks.allSatisfy { $0.typeID == type.id && $0.day >= "2026-09-01" && $0.day <= "2026-10-03" }, "Live type/date filters")
            print("Live API: \(catalogue.count) types; \(decks.count) matching decks")
        }
        print("All calculation, filter, persistence, and data checks passed.")
    }
}
