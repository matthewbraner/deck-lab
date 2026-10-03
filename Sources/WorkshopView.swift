import SwiftUI

struct WorkshopView: View {
    @ObservedObject var model:Model
    @Environment(\.dismiss) var dismiss
    @Binding var tab:String
    @State private var selected:String?
    @State private var error:String?
    @State private var searchName=""
    var currentFormat:GameFormat { GameFormat(rawValue:model.snapshot?.format ?? model.format.rawValue) ?? model.format }
    var body:some View {
        VStack(alignment:.leading,spacing:0) {
            HStack(alignment:.center,spacing:16) {
                Image(systemName:LabTool.find(tab).symbol).font(.system(size:24,weight:.light)).foregroundStyle(LabStyle.accent).frame(width:38)
                VStack(alignment:.leading,spacing:6) {Text(LabTool.find(tab).title).font(.system(size:30,weight:.semibold));Text(LabTool.find(tab).subtitle).font(.system(size:13)).foregroundStyle(.secondary)}
                Spacer(minLength:0)
            }.padding(28)
            if let error { Text(error).foregroundStyle(.orange).textSelection(.enabled).padding(.horizontal,28) }
            if let error=model.storageError { Label(error,systemImage:"exclamationmark.triangle").foregroundStyle(.orange).padding(.horizontal,28) }
            Group {
                switch tab {
                case "Builds": builds
                case "Card search": CardSearchView(model:model)
                case "Advanced probabilities": AdvancedOddsView(model:model)
                case "Substitutions": SubstitutionsView(model:model)
                case "Collection locations": LocationsView(model:model)
                case "Share deck": ShareDeckView(model:model)
                case "Recovery": RecoveryView(model:model)
                case "Hands & probability": ProbabilityView(model:model)
                case "Side plans": SidePlansView(model:model)
                case "Match log": MatchLogView(model:model)
                case "Build history": BuildHistoryView(model:model)
                case "Shopping list": ShoppingView(model:model)
                case "Collection browser": CollectionBrowser(model:model)
                case "Price history & alerts": PriceHistoryView(model:model)
                case "Dataset trends": TrendsView(model:model)
                case "What can I build?": RecommendationsView(model:model)
                case "Core & flex": CoreFlexView(model:model)
                case "Compare": ComparisonView(model:model)
                case "Import & backup": ImportBackupView(model:model)
                default: searches
                }
            }.id(tab).padding(18).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).labSurface().padding(.horizontal,28).padding(.bottom,24)
        }.frame(maxWidth:.infinity,maxHeight:.infinity).background(LabStyle.canvas)
    }
    var builds:some View {
        HStack(alignment:.top,spacing:12) {
            VStack(alignment:.leading,spacing:12) {
                Button("New deck") { let b=PersonalBuild(name:"New build",format:model.format,cards:[]);model.putBuild(b);selected=b.id }.buttonStyle(.borderedProminent).tint(LabStyle.action)
                Button("Save current average") { let b=PersonalBuild.average(model.decks,name:"\(model.snapshot?.type.name ?? "Deck") — my build",format:currentFormat);model.putBuild(b);selected=b.id }.disabled(model.decks.isEmpty)
                Menu("Copy source list…") {
                    ForEach(model.decks) { deck in Button("\(deck.title ?? deck.typeName) · \(deck.author) · \(deck.day)") { let b=PersonalBuild.from(deck,format:currentFormat);model.putBuild(b);selected=b.id } }
                }.disabled(model.decks.isEmpty)
                List(selection:$selected) {
                    ForEach(model.workshop.builds) { build in
                        HStack(spacing:10) {
                            if let card=build.cards.first?.card {CardArtwork(info:model.info(card)).frame(width:38,height:55).allowsHitTesting(false).accessibilityHidden(true)}
                            VStack(alignment:.leading,spacing:5) {Text(build.name).font(.system(size:13,weight:.semibold));Text("\(build.format.rawValue) · \(build.deck.total) cards").font(.caption).foregroundStyle(.secondary);if build.allocated {Text("Assembled").font(.caption2).foregroundStyle(LabStyle.accent)}}
                        }.padding(.vertical,7).tag(build.id).contextMenu { Button("Delete build") { var next=model.workshop;next.builds.removeAll{$0.id==build.id};selected=nil;model.saveWorkshop(next) } }
                    }
                }
                Text("Builds save automatically. An average is a starting point; it may mix incompatible strategies.").font(.caption).foregroundStyle(.secondary)
            }.frame(width:240).frame(maxHeight:.infinity,alignment:.top)
            Divider()
            if let id=selected,model.workshop.builds.contains(where:{$0.id==id}) { BuildEditor(model:model,buildID:id).id(id).padding(.leading,12) }
            else { ContentUnavailableView("Your saved builds",systemImage:"rectangle.stack.badge.plus",description:Text("Create a build, copy the current average, or import a YDK file.")) }
        }.onAppear {if selected==nil {selected=model.workshop.builds.first?.id}}
    }
    var searches:some View {
        VStack(alignment:.leading,spacing:16) {
            Text("Save the current explorer's format, deck type, event tier, date range, rank, and card filters. Dates remain fixed until you edit them.").foregroundStyle(.secondary)
            HStack { TextField("Search name",text:$searchName);Button("Save current search") { model.saveSearch(searchName);searchName="" }.disabled(model.type==nil) }
            List {
                ForEach(model.workshop.searches) { search in
                    HStack {
                        VStack(alignment:.leading) { Text(search.name).bold();Text("\(search.format.rawValue) · \(search.type.name) · \(Model.day(search.start)) – \(Model.day(search.end))").font(.caption);Text("\(search.filters.requiredCards.count) required · \(search.filters.excludedCards.count) excluded · \(search.tier.rawValue)").font(.caption).foregroundStyle(.secondary) }
                        Spacer();Button("Load") { model.applySearch(search);tab="Explorer" }
                        Button("Remove") { var next=model.workshop;next.searches.removeAll { $0.id==search.id };model.saveWorkshop(next) }
                    }
                }
            }
            Text("Favorites appear first in the deck sidebar. Right-click a deck type to favorite or unfavorite it.").font(.callout)
        }
    }
}

