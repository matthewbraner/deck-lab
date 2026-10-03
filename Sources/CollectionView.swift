import SwiftUI

func dollars(_ cents: Int) -> String { String(format:"$%.2f",Double(cents)/100) }

@MainActor extension Model {
    func saveInventory(_ candidate: Inventory) {
        guard let store else { storageError = "Local storage is unavailable. Collection changes were not saved."; return }
        do { try captureRecovery("Collection edit");try store.write(candidate,name:"inventory.json"); inventory = candidate; storageError = nil }
        catch { storageError = "Collection change could not be saved: \(error.localizedDescription)" }
    }
    func setOwned(_ variant: CardVariant, count: Int) {
        var updated = inventory; updated.variants[variant.id] = variant; updated.quantities[variant.id] = max(0,min(9999,count)); saveInventory(updated)
    }
    func setUnassigned(_ name: String, count: Int) {
        var updated = inventory;if updated.displayNames == nil { updated.displayNames=[:] };updated.displayNames?[collectionKey(name)]=name; updated.unassigned[collectionKey(name)] = max(0,min(9999,count)); saveInventory(updated)
    }
    func setTarget(_ variant: CardVariant) {
        var updated = inventory; updated.variants[variant.id] = variant; updated.targets[variant.cardKey] = variant.id; saveInventory(updated)
    }
    func needsPriceUpdate(_ variant: CardVariant) -> Bool {
        guard let quote = quotes[variant.id] else { return true }
        return !quote.verified || !quote.isFresh || quote.condition != variant.condition || quote.edition != variant.edition
    }
    var lastSuccessfulPriceUpdate: Date? { quotes.values.filter { $0.verified }.map(\.checked).max() }
    var priceUpdateSummary: String {
        lastSuccessfulPriceUpdate.map { "Last successful price update: \($0.formatted(date:.abbreviated,time:.shortened)) · Individual quotes may be older." } ?? "No successful price updates yet."
    }
    func updateQuote(_ variant: CardVariant, fetch: (CardVariant) async throws -> PriceQuote = { try await TCG.shared.quote($0) }) async throws {
        guard needsPriceUpdate(variant), !refreshingQuoteIDs.contains(variant.id) else { return }
        refreshingQuoteIDs.insert(variant.id)
        defer { refreshingQuoteIDs.remove(variant.id) }
        defer {
            do { try store?.write(pricingErrors,name:"tcg-pricing-errors.json") }
            catch { storageError = "Price refresh status could not be saved: \(error.localizedDescription)" }
        }
        do {
            let value = try await fetch(variant)
            recordPrice(value)
            quotes[variant.id] = value; pricingErrors[variant.id] = nil
            do { try store?.write(quotes,name:"tcg-quotes.json") } catch { storageError = "Price loaded but could not be saved: \(error.localizedDescription)" }
        } catch { pricingErrors[variant.id] = error.localizedDescription; throw error }
    }
    func priceCollection() {
        guard !pricingBusy else { return }
        let cards = Set(stats.map { collectionKey($0.card.name) })
        let variants = inventory.variants.values.filter { cards.contains($0.cardKey) && ((inventory.quantities[$0.id] ?? 0) > 0 || inventory.targets[$0.cardKey] == $0.id) }.sorted { $0.id < $1.id }
        guard !variants.isEmpty else { pricingProgress = "Choose a printing for a card to start pricing."; return }
        let pending = variants.filter { needsPriceUpdate($0) }
        guard !pending.isEmpty else { pricingProgress = "Prices are up to date (checked within 24 hours). No requests sent."; return }
        pricingBusy = true
        priceTask = Task {
            var failures = 0
            for (i,variant) in pending.enumerated() {
                if Task.isCancelled { break }
                pricingProgress = "Pricing \(i + 1) of \(pending.count): \(variant.cardName)…"
                do { try await updateQuote(variant) } catch {
                    if Task.isCancelled { break }; failures += 1
                    if (error as? TCGServiceError)?.stopsBatch == true { break }
                }
            }
            pricingBusy = false
            pricingProgress = Task.isCancelled ? "Price refresh cancelled. Existing quotes were preserved." : failures > 0 ? "Some quotes are unavailable. Existing cached quotes are preserved; inspect a card for details." : "Selected prices updated. Shipping and tax are not included."
        }
    }
}

