import SwiftUI

struct BuildEditor:View {
    @ObservedObject var model:Model
    let buildID:String
    @State private var query=""
    @State private var zone=BuildZone.main
    @State private var notice=""
    @State private var refreshing=false
    @State private var manage:Card?
    var build:PersonalBuild { model.workshop.builds.first { $0.id==buildID } ?? PersonalBuild(name:"Unavailable build",format:.tcg,cards:[]) }
    func edit(_ change:(inout PersonalBuild)->Void) { guard model.workshop.builds.contains(where:{$0.id==buildID}) else{return};var b=build;change(&b);model.putBuild(b) }
    var matches:[CardInfo] {
        guard query.count>=2 else { return [] }
        var seen=Set<String>()
        return model.cardIndex.values.filter { seen.insert($0.id).inserted && $0.name.localizedCaseInsensitiveContains(query) }.sorted { $0.name<$1.name }.prefix(8).map { $0 }
    }
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:14) {
                TextField("Build name",text:Binding(get:{build.name},set:{value in edit { $0.name=value } })).font(.system(size:23,weight:.semibold,design:.rounded)).accessibilityLabel("Deck name")
                HStack {
                    Picker("Format",selection:Binding(get:{build.format},set:{value in edit { $0.format=value } })) { ForEach(GameFormat.allCases,id:\.self) { Text($0.rawValue).tag($0) } }.frame(width:220)
                    Button("Duplicate") { var b=build;b.id=UUID().uuidString;b.name+=" copy";b.allocated=false;model.putBuild(b);notice="Copy saved in the build list." }
                    Button("Export YDK") { do { try saveFile(exportYDK(build,cards:model.cardIndex),name:"deck.ydk") } catch { notice=error.localizedDescription } }
                }
                Text(build.origin).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                if !notice.isEmpty { Text(notice).foregroundStyle(.orange) }
                let validation=checkLegality(build,cards:model.cardIndex,points:model.genesysIndex,masterDuel:model.masterDuelRules)
                Text("Rules: \(validation.errors.count) violations · \(validation.unknown.count) checks need review. Details below the card list.").font(.callout).foregroundStyle(validation.errors.isEmpty && validation.unknown.isEmpty ? .teal : .orange)
                ownership
                Divider()
                HStack { LabSearch(title:"Search cards to add",text:$query);Picker("Zone",selection:$zone) { ForEach(BuildZone.allCases,id:\.self) { Text($0.rawValue).tag($0) } }.frame(width:150) }
                ForEach(matches) { info in
                    Button("Add \(info.name) to \(zone.rawValue)") {
                        edit { b in b.cards.append(BuildCard(card:Card(id:"ygo:"+info.id,name:info.name,rarity:info.mdRarity),zone:zone,count:1)) };query=""
                    }.buttonStyle(.borderless)
                }
                ForEach(BuildZone.allCases,id:\.self) { zone in
                    HStack {Text(zone.rawValue+" Deck").font(.headline);LabBadge(text:"\(build.cards.filter{$0.zone==zone}.reduce(0){$0+$1.count}) cards");Spacer()}.padding(.top,8)
                    ForEach(build.cards.filter { $0.zone==zone }) { row in
                        HStack(spacing:12) {
                            CardArtwork(info:model.info(row.card)).frame(width:35,height:51)
                            VStack(alignment:.leading,spacing:4) {Text(row.card.name).font(.system(size:13,weight:.medium));Text("\(model.inventory.owned(row.card.name)) owned").font(.caption).foregroundStyle(.secondary)}.frame(maxWidth:.infinity,alignment:.leading)
                            LabQuantity(title:row.card.name,value:Binding(get:{row.count},set:{value in edit { b in if let i=b.cards.firstIndex(where:{$0.id==row.id}) { b.cards[i].count=value } } }))
                            Button("Printing") { manage=row.card }.font(.caption).accessibilityLabel("Choose printing and owned copies for \(row.card.name)")
                        }.padding(10).background(.primary.opacity(0.025),in:RoundedRectangle(cornerRadius:10))
                    }
                }
                Divider();legality
            }.padding(6)
        }.sheet(item:$manage) { card in CardCollectionEditor(model:model,card:card) }
    }
    var ownership:some View {
        let totals=buildTotals(stats:aggregate([build.deck]),sample:1,inventory:model.inventory,quotes:model.quotes,roundUp:false)
        let available=availableInventory(model.inventory,excluding:build.id,builds:model.workshop.builds)
        let free=buildTotals(stats:aggregate([build.deck]),sample:1,inventory:available,quotes:model.quotes,roundUp:false)
        let conflicts=allocationConflicts(model.workshop.builds,inventory:model.inventory)
        return VStack(alignment:.leading,spacing:8) {
            HStack {Text("\(totals.coveredCopies) / \(totals.targetCopies) copies owned").font(.headline);Spacer();Text("\(free.coveredCopies) available").font(.caption).foregroundStyle(.secondary)}
            ProgressView(value:Double(totals.coveredCopies),total:Double(max(1,totals.targetCopies))).tint(LabStyle.accent).accessibilityLabel("Deck collection completion")
            Text("Built value \(dollars(totals.builtCents)) + \(totals.unpricedBuiltCopies) unpriced · To finish \(dollars(totals.missingCents)) + \(totals.unpricedMissingCopies) unpriced").font(.caption)
            Toggle("Assembled — reserve these physical copies",isOn:Binding(get:{build.allocated},set:{value in edit { $0.allocated=value } }))
            Text("Reservations track card quantities across all printings. They do not change your collection. Conflicts remain visible until quantities or reservations are adjusted.").font(.caption).foregroundStyle(.secondary)
            ForEach(conflicts) { conflict in Text("\(conflict.name): \(conflict.requested) reserved / \(conflict.owned) owned · \(conflict.builds.joined(separator:", "))").font(.caption).foregroundStyle(.orange) }
        }.padding(12).background(.primary.opacity(0.04)).clipShape(RoundedRectangle(cornerRadius:8))
    }
    var legality:some View {
        let report=checkLegality(build,cards:model.cardIndex,points:model.genesysIndex,masterDuel:model.masterDuelRules)
        return VStack(alignment:.leading,spacing:8) {
            HStack {
                Text("Legality checks").font(.headline);Spacer()
                Button(refreshing ? "Refreshing…" : "Refresh rules data") { refreshing=true;Task { await model.refreshRules();refreshing=false } }.disabled(refreshing)
            }
            if build.format == .genesys {
                Stepper("Genesys cap: \(build.pointCap) · Calculated points: \(report.points)",value:Binding(get:{build.pointCap},set:{value in edit { $0.pointCap=value } }),in:0...10000)
                Link("Official Genesys rules and points",destination:URL(string:"https://www.yugioh-card.com/en/genesys/")!)
            }
            Text(model.cardDataDate.map { "YGOPRODeck data checked \($0.formatted(date:.abbreviated,time:.shortened))" } ?? "Rules data not loaded").font(.caption).foregroundStyle(.secondary)
            if build.format == .masterDuel { Text(model.masterDuelRules.map { "Master Duel limits checked \($0.fetched.formatted())" } ?? "Refresh rules to load Master Duel limits").font(.caption) }
            if build.format == .edison { Link("Official March 2010 banlist",destination:URL(string:"https://img.yugioh-card.com/en/downloads/alt_format/2010-03-01.pdf")!) }
            if let issue=model.cardDataError { Text(issue).foregroundStyle(.orange) }
            if report.errors.isEmpty { Text(report.unknown.isEmpty ? "No issues found in supported checks." : "No structural violations found; verification is incomplete.").foregroundStyle(report.unknown.isEmpty ? .teal : .orange) }
            ForEach(report.errors,id:\.self) { Text("• "+$0).foregroundStyle(.red) }
            ForEach(report.unknown,id:\.self) { Text("• "+$0).font(.caption).foregroundStyle(.orange) }
            Text("Checks cover deck size, zones, copy limits, provider card-pool metadata, and Genesys points. Master Duel uses its live card limits after refresh; Edison uses the official March 2010 list. Event-specific rules and shared-name effects may need manual review.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct ComparisonView:View {
    @ObservedObject var model:Model
    @State private var left=""
    @State private var right="average"
    var options:[PersonalBuild] {
        let format=GameFormat(rawValue:model.snapshot?.format ?? model.format.rawValue) ?? model.format
        var average=PersonalBuild.average(model.decks,name:"Current average",format:format);average.id="average"
        return model.workshop.builds+[average]+model.decks.map { deck in var b=PersonalBuild.from(deck,format:format);b.id="source:"+deck.id;b.name="Source: \(deck.title ?? deck.typeName) · \(deck.author) · \(deck.day)";return b }
    }
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack {
                Picker("From",selection:$left) { Text("Choose a build").tag("");ForEach(options) { Text($0.name).tag($0.id) } }
                Picker("To",selection:$right) { ForEach(options) { Text($0.name).tag($0.id) } }
            }
            if let a=options.first(where:{$0.id==left}),let b=options.first(where:{$0.id==right}) {
                let rows=compareBuilds(a,b)
                let cost=switchCost(a,b)
                Text("\(a.format.rawValue) → \(b.format.rawValue) · \(rows.count) changed card/zone entries").font(.headline)
                Text("Additional copies needed beyond the From deck: \(cost.0) · Estimated purchase value \(dollars(cost.1)) + \(cost.2) unpriced. Zone moves do not count as purchases; this estimate does not credit other collection copies or resale.").foregroundStyle(.secondary)
                List(rows) { row in HStack { Text(row.card.name).frame(maxWidth:.infinity,alignment:.leading);Text(row.zone.rawValue).frame(width:60);Text("\(row.before) → \(row.after)").monospacedDigit().frame(width:60);Text(row.difference>0 ? "+\(row.difference)" : "\(row.difference)").foregroundStyle(row.difference>0 ? .teal : .orange).frame(width:35) } }
                if rows.isEmpty { Text("The card lists match.") }
            } else { ContentUnavailableView("Compare two builds",systemImage:"arrow.left.arrow.right",description:Text("Choose a saved build, source list, or the current rounded average.")) }
        }
    }
    func switchCost(_ a:PersonalBuild,_ b:PersonalBuild) -> (Int,Int,Int) {
        var copies=0,cents=0,unknown=0;let names=Dictionary(b.cards.map { (collectionKey($0.card.name),$0.card.name) },uniquingKeysWith:{$1})
        for (key,total) in b.counts { let n=max(0,total-(a.counts[key] ?? 0));copies+=n
            if let v=model.inventory.target(names[key] ?? key),let q=model.quotes[v.id],q.verified { cents+=n*q.cents } else { unknown+=n }
        };return (copies,cents,unknown)
    }
}