struct CoreFlexView:View {
    @ObservedObject var model:Model
    @State private var threshold=80.0
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:14) {
                Text("Current filtered dataset · \(model.decks.count) lists").font(.headline)
                HStack { Text("Core threshold: \(Int(threshold))% inclusion");Slider(value:$threshold,in:50...100,step:5).frame(width:240) }
                Text("Core means commonly included, not mandatory or proven optimal. Flex cards appear below the threshold. Small samples are less reliable.").foregroundStyle(.secondary)
                ForEach([true,false],id:\.self) { core in
                    Text(core ? "Core cards" : "Flex choices").font(.title3.bold())
                    ForEach(model.stats.filter { (100*Double($0.included)/Double(max(1,model.decks.count))>=threshold)==core }) { row in
                        HStack { Text(row.card.name);Spacer();Text("\(row.included)/\(model.decks.count) lists · \(String(format:"%.2f",Double(row.total)/Double(max(1,model.decks.count)))) copies on average").foregroundStyle(.secondary) }
                    }
                }
                Divider();Text("Cards that travel together").font(.title3.bold())
                Text("Optional groups appearing in exactly the same source lists, at least twice. Co-occurrence is evidence of a package, not proof of synergy. Copy a source list to preserve its combinations.").foregroundStyle(.secondary)
                let packages=commonPackages(model.decks)
                if packages.isEmpty { Text("No repeated optional groups in this sample.") }
                ForEach(packages) { package in
                    VStack(alignment:.leading) { Text("\(package.count)/\(package.total) lists").bold();Text(package.cards.joined(separator:" · ")) }.padding(10).frame(maxWidth:.infinity,alignment:.leading).background(.primary.opacity(0.04)).clipShape(RoundedRectangle(cornerRadius:8))
                }
            }.padding(8)
        }
    }
}

