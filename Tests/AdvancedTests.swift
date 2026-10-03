import Foundation
@main struct AdvancedTests {
 static func main() throws {
 func check(_ v:Bool,_ s:String){precondition(v,s)}
 let a=Card(id:"1",name:"Starter",rarity:""),b=Card(id:"2",name:"Filler",rarity:"")
 let build=PersonalBuild(name:"Conditional",format:.tcg,cards:[BuildCard(card:a,zone:.main,count:3),BuildCard(card:b,zone:.main,count:3),BuildCard(card:a,zone:.side,count:1)])
 let remaining=try remainingBuild(build,removed:["starter":2,"filler":1]);check(physicalMain(remaining).count==3,"Known cards removed from main only");check(remaining.counts["starter"]==2,"Side remains unchanged")
 check(abs(hypergeometric(deck:3,hits:1,hand:1,count:1)-1.0/3)<1e-10,"Conditional odds")
 do{_=try remainingBuild(build,removed:["starter":4]);fatalError("Over-removal accepted")}catch{}
 var inv=Inventory();inv.unassigned["starter"]=2
 var data=AdvancedData();data.locations=[CardLocation(holdingID:"unspecified:starter",label:"Binder",count:2)]
 check(locationIssues(data,inventory:inv).isEmpty,"Located copies fit ownership");inv.unassigned["starter"]=1;check(locationIssues(data,inventory:inv).count==1,"Inventory reduction surfaces conflict")
 func info(_ id:Int)->CardInfo { CardInfo(id:String(id),name:id==1 ? "Starter" : "Card \(id)",type:"Effect Monster",description:"Draw a card",race:"Warrior",attribute:"LIGHT",archetype:"",atk:1500,def:1000,level:4,formats:["TCG"],genesysPoints:nil,mdRarity:"",link:"",aliases:[],banlist:[:]) }
 let spell=CardInfo(id:"spell",name:"Spell",type:"Spell Card",description:"",race:"",attribute:"",archetype:"",atk:nil,def:nil,level:nil,formats:[],genesysPoints:nil,mdRarity:"",link:"",aliases:[])
 var missingStats=CardSearchFilter();missingStats.minATK = -5;check(!missingStats.matches(spell,points:[:]),"Missing ATK never satisfies even a negative minimum");missingStats=CardSearchFilter();missingStats.maxDEF=Int.max;check(!missingStats.matches(spell,points:[:]),"Missing DEF never satisfies an active maximum")
 let c=info(1);var filter=CardSearchFilter();filter.effect="draw";filter.minATK=1000;filter.maxATK=1600;check(filter.matches(c,points:[:]),"Combined effect and stats");filter.attribute="DARK";check(!filter.matches(c,points:[:]),"Attribute filter");filter.attribute="All";filter.maxPoints=10;check(!filter.matches(c,points:[:]),"Missing points never treated as zero")
 var cards:[String:CardInfo]=[:],rows:[BuildCard]=[]
 for i in 1...15 {let c=info(i);cards[c.name.lowercased()]=c;rows.append(BuildCard(card:Card(id:c.id,name:c.name,rarity:""),zone:.main,count:i==1 ? 1 : (i==15 ? 0 : 3)))}
 rows=rows.filter{$0.count>0}; // one starter + thirteen triples = 40
 let source=PersonalBuild(name:"Optimizer",format:.tcg,cards:rows)
 let bucket=CardBucket(buildID:source.id,name:"Starter",cards:["starter"])
 let route=ComboRoute(buildID:source.id,name:"Open starter",needs:[ComboNeed(bucketID:bucket.id)])
 let r=try optimizeRatios(build:source,unlocked:["starter","card2"],targetSize:40,hand:5,buckets:[bucket],routes:[route],cards:cards,points:[:],md:nil,inventory:Inventory(),quotes:[:],budget:nil)
 check(r.build.counts["starter"]==3 && r.build.counts["card2"]==1,"Optimizer maximizes starter ratio at fixed deck size")
 check(r.checked==3 && r.build.id != source.id && source.counts["starter"]==1,"Exhaustive size-valid candidates and immutable source")
 check(abs(r.probability-(1-choose(37,5)/choose(40,5)))<1e-10,"Optimized exact probability")
 do{_=try optimizeRatios(build:source,unlocked:["starter","card2"],targetSize:40,hand:5,buckets:[bucket],routes:[route],cards:cards,points:[:],md:nil,inventory:Inventory(),quotes:[:],budget:0);fatalError("Unpriced budget accepted")}catch{}
 check(htmlEscape("<script> & \"")=="&lt;script&gt; &amp; &quot;","HTML escaping")
 let decoded=try JSONDecoder().decode(AdvancedData.self,from:JSONEncoder().encode(data));check(decoded.locations[0].count==2,"Location persistence")
 print("Advanced tests passed: conditional removal/odds, ownership conflicts, effect/stat filters, exhaustive optimizer and budget, persistence, escaping.")
 }
}
