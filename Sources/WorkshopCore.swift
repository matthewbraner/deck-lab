import Foundation

enum BuildZone: String, Codable, CaseIterable { case main = "Main", extra = "Extra", side = "Side" }
struct BuildCard: Identifiable, Codable, Hashable {
    var card: Card
    var zone: BuildZone
    var count: Int
    var id: String { collectionKey(card.name) + ":" + zone.rawValue }
}
struct PersonalBuild: Identifiable, Codable {
    var id = UUID().uuidString
    var name: String
    var format: GameFormat
    var cards: [BuildCard]
    var allocated = false
    var pointCap = 100
    var updated = Date()
    var origin = "Personal build"
    var deck: Deck {
        func entries(_ zone: BuildZone) -> [Entry] { cards.filter { $0.zone == zone && $0.count > 0 }.map { Entry(card:$0.card,amount:$0.count) } }
        return Deck(id:id,typeID:id,typeName:name,created:"",rank:"",tournament:"",placement:"",author:"You",path:"",engines:[],flagged:false,main:entries(.main),extra:entries(.extra),side:entries(.side),format:format.rawValue)
    }
    var counts: [String:Int] { Dictionary(cards.map { (collectionKey($0.card.name), $0.count) },uniquingKeysWith:+) }
    static func from(_ deck: Deck, format: GameFormat) -> PersonalBuild {
        let cards = [(BuildZone.main,deck.main),(.extra,deck.extra),(.side,deck.side)].flatMap { zone, entries in entries.map { BuildCard(card:$0.card,zone:zone,count:$0.amount) } }
        return PersonalBuild(name:deck.title ?? deck.typeName,format:format,cards:mergeBuildCards(cards),origin:deck.sourceURL?.absoluteString ?? "Source list")
    }
    static func average(_ decks: [Deck], name: String, format: GameFormat) -> PersonalBuild {
        let rows=aggregate(decks); let n=Double(max(1,decks.count))
        let cards=rows.flatMap { row in [(BuildZone.main,row.main),(.extra,row.extra),(.side,row.side)].compactMap { zone,total -> BuildCard? in
            let count=Int((Double(total)/n).rounded());return count>0 ? BuildCard(card:row.card,zone:zone,count:count) : nil
        } }
        return PersonalBuild(name:name,format:format,cards:cards,origin:"Rounded zone averages from \(decks.count) lists; review core/flex and legality before play")
    }
}
func mergeBuildCards(_ rows:[BuildCard]) -> [BuildCard] {
    var merged:[String:BuildCard]=[:]
    for row in rows { if let old=merged[row.id] { merged[row.id]=BuildCard(card:old.card,zone:old.zone,count:old.count+row.count) } else { merged[row.id]=row } }
    return merged.values.sorted { $0.id<$1.id }
}
struct SavedSearch: Identifiable, Codable {
    var id = UUID().uuidString
    var name: String
    var format: GameFormat
    var type: DeckType
    var start: Date
    var end: Date
    var tier: EventTier
    var filters: Filters
}
struct WorkshopData: Codable {
    var builds: [PersonalBuild] = []
    var searches: [SavedSearch] = []
    var favorites: Set<String> = []
}
struct BuildComparison: Identifiable {
    var id: String
    var card: Card
    var zone: BuildZone
    var before: Int
    var after: Int
    var difference: Int { after-before }
}
func compareBuilds(_ before: PersonalBuild, _ after: PersonalBuild) -> [BuildComparison] {
    let a=Dictionary(uniqueKeysWithValues:mergeBuildCards(before.cards).map { ($0.id,$0) })
    let b=Dictionary(uniqueKeysWithValues:mergeBuildCards(after.cards).map { ($0.id,$0) })
    return Set(a.keys).union(b.keys).sorted().compactMap { key in
        let x=a[key]?.count ?? 0, y=b[key]?.count ?? 0
        guard x != y, let row=b[key] ?? a[key] else { return nil }
        return BuildComparison(id:key,card:row.card,zone:row.zone,before:x,after:y)
    }
}
struct AllocationConflict: Identifiable {
    var id: String
    var name: String
    var owned: Int
    var requested: Int
    var builds: [String]
}
func allocationConflicts(_ builds:[PersonalBuild], inventory:Inventory) -> [AllocationConflict] {
    let active=builds.filter(\.allocated)
    var cards:[String:Card]=[:]; for build in active { for row in build.cards { cards[collectionKey(row.card.name)]=row.card } }
    return cards.compactMap { key,card in
        let users=active.filter { ($0.counts[key] ?? 0)>0 };let required=users.reduce(0) { $0+($1.counts[key] ?? 0) };let owned=inventory.owned(card.name)
        return required>owned ? AllocationConflict(id:key,name:card.name,owned:owned,requested:required,builds:users.map(\.name)) : nil
    }.sorted { $0.name<$1.name }
}
func availableInventory(_ inventory:Inventory, excluding buildID:String?, builds:[PersonalBuild]) -> Inventory {
    var result=inventory
    for build in builds where build.allocated && build.id != buildID {
        for (key,count) in build.counts {
            var left=count
            for id in result.variants.keys.sorted() where result.variants[id]?.cardKey == key {
                let taken=min(left,result.quantities[id] ?? 0);result.quantities[id,default:0]-=taken;left-=taken
            }
            result.unassigned[key]=max(0,(result.unassigned[key] ?? 0)-left)
        }
    }
    return result
}
struct CardPackage: Identifiable {
    let id: String
    let cards: [String]
    let count: Int
    let total: Int
}
func commonPackages(_ decks:[Deck], minimum:Int=2) -> [CardPackage] {
    // Exact co-occurrence signatures group optional cards used by the same lists.
    var patterns:[String:[String]]=[:];var names:[String:String]=[:];var occurrences:[String:[Int]]=[:]
    for (index,deck) in decks.enumerated() {
        for e in deck.main+deck.extra+deck.side where e.amount>0 { let key=collectionKey(e.card.name); names[key]=e.card.name;if !(occurrences[key] ?? []).contains(index) { occurrences[key,default:[]].append(index) } }
    }
    for (key,indexes) in occurrences where indexes.count>=minimum && indexes.count<decks.count {
        patterns[indexes.map(String.init).joined(separator:","),default:[]].append(names[key]!)
    }
    return patterns.compactMap { signature,names in
        guard names.count>1 else { return nil };return CardPackage(id:signature,cards:names.sorted(),count:signature.split(separator:",").count,total:decks.count)
    }.sorted { $0.count == $1.count ? $0.id<$1.id : $0.count>$1.count }
}
struct LegalityReport {
    var errors:[String]=[]
    var unknown:[String]=[]
    var points=0
}
func checkLegality(_ build:PersonalBuild,cards:[String:CardInfo],points:[String:CardInfo],masterDuel:MasterDuelRules?=nil) -> LegalityReport {
    var result=LegalityReport()
    func count(_ z:BuildZone) -> Int { build.cards.filter { $0.zone==z }.reduce(0) { $0+$1.count } }
    let main=count(.main),extra=count(.extra),side=count(.side)
    if main<40 || (build.format != .goat && main>60) { result.errors.append("Main Deck has \(main) cards; expected \(build.format == .goat ? "at least 40" : "40–60").") }
    if build.format != .goat && extra>15 { result.errors.append("Extra Deck has \(extra) cards; maximum 15.") }
    if side>15 || (build.format == .goat && side != 0 && side != 15) { result.errors.append("Side Deck has \(side) cards; \(build.format == .goat ? "use 0 or 15" : "maximum 15").") }
    if build.format == .masterDuel && side>0 { result.unknown.append("Master Duel ladder has no Side Deck; side cards require an event-specific rule.") }
    let missingBanlist = build.format == .masterDuel && masterDuel == nil
    if missingBanlist { result.unknown.append("\(build.format.rawValue) Forbidden/Limited list is not supplied by this provider. Check the event's list.") }
    let totals=build.counts
    var processed=Set<String>()
    for row in build.cards {
        let key=collectionKey(row.card.name)
        guard row.count>0 else { result.errors.append("\(row.card.name): quantity must be positive.");continue }
        guard let info=cards[row.card.name.lowercased()] else { result.unknown.append("No rules data for \(row.card.name).");continue }
        let extraType=["Fusion","Synchro","XYZ","Xyz","Link"].contains { info.type.contains($0) }
        if row.zone == .extra && !extraType || row.zone == .main && extraType { result.errors.append("\(row.card.name) is in the wrong zone (\(row.zone.rawValue)).") }
        if info.type.contains("Token") || info.type.contains("Skill") { result.errors.append("\(row.card.name) cannot be included in this deck.") }
        if build.format == .genesys {
            if info.type.contains("Link") || info.type.contains("Pendulum") { result.errors.append("\(row.card.name) is not allowed in Genesys.") }
            if let p=points[info.name.lowercased()]?.genesysPoints { result.points += p*row.count } else { result.unknown.append("Genesys points unavailable for \(info.name).") }
        }
        if processed.insert(key).inserted {
            var limit=3
            if build.format == .edison { limit=edisonLimits[key] ?? 3 }
            else if build.format == .masterDuel,let masterDuel {
                if let known=masterDuel.limits[key] { limit=known } else { result.errors.append("\(info.name) is not in the released Master Duel card pool.") }
            }
            else if build.format != .genesys && !missingBanlist {
                let field=build.format == .tcg ? "ban_tcg" : build.format == .ocg ? "ban_ocg" : "ban_goat"
                if let limits=info.banlist { switch limits[field] { case "Banned":limit=0;case "Limited":limit=1;case "Semi-Limited":limit=2;default:break } }
                else { result.unknown.append("Refresh rules data before checking \(info.name)'s card limit.") }
            }
            if (totals[key] ?? 0)>limit { result.errors.append("\(info.name): \(totals[key]!) copies across all zones; limit \(limit).") }
            let pool=build.format == .masterDuel ? "Master Duel" : build.format == .genesys ? "TCG" : build.format == .goat ? "Goat" : build.format.rawValue
            if !(build.format == .masterDuel && masterDuel != nil) && !info.formats.contains(where:{$0.caseInsensitiveCompare(pool) == .orderedSame}) { result.unknown.append("\(info.name): \(pool) card-pool eligibility unconfirmed.") }
            if info.description.localizedCaseInsensitiveContains("always treated as") { result.unknown.append("\(info.name): review shared-name deck limits.") }
        }
    }
    if build.format == .genesys && result.points>build.pointCap { result.errors.append("Genesys points \(result.points) exceed cap \(build.pointCap).") }
    result.errors=Array(Set(result.errors)).sorted();result.unknown=Array(Set(result.unknown)).sorted()
    return result
}

