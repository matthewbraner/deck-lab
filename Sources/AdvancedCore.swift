import Foundation
struct SubstitutionGroup:Identifiable,Codable {
    var id=UUID().uuidString
    var name:String
    var cards:[String]=[]
    var notes=""
}
struct CardLocation:Identifiable,Codable {
    var id=UUID().uuidString
    var holdingID:String // variant ID or unspecified:<normalized name>
    var label:String
    var count:Int
}
struct AdvancedData:Codable {
    var substitutions:[SubstitutionGroup]=[]
    var locations:[CardLocation]=[]
}
struct CardSearchFilter {
    var name="",effect="",type="All",attribute="All",race="All"
    var level:Int?,minATK:Int?,maxATK:Int?,minDEF:Int?,maxDEF:Int?,maxPoints:Int?
    func matches(_ c:CardInfo,points:[String:CardInfo])->Bool {
        if !name.isEmpty && !c.name.localizedCaseInsensitiveContains(name) {return false}
        if !effect.isEmpty && !c.description.localizedCaseInsensitiveContains(effect) {return false}
        if type != "All" && c.type != type || attribute != "All" && c.attribute != attribute || race != "All" && c.race != race {return false}
        if let level,c.level != level {return false}
        if let minATK {guard let atk=c.atk,atk>=minATK else{return false}};if let maxATK {guard let atk=c.atk,atk<=maxATK else{return false}}
        if let minDEF {guard let def=c.def,def>=minDEF else{return false}};if let maxDEF {guard let def=c.def,def<=maxDEF else{return false}}
        if let maxPoints, (points[c.name.lowercased()]?.genesysPoints ?? Int.max)>maxPoints{return false}
        return true
    }
}
func remainingBuild(_ build:PersonalBuild,removed:[String:Int]) throws -> PersonalBuild {
    var result=build
    for (name,n) in removed {
        guard n>=0 else{throw DataError.message("Removed counts cannot be negative.")}
        if n==0{continue}
        let indexes=result.cards.indices.filter { result.cards[$0].zone == .main && collectionKey(result.cards[$0].card.name)==name }
        guard indexes.reduce(0,{$0+result.cards[$1].count})>=n else{throw DataError.message("More copies removed than exist in the Main Deck.")}
        var left=n
        for i in indexes {let used=min(left,result.cards[i].count);result.cards[i].count-=used;left-=used}
    }
    result.cards.removeAll{$0.count==0};return result
}
func locationHoldingCount(_ id:String,inventory:Inventory)->Int {
    if id.hasPrefix("unspecified:"){return inventory.unassigned[String(id.dropFirst(12))] ?? 0}
    return inventory.quantities[id] ?? 0
}
func locationIssues(_ data:AdvancedData,inventory:Inventory)->[String] {
    Dictionary(grouping:data.locations,by: \.holdingID).compactMap { id,rows in
        let sum=rows.reduce(0){$0+$1.count},owned=locationHoldingCount(id,inventory:inventory)
        return sum>owned ? "\(rows.map(\.label).joined(separator:", ")): \(sum) located copies exceed \(owned) owned." : nil
    }.sorted()
}
struct OptimizationResult {
    var build:PersonalBuild
    var probability:Double
    var checked:Int
    var legalCandidates:Int
    var unknownRules:Int
}
func optimizeRatios(build:PersonalBuild,unlocked:Set<String>,targetSize:Int,hand:Int,buckets:[CardBucket],routes:[ComboRoute],cards:[String:CardInfo],points:[String:CardInfo],md:MasterDuelRules?,inventory:Inventory,quotes:[String:PriceQuote],budget:Int?,allowIncomplete:Bool=false) throws -> OptimizationResult {
    let rows=mergeBuildCards(build.cards.filter{$0.zone == .main})
    let variable=rows.filter{unlocked.contains(collectionKey($0.card.name))}
    guard !variable.isEmpty,variable.count<=7,targetSize>=40,targetSize<=60 else {throw DataError.message("Unlock 1–7 Main Deck card types and choose a target size of 40–60.")}
    let fixed=rows.filter{!unlocked.contains(collectionKey($0.card.name))}
    let fixedCount=fixed.reduce(0){$0+$1.count}
    var best:PersonalBuild?,bestP = -1.0,checked=0,legal=0,unknown=0,work=0
    var choice:[BuildCard]=[]
    func visit(_ index:Int,_ remaining:Int) throws {
        work+=1;if work%50==0{try Task.checkCancellation()}
        guard remaining>=0,remaining<=3*(variable.count-index) else{return}
        if index<variable.count {
            for n in 0...3 { var row=variable[index];row.count=n;choice.append(row);try visit(index+1,remaining-n);choice.removeLast() };return
        }
        guard remaining==0 else{return};checked+=1
        var candidate=build;candidate.cards=build.cards.filter{$0.zone != .main}+fixed+choice.filter{$0.count>0}
        let report=checkLegality(candidate,cards:cards,points:points,masterDuel:md)
        guard report.errors.isEmpty else{return}
        if !report.unknown.isEmpty {unknown+=1;if !allowIncomplete{return}}
        if let budget {
            let totals=buildTotals(stats:aggregate([candidate.deck]),sample:1,inventory:inventory,quotes:quotes,roundUp:false)
            guard totals.unpricedMissingCopies==0,totals.missingCents<=budget else{return}
        }
        legal+=1
        guard legal<=2000 else{throw DataError.message("Search is too large. Lock more cards; no partial optimum was returned.")}
        let input=try probabilityInput(build:candidate,buckets:buckets,routes:routes,hand:hand)
        let p=try exactCombo(input,nodeLimit:30000).probability
        if p>bestP+1e-12 {bestP=p;best=candidate}
    }
    try visit(0,targetSize-fixedCount)
    guard var winner=best else{throw DataError.message("No candidate meets deck size, copy limits, rule coverage, and budget. \(unknown) candidates had incomplete rule data. Refresh rules or explicitly allow incomplete checks.")}
    winner.id=UUID().uuidString;winner.name+=" · optimized";winner.allocated=false;winner.origin="Exhaustive 0–3-copy search over \(variable.count) unlocked card types; \(checked) size-valid candidates; other cards locked."
    return OptimizationResult(build:winner,probability:bestP,checked:checked,legalCandidates:legal,unknownRules:unknown)
}
func htmlEscape(_ text:String)->String {text.replacingOccurrences(of:"&",with:"&amp;").replacingOccurrences(of:"<",with:"&lt;").replacingOccurrences(of:">",with:"&gt;").replacingOccurrences(of:"\"",with:"&quot;")}
