import Foundation
@main struct LabTests {
 static func main() throws {
    func check(_ yes:Bool,_ message:String){precondition(yes,message)}
    func near(_ a:Double,_ b:Double,_ message:String){check(abs(a-b)<1e-10,message)}
    let ca=Card(id:"1",name:"A",rarity:""),cb=Card(id:"2",name:"B",rarity:""),cc=Card(id:"3",name:"C",rarity:""),cd=Card(id:"4",name:"D",rarity:"")
    var build=PersonalBuild(name:"Probability fixture",format:.tcg,cards:[ca,cb,cc,cd].map{BuildCard(card:$0,zone:.main,count:1)})
    let a=CardBucket(buildID:build.id,name:"Starters",cards:["a","c"]),b=CardBucket(buildID:build.id,name:"Extenders",cards:["b","c"])
    var route=ComboRoute(buildID:build.id,name:"Two ingredients",needs:[ComboNeed(bucketID:a.id),ComboNeed(bucketID:b.id)])
    let input=try probabilityInput(build:build,buckets:[a,b],routes:[route],hand:2)
    near(try exactCombo(input).probability,0.5,"Distinct overlap uses matching not independent probabilities")
    route.distinctCopies=false
    let shared=try probabilityInput(build:build,buckets:[a,b],routes:[route],hand:2)
    near(try exactCombo(shared).probability,4.0/6,"One multifunctional card may satisfy both presence tests")
    let r1=ComboRoute(buildID:build.id,name:"A",needs:[ComboNeed(bucketID:a.id)]),r2=ComboRoute(buildID:build.id,name:"B",needs:[ComboNeed(bucketID:b.id)])
    let union=try probabilityInput(build:build,buckets:[a,b],routes:[r1,r2],hand:1)
    near(try exactCombo(union).probability,0.75,"OR union avoids double counting overlap")
    let maxRule=ComboRoute(buildID:build.id,name:"Avoid bricks",needs:[ComboNeed(bucketID:a.id,minimum:0,maximum:0)])
    near(try exactCombo(probabilityInput(build:build,buckets:[a],routes:[maxRule],hand:2)).probability,1.0/6,"Zero/max bucket constraint")
    near(try exactCombo(probabilityInput(build:build,buckets:[a],routes:[r1],hand:0)).probability,0,"Empty hand")
    for n in 1...60 { for k in [0,n/2,n] { let hand=min(5,n);near((0...hand).reduce(0){$0+hypergeometric(deck:n,hits:k,hand:hand,count:$1)},1,"Distribution normalizes") } }
    near((1...5).reduce(0){$0+hypergeometric(deck:40,hits:3,hand:5,count:$1)},1-choose(37,5)/choose(40,5),"40-card starter odds")
    // Exhaustively compare all physical 3-card subsets against the grouped exact engine.
    let masks=[0,1,1,2,3,3,0,2]
    let exhaustive=ProbabilityInput(masks:masks,bucketIDs:[a.id,b.id],routes:[r1,r2],hand:3)
    var successes=0,total=0
    for i in 0..<masks.count {for j in (i+1)..<masks.count {for k in (j+1)..<masks.count {total+=1;if comboMatches([masks[i],masks[j],masks[k]],input:exhaustive){successes+=1}}}}
    near(try exactCombo(exhaustive).probability,Double(successes)/Double(total),"Grouped category weights match exhaustive physical draws")
    do { _=try exactCombo(input,nodeLimit:1);fatalError("Complexity limit missing") } catch {}
    let simulation=try simulateCombo(input,trials:3000);check(abs(simulation.probability-0.5)<0.07 && simulation.lower<simulation.upper && !simulation.exact,"Monte Carlo estimate and interval")
    var emptyRoute=route;emptyRoute.needs=[]
    do{_=try probabilityInput(build:build,buckets:[a,b],routes:[emptyRoute],hand:2);fatalError("Empty route accepted")}catch{}
    var inv=Inventory();inv.unassigned=["a":2]
    let first=PersonalBuild(name:"One",format:.tcg,cards:[BuildCard(card:ca,zone:.main,count:3)])
    let second=PersonalBuild(name:"Two",format:.tcg,cards:[BuildCard(card:ca,zone:.main,count:2)])
    check(shoppingList(builds:[first,second],inventory:inv,quotes:[:],simultaneous:false)[0].missing==1,"Shared shopping uses max and subtracts owned once")
    check(shoppingList(builds:[first,second],inventory:inv,quotes:[:],simultaneous:true)[0].missing==3,"Simultaneous shopping sums requirements")
    build.cards.append(BuildCard(card:cb,zone:.side,count:2))
    let plan=SidePlan(buildID:build.id,matchup:"Test",swaps:[SideSwap(outgoing:"A",incoming:"B",count:1)])
    let sided=try applySidePlan(plan,to:build)
    check(sided.deck.main.reduce(0){$0+$1.amount}==4 && sided.deck.side.reduce(0){$0+$1.amount}==2 && sided.counts==build.counts,"Side swaps preserve zones sizes and collection needs")
    var invalid=plan;invalid.swaps[0].count=3
    do{_=try applySidePlan(invalid,to:build);fatalError("Unavailable swap accepted")}catch{}
    let revision=BuildRevision(build:build,note:"Before test")
    let match=MatchRecord(build:build,opponent:"Opponent",result:"Win",turnOrder:"Going first",notes:"Test")
    build.cards=[]
    check(!revision.build.cards.isEmpty && !match.build.cards.isEmpty,"Versions and matches are immutable snapshots")
    var lab=LabData();lab.buckets=[a,b];lab.combos=[route];lab.revisions=[revision];lab.matches=[match];lab.sidePlans=[plan]
    try validateLab(lab)
    var broken=lab;broken.combos[0].needs[0].minimum=11
    do { try validateLab(broken);fatalError("Invalid backup probability rule accepted") } catch {}
    let decoded=try JSONDecoder().decode(LabData.self,from:JSONEncoder().encode(lab))
    check(decoded.buckets==lab.buckets && decoded.matches[0].build.cards==match.build.cards,"Lab persistence roundtrip")
    let trends=trendChanges([first.deck],[second.deck]);near(trends[0].change,0,"Same inclusion different copies");near(trends[0].oldCopies,3,"Earlier mean")
    print("Lab tests passed: exact/overlap/OR probabilities, hypergeometric normalization, simulation, shopping, side plans, version snapshots, trends, persistence.")
 }
}