struct Recommendation:Identifiable {
    var build:PersonalBuild
    var totals:BuildTotals
    var id:String { build.id }
    var completion:Double { Double(totals.coveredCopies)/Double(max(1,totals.targetCopies)) }
}
struct RecommendationsView:View {
    @ObservedObject var model:Model
    @State private var budget="30"
    @State private var useBudget=false
    @State private var availableOnly=true
    @State private var sort="Completion"
    @State private var notice=""
    var candidates:[Recommendation] {
        let format=GameFormat(rawValue:model.snapshot?.format ?? model.format.rawValue) ?? model.format
        let sources=model.decks.map { deck in var b=PersonalBuild.from(deck,format:format);b.id="source:"+deck.id;return b }
        let all=model.workshop.builds + sources
        var result=all.map { build -> Recommendation in
            let inventory=availableOnly ? availableInventory(model.inventory,excluding:build.id,builds:model.workshop.builds) : model.inventory
            return Recommendation(build:build,totals:buildTotals(stats:aggregate([build.deck]),sample:1,inventory:inventory,quotes:model.quotes,roundUp:false))
        }
        if useBudget { guard let cents=budgetCents(budget) else { return [] };result=result.filter { $0.totals.unpricedMissingCopies==0 && $0.totals.missingCents<=cents } }
        return result.sorted { a,b in
            if sort == "Cost to finish" {
                if (a.totals.unpricedMissingCopies==0) != (b.totals.unpricedMissingCopies==0) { return a.totals.unpricedMissingCopies==0 }
                if a.totals.missingCents != b.totals.missingCents { return a.totals.missingCents<b.totals.missingCents }
            }
            return a.completion == b.completion ? a.build.name<b.build.name : a.completion>b.completion
        }
    }
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Text("Ranked from your saved builds and the current filtered source lists. Load All deck types in the explorer to compare more archetypes. Source lists remain intact.").foregroundStyle(.secondary)
            HStack {
                Toggle("Budget",isOn:$useBudget);TextField("USD",text:$budget).frame(width:70);Text("USD to finish")
                Toggle("Reserve copies in assembled builds",isOn:$availableOnly)
                Picker("Sort",selection:$sort) { Text("Completion").tag("Completion");Text("Cost to finish").tag("Cost to finish") }.frame(width:210)
            }
            if useBudget && budgetCents(budget)==nil { Text("Enter a non-negative budget in USD.").foregroundStyle(.orange) }
            Text("Budget results require prices for every missing copy. Missing quotes are never treated as free. Quotes exclude shipping and tax; candidates may need legality review.").font(.caption).foregroundStyle(.secondary)
            if !notice.isEmpty { Text(notice).foregroundStyle(.teal) }
            ScrollView {
                LazyVStack(alignment:.leading,spacing:10) {
                    ForEach(candidates) { item in
                        HStack {
                            VStack(alignment:.leading,spacing:5) {
                                Text(item.build.name).bold();Text("\(item.build.format.rawValue) · \(item.totals.coveredCopies)/\(item.totals.targetCopies) owned · \(item.totals.missingCopies) missing").font(.caption)
                                Text("To finish: \(dollars(item.totals.missingCents))\(item.totals.unpricedMissingCopies>0 ? " + \(item.totals.unpricedMissingCopies) unpriced copies" : "")").foregroundStyle(.secondary)
                            };Spacer()
                            Button("Save a copy") { var copy=item.build;copy.id=UUID().uuidString;copy.allocated=false;model.putBuild(copy);notice="Saved \(copy.name) in Builds." }
                        }.padding(12).background(.primary.opacity(0.04)).clipShape(RoundedRectangle(cornerRadius:8))
                    }
                    if candidates.isEmpty { Text("No candidates match. Load source lists or add a saved build; choose printings in Collection & cost to complete price estimates.").padding() }
                }
            }
        }
    }
}
