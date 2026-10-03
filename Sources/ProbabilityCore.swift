import Foundation

func choose(_ n:Int,_ k:Int) -> Double {
    guard n>=0,k>=0,k<=n else { return 0 };let r=min(k,n-k)
    if r==0 { return 1 };return (1...r).reduce(1.0) { $0*Double(n-r+$1)/Double($1) }
}
func hypergeometric(deck:Int,hits:Int,hand:Int,count:Int) -> Double {
    guard deck>0,hits>=0,hits<=deck,hand>=0,hand<=deck else { return 0 }
    return choose(hits,count)*choose(deck-hits,hand-count)/choose(deck,hand)
}
struct HandCard:Identifiable { let id=UUID();let card:Card }
func physicalMain(_ build:PersonalBuild) -> [Card] {
    build.cards.filter{$0.zone == .main && $0.count>0}.flatMap { Array(repeating:$0.card,count:min(9999,$0.count)) }
}
struct ProbabilityInput:Sendable {
    let masks:[Int]
    let bucketIDs:[String]
    let routes:[ComboRoute]
    let hand:Int
}
struct ProbabilityResult:Sendable {
    let probability:Double
    let exact:Bool
    let trials:Int
    let lower:Double
    let upper:Double
}
func probabilityInput(build:PersonalBuild,buckets:[CardBucket],routes:[ComboRoute],hand:Int) throws -> ProbabilityInput {
    guard !routes.isEmpty,routes.allSatisfy({!$0.needs.isEmpty}),buckets.count<=12 else { throw DataError.message("Add at least one route with requirements. Up to 12 buckets are supported per calculation.") }
    let keys=buckets.map(\.id)
    for route in routes { for need in route.needs {
        guard keys.contains(need.bucketID),need.minimum>=0,need.maximum>=need.minimum,need.maximum<=10 else { throw DataError.message("A requirement has a missing bucket or invalid range (0–10).") }
    } }
    let cards=physicalMain(build)
    guard cards.count>0,cards.count<=100,hand>=0,hand<=min(10,cards.count) else { throw DataError.message("Use a Main Deck of 1–100 cards and a hand size of 0–10, no larger than the deck.") }
    let masks=cards.map { card in buckets.enumerated().reduce(0) { mask,pair in pair.element.cards.contains(collectionKey(card.name)) ? mask | (1<<pair.offset) : mask } }
    return ProbabilityInput(masks:masks,bucketIDs:keys,routes:routes,hand:hand)
}
func routeMatches(_ masks:[Int],route:ComboRoute,bucketIDs:[String]) -> Bool {
    guard !route.needs.isEmpty else { return false }
    var slots:[Int]=[]
    for need in route.needs {
        guard let index=bucketIDs.firstIndex(of:need.bucketID) else { return false };let bit=1<<index
        let count=masks.filter{($0 & bit) != 0}.count
        if count<need.minimum || count>need.maximum { return false }
        slots+=Array(repeating:bit,count:need.minimum)
    }
    guard route.distinctCopies else { return true }
    if slots.count>masks.count { return false }
    // Bipartite matching: a physical card can fill only one requirement slot.
    var assigned=Array(repeating:-1,count:masks.count)
    func augment(_ slot:Int,_ visited:inout Set<Int>) -> Bool {
        for i in masks.indices where (masks[i] & slots[slot]) != 0 && visited.insert(i).inserted {
            if assigned[i]<0 || augment(assigned[i],&visited) { assigned[i]=slot;return true }
        };return false
    }
    for slot in slots.indices { var visited=Set<Int>();if !augment(slot,&visited) { return false } };return true
}
func comboMatches(_ masks:[Int],input:ProbabilityInput) -> Bool { input.routes.contains { routeMatches(masks,route:$0,bucketIDs:input.bucketIDs) } }
func exactCombo(_ input:ProbabilityInput,nodeLimit:Int=350000) throws -> ProbabilityResult {
    let groups=Dictionary(grouping:input.masks,by:{$0}).map { ($0.key,$0.value.count) }.sorted{$0.0<$1.0}
    let denominator=choose(input.masks.count,input.hand)
    var success=0.0,nodes=0,hand:[Int]=[]
    var remaining=Array(repeating:0,count:groups.count+1)
    for i in groups.indices.reversed() { remaining[i]=remaining[i+1]+groups[i].1 }
    func visit(_ i:Int,_ left:Int,_ weight:Double) throws {
        nodes+=1
        if nodes%1000==0 { try Task.checkCancellation() }
        guard nodes<=nodeLimit else { throw DataError.message("Exact calculation exceeded the complexity limit. Choose Monte Carlo for an estimate, or simplify the buckets/routes.") }
        if left==0 { if comboMatches(hand,input:input) { success+=weight };return }
        guard i<groups.count,remaining[i]>=left else { return }
        let low=max(0,left-remaining[i+1]),high=min(left,groups[i].1)
        if low>high { return }
        for n in low...high {
            hand+=Array(repeating:groups[i].0,count:n)
            try visit(i+1,left-n,weight*choose(groups[i].1,n))
            if n>0 { hand.removeLast(n) }
        }
    }
    try visit(0,input.hand,1)
    let p=min(1,max(0,success/denominator));return ProbabilityResult(probability:p,exact:true,trials:0,lower:p,upper:p)
}
func simulateCombo(_ input:ProbabilityInput,trials:Int=30000) throws -> ProbabilityResult {
    guard trials>0 else { throw DataError.message("Simulation needs a positive trial count.") }
    var hits=0,rng=SystemRandomNumberGenerator()
    for trial in 0..<trials {
        if trial%500==0 { try Task.checkCancellation() }
        var deck=input.masks
        for i in 0..<input.hand { let j=Int.random(in:i..<deck.count,using:&rng);deck.swapAt(i,j) }
        if comboMatches(Array(deck.prefix(input.hand)),input:input) { hits+=1 }
    }
    let n=Double(trials),p=Double(hits)/n,z=1.95996398454005,d=1+z*z/n
    let center=(p+z*z/(2*n))/d,margin=z*sqrt(p*(1-p)/n+z*z/(4*n*n))/d
    return ProbabilityResult(probability:p,exact:false,trials:trials,lower:max(0,center-margin),upper:min(1,center+margin))
}
