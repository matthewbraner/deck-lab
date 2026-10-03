import SwiftUI
struct CardSearchView:View {
 @ObservedObject var model:Model
 @State var filter=CardSearchFilter()
 @State var selected:String?
 @State var expanded=false
 @State var notice=""
 var cards:[CardInfo] {Dictionary(grouping:Array(model.cardIndex.values),by: \.id).compactMap{$0.value.first}.sorted{$0.name<$1.name}}
 var matches:[CardInfo] {cards.filter{filter.matches($0,points:model.genesysIndex)}}
 var body:some View {VStack(alignment:.leading,spacing:16) {
    HStack(spacing:12) {LabSearch(title:"Search card names",text:$filter.name);LabSearch(title:"Find words in card effects",text:$filter.effect);Button {expanded.toggle()} label:{Label("Filters",systemImage:"slider.horizontal.3")}.accessibilityValue(expanded ? "Expanded" : "Collapsed");Button("Reset"){filter=CardSearchFilter()}}
    if expanded {VStack(alignment:.leading,spacing:14) {
        HStack(spacing:16) {
            Picker("Type",selection:$filter.type){Text("All").tag("All");ForEach(Array(Set(cards.map(\.type))).filter{!$0.isEmpty}.sorted(),id:\.self){Text($0).tag($0)}}
            Picker("Attribute",selection:$filter.attribute){Text("All").tag("All");ForEach(Array(Set(cards.map(\.attribute))).filter{!$0.isEmpty}.sorted(),id:\.self){Text($0).tag($0)}}
            Picker("Race",selection:$filter.race){Text("All").tag("All");ForEach(Array(Set(cards.map(\.race))).filter{!$0.isEmpty}.sorted(),id:\.self){Text($0).tag($0)}}
        }
        HStack(spacing:12){statField("Level / rank",$filter.level);statField("Min ATK",$filter.minATK);statField("Max ATK",$filter.maxATK);statField("Min DEF",$filter.minDEF);statField("Max DEF",$filter.maxDEF);statField("Max points",$filter.maxPoints)}
        Text("Leave a stat blank to ignore it. Points use your cached Genesys data.").font(.caption).foregroundStyle(.secondary)
    }.padding(16).background(.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:12))}
    HStack {Text("\(matches.count.formatted()) cards").font(.system(size:13,weight:.semibold));Spacer();if !notice.isEmpty {Label(notice,systemImage:"checkmark.circle").font(.caption).foregroundStyle(LabStyle.accent)}}
    HStack(alignment:.top,spacing:20) {
        ScrollView {LazyVGrid(columns:[GridItem(.adaptive(minimum:125,maximum:180),spacing:14)],spacing:14){ForEach(matches){c in Button{selected=c.id}label:{VStack(alignment:.leading,spacing:9){CardArtwork(info:c).frame(height:175).frame(maxWidth:.infinity).allowsHitTesting(false).accessibilityHidden(true);Text(c.name).font(.system(size:12,weight:.medium)).lineLimit(2).frame(height:32,alignment:.topLeading).frame(maxWidth:.infinity,alignment:.leading)}.padding(10).background(selected==c.id ? LabStyle.accent.opacity(0.10) : .primary.opacity(0.025),in:RoundedRectangle(cornerRadius:12)).overlay(RoundedRectangle(cornerRadius:12).strokeBorder(selected==c.id ? LabStyle.accent : .primary.opacity(0.07),lineWidth:selected==c.id ? 2 : 1))}.buttonStyle(.plain).accessibilityLabel("\(c.name), show card details").accessibilityValue(selected==c.id ? "Selected" : "")}}.padding(2)}.frame(maxWidth:.infinity,maxHeight:.infinity)
        if let c=cards.first(where:{$0.id==selected}) {
            Divider()
            ScrollView { VStack(alignment:.leading,spacing:14) {
                HStack {Text("CARD DETAILS").font(.system(size:10,weight:.semibold)).tracking(1).foregroundStyle(.secondary);Spacer();Button {selected=nil}label:{Image(systemName:"xmark")}.accessibilityLabel("Close card details").help("Close card details")}
                CardArtwork(info:c).frame(width:180,height:260).frame(maxWidth:.infinity)
                Text(c.name).font(.system(size:20,weight:.bold,design:.rounded))
                Text([c.type,c.attribute,c.race].filter{!$0.isEmpty}.joined(separator:" · ")).font(.caption).foregroundStyle(.secondary)
                Text(c.description).font(.system(size:13)).lineSpacing(3).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
                Button {if !model.filters.requiredCards.contains(c.name){model.filters.requiredCards.append(c.name)};notice="Required in explorer"}label:{Label("Require in explorer",systemImage:"plus.circle")}.frame(maxWidth:.infinity)
                Button {if !model.filters.excludedCards.contains(c.name){model.filters.excludedCards.append(c.name)};notice="Excluded from explorer"}label:{Label("Exclude from explorer",systemImage:"minus.circle")}.frame(maxWidth:.infinity)
            }.frame(maxWidth:.infinity,alignment:.leading) }.frame(width:270)
        }
    }
    if matches.isEmpty {ContentUnavailableView.search(text:filter.name)}
 } }
 func statField(_ title:String,_ value:Binding<Int?>)->some View {VStack(alignment:.leading,spacing:5){Text(title).font(.caption).foregroundStyle(.secondary);TextField("Any",value:value,format:.number).accessibilityLabel(title)}.frame(maxWidth:.infinity)}
}
struct AdvancedOddsView:View {
 @ObservedObject var model:Model
 @State var mode="Compare probabilities"
 @State var first=""
 @State var second=""
 @State var hand=5
 @State var wanted=1
 @State var bucketID=""
 @State var removed:[String:Int]=[:]
 @State var unlocked:Set<String>=[]
 @State var target=40
 @State var budget=""
 @State var allowUnknown=false
 @State var result=""
 @State var busy=false
 @State var optimized:PersonalBuild?
 var build:PersonalBuild? {model.workshop.builds.first{$0.id==first}}
 var buckets:[CardBucket] {model.lab.buckets.filter{$0.buildID==first}}
 var routes:[ComboRoute] {model.lab.combos.filter{$0.buildID==first}}
 var body:some View {VStack(alignment:.leading,spacing:12) {
 Picker("Tool",selection:$mode){ForEach(["Compare probabilities","Conditional draws","Optimize ratios"],id:\.self){Text($0)}}.pickerStyle(.segmented).tint(LabStyle.action)
 HStack {Picker("Reference build",selection:$first){Text("Choose").tag("");ForEach(model.workshop.builds){Text($0.name).tag($0.id)}};Stepper("Draw \(hand)",value:$hand,in:0...10)}
 if let b=build {
 if mode=="Compare probabilities" {
 Picker("Compare with",selection:$second){Text("Choose").tag("");ForEach(model.workshop.builds){Text($0.name).tag($0.id)}}
 Text("Both builds use the reference build’s buckets and all its combo routes (OR). Each bucket shows the chance to draw at least one member.").foregroundStyle(.secondary)
 if let other=model.workshop.builds.first(where:{$0.id==second}) {ForEach(buckets){bucket in HStack{Text(bucket.name);Spacer();Text("\(percent(hit(b,bucket))) → \(percent(hit(other,bucket)))")}}}
 Button("Calculate exact combo comparison"){calculate()}.disabled(busy || second.isEmpty)
 } else if mode=="Conditional draws" {
 Text("Mark cards already seen in hand, field, graveyard, or elsewhere outside the deck. Results count only the NEXT draws from the remaining Main Deck.")
 Picker("Bucket",selection:$bucketID){Text("Choose").tag("");ForEach(buckets){Text($0.name).tag($0.id)}}
 Stepper("At least \(wanted) hits",value:$wanted,in:0...10)
 if let remaining=try? remainingBuild(b,removed:removed),let bucket=buckets.first(where:{$0.id==bucketID}) {let n=physicalMain(remaining).count;let k=physicalMain(remaining).filter{bucket.cards.contains(collectionKey($0.name))}.count;Text("\(n) cards left · \(k) bucket cards · Probability: \(hand<=n ? percent((wanted...max(wanted,hand)).reduce(0){$0+hypergeometric(deck:n,hits:k,hand:hand,count:$1)}) : "Draw exceeds remaining deck")").font(.headline)}
 Button("Clear known cards"){removed=[:]}
 ScrollView{ForEach(b.cards.filter{$0.zone == .main}){row in Stepper("\(row.card.name): \(removed[collectionKey(row.card.name)] ?? 0) removed",value:Binding(get:{removed[collectionKey(row.card.name)] ?? 0},set:{removed[collectionKey(row.card.name)]=$0}),in:0...row.count)}}
 } else {
 Text("Unlock up to 7 existing Main Deck card types. Searches 0–3 copies each, keeping other cards fixed, to maximize any reference combo route. Save the result as a separate build.")
 HStack{Stepper("Target \(target)",value:$target,in:40...60);TextField("Optional budget to finish (USD)",text:$budget);Toggle("Allow incomplete rule checks",isOn:$allowUnknown)}
 HStack{Button("Refresh legality data"){Task{await model.refreshRules()}};Button("Optimize"){calculate()}.disabled(busy || unlocked.isEmpty);if let optimized{Button("Save optimized copy"){model.putBuild(optimized);self.optimized=nil;result+="\nSaved in Builds."}}}
 ScrollView {ForEach(b.cards.filter{$0.zone == .main}){row in Toggle("Unlock \(row.card.name) (currently \(row.count))",isOn:Binding(get:{unlocked.contains(collectionKey(row.card.name))},set:{if $0{unlocked.insert(collectionKey(row.card.name))}else{unlocked.remove(collectionKey(row.card.name))}}))}}
 }
 }
 if busy{ProgressView()};Text(result).textSelection(.enabled)
 }.onChange(of:first){_,_ in removed=[:];unlocked=[];result="";optimized=nil;bucketID=""}.onChange(of:mode){_,_ in result="";optimized=nil}.onChange(of:hand){_,_ in result="";optimized=nil}.onChange(of:second){_,_ in result=""}.onChange(of:unlocked){_,_ in optimized=nil;result=""}.onChange(of:target){_,_ in optimized=nil;result=""}.onChange(of:budget){_,_ in optimized=nil;result=""}.onChange(of:allowUnknown){_,_ in optimized=nil;result=""}.disabled(busy)
 }
 func percent(_ x:Double)->String{String(format:"%.2f%%",x*100)}
 func hit(_ b:PersonalBuild,_ bucket:CardBucket)->Double {let cards=physicalMain(b);guard hand<=cards.count else{return 0};return 1-hypergeometric(deck:cards.count,hits:cards.filter{bucket.cards.contains(collectionKey($0.name))}.count,hand:hand,count:0)}
 func calculate(){guard let b=build else{return};busy=true;result="";optimized=nil
 let other=model.workshop.builds.first{$0.id==second},buckets=buckets,routes=routes,mode=mode,hand=hand,unlocked=unlocked,target=target,allow=allowUnknown,cards=model.cardIndex,points=model.genesysIndex,md=model.masterDuelRules,inventory=model.inventory,quotes=model.quotes,budgetText=budget
 Task {do {let output=try await Task.detached {()->(String,PersonalBuild?) in
 if mode=="Compare probabilities"{guard let other else{throw DataError.message("Choose two builds")};let a=try exactCombo(probabilityInput(build:b,buckets:buckets,routes:routes,hand:hand)).probability;let c=try exactCombo(probabilityInput(build:other,buckets:buckets,routes:routes,hand:hand)).probability;return(String(format:"Any combo: %.2f%% → %.2f%% (%+.2f percentage points)",a*100,c*100,(c-a)*100),nil)}
 let budget=budgetCents(budgetText);if !budgetText.isEmpty && budget==nil{throw DataError.message("Enter a valid budget")}
 let r=try optimizeRatios(build:b,unlocked:unlocked,targetSize:target,hand:hand,buckets:buckets,routes:routes,cards:cards,points:points,md:md,inventory:inventory,quotes:quotes,budget:budget,allowIncomplete:allow)
 let changes=compareBuilds(b,r.build).filter{$0.before != $0.after}.map{"\($0.card.name): \($0.before) → \($0.after)"}.joined(separator:"\n")
 return(String(format:"Best exact probability: %.2f%% · %d eligible / %d size-valid candidates\n",r.probability*100,r.legalCandidates,r.checked)+changes,r.build)
 }.value;result=output.0;optimized=output.1}catch{result=error.localizedDescription};busy=false}
 }
}
