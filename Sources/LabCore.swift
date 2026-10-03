import Foundation

struct CardBucket:Identifiable,Codable,Hashable,Sendable {
    var id=UUID().uuidString
    var buildID:String
    var name:String
    var role="Custom"
    var cards:Set<String>=[] // normalized names; all physical copies of each selected card
}
struct ComboNeed:Identifiable,Codable,Hashable,Sendable {
    var id=UUID().uuidString
    var bucketID:String
    var minimum=1
    var maximum=10
}
struct ComboRoute:Identifiable,Codable,Hashable,Sendable {
    var id=UUID().uuidString
    var buildID:String
    var name:String
    var needs:[ComboNeed]=[]
    var distinctCopies=true
    var notes=""
}
struct BuildRevision:Identifiable,Codable {
    var id=UUID().uuidString
    var date=Date()
    var build:PersonalBuild
    var note:String
}
struct MatchRecord:Identifiable,Codable {
    var id=UUID().uuidString
    var date=Date()
    var build:PersonalBuild
    var opponent:String
    var result:String
    var turnOrder:String
    var notes:String
}
struct SideSwap:Identifiable,Codable {
    var id=UUID().uuidString
    var outgoing:String
    var incoming:String
    var zone=BuildZone.main
    var count=1
}
struct SidePlan:Identifiable,Codable {
    var id=UUID().uuidString
    var buildID:String
    var matchup:String
    var turnOrder="Going first"
    var swaps:[SideSwap]=[]
    var notes=""
}
struct PriceWatch:Identifiable,Codable {
    var id:String { variantID }
    var variantID:String
    var targetCents:Int
}
struct TrendSample:Identifiable,Codable {
    var id=UUID().uuidString
    var name:String
    var date=Date()
    var format:GameFormat
    var from:String
    var through:String
    var criteria:String
    var decks:[Deck]
}
struct LabData:Codable {
    var buckets:[CardBucket]=[]
    var combos:[ComboRoute]=[]
    var revisions:[BuildRevision]=[]
    var matches:[MatchRecord]=[]
    var sidePlans:[SidePlan]=[]
    var priceHistory:[String:[PriceQuote]]=[:]
    var watches:[PriceWatch]=[]
    var autoRefreshPrices=false
    var trends:[TrendSample]=[]
}
struct ShoppingItem:Identifiable {
    var id:String
    var name:String
    var required:Int
    var owned:Int
    var missing:Int { max(0,required-owned) }
    var variant:CardVariant?
    var quote:PriceQuote?
}
func shoppingList(builds:[PersonalBuild],inventory:Inventory,quotes:[String:PriceQuote],simultaneous:Bool) -> [ShoppingItem] {
    var counts:[String:Int]=[:],names:[String:String]=[:]
    for build in builds {
        for row in build.cards { names[collectionKey(row.card.name)]=row.card.name }
        for (key,n) in build.counts { counts[key]=simultaneous ? (counts[key] ?? 0)+n : max(counts[key] ?? 0,n) }
    }
    return counts.map { key,n in
        let name=names[key] ?? key,v=inventory.target(names[key] ?? key)
        let q=v.flatMap { quotes[$0.id] }.flatMap { $0.verified ? $0 : nil }
        return ShoppingItem(id:key,name:name,required:n,owned:inventory.owned(name),variant:v,quote:q)
    }.sorted { $0.name<$1.name }
}
func applySidePlan(_ plan:SidePlan,to original:PersonalBuild) throws -> PersonalBuild {
    var b=original
    for swap in plan.swaps {
        guard swap.count>0,swap.zone != .side,collectionKey(swap.outgoing) != collectionKey(swap.incoming) else { throw DataError.message("Each swap needs different cards and a positive quantity.") }
        guard let oi=b.cards.firstIndex(where:{$0.zone==swap.zone && collectionKey($0.card.name)==collectionKey(swap.outgoing)}),
              let ii=b.cards.firstIndex(where:{$0.zone == .side && collectionKey($0.card.name)==collectionKey(swap.incoming)}),
              b.cards[oi].count>=swap.count,b.cards[ii].count>=swap.count else { throw DataError.message("Not enough copies for \(swap.outgoing) → \(swap.incoming). Check this plan against the current build.") }
        let out=b.cards[oi].card,inc=b.cards[ii].card
        b.cards[oi].count-=swap.count;b.cards[ii].count-=swap.count
        b.cards += [BuildCard(card:out,zone:.side,count:swap.count),BuildCard(card:inc,zone:swap.zone,count:swap.count)]
        b.cards=mergeBuildCards(b.cards.filter{$0.count>0})
    }
    b.id=UUID().uuidString;b.allocated=false;b.name+=" · vs \(plan.matchup) · \(plan.turnOrder)";b.origin="Side plan from \(original.name)";return b
}
struct TrendChange:Identifiable {
    var id:String
    var name:String
    var oldRate:Double
    var newRate:Double
    var oldCopies:Double
    var newCopies:Double
    var change:Double { newRate-oldRate }
}
func trendChanges(_ a:[Deck],_ b:[Deck]) -> [TrendChange] {
    let x=Dictionary(aggregate(a).map{(collectionKey($0.card.name),$0)},uniquingKeysWith:{$1})
    let y=Dictionary(aggregate(b).map{(collectionKey($0.card.name),$0)},uniquingKeysWith:{$1})
    return Set(x.keys).union(y.keys).map { k in
        TrendChange(id:k,name:(y[k] ?? x[k])!.card.name,oldRate:Double(x[k]?.included ?? 0)/Double(max(1,a.count)),newRate:Double(y[k]?.included ?? 0)/Double(max(1,b.count)),oldCopies:Double(x[k]?.total ?? 0)/Double(max(1,a.count)),newCopies:Double(y[k]?.total ?? 0)/Double(max(1,b.count)))
    }.sorted { abs($0.change)==abs($1.change) ? $0.name<$1.name : abs($0.change)>abs($1.change) }
}

func validateLab(_ lab:LabData) throws {
    func unique(_ ids:[String])->Bool { Set(ids).count==ids.count }
    func validBuild(_ b:PersonalBuild)->Bool { b.pointCap>=0 && b.cards.allSatisfy{$0.count>0 && $0.count<=9999} }
    guard unique(lab.buckets.map(\.id)),unique(lab.combos.map(\.id)),unique(lab.revisions.map(\.id)),unique(lab.matches.map(\.id)),unique(lab.sidePlans.map(\.id)),unique(lab.watches.map(\.id)),unique(lab.trends.map(\.id)),
          Dictionary(grouping:lab.buckets,by: \.buildID).values.allSatisfy({$0.count<=12}),
          lab.combos.allSatisfy({ route in unique(route.needs.map(\.id)) && route.needs.allSatisfy{need in need.minimum>=0 && need.maximum>=need.minimum && need.maximum<=10 && lab.buckets.contains{$0.id==need.bucketID && $0.buildID==route.buildID}} }),
          lab.revisions.allSatisfy({validBuild($0.build)}),lab.matches.allSatisfy({validBuild($0.build)}),
          lab.sidePlans.allSatisfy({$0.swaps.allSatisfy{$0.count>0 && $0.count<=9999 && $0.zone != .side}}),
          lab.watches.allSatisfy({$0.targetCents>=0 && $0.targetCents<=1_000_000_000}),
          lab.priceHistory.allSatisfy({id,quotes in quotes.allSatisfy{$0.variantID==id && $0.cents>=0 && $0.cents<=1_000_000_000}})
    else { throw DataError.message("Backup contains duplicate IDs, invalid probability rules, or invalid saved quantities/prices.") }
}
