import SwiftUI
@main struct FeatureTests {
 @MainActor static func main() async throws {
    let seed = CommandLine.arguments.dropFirst().first
    let directory = seed.map { URL(fileURLWithPath:$0) } ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { if seed == nil { try? FileManager.default.removeItem(at:directory) } }
    let m=Model(storeDirectory:directory)
    func check(_ value:Bool,_ message:String) { precondition(value,message) }
    let db=try await YGO.shared.cardDatabase();m.cardIndex=db.index
    m.format = .tcg;await m.enrichCards();check(m.genesysIndex["ash blossom & joyous spring"]?.genesysPoints != nil,"Genesys search points load without switching formats")
    let normal=Array(db.cards.filter{$0.type=="Normal Monster" && $0.formats.contains("TCG") && ($0.banlist ?? [:]).isEmpty}.sorted{$0.name<$1.name}.prefix(15))
    check(normal.count==15,"Fixture has enough cards")
    func card(_ c:CardInfo)->Card{Card(id:"ygo:"+c.id,name:c.name,rarity:"")}
    let priced=card(db.index["banishment of the darklords"]!)
    var cards=Array(normal.prefix(13)).map{BuildCard(card:card($0),zone:.main,count:3)}
    cards[0]=BuildCard(card:priced,zone:.main,count:3)
    cards.append(BuildCard(card:card(normal[13]),zone:.main,count:1))
    cards.append(BuildCard(card:card(normal[14]),zone:.side,count:3))
    var first=PersonalBuild(name:"QA · Baseline 40",format:.tcg,cards:cards)
    var second=first;second.id=UUID().uuidString;second.name="QA · Alternative 40";second.cards[0].count=1;second.cards[13].count=3
    m.putBuild(first);m.putBuild(second)
    check(m.workshop.builds.count==2 && physicalMain(first).count==40,"Create independent builds")
    first.cards[0].count=2;m.putBuild(first)
    check(m.lab.revisions.count==1 && m.lab.revisions[0].build.cards[0].count==3,"Edit captures prior version")
    first.cards[0].count=3;m.putBuild(first)
    let ydk=try exportYDK(first,cards:db.index);let imported=try parseYDK(ydk,cards:db.index,format:.tcg)
    check(imported.counts==first.counts && imported.deck.side.count==1,"YDK roundtrip includes side")
    let csv="name,quantity\nBanishment of the Darklords,2\n\(csvField(normal[13].name)),5"
    let incoming=try parseCollection(csv,cards:db.index)
    m.importCollection(incoming,replace:true);m.importCollection(incoming,replace:false)
    check(m.inventory.owned(priced.name)==4,"Collection add merges quantities")
    m.importCollection(incoming,replace:true);check(m.inventory.owned(priced.name)==2,"Collection replace")
    m.setUnassigned(priced.name,count:-1);check(m.inventory.owned(priced.name)==0,"Negative owned counts clamp")
    m.setUnassigned(priced.name,count:20000);check(m.inventory.owned(priced.name)==9999,"Owned count upper bound")
    m.setUnassigned(priced.name,count:0)
    let product=TCGProduct(id:679024,name:priced.name,rarity:"Ultra Rare",set:"Battles of Legend: Monster Mayhem",number:"BLMM-EN089",indicativeLow:0)
    let variant=CardVariant(cardName:priced.name,product:product,condition:"Near Mint",edition:"1st Edition")
    m.setOwned(variant,count:2);m.setTarget(variant)
    let quote=PriceQuote(variantID:variant.id,cents:125,shippingCents:99,seller:"QA fixture",listingID:"qa",quantity:10,checked:Date(),condition:variant.condition,edition:variant.edition,verified:true)
    check(!m.lab.autoRefreshPrices,"Price automation defaults off")
    check(m.needsPriceUpdate(variant),"Missing quote needs updating")
    m.quotes[variant.id]=quote;try m.store!.write(m.quotes,name:"tcg-quotes.json");m.recordPrice(quote);m.recordPrice(quote)
    check(m.lab.priceHistory[variant.id]?.count==1,"Price history deduplicates same fetch")
    var fetchCount=0
    try await m.updateQuote(variant,fetch:{ _ in fetchCount+=1;return quote })
    check(fetchCount==0 && m.lastSuccessfulPriceUpdate==quote.checked,"Fresh quote skips network and keeps successful timestamp")
    m.changeLab{$0.watches=[PriceWatch(variantID:variant.id,targetCents:125)]}
    check(m.triggeredWatches.count==1,"Watch triggers at equal price")
    m.pricingErrors[variant.id]="Refresh failed"
    check(m.triggeredWatches.isEmpty,"Failed refresh does not trigger a current price alert")
    try m.store!.write(m.pricingErrors,name:"tcg-pricing-errors.json")
    let failedReload=Model(storeDirectory:directory)
    check(failedReload.pricingErrors[variant.id] != nil && failedReload.triggeredWatches.isEmpty,"Failed refresh state survives restart")
    m.pricingErrors[variant.id]=nil
    try m.store!.write(m.pricingErrors,name:"tcg-pricing-errors.json")
    let stale=PriceQuote(variantID:variant.id,cents:125,shippingCents:99,seller:"QA fixture",listingID:"old",quantity:10,checked:Date().addingTimeInterval(-90000),condition:variant.condition,edition:variant.edition,verified:true)
    m.quotes[variant.id]=stale
    check(!stale.isFresh && m.triggeredWatches.isEmpty,"Stale prices remain available without triggering alerts")
    check(m.needsPriceUpdate(variant),"Stale quote needs updating")
    try await m.updateQuote(variant,fetch:{ _ in fetchCount+=1;return quote })
    check(fetchCount==1 && m.quotes[variant.id]?.checked==quote.checked && m.refreshingQuoteIDs.isEmpty,"Stale quote refreshes and releases busy state")
    await m.refreshWatchedPrices()
    check(m.watchStatus.contains("1 already fresh"),"Watch refresh skips fresh quotes without network")
    let stats=aggregate([first.deck]);let totals=buildTotals(stats:stats,sample:1,inventory:m.inventory,quotes:m.quotes,roundUp:false)
    check(totals.builtCents==250 && totals.missingCents==125 && totals.unpricedMissingCopies>0,"Exact printing valuation and unpriced remainder")
    first.allocated=true;second.allocated=true;m.putBuild(first);m.putBuild(second)
    check(!allocationConflicts(m.workshop.builds,inventory:m.inventory).isEmpty,"Conflicting assembled decks reported")
    check(availableInventory(m.inventory,excluding:first.id,builds:m.workshop.builds).owned(priced.name)==1,"Other build reservation deducted")
    first.allocated=false;second.allocated=false;m.putBuild(first);m.putBuild(second)
    let shared=shoppingList(builds:[first,second],inventory:m.inventory,quotes:m.quotes,simultaneous:false)
    let simultaneous=shoppingList(builds:[first,second],inventory:m.inventory,quotes:m.quotes,simultaneous:true)
    check(shared.first{$0.name==priced.name}?.missing==1 && simultaneous.first{$0.name==priced.name}?.missing==2,"Shopping modes")
    let starter=CardBucket(buildID:first.id,name:"Starters",role:"Starter",cards:[collectionKey(priced.name)])
    let extender=CardBucket(buildID:first.id,name:"Extenders",role:"Extender",cards:[collectionKey(normal[13].name)])
    let route=ComboRoute(buildID:first.id,name:"Open a starter",needs:[ComboNeed(bucketID:starter.id)])
    let plan=SidePlan(buildID:first.id,matchup:"QA matchup",swaps:[SideSwap(outgoing:priced.name,incoming:normal[14].name,count:1)])
    m.changeLab{$0.buckets=[starter,extender];$0.combos=[route];$0.sidePlans=[plan];$0.matches=[MatchRecord(build:first,opponent:"QA matchup",result:"Win",turnOrder:"Going first",notes:"Fixture")]}
    let exact=try exactCombo(probabilityInput(build:first,buckets:[starter,extender],routes:[route],hand:5))
    check(abs(exact.probability-(1-choose(37,5)/choose(40,5)))<1e-10,"Model buckets feed exact combo calculation")
    let post=try applySidePlan(plan,to:first);check(physicalMain(post).count==40 && post.counts==first.counts && post.id != first.id,"Side plan preserves copies and creates separate build")
    var advanced=AdvancedData();advanced.substitutions=[SubstitutionGroup(name:"QA alternatives",cards:[priced.name,normal[13].name])];advanced.locations=[CardLocation(holdingID:variant.id,label:"QA binder",count:1)];m.saveAdvanced(advanced)
    check(locationIssues(m.advanced,inventory:m.inventory).isEmpty,"Place owned printing")
    m.setOwned(variant,count:0);check(!locationIssues(m.advanced,inventory:m.inventory).isEmpty,"Location conflict after reducing ownership");m.recover();check(m.inventory.owned(priced.name)==2,"Undo collection edit")
    m.format = .tcg;let type=DeckType(id:"ygo:Darklord",name:"Darklord");m.types=[type];m.selectedType=type.id
    m.snapshot=Snapshot(type:type,from:"2026-09-03",through:"2026-10-03",fetched:Date(),decks:[first.deck,second.deck],format:"TCG",eventTier:EventTier.any.rawValue)
    try m.store!.write(m.snapshot!,name:"latest-snapshot.json")
    m.setRole(priced.id,.engine);check(m.role(priced.id) == .engine,"Card role saved")
    m.favorite(type);check(m.workshop.favorites.contains("darklord"),"Favorite toggled")
    m.setHidden(type,true);check(m.isHidden(type) && m.selectedType==nil,"Hide clears active selection")
    m.setHidden(type,false);m.selectedType=type.id
    m.filters.requiredCards=[priced.name];m.saveSearch("QA · Include starter");check(m.workshop.searches.last?.filters.requiredCards==[priced.name],"Saved search captures exact card filters")
    m.captureTrend("QA · Earlier");m.snapshot=Snapshot(type:type,from:"2026-09-03",through:"2026-10-03",fetched:Date(),decks:[second.deck],format:"TCG");m.captureTrend("QA · Later")
    check(m.lab.trends.count==2 && !trendChanges(m.lab.trends[0].decks,m.lab.trends[1].decks).isEmpty,"Dataset capture and comparison")
    let previousSnapshot=m.snapshot
    m.start=Date(timeIntervalSince1970:2_000_000_000);m.end=Date(timeIntervalSince1970:1_900_000_000);m.load()
    check(!m.loading && m.error?.contains("start date") == true && m.snapshot?.fetched==previousSnapshot?.fetched,"Invalid date range preserves cached snapshot")
    m.format = .masterDuel;m.start=Date(timeIntervalSince1970:0);m.end=Date();m.load()
    check(!m.loading && m.error?.contains("launch") == true,"Master Duel date validation")
    m.format = .tcg;m.start=Date(timeIntervalSince1970:1_788_393_600);m.end=Date();m.error=nil
    let full=m.fullBackup;let encoded=try JSONEncoder().encode(full);let roundtrip=try JSONDecoder().decode(WorkshopBackup.self,from:encoded);try validateBackup(roundtrip)
    let restore=Model(storeDirectory:directory.appendingPathComponent("roundtrip"));try restore.restoreBackup(roundtrip)
    check(restore.workshop.builds.count==2 && restore.inventory.owned(priced.name)==2 && restore.lab.buckets.count==2 && restore.lab.combos.count==1 && restore.advanced.locations.count==1 && restore.workshop.searches.count==1 && restore.lab.sidePlans.count==1 && restore.lab.matches.count==1 && restore.lab.trends.count==2,"Full backup restores all modules")
    var bad=roundtrip;bad.inventory.quantities[variant.id] = -1
    do {try restore.restoreBackup(bad);fatalError("Invalid backup accepted")}catch{}
    check(restore.inventory.owned(priced.name)==2,"Rejected backup preserves data")
    let reload=Model(storeDirectory:directory);check(reload.workshop.builds.count==2 && reload.lab.watches.count==1 && reload.roles==m.roles && reload.advanced.substitutions.count==1,"Restart persistence")
    let html=deckHTML(first,images:[:],labels:[:]);check(html.contains(priced.name),"HTML export contains deck cards")
    let png=try deckPNG(first,images:[:],labels:[:]);check(png.count>10000,"PNG renders populated deck")
    try html.write(to:directory.appendingPathComponent("qa-deck.html"),atomically:true,encoding:.utf8);try png.write(to:directory.appendingPathComponent("qa-deck.png"));try ydk.write(to:directory.appendingPathComponent("qa-deck.ydk"),atomically:true,encoding:.utf8)
    print("Feature integration passed: model edits, all-module backup/reload, quantities, imports, targets/value, watches/history, allocations, shopping, buckets/combos, side plans, locations, roles, favorites/hiding, saved searches, trends, HTML/PNG/YDK export.")
    if seed != nil {print("QA fixture saved: \(directory.path)")}
 }
}
