import SwiftUI
import Charts
struct ShoppingView:View {
    @ObservedObject var model:Model
    @State private var selected:Set<String>=[]
    @State private var simultaneous=false
    @State private var reserveOthers=true
    @State private var manage:Card?
    @State private var notice=""
    var items:[ShoppingItem] {
        let builds=model.workshop.builds.filter{selected.contains($0.id)}
        let inventory=reserveOthers ? availableInventory(model.inventory,excluding:nil,builds:model.workshop.builds.filter{!selected.contains($0.id)}) : model.inventory
        return shoppingList(builds:builds,inventory:inventory,quotes:model.quotes,simultaneous:simultaneous)
    }
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            ScrollView(.horizontal) { HStack { ForEach(model.workshop.builds) { build in Toggle(build.name,isOn:Binding(get:{selected.contains(build.id)},set:{v in if v {selected.insert(build.id)}else{selected.remove(build.id)}})).toggleStyle(.checkbox) } } }
            Toggle("Build all selected decks simultaneously (sum copies)",isOn:$simultaneous)
            Toggle("Reserve copies in other assembled decks",isOn:$reserveOthers)
            Text(simultaneous ? "Every selected deck needs its own copies. Owned copies are subtracted once from the combined requirement." : "Shared-pool mode: use the largest requirement per card across selected decks. This assumes you swap cards between decks rather than keeping them all assembled.").font(.caption).foregroundStyle(.secondary)
            let missing=items.filter{$0.missing>0}
            let cents=missing.reduce(0){$0+$1.missing*($1.quote?.cents ?? 0)}
            let unpriced=missing.filter{$0.quote==nil}.reduce(0){$0+$1.missing}
            HStack { Text("\(missing.reduce(0){$0+$1.missing}) copies to buy · \(dollars(cents)) + \(unpriced) unpriced copies").bold();Spacer();Button("Export shopping CSV"){export()} }
            Text("Selected English printing/condition quotes; shipping and tax excluded. A low quote may not cover all requested copies at that price. Links open product pages; no purchases are made.").font(.caption).foregroundStyle(.secondary)
            if !notice.isEmpty { Text(notice).foregroundStyle(.orange) }
            List(missing) { item in
                HStack {
                    VStack(alignment:.leading,spacing:4) { Text("\(item.missing)× \(item.name)").bold();Text("Need \(item.required) · available \(item.owned)").font(.caption);if let v=item.variant { Text(v.label).font(.caption).foregroundStyle(.secondary) } }
                    Spacer();Text(item.quote.map{dollars($0.cents*item.missing)} ?? "Unpriced")
                    Button("Choose printing"){manage=Card(id:"collection:"+item.id,name:item.name,rarity:"")}
                    if let v=item.variant { Link("TCGplayer",destination:v.product.url) }
                }
            }
            if selected.isEmpty { Text("Select saved builds above to create a shopping list.") }
        }.sheet(item:$manage) { CardCollectionEditor(model:model,card:$0) }
    }
    func export() {
        var lines=["name,missing,required,available,printing,condition,unit_usd,subtotal_usd,checked,url"]
        lines+=items.filter{$0.missing>0}.map { item in
            [item.name,String(item.missing),String(item.required),String(item.owned),item.variant?.product.label ?? "",item.variant?.condition ?? "",item.quote.map{String(format:"%.2f",Double($0.cents)/100)} ?? "",item.quote.map{String(format:"%.2f",Double($0.cents*item.missing)/100)} ?? "",item.quote?.checked.ISO8601Format() ?? "",item.variant?.product.url.absoluteString ?? ""].map(csvField).joined(separator:",")
        }
        do { try saveFile(lines.joined(separator:"\n"),name:"shopping-list.csv") } catch { notice=error.localizedDescription }
    }
}
struct CollectionBrowser:View {
    @ObservedObject var model:Model
    @State private var query=""
    @State private var rarity="All"
    @State private var set="All"
    @State private var condition="All"
    @State private var extras=false
    @State private var keep=3
    @State private var editing:Card?
    @State private var add=""
    var holdings:[CardVariant] { model.inventory.variants.values.filter{(model.inventory.quantities[$0.id] ?? 0)>0} }
    var keys:[String] { let names=model.collectionNames;return Set(model.inventory.unassigned.filter{$0.value>0}.map(\.key)).union(holdings.map(\.cardKey)).sorted { (names[$0] ?? $0)<(names[$1] ?? $1) } }
    func reserved(_ key:String)->Int { model.workshop.builds.filter(\.allocated).reduce(0){$0+($1.counts[key] ?? 0)} }
    func surplus(_ key:String)->Int { max(0,model.inventory.owned(key)-max(keep,reserved(key))) }
    var rows:[String] { let names=model.collectionNames;return keys.filter { key in
        let name=names[key] ?? key
        let owned=model.inventory.holdings(name)
        let filterMatch=(rarity=="All" && set=="All" && condition=="All") || owned.contains { (rarity=="All" || $0.product.rarity==rarity) && (set=="All" || $0.product.set==set) && (condition=="All" || $0.condition==condition) }
        return filterMatch && (!extras || surplus(key)>0) && (query.isEmpty || name.localizedCaseInsensitiveContains(query) || owned.contains{$0.product.number.localizedCaseInsensitiveContains(query)})
    } }
    var suggestions:[CardInfo] { guard add.count>=3 else{return []};var seen=Set<String>();return model.cardIndex.values.filter{seen.insert($0.id).inserted && $0.name.localizedCaseInsensitiveContains(add)}.sorted{$0.name<$1.name}.prefix(6).map{$0} }
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack { TextField("Search owned cards or set number",text:$query);Text("\(keys.count) cards · \(model.inventory.ownedTotal) copies").bold() }
            HStack {
                Picker("Rarity",selection:$rarity){Text("All").tag("All");ForEach(Array(Set(holdings.map{$0.product.rarity})).sorted(),id:\.self){Text($0)}}
                Picker("Set",selection:$set){Text("All").tag("All");ForEach(Array(Set(holdings.map{$0.product.set})).sorted(),id:\.self){Text($0)}}
                Picker("Condition",selection:$condition){Text("All").tag("All");ForEach(Array(Set(holdings.map(\.condition))).sorted(),id:\.self){Text($0)}}
            }
            HStack { Toggle("Only extras / trade candidates",isOn:$extras);Stepper("Keep at least \(keep) per card",value:$keep,in:0...99) }
            Text("Trade candidates are copies above your keep count and assembled-deck reservations. Owned totals include all printings; rarity/set/condition filters require a matching owned printing.").font(.caption).foregroundStyle(.secondary)
            let names=model.collectionNames
            List(rows,id:\.self) { key in
                HStack {
                    VStack(alignment:.leading) { Text(names[key] ?? key).bold();Text(model.inventory.holdings(names[key] ?? key).map(\.label).joined(separator:"; ")).font(.caption).foregroundStyle(.secondary) }
                    Spacer();Text("Own \(model.inventory.owned(key)) · reserved \(reserved(key)) · extras \(surplus(key))").font(.caption)
                    Button("Manage"){editing=Card(id:"collection:"+key,name:names[key] ?? key,rarity:"")}
                }
            }
            TextField("Add a card to the collection (search 3+ letters)",text:$add)
            ForEach(suggestions){info in Button(info.name){editing=Card(id:"ygo:"+info.id,name:info.name,rarity:info.mdRarity);add=""}.buttonStyle(.borderless) }
        }.sheet(item:$editing){CardCollectionEditor(model:model,card:$0)}
    }
}
struct PriceHistoryView:View {
    @ObservedObject var model:Model
    @State private var selected=""
    @State private var target="1.00"
    @State private var notice=""
    var variants:[CardVariant] { model.inventory.variants.values.sorted{$0.cardName == $1.cardName ? $0.label<$1.label : $0.cardName<$1.cardName} }
    var history:[PriceQuote] {
        var rows=model.lab.priceHistory[selected] ?? []
        if let q=model.quotes[selected],!rows.contains(where:{$0.checked==q.checked}) {rows.append(q)}
        return rows.sorted{$0.checked<$1.checked}
    }
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:12) {
                Toggle("Automatically check for missing or stale watched prices (optional)",isOn:Binding(get:{model.lab.autoRefreshPrices},set:{v in model.changeLab{$0.autoRefreshPrices=v}}))
                Text("Manual updates are the default. Updates fetch only missing quotes or quotes older than 24 hours. Optional automatic checks run every 15 minutes while the app is open. History starts with your first successful quote.").font(.caption).foregroundStyle(.secondary)
                HStack { Button(model.watchRefreshBusy ? "Refreshing…" : "Update watched prices"){Task{await model.refreshWatchedPrices()}}.disabled(model.watchRefreshBusy || model.lab.watches.isEmpty);Text(model.watchStatus).font(.caption) }
                Text(model.priceUpdateSummary).font(.caption).foregroundStyle(.secondary)
                ForEach(model.lab.watches) { watch in
                    let variant=model.inventory.variants[watch.variantID],quote=model.quotes[watch.variantID]
                    HStack {
                        VStack(alignment:.leading) {
                            Text(variant.map{"\($0.cardName) · \($0.label)"} ?? "Printing unavailable").bold()
                            Text("Target ≤ \(dollars(watch.targetCents)) · last verified \(quote.map{dollars($0.cents)} ?? "unknown") · \(quote?.checked.formatted() ?? "not checked")").font(.caption)
                            if let quote { Text(quote.freshnessLabel).font(.caption).foregroundStyle(.secondary) }
                            if let quote,quote.cents<=watch.targetCents,quote.verified,quote.isFresh,model.pricingErrors[watch.variantID] == nil { Text("Target reached at last successful check").foregroundStyle(.teal) }
                            if let error=model.pricingErrors[watch.variantID] { Text(error).font(.caption).foregroundStyle(.orange) }
                        };Spacer();Button("Chart"){selected=watch.variantID};Button("Remove watch"){model.changeLab{$0.watches.removeAll{$0.variantID==watch.variantID}}}
                    }.padding(10).background(.primary.opacity(0.04)).clipShape(RoundedRectangle(cornerRadius:8))
                }
                Divider()
                Picker("Printing",selection:$selected){Text("Select a known printing").tag("");ForEach(variants){Text("\($0.cardName) · \($0.label)").tag($0.id)}}
                HStack {
                    TextField("Alert threshold USD",text:$target).frame(width:180)
                    Button("Save price watch") { if let cents=budgetCents(target){model.changeLab{$0.watches.removeAll{$0.variantID==selected};$0.watches.append(PriceWatch(variantID:selected,targetCents:cents))};notice="Watch saved."} }.disabled(model.inventory.variants[selected]==nil || budgetCents(target)==nil)
                    Button("Update this price"){Task{if let v=model.inventory.variants[selected]{do{try await model.updateQuote(v)}catch{notice=error.localizedDescription}}}}.disabled(model.inventory.variants[selected]==nil || model.watchRefreshBusy || model.refreshingQuoteIDs.contains(selected))
                }
                if !notice.isEmpty { Text(notice).foregroundStyle(.orange) }
                if !history.isEmpty {
                    Chart(Array(history.enumerated()),id:\.offset) { row in
                        LineMark(x:.value("Checked",row.element.checked),y:.value("USD",Double(row.element.cents)/100)).foregroundStyle(.teal)
                        PointMark(x:.value("Checked",row.element.checked),y:.value("USD",Double(row.element.cents)/100)).foregroundStyle(.teal)
                    }.frame(height:220)
                    ForEach(Array(history.reversed().enumerated()),id:\.offset){row in Text("\(row.element.checked.formatted()) · \(dollars(row.element.cents)) · \(row.element.seller)").font(.caption) }
                } else { Text("Choose a printing and fetch a quote to begin its history. Add printings through the collection browser or a build's Printing button.").foregroundStyle(.secondary) }
            }.padding(4)
        }
    }
}
