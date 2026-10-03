import Foundation
@main struct WorkshopTests {
 static func main() throws {
  func check(_ value:Bool,_ message:String) { precondition(value,message) }
  func info(_ id:String,_ name:String,_ type:String="Effect Monster",_ banned:[String:String]=[:],_ points:Int?=0)->CardInfo {
   CardInfo(id:id,name:name,type:type,description:"",race:"",attribute:"",archetype:"",atk:nil,def:nil,level:nil,formats:["TCG","OCG","Goat","Edison","Master Duel"],genesysPoints:points,mdRarity:"",link:"",aliases:[],banlist:banned)
  }
  check(budgetCents("nan")==nil && budgetCents("inf")==nil && budgetCents("-1")==nil && budgetCents("30.50")==3050,"Budget rejects nonfinite values")
  let a=Card(id:"ygo:1",name:"Card, A",rarity:""),b=Card(id:"ygo:2",name:"Card B",rarity:"")
  let ia=info("1",a.name),ib=info("2",b.name,"Fusion Monster",["ban_tcg":"Limited"],50)
  let db=["1":ia,"2":ib,a.name.lowercased():ia,b.name.lowercased():ib]
  let one=PersonalBuild(name:"One",format:.tcg,cards:[BuildCard(card:a,zone:.main,count:3),BuildCard(card:b,zone:.extra,count:1)],allocated:true)
  let two=PersonalBuild(name:"Two",format:.tcg,cards:[BuildCard(card:a,zone:.side,count:2),BuildCard(card:b,zone:.extra,count:2)],allocated:true)
  let diff=compareBuilds(one,two);check(diff.count==3,"Zone differences retained")
  var inventory=Inventory();inventory.unassigned=[collectionKey(a.name):4,collectionKey(b.name):1]
  let conflicts=allocationConflicts([one,two],inventory:inventory)
  check(conflicts.count==2 && conflicts.first{$0.name==a.name}?.requested==5,"Shared copies produce conflicts")
  let free=availableInventory(inventory,excluding:two.id,builds:[one,two]);check(free.owned(a.name)==1 && free.owned(b.name)==0,"Exclude own reservation")
  let ydk=try exportYDK(one,cards:db);let imported=try parseYDK(ydk,cards:db,format:.tcg)
  check(imported.deck.total==4 && imported.deck.extra.first?.amount==1,"YDK zone/passcode roundtrip")
  do { _=try parseYDK("#main\n999999",cards:db,format:.tcg);fatalError("Unknown passcode accepted") } catch {}
  let csv="name,quantity\n\"Card, A\",3\nCard B,2"
  let incoming=try parseCollection(csv,cards:db);check(incoming.owned(a.name)==3,"Quoted comma import")
  let exported=collectionCSV(incoming,names:[collectionKey(a.name):a.name,collectionKey(b.name):b.name])
  let roundtrip=try parseCollection(exported,cards:db);check(roundtrip.owned(a.name)==3 && roundtrip.owned(b.name)==2,"CSV roundtrip")
  check(try parseCollection("2 Card, A\n1 Card B",cards:db).owned(a.name)==2,"Pasted collection")
  do { _=try parseCollection("name,quantity\nCard B,-2",cards:db);fatalError("Negative accepted") } catch {}
  var f=Filters();f.requiredCards=[a.name];let saved=SavedSearch(name:"Test",format:.genesys,type:DeckType(id:"x",name:"X"),start:Date(),end:Date(),tier:.premier,filters:f)
  var w=WorkshopData();w.builds=[one,two];w.searches=[saved];w.favorites=["x"]
  let restored=try JSONDecoder().decode(WorkshopData.self,from:JSONEncoder().encode(w));check(restored.builds[0].allocated && restored.searches[0].filters.requiredCards==[a.name],"Persistent build allocation and search filters")
  let report=checkLegality(two,cards:db,points:db);check(report.errors.contains{$0.contains("limit 1")},"Banlist count across zones")
  var genesys=two;genesys.format = .genesys;genesys.pointCap=50
  let g=checkLegality(genesys,cards:db,points:db);check(g.points==100 && g.errors.contains{$0.contains("exceed cap")},"Genesys all-zone points")
  var md=one;md.format = .masterDuel;check(!checkLegality(md,cards:db,points:db).unknown.isEmpty,"Unsupported banlist not claimed legal")
  check(edisonLimits.count==135 && edisonLimits[collectionKey("Pot of Greed")]==0 && edisonLimits[collectionKey("Heavy Storm")]==1 && edisonLimits[collectionKey("Royal Oppression")]==2,"Official Edison list counts and categories")
  let mdRules=MasterDuelRules(fetched:Date(),limits:[collectionKey(a.name):1,collectionKey(b.name):3])
  check(checkLegality(md,cards:db,points:db,masterDuel:mdRules).errors.contains{$0.contains("limit 1")},"Master Duel live limits applied")
  let avg=PersonalBuild.average([one.deck,two.deck],name:"Avg",format:.tcg);check(avg.deck.extra.first?.amount==2,"Average rounds by zone")
  let empty=PersonalBuild(name:"Empty",format:.tcg,cards:[])
  let packages=commonPackages([one.deck,one.deck,empty.deck]);check(packages.count==1 && packages[0].cards.count==2 && packages[0].count==2,"Repeated optional package")
  check(commonPackages([one.deck,one.deck,two.deck]).isEmpty,"Universal cards are not optional packages")
  let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer { try? FileManager.default.removeItem(at:dir) }
  let store=try LocalStore(directory:dir);try store.write(w,name:"workshop.json");check(try store.read("workshop.json",as:WorkshopData.self)?.builds.count==2,"Disk persistence")
  print("Workshop tests passed: builds, comparisons, allocations, CSV/YDK, persistence, rules and points.")
 }
}