struct CollectionView: View {
    @ObservedObject var model: Model
    @State private var query = ""
    @State private var onlyMissing = false
    @State private var roundUp = false
    @State private var selected: String?
    @State private var editing: Card?
    var stats: [CardStats] { model.stats }
    var totals: BuildTotals { buildTotals(stats:stats,sample:model.decks.count,inventory:model.inventory,quotes:model.quotes,roundUp:roundUp) }
    func target(_ s: CardStats) -> Int { targetCopies(s,sample:model.decks.count,roundUp:roundUp) }
    func missing(_ s: CardStats) -> Int { max(0,target(s)-model.inventory.owned(s.card.name)) }
    var rows: [CardStats] { stats.filter { (query.isEmpty || $0.card.name.localizedCaseInsensitiveContains(query)) && (!onlyMissing || missing($0)>0) } }
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                VStack(alignment:.leading,spacing:4) {
                    Text("Your physical collection").font(.headline)
                    Text("Shared across decks · Target uses rounded average copies in all matching decks, across all zones.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if model.pricingBusy { ProgressView().controlSize(.small); Button("Cancel") { model.priceTask?.cancel() } }
                else { Button("Update prices") { model.priceCollection() }.help("Fetch missing quotes and quotes older than 24 hours for this dataset.") }
            }
            Text(model.priceUpdateSummary).font(.caption).foregroundStyle(.secondary)
            HStack(spacing:20) {
                costMetric("TARGET COPIES", "\(totals.coveredCopies) / \(totals.targetCopies)", "\(totals.missingCopies) copies missing")
                costMetric("TARGET COST", dollars(totals.targetCents), totals.unpricedTargetCopies > 0 ? "+ \(totals.unpricedTargetCopies) unpriced copies" : "selected printings")
                costMetric("BUILT SO FAR", dollars(totals.builtCents), totals.unpricedBuiltCopies > 0 ? "+ \(totals.unpricedBuiltCopies) unpriced copies" : "owned copies toward target")
                costMetric("COST TO FINISH", dollars(totals.missingCents), totals.unpricedMissingCopies > 0 ? "+ \(totals.unpricedMissingCopies) unpriced copies" : "missing copies at selected low")
            }
            Text("Values use last verified quotes and may change. Open a card to see its check time and refresh status.").font(.caption).foregroundStyle(.secondary)
            ProgressView(value:Double(totals.coveredCopies),total:Double(max(1,totals.targetCopies))).tint(.teal)
            HStack {
                TextField("Find a card",text:$query).textFieldStyle(.roundedBorder).frame(maxWidth:260)
                Toggle("Only missing",isOn:$onlyMissing)
                Spacer()
                Picker("Round target",selection:$roundUp) { Text("Nearest whole copy").tag(false); Text("Always round up").tag(true) }.frame(width:260)
            }
            if !model.pricingProgress.isEmpty { Text(model.pricingProgress).font(.caption).foregroundStyle(.secondary) }
            Table(rows,selection:$selected) {
                TableColumn("Card") { s in Text(s.card.name).lineLimit(1).help(s.card.name) }.width(min:200,ideal:280)
                TableColumn("Mean") { s in Text(String(format:"%.2f",s.average(s.total,sample:model.decks.count,mode:.all))).monospacedDigit() }.width(50)
                TableColumn("Target") { s in Text("\(target(s))").monospacedDigit() }.width(50)
                TableColumn("Owned") { s in Text("\(model.inventory.owned(s.card.name))").monospacedDigit() }.width(50)
                TableColumn("Missing") { s in Text("\(missing(s))").monospacedDigit().foregroundStyle(missing(s)>0 ? .orange : .secondary) }.width(55)
                TableColumn("Verified low") { s in
                    if let v = model.inventory.target(s.card.name), let q = model.quotes[v.id], q.verified { Text(dollars(q.cents)).monospacedDigit().help("\(v.label) · \(q.seller) · Checked \(q.checked.formatted())") }
                    else { Text("Unpriced").foregroundStyle(.secondary) }
                }.width(90)
                TableColumn("To buy") { s in
                    if missing(s)==0 { Text("$0.00").foregroundStyle(.secondary) }
                    else if let v=model.inventory.target(s.card.name),let q=model.quotes[v.id],q.verified { Text(dollars(missing(s)*q.cents)).monospacedDigit() }
                    else { Text("—").foregroundStyle(.secondary) }
                }.width(70)
                TableColumn("Printing & collection") { s in Button("Edit collection") { editing=s.card }.accessibilityLabel("Edit collection for \(s.card.name)").buttonStyle(.borderless) }.width(130)
            }.alternatingRowBackgrounds()
            HStack {
                Text("Owned value for cards in this dataset: \(dollars(totals.collectionCents))\(totals.unpricedCollectionCopies>0 ? " + \(totals.unpricedCollectionCopies) unpriced copies" : "")")
                Spacer(); Text("USD · Item prices only · Quotes are estimates")
            }.font(.caption).foregroundStyle(.secondary)
            if model.snapshot?.format == "Master Duel" || model.snapshot?.format == nil { Text("This tracks physical cards, not your Master Duel account inventory.").font(.caption).foregroundStyle(.secondary) }
        }.padding(.horizontal,24).padding(.bottom,8)
        .sheet(item:$editing) { card in CardCollectionEditor(model:model,card:card) }
    }
    func costMetric(_ title:String,_ value:String,_ note:String) -> some View {
        LabMetric(title:title.capitalized,value:value,note:note,symbol:title.contains("COST") ? "dollarsign.circle" : "rectangle.stack")
    }
}

