import SwiftUI
struct SubstitutionsView:View {
 @ObservedObject var model:Model
 @State var name=""
 @State var members=""
 @State var notes=""
 @State var groupID=""
 @State var buildID=""
 @State var from=""
 @State var to=""
 @State var count=1
 @State var notice=""
 var group:SubstitutionGroup?{model.advanced.substitutions.first{$0.id==groupID}}
 var build:PersonalBuild?{model.workshop.builds.first{$0.id==buildID}}
 var body:some View {ScrollView{VStack(alignment:.leading,spacing:12){
 Text("Interchangeable card groups").font(.headline)
 Text("Define your own alternatives. Membership is your judgment; swapping cards does not guarantee the same combo or function.")
 TextField("Group name",text:$name);TextField("Exact card names, one per line",text:$members,axis:.vertical).lineLimit(3...8);TextField("Why these can substitute",text:$notes)
 Button("Save group"){let names=members.split(separator:"\n").map{String($0).trimmingCharacters(in:.whitespaces)};guard !name.isEmpty,Set(names.map(collectionKey)).count>=2,names.allSatisfy({model.cardIndex[$0.lowercased()] != nil})else{notice="Enter a name and at least two exact card names from Card search.";return};var next=model.advanced;next.substitutions.append(SubstitutionGroup(name:name,cards:Array(Set(names)).sorted(),notes:notes));model.saveAdvanced(next);name="";members="";notes=""}
 ForEach(model.advanced.substitutions){g in HStack{VStack(alignment:.leading){Text(g.name).bold();Text(g.cards.joined(separator:" · "));Text(g.notes).foregroundStyle(.secondary)};Spacer();Button("Remove"){var next=model.advanced;next.substitutions.removeAll{$0.id==g.id};model.saveAdvanced(next)}}}
 Divider();Text("Try an owned alternative").font(.headline)
 Picker("Group",selection:$groupID){Text("Choose").tag("");ForEach(model.advanced.substitutions){Text($0.name).tag($0.id)}}
 Picker("Build",selection:$buildID){Text("Choose").tag("");ForEach(model.workshop.builds){Text($0.name).tag($0.id)}}
 if let g=group,let b=build {
 Picker("Replace",selection:$from){Text("Choose").tag("");ForEach(b.cards.filter{g.cards.map(collectionKey).contains(collectionKey($0.card.name))}){Text("\($0.card.name) · \($0.zone.rawValue)").tag($0.id)}}
 Picker("With",selection:$to){Text("Choose").tag("");ForEach(g.cards.filter{model.inventory.owned($0)>0},id:\.self){Text("\($0) · \(model.inventory.owned($0)) owned").tag($0)}}
 Stepper("Copies: \(count)",value:$count,in:1...3)
 Button("Save substituted copy"){
 guard let row=b.cards.first(where:{$0.id==from}),let info=model.cardIndex[to.lowercased()],count<=row.count,collectionKey(to) != collectionKey(row.card.name) else{notice="Choose different cards and a quantity present in the build.";return}
 let existing=b.counts[collectionKey(to)] ?? 0
 guard model.inventory.owned(to)>=existing+count else{notice="Not enough owned copies for this replacement plus copies already in the build.";return}
 var copy=b;copy.id=UUID().uuidString;copy.name+=" · alternative";copy.allocated=false
 copy.cards=copy.cards.map{var r=$0;if r.id==row.id{r.count-=count};return r}.filter{$0.count>0};copy.cards.append(BuildCard(card:Card(id:info.id,name:info.name,rarity:""),zone:row.zone,count:count));copy.cards=mergeBuildCards(copy.cards)
 let report=checkLegality(copy,cards:model.cardIndex,points:model.genesysIndex,masterDuel:model.masterDuelRules)
 model.putBuild(copy);notice="Saved \(copy.name). Legality: \(report.errors.count) errors, \(report.unknown.count) unknown checks. Review in Builds."
 }
 }
 Text(notice).foregroundStyle(.orange)
 }}}
}
struct LocationsView:View {
 @ObservedObject var model:Model
 @State var holding=""
 @State var label=""
 @State var count=1
 @State var notice=""
 var holdings:[String] {(Array(model.inventory.quantities.keys)+model.inventory.unassigned.keys.map{"unspecified:"+$0}).filter{locationHoldingCount($0,inventory:model.inventory)>0}.sorted()}
 func title(_ id:String)->String {if id.hasPrefix("unspecified:"){let key=String(id.dropFirst(12));return (model.collectionNames[key] ?? key)+" · unspecified printing"};guard let v=model.inventory.variants[id]else{return id};return "\(v.cardName) · \(v.label)"}
 var body:some View {VStack(alignment:.leading,spacing:12){
 Text("Physical storage locations").font(.headline);Text("Split owned copies between a binder, box, trade binder, or assembled deck. Locations describe storage; assembled-build reservations remain separate.")
 Picker("Holding",selection:$holding){Text("Choose owned cards").tag("");ForEach(holdings,id:\.self){Text("\(title($0)) · \(locationHoldingCount($0,inventory:model.inventory)) owned").tag($0)}}
 HStack{TextField("Location, e.g. Blue binder / page 4",text:$label);Stepper("\(count) copies",value:$count,in:1...9999);Button("Place copies"){
 let used=model.advanced.locations.filter{$0.holdingID==holding}.reduce(0){$0+$1.count}
 guard !label.trimmingCharacters(in:.whitespaces).isEmpty,count+used<=locationHoldingCount(holding,inventory:model.inventory)else{notice="Choose a location and no more than the unlocated owned quantity.";return}
 var next=model.advanced;next.locations.append(CardLocation(holdingID:holding,label:label,count:count));model.saveAdvanced(next);notice="Copies placed."}}
 ForEach(locationIssues(model.advanced,inventory:model.inventory),id:\.self){Text($0).foregroundStyle(.orange)}
 Text(notice)
 List(model.advanced.locations){row in HStack{VStack(alignment:.leading){Text(title(row.holdingID));Text("\(row.count) copies · \(row.label)").foregroundStyle(.secondary)};Spacer();Button("Unplace / move"){holding=row.holdingID;label=row.label;count=row.count;var next=model.advanced;next.locations.removeAll{$0.id==row.id};model.saveAdvanced(next)}}}
 }}
}
