import SwiftUI
import Charts
func percent(_ value:Double) -> String { String(format:"%.2f%%",100*value) }
struct BuildChooser:View {
    @ObservedObject var model:Model
    @Binding var selected:String
    var body:some View { Picker("Saved build",selection:$selected) { Text("Choose a build").tag("");ForEach(model.workshop.builds) { Text($0.name).tag($0.id) } }.frame(maxWidth:500).onAppear { if selected.isEmpty { selected=model.workshop.builds.first?.id ?? "" } } }
}
struct ProbabilityView:View {
    @ObservedObject var model:Model
    @State private var selected=""
    @State private var page="Test hands"
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            BuildChooser(model:model,selected:$selected)
            Picker("Tool",selection:$page) { ForEach(["Test hands","Buckets","Hypergeometric","Combos"],id:\.self) { Text($0) } }.pickerStyle(.segmented).tint(LabStyle.action)
            if let build=model.workshop.builds.first(where:{$0.id==selected}) {
                Group { switch page {
                case "Buckets":BucketsView(model:model,build:build)
                case "Hypergeometric":HypergeometricView(model:model,build:build)
                case "Combos":ComboCalculator(model:model,build:build)
                default:HandSimulator(model:model,build:build)
                } }.id(build.id)
            } else { Text("Save or import a build to start testing.").foregroundStyle(.secondary);Spacer() }
        }
    }
}
struct BucketsView:View {
    @ObservedObject var model:Model
    let build:PersonalBuild
    @State private var selected=""
    @State private var name=""
    var buckets:[CardBucket] { model.lab.buckets.filter{$0.buildID==build.id} }
    var bucket:CardBucket? { buckets.first{$0.id==selected} }
    func edit(_ change:(inout CardBucket)->Void) { model.changeLab { lab in if let i=lab.buckets.firstIndex(where:{$0.id==selected}) { change(&lab.buckets[i]) } } }
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Text("Buckets group Main Deck cards by purpose. A card can belong to several buckets; its physical copies are counted once per bucket. Starter and Brick tags also appear in test hands.").foregroundStyle(.secondary)
            HStack { TextField("New bucket name",text:$name);Button("Add bucket") { let b=CardBucket(buildID:build.id,name:name);model.changeLab{$0.buckets.append(b)};selected=b.id;name="" }.disabled(name.trimmingCharacters(in:.whitespaces).isEmpty || buckets.count>=12) }
            Picker("Bucket",selection:$selected) { Text("Select bucket").tag("");ForEach(buckets) { Text($0.name).tag($0.id) } }
            if let bucket {
                HStack {
                    TextField("Name",text:Binding(get:{bucket.name},set:{v in edit{$0.name=v}}))
                    Picker("Role",selection:Binding(get:{bucket.role},set:{v in edit{$0.role=v}})) { ForEach(["Custom","Starter","Extender","Brick","Interaction"],id:\.self) { Text($0) } }.frame(width:220)
                    Button("Remove bucket") { model.changeLab { $0.buckets.removeAll{$0.id==selected};for i in $0.combos.indices { $0.combos[i].needs.removeAll{$0.bucketID==selected} } };selected="" }
                }
                let main=mergeBuildCards(build.cards.filter{$0.zone == .main})
                let hits=main.filter{bucket.cards.contains(collectionKey($0.card.name))}.reduce(0){$0+$1.count}
                Text("\(hits) / \(main.reduce(0){$0+$1.count}) Main Deck copies · Up to 12 buckets per build").bold()
                List(main) { row in
                    Toggle("\(row.count)× \(row.card.name)",isOn:Binding(get:{bucket.cards.contains(collectionKey(row.card.name))},set:{v in edit { if v { $0.cards.insert(collectionKey(row.card.name)) } else { $0.cards.remove(collectionKey(row.card.name)) } } }))
                }
            } else { Spacer() }
        }.onAppear { selected=buckets.first?.id ?? "" }
    }
}
struct HandSimulator:View {
    @ObservedObject var model:Model
    let build:PersonalBuild
    @State private var handSize=5
    @State private var hand:[HandCard]=[]
    @State private var remaining:[Card]=[]
    var buckets:[CardBucket] { model.lab.buckets.filter{$0.buildID==build.id} }
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:14) {
                HStack {
                    Stepper("Opening cards: \(handSize)",value:$handSize,in:1...10).frame(width:200)
                    Button("Shuffle & draw") { var deck=physicalMain(build).shuffled();hand=deck.prefix(handSize).map{HandCard(card:$0)};deck.removeFirst(min(handSize,deck.count));remaining=deck }.disabled(physicalMain(build).count<handSize || physicalMain(build).count>100)
                    Button("Draw next") { if !remaining.isEmpty { hand.append(HandCard(card:remaining.removeFirst())) } }.disabled(hand.isEmpty || remaining.isEmpty)
                    Text("\(remaining.count) cards remain")
                }
                Text("Draws without replacement from Main only. Five cards models an opening hand; six models cards seen after the first draw. This does not simulate effects, searches, interruptions, or turn legality.").font(.caption).foregroundStyle(.secondary)
                if hand.isEmpty {
                    VStack(spacing:18) {
                        HStack(spacing:14){ForEach(0..<5,id:\.self){i in RoundedRectangle(cornerRadius:8).fill(LabStyle.canvas).overlay(RoundedRectangle(cornerRadius:8).strokeBorder(.primary.opacity(0.12))).overlay {Image(systemName:"rectangle.stack").font(.system(size:28,weight:.ultraLight)).foregroundStyle(LabStyle.accent.opacity(0.3))}.frame(width:120,height:175).rotationEffect(.degrees(Double(i-2)*3))}}
                        Text("Your opening hand starts here").font(.system(size:20,weight:.medium))
                        Text("Shuffle your saved build to draw an opening hand.").font(.system(size:12)).foregroundStyle(.secondary)
                    }.frame(maxWidth:.infinity).padding(.vertical,60).accessibilityElement(children:.combine)
                }
                LazyVGrid(columns:[GridItem(.adaptive(minimum:190,maximum:240),spacing:18)],alignment:.leading) {
                    ForEach(hand) { item in VStack { CardArtwork(info:model.info(item.card)).frame(height:255);Text(item.card.name).font(.system(size:13,weight:.medium)).multilineTextAlignment(.center);Text(buckets.filter{$0.cards.contains(collectionKey(item.card.name))}.map(\.role).filter{$0 != "Custom"}.joined(separator:" · ")).font(.caption2).foregroundStyle(.teal) }.padding(8) }
                }
                ForEach(buckets) { b in Text("\(b.name): \(hand.filter{b.cards.contains(collectionKey($0.card.name))}.count) in hand") }
                if !hand.isEmpty {
                    let masks=hand.map { c in buckets.enumerated().reduce(0) { mask,pair in pair.element.cards.contains(collectionKey(c.card.name)) ? mask | (1<<pair.offset) : mask } }
                    ForEach(model.lab.combos.filter{$0.buildID==build.id}) { route in Text("\(routeMatches(masks,route:route,bucketIDs:buckets.map(\.id)) ? "✓" : "—") \(route.name)").foregroundStyle(.secondary) }
                }
            }.padding(4)
        }.onChange(of:build.cards) { _,_ in hand=[];remaining=[] }
    }
}
struct HypergeometricView:View {
    @ObservedObject var model:Model
    let build:PersonalBuild
    @State private var bucketID=""
    @State private var hand=5
    @State private var wanted=1
    @State private var hypothetical=false
    @State private var copies=3
    var buckets:[CardBucket] { model.lab.buckets.filter{$0.buildID==build.id} }
    var total:Int { build.cards.filter{$0.zone == .main}.reduce(0){$0+$1.count} }
    var hits:Int { hypothetical ? min(copies,total) : build.cards.filter { $0.zone == .main && (buckets.first{$0.id==bucketID}?.cards.contains(collectionKey($0.card.name)) ?? false) }.reduce(0){$0+$1.count} }
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:14) {
                Picker("Bucket",selection:$bucketID) { Text("Choose a bucket").tag("");ForEach(buckets) { Text($0.name).tag($0.id) } }
                HStack { Stepper("Cards seen: \(hand)",value:$hand,in:0...min(10,max(0,total))).frame(width:220);Stepper("Desired hits: \(wanted)",value:$wanted,in:0...10).frame(width:220) }
                Toggle("Explore a hypothetical ratio (does not edit the build)",isOn:$hypothetical)
                if hypothetical { Stepper("Bucket copies: \(copies)",value:$copies,in:0...max(0,min(100,total))) }
                if total>0 && total<=100 && hand<=total && (hypothetical || !bucketID.isEmpty) {
                    let distribution=(0...hand).map { hypergeometric(deck:total,hits:hits,hand:hand,count:$0) }
                    Text("\(hits) / \(total) bucket copies · \(hand) cards seen · expected hits \(String(format:"%.3f",Double(hand)*Double(hits)/Double(total)))").font(.headline)
                    HStack(spacing:24) {
                        Text("Exactly \(wanted): \(percent(hypergeometric(deck:total,hits:hits,hand:hand,count:wanted)))")
                        Text("At least \(wanted): \(percent(distribution.enumerated().filter{$0.offset>=wanted}.reduce(0){$0+$1.element}))")
                        Text("At most \(wanted): \(percent(distribution.enumerated().filter{$0.offset<=wanted}.reduce(0){$0+$1.element}))")
                    }
                    Chart(Array(distribution.enumerated()),id:\.offset) { item in BarMark(x:.value("Hits",String(item.offset)),y:.value("Probability",item.element)).foregroundStyle(.teal) }.chartYScale(domain:0...1).frame(height:200)
                    Text("P(X = k) = C(K,k) × C(N−K,n−k) / C(N,n)").font(.system(.body,design:.monospaced))
                    Text("Ratio comparison: at least \(wanted) in \(hand)").font(.headline)
                    ForEach(max(0,hits-3)...min(total,hits+3),id:\.self) { k in HStack { Text("\(k)/\(total)").frame(width:90,alignment:.leading);Text(percent((0...hand).filter{$0>=wanted}.reduce(0){$0+hypergeometric(deck:total,hits:k,hand:hand,count:$1)})) } }
                } else { Text("Choose a bucket and use a Main Deck of 1–100 cards. The hand cannot exceed the deck.") }
                Text("Exact single-bucket probabilities assume a uniformly shuffled deck, without replacement. Use Combos for joint conditions; multiplying overlapping bucket probabilities would be incorrect.").font(.caption).foregroundStyle(.secondary)
            }.padding(4)
        }.onAppear { bucketID=buckets.first?.id ?? "";hand=min(5,total) }
    }
}
struct ComboCalculator:View {
    @ObservedObject var model:Model
    let build:PersonalBuild
    @State private var selected=""
    @State private var name=""
    @State private var hand=5
    @State private var method="Exact"
    @State private var allRoutes=true
    @State private var result:ProbabilityResult?
    @State private var status=""
    @State private var worker:Task<ProbabilityResult,Error>?
    @State private var generation=UUID()
    @State private var busy=false
    var buckets:[CardBucket] { model.lab.buckets.filter{$0.buildID==build.id} }
    var routes:[ComboRoute] { model.lab.combos.filter{$0.buildID==build.id} }
    var route:ComboRoute? { routes.first{$0.id==selected} }
    func edit(_ change:(inout ComboRoute)->Void) { model.changeLab { if let i=$0.combos.firstIndex(where:{$0.id==selected}) { change(&$0.combos[i]) } } }
    func invalidate() { worker?.cancel();worker=nil;generation=UUID();busy=false;result=nil;status="" }
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:12) {
                Text("Each route is an AND of bucket ranges. ‘Any saved route’ evaluates their union once per hand. This calculates access to ingredients, not whether a sequence resolves legally.").foregroundStyle(.secondary)
                HStack { TextField("New route name",text:$name);Button("Add route") { let r=ComboRoute(buildID:build.id,name:name);model.changeLab{$0.combos.append(r)};selected=r.id;name="" }.disabled(name.isEmpty || routes.count>=12) }
                Picker("Edit route",selection:$selected) { Text("Select route").tag("");ForEach(routes) { Text($0.name).tag($0.id) } }
                if let route {
                    HStack { TextField("Route name",text:Binding(get:{route.name},set:{v in edit{$0.name=v}}));Button("Remove route") { model.changeLab{$0.combos.removeAll{$0.id==selected}};selected="" } }
                    Toggle("Require distinct copies for minimum requirements",isOn:Binding(get:{route.distinctCopies},set:{v in edit{$0.distinctCopies=v}}))
                    Text("When enabled, one physical card cannot fill two minimum slots. Maximums always constrain the total cards drawn from each bucket. When disabled, one drawn card may satisfy several bucket-presence conditions.").font(.caption).foregroundStyle(.secondary)
                    ForEach(route.needs) { need in
                        HStack {
                            Text(buckets.first{$0.id==need.bucketID}?.name ?? "Missing bucket").frame(width:160,alignment:.leading)
                            Stepper("Min \(need.minimum)",value:Binding(get:{need.minimum},set:{v in edit { r in if let i=r.needs.firstIndex(where:{$0.id==need.id}) { r.needs[i].minimum=v;r.needs[i].maximum=max(v,r.needs[i].maximum) } } }),in:0...10)
                            Stepper("Max \(need.maximum)",value:Binding(get:{need.maximum},set:{v in edit { r in if let i=r.needs.firstIndex(where:{$0.id==need.id}) { r.needs[i].maximum=v } } }),in:need.minimum...10)
                            Button("Remove") { edit{$0.needs.removeAll{$0.id==need.id}} }
                        }
                    }
                    Menu("Add bucket requirement") { ForEach(buckets.filter { b in !route.needs.contains{$0.bucketID==b.id} }) { b in Button(b.name) { edit{$0.needs.append(ComboNeed(bucketID:b.id))} } } }.disabled(buckets.isEmpty)
                    TextField("Combo sequence / assumptions / notes",text:Binding(get:{route.notes},set:{v in edit{$0.notes=v}}))
                }
                Divider()
                HStack { Stepper("Cards seen: \(hand)",value:$hand,in:0...10).frame(width:190);Toggle("Any saved route (OR)",isOn:$allRoutes);Picker("Method",selection:$method) { Text("Exact").tag("Exact");Text("Monte Carlo").tag("Monte Carlo") }.frame(width:230) }
                HStack { Button(busy ? "Calculating…" : "Calculate") { calculate() }.disabled(busy);if busy { Button("Cancel") { invalidate() } } }
                if !status.isEmpty { Text(status).foregroundStyle(.orange) }
                if let result {
                    Text("\(percent(result.probability)) success").font(.title.bold()).foregroundStyle(.teal)
                    Text(result.exact ? "Exact multivariate hypergeometric enumeration; overlapping cards and routes are handled jointly." : "\(result.trials) random hands · 95% Wilson interval \(percent(result.lower))–\(percent(result.upper)). Estimates vary between runs.").foregroundStyle(.secondary)
                }
            }.padding(4)
        }.onAppear{selected=routes.first?.id ?? ""}
         .onChange(of:model.lab.buckets){_,_ in invalidate()}.onChange(of:model.lab.combos){_,_ in invalidate()}.onChange(of:build.cards){_,_ in invalidate()}
         .onChange(of:hand){_,_ in invalidate()}.onChange(of:method){_,_ in invalidate()}.onChange(of:allRoutes){_,_ in invalidate()}.onChange(of:selected){_,_ in invalidate()}.onDisappear{worker?.cancel()}
    }
    func calculate() {
        invalidate()
        do {
            let chosen=allRoutes ? routes : routes.filter{$0.id==selected}
            let input=try probabilityInput(build:build,buckets:buckets,routes:chosen,hand:hand)
            let exact=method == "Exact",token=generation;busy=true
            let job=Task.detached(priority:.userInitiated) { try exact ? exactCombo(input) : simulateCombo(input) };worker=job
            Task { do { let value=try await job.value;if generation==token { result=value;busy=false } } catch { if generation==token { status=error.localizedDescription;busy=false } } }
        } catch { status=error.localizedDescription }
    }
}