struct CardCollectionEditor: View {
    @ObservedObject var model: Model
    let card: Card
    @Environment(\.dismiss) private var dismiss
    @State private var products: [TCGProduct] = []
    @State private var productID = 0
    @State private var skus: [TCGSKU] = []
    @State private var condition = "Near Mint"
    @State private var edition = ""
    @State private var loading = false
    @State private var loadingSKU = false
    @State private var quoting = false
    @State private var error: String?
    var product: TCGProduct? { products.first { $0.id==productID } }
    var conditions: [String] {
        let order=["Near Mint","Lightly Played","Moderately Played","Heavily Played","Damaged"]
        return Array(Set(skus.map(\.condition))).sorted { (order.firstIndex(of:$0) ?? 99) < (order.firstIndex(of:$1) ?? 99) }
    }
    var editions: [String] { Array(Set(skus.filter { $0.condition==condition }.map(\.edition))).sorted() }
    var variant: CardVariant? {
        guard let product, skus.contains(where: { $0.condition==condition && $0.edition==edition }) else { return nil }
        return CardVariant(cardName:card.name,product:product,condition:condition,edition:edition)
    }
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack { VStack(alignment:.leading,spacing:4) { Text(card.name).font(.title2.bold());Text("Physical collection · English printings · USD").font(.caption).foregroundStyle(.secondary) };Spacer();Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
            ScrollView {
                VStack(alignment:.leading,spacing:16) {
                    HStack(alignment:.top,spacing:18) {
                        CardArtwork(info:model.info(card)).frame(width:120,height:176)
                        VStack(alignment:.leading,spacing:8) {
                            if let info=model.info(card) { Text(info.type).font(.headline);Text(info.description).font(.callout).lineLimit(7) }
                            Text("Tap image to enlarge. Artwork is from YGOPRODeck; the selected TCGplayer printing may differ.").font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth:.infinity,alignment:.leading)
                    }
                    HStack { Text("Unspecified copies owned");Spacer();quantity(Binding(get:{model.inventory.unassigned[collectionKey(card.name)] ?? 0},set:{model.setUnassigned(card.name,count:$0)})) }
                    Text("These copies count toward completion but remain unpriced. Move the count to a specific printing below when you know it; don’t count the same copies twice.").font(.caption).foregroundStyle(.secondary)
                    Divider()
                    HStack { Text("Choose rarity, set, and condition").font(.headline);Spacer();Button("Refresh printings") { Task { await loadProducts(force:true) } }.disabled(loading) }
                    if loading { ProgressView("Loading TCGplayer printings…") }
                    if !products.isEmpty {
                        Picker("Printing",selection:$productID) { ForEach(products) { p in Text(p.label).tag(p.id) } }
                        if loadingSKU { ProgressView("Loading available conditions…").controlSize(.small) }
                        HStack {
                            Picker("Condition",selection:$condition) { ForEach(conditions,id:\.self) { Text($0).tag($0) } }
                            Picker("Edition",selection:$edition) { ForEach(editions,id:\.self) { Text($0).tag($0) } }
                        }.disabled(loadingSKU)
                        if let v=variant {
                            HStack { Text("Owned in this printing");Spacer();quantity(Binding(get:{model.inventory.quantities[v.id] ?? 0},set:{model.setOwned(v,count:$0)})) }
                            HStack {
                                Button(model.inventory.target(card.name)?.id==v.id ? "Update price" : "Use for target & update price") {
                                    model.setTarget(v)
                                    Task { quoting=true;error=nil;defer { quoting=false };do { try await model.updateQuote(v) } catch { self.error=error.localizedDescription } }
                                }.buttonStyle(.borderedProminent).tint(LabStyle.action).disabled(quoting || model.refreshingQuoteIDs.contains(v.id))
                                if quoting { ProgressView().controlSize(.small) }
                                Spacer();Link("View on TCGplayer",destination:v.product.url)
                            }
                            if let q=model.quotes[v.id] {
                                VStack(alignment:.leading,spacing:5) {
                                    Text("\(dollars(q.cents)) · Last verified seller low").font(.title3.bold())
                                    Text(q.freshnessLabel + (q.isFresh ? " · Updates skip fresh quotes" : "")).font(.caption).foregroundStyle(q.isFresh ? Color.secondary : Color.orange)
                                    Text("\(v.condition) · \(v.edition) · \(q.seller) · \(q.quantity) copies listed").font(.callout)
                                    Text("Checked \(q.checked.formatted(date:.abbreviated,time:.shortened)). Listing shipping: \(dollars(q.shippingCents)); not included in deck totals.").font(.caption).foregroundStyle(.secondary)
                                }.padding(14).frame(maxWidth:.infinity,alignment:.leading).background(Color.teal.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius:10))
                            }
                            if let problem=model.pricingErrors[v.id],error==nil { Text(problem).foregroundStyle(.orange).font(.callout) }
                        }
                    } else if !loading { Text("No matching TCGplayer printings were found. Unspecified owned copies can still be recorded.").foregroundStyle(.secondary) }
                    if let error { Text(error).font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
                    if let error=model.storageError { Text(error).font(.callout).foregroundStyle(.orange) }
                    Divider()
                    Text("All owned printings of this card").font(.headline)
                    ForEach(model.inventory.holdings(card.name)) { v in
                        HStack(alignment:.top) {
                            VStack(alignment:.leading,spacing:3) { Text(v.label).font(.callout);if let q=model.quotes[v.id] { Text("\(dollars(q.cents)) each · \(q.checked.formatted(date:.abbreviated,time:.shortened))").font(.caption).foregroundStyle(.secondary) } else { Text("Not priced yet").font(.caption).foregroundStyle(.secondary) } }
                            Spacer();quantity(Binding(get:{model.inventory.quantities[v.id] ?? 0},set:{model.setOwned(v,count:$0)}))
                        }
                    }
                    Text("Owned quantities are shared across deck types and formats. Selecting a different target does not change existing holdings. All quotes require matching condition/edition, stock, and the verified-seller flag. Totals exclude shipping and tax and are not a checkout quote.").font(.caption).foregroundStyle(.secondary)
                }.padding(.trailing,8)
            }
        }.padding(24).frame(width:780,height:690)
        .task { await loadProducts() }
        .task(id:productID) { if productID != 0 { await loadSKUs() } }
        .onChange(of:condition) { _,_ in if !editions.contains(edition) { edition=editions.first ?? "" } }
    }
    func quantity(_ binding:Binding<Int>) -> some View {
        LabQuantity(title:card.name,value:binding,maximum:9999)
    }
    func loadProducts(force:Bool=false) async {
        loading=true;error=nil;defer { loading=false }
        do {
            let result=try await TCG.shared.search(card.name,force:force)
            guard !Task.isCancelled else { return }
            products=result
            if let target=model.inventory.target(card.name),products.contains(where:{$0.id==target.product.id}) { productID=target.product.id }
            else { productID=products.min { ($0.indicativeLow ?? .infinity) < ($1.indicativeLow ?? .infinity) }?.id ?? 0 }
        } catch { self.error=error.localizedDescription }
    }
    func loadSKUs() async {
        guard let product else { return };loadingSKU=true;skus=[];defer { loadingSKU=false }
        do {
            let result=try await TCG.shared.skus(product)
            guard !Task.isCancelled,product.id==productID else { return }
            skus=result
            if let target=model.inventory.target(card.name),target.product.id==productID { condition=target.condition;edition=target.edition }
            else { condition=conditions.contains("Near Mint") ? "Near Mint" : conditions.first ?? "";edition=editions.first ?? "" }
        } catch { if !Task.isCancelled { self.error=error.localizedDescription } }
    }
}