// Strict parsing is atomic: malformed lines never partially change a collection or build.
func csvRows(_ text:String) throws -> [[String]] {
    var rows:[[String]]=[],row:[String]=[],field="",quoted=false
    let chars=Array(text);var i=0
    while i<chars.count {
        let c=chars[i]
        if c == "\"" {
            if quoted && i+1<chars.count && chars[i+1] == "\"" { field.append("\"");i+=1 } else { quoted.toggle() }
        } else if c == "," && !quoted { row.append(field);field="" }
        else if (c == "\n" || c == "\r") && !quoted {
            if c == "\r" && i+1<chars.count && chars[i+1] == "\n" { i+=1 }
            row.append(field);if row.contains(where:{ !$0.isEmpty }) { rows.append(row) };row=[];field=""
        } else { field.append(c) };i+=1
    }
    guard !quoted else { throw DataError.message("Unclosed quote in CSV.") }
    row.append(field);if row.contains(where:{ !$0.isEmpty }) { rows.append(row) };return rows
}
func csvField(_ value:String) -> String { "\""+value.replacingOccurrences(of:"\"",with:"\"\"")+"\"" }
func collectionCSV(_ inventory:Inventory,names:[String:String]) -> String {
    var rows=["name,quantity,product_id,rarity,set,number,condition,edition"]
    for (key,count) in inventory.unassigned.sorted(by:{$0.key<$1.key}) where count>0 { rows.append([names[key] ?? key,String(count),"","","","","", ""].map(csvField).joined(separator:",")) }
    for v in inventory.variants.values.sorted(by:{$0.id<$1.id}) where (inventory.quantities[v.id] ?? 0)>0 {
        rows.append([v.cardName,String(inventory.quantities[v.id]!),String(v.product.id),v.product.rarity,v.product.set,v.product.number,v.condition,v.edition].map(csvField).joined(separator:","))
    };return rows.joined(separator:"\n")
}
func parseCollection(_ text:String,cards:[String:CardInfo]) throws -> Inventory {
    let firstLine=text.components(separatedBy:.newlines).first ?? ""
    let firstRow=try csvRows(firstLine).first ?? []
    let appearsCSV=firstRow.map{$0.lowercased().trimmingCharacters(in:.whitespaces)}.contains("quantity")
    let rows=appearsCSV ? try csvRows(text) : text.components(separatedBy:.newlines).filter{!$0.trimmingCharacters(in:.whitespaces).isEmpty}.map{[$0]}
    var result=Inventory()
    let header=rows.first?.map { $0.lowercased().trimmingCharacters(in:.whitespacesAndNewlines) } ?? []
    let isCSV=header.contains("name") && header.contains("quantity")
    for (index,row) in (isCSV ? Array(rows.dropFirst()) : rows).enumerated() {
        var name="",count:Int?,fields:[String:String]=[:]
        if isCSV { for (i,key) in header.enumerated() { fields[key]=i<row.count ? row[i] : "" };name=fields["name"] ?? "";count=Int(fields["quantity"] ?? "") }
        else {
            let line=row.joined(separator:",").trimmingCharacters(in:.whitespacesAndNewlines)
            let parts=line.split(separator:" ",maxSplits:1);if parts.count==2 { count=Int(parts[0].replacingOccurrences(of:"x",with:""));name=String(parts[1]) }
        }
        name=name.trimmingCharacters(in:.whitespacesAndNewlines)
        guard let count,count>=0,count<=9999,!name.isEmpty else { throw DataError.message("Invalid quantity or card on import row \(index+1). Use name,quantity CSV or ‘3 Card Name’ lines.") }
        if let info=cards[name.lowercased()] { name=info.name }
        if result.displayNames == nil { result.displayNames=[:] };result.displayNames?[collectionKey(name)]=name
        if let raw=fields["product_id"], !raw.isEmpty {
            guard let id=Int(raw),id>0,let condition=fields["condition"],!condition.isEmpty,let edition=fields["edition"],!edition.isEmpty else { throw DataError.message("Printing on row \(index+1) needs a product ID, condition, and edition.") }
            let product=TCGProduct(id:id,name:name,rarity:fields["rarity"] ?? "",set:fields["set"] ?? "",number:fields["number"] ?? "",indicativeLow:nil)
            let variant=CardVariant(cardName:name,product:product,condition:condition,edition:edition)
            if let old=result.variants[variant.id],collectionKey(old.cardName) != collectionKey(name) { throw DataError.message("A product ID was assigned to different cards.") }
            result.variants[variant.id]=variant;result.quantities[variant.id,default:0]+=count
        } else { result.unassigned[collectionKey(name),default:0]+=count }
    }
    guard !result.unassigned.isEmpty || !result.variants.isEmpty else { throw DataError.message("No collection rows found.") };return result
}
func parseYDK(_ text:String,cards:[String:CardInfo],format:GameFormat) throws -> PersonalBuild {
    var zone=BuildZone.main,rows:[BuildCard]=[]
    for (i,line) in text.components(separatedBy:.newlines).enumerated() {
        let value=line.trimmingCharacters(in:.whitespacesAndNewlines)
        if value == "#main" { zone = .main;continue };if value == "#extra" { zone = .extra;continue };if value == "!side" { zone = .side;continue }
        if value.isEmpty || value.hasPrefix("#") { continue }
        guard Int(value) != nil,let info=cards[value] else { throw DataError.message("Unknown card passcode on YDK line \(i+1): \(value). Refresh card data first.") }
        rows.append(BuildCard(card:Card(id:"ygo:"+info.id,name:info.name,rarity:info.mdRarity),zone:zone,count:1))
    }
    guard !rows.isEmpty,rows.count<=1000 else { throw DataError.message("YDK must contain 1–1,000 cards.") }
    return PersonalBuild(name:"Imported deck",format:format,cards:mergeBuildCards(rows),origin:"YDK import")
}
func exportYDK(_ build:PersonalBuild,cards:[String:CardInfo]) throws -> String {
    var lines=["#created by Deck Lab"]
    for zone in BuildZone.allCases {
        lines.append(zone == .main ? "#main" : zone == .extra ? "#extra" : "!side")
        for row in build.cards where row.zone==zone && row.count>0 {
            guard let info=cards[row.card.name.lowercased()],Int(info.id) != nil else { throw DataError.message("Missing passcode for \(row.card.name). Refresh card data before exporting.") }
            lines+=Array(repeating:info.id,count:row.count)
        }
    };return lines.joined(separator:"\n")+"\n"
}

func budgetCents(_ text:String) -> Int? {
    guard let value=Double(text),value.isFinite,value>=0,value<=10_000_000 else { return nil }
    return Int((value*100).rounded(.down))
}
