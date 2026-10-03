import SwiftUI
import AppKit

@MainActor final class Model: ObservableObject {
    @Published var advanced = AdvancedData()
    @Published var recovery = RecoveryIndex()
    var suppressRecovery=false
    @Published var lab = LabData()
    @Published var watchRefreshBusy=false
    @Published var watchStatus=""
    @Published var workshop = WorkshopData()
    @Published var masterDuelRules: MasterDuelRules?
    @Published var hiddenTypes: Set<String> = []
    @Published var inventory = Inventory()
    @Published var quotes: [String:PriceQuote] = [:]
    @Published var pricingBusy = false
    @Published var pricingProgress = ""
    @Published var refreshingQuoteIDs: Set<String> = []
    @Published var pricingErrors: [String:String] = [:]
    var priceTask: Task<Void,Never>?
    @Published var types: [DeckType] = []
    @Published var format = GameFormat.masterDuel
    @Published var eventTier = EventTier.any
    @Published var cardIndex: [String: CardInfo] = [:]
    @Published var genesysIndex: [String: CardInfo] = [:]
    @Published var cardDataDate: Date?
    @Published var cardDataError: String?
    private var mdTypes: [DeckType] = []
    private var ygoTypes: [DeckType] = []
    @Published var selectedType: String? = nil
    @Published var snapshot: Snapshot?
    @Published var roles: [String: CardRole] = [:]
    @Published var filters = Filters()
    @Published var start = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
    @Published var end = Date()
    @Published var loading = false
    @Published var loadingTypes = false
    @Published var progress = ""
    @Published var error: String?
    @Published var storageError: String?
    var store: LocalStore?
    private var task: Task<Void, Never>?
    private var generation = UUID()
    var type: DeckType? { selectedType == "all" ? DeckType(id:"all",name:"All deck types") : types.first { $0.id == selectedType } }
    static func day(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
    var from: String { Self.day(start) }
    var through: String { Self.day(end) }
    var pending: Bool { snapshot?.type.id != selectedType || snapshot?.from != from || snapshot?.through != through || (snapshot?.format ?? GameFormat.masterDuel.rawValue) != format.rawValue || (snapshot?.eventTier ?? EventTier.any.rawValue) != eventTier.rawValue }
    var decks: [Deck] { (snapshot?.decks ?? []).filter(filters.matches) }
    var stats: [CardStats] { aggregate(decks) }
    var availableRanks: [String] { Array(Set((snapshot?.decks ?? []).map(\.rank).filter { !$0.isEmpty })).sorted() }
    var tournaments: [String] { Array(Set((snapshot?.decks ?? []).map(\.tournament).filter { !$0.isEmpty })).sorted() }
    init(storeDirectory:URL? = nil) {
        do {
            let s = try LocalStore(directory:storeDirectory); store = s
            advanced = try s.read("advanced.json",as:AdvancedData.self) ?? AdvancedData()
            recovery = try s.read("recovery-index.json",as:RecoveryIndex.self) ?? RecoveryIndex()
            masterDuelRules = try s.read("md-rules.json",as:MasterDuelRules.self)
            lab = try s.read("lab.json",as:LabData.self) ?? LabData()
            workshop = try s.read("workshop.json",as:WorkshopData.self) ?? WorkshopData()
            roles = try s.read("classifications.json", as: [String: CardRole].self) ?? [:]
            hiddenTypes = Set(try s.read("hidden-deck-types.json",as:[String].self) ?? [])
            inventory = try s.read("inventory.json", as: Inventory.self) ?? Inventory()
            quotes = try s.read("tcg-quotes.json", as: [String:PriceQuote].self) ?? [:]
            pricingErrors = try s.read("tcg-pricing-errors.json", as: [String:String].self) ?? [:]
            mdTypes = try s.read("catalogue.json", as: [DeckType].self) ?? []
            ygoTypes = try s.read("ygo-catalogue.json", as: [DeckType].self) ?? []
            types = mdTypes
            snapshot = try s.read("latest-snapshot.json", as: Snapshot.self)
            if let snapshot {
                format = GameFormat(rawValue: snapshot.format ?? "Master Duel") ?? .masterDuel
                eventTier = EventTier(rawValue: snapshot.eventTier ?? "All events") ?? .any
                types = format == .masterDuel ? mdTypes : ygoTypes
                selectedType = snapshot.type.id
                let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
                start = f.date(from: snapshot.from) ?? start; end = f.date(from: snapshot.through) ?? end
            }
        } catch { storageError = "Local data could not be read: \(error.localizedDescription). Existing files have been preserved." }
    }
    func catalogue() async {
        guard !loadingTypes else { return }
        loadingTypes = true; defer { loadingTypes = false }
        let requestedFormat = format
        do {
            let loaded = try await (requestedFormat == .masterDuel ? MDM.catalogue() : YGO.archetypes())
            if requestedFormat == .masterDuel { mdTypes = loaded } else { ygoTypes = loaded }
            do { try store?.write(loaded, name: requestedFormat == .masterDuel ? "catalogue.json" : "ygo-catalogue.json") } catch { storageError = "Could not save the deck catalogue: \(error.localizedDescription)" }
            guard format == requestedFormat else { return }
            types = loaded
            if selectedType == nil { selectedType = types.first { $0.name == (format == .genesys ? "Darklord" : "Sky Striker") }?.id ?? types.first?.id }
            if snapshot == nil || snapshot?.format != format.rawValue && format != .masterDuel { load() }
        } catch { self.error = "Could not refresh deck types: \(error.localizedDescription)" }
    }
    func changeFormat(_ value: GameFormat) {
        cancel(); format = value; eventTier = .any; filters = Filters(); selectedType = nil
        types = value == .masterDuel ? mdTypes : ygoTypes
        selectedType = types.first { $0.name == (value == .genesys ? "Darklord" : "Sky Striker") }?.id
        Task { await catalogue(); if !loading, selectedType != nil { load() } }
    }
    func enrichCards(force: Bool = false) async {
        do {
            let db = try await YGO.shared.cardDatabase(force: force)
            cardIndex = db.index; cardDataDate = db.fetched; cardDataError = nil
            do {
                let points = try await YGO.shared.cardDatabase(genesys: true, force: force)
                genesysIndex = points.index
            }
        } catch { cardDataError = "Card details: \(error.localizedDescription)" }
    }
    func info(_ card: Card) -> CardInfo? { cardIndex[String(card.id.replacingOccurrences(of:"ygo:",with:""))] ?? cardIndex[card.name.lowercased()] }
    func points(_ card: Card) -> Int? { genesysIndex[card.name.lowercased()]?.genesysPoints }
    func isHidden(_ type: DeckType) -> Bool { hiddenTypes.contains(normalizedCardName(type.name)) }
    func setHidden(_ type: DeckType, _ hidden: Bool) {
        guard let store else { storageError="Local storage is unavailable. Hidden deck types were not saved."; return }
        var updated=hiddenTypes
        if hidden { updated.insert(normalizedCardName(type.name)) } else { updated.remove(normalizedCardName(type.name)) }
        do { try captureRecovery("Hidden deck types");try store.write(Array(updated).sorted(),name:"hidden-deck-types.json");hiddenTypes=updated;if hidden && selectedType==type.id { cancel();selectedType=nil } }
        catch { storageError="Could not save hidden deck types: \(error.localizedDescription)" }
    }
    func choose(_ id: String?) { selectedType = id; filters.exactRank = "All"; filters.tournament = "All"; load() }
    func load() {
        guard let type else { return }
        task?.cancel()
        let current = UUID(); generation = current
        guard from <= through else { loading = false; error = "The start date must be on or before the end date."; return }
        guard format != .masterDuel || from >= "2022-01-19" else { loading = false; error = "Choose a start date on or after Master Duel's launch: January 19, 2022."; return }
        loading = true; error = nil; progress = "Connecting to \(format.provider)…"
        let a = from, b = through, selectedFormat = format, selectedTier = eventTier
        let next = Self.day(Calendar.current.date(byAdding: .day, value: 1, to: end)!)
        task = Task {
            do {
                let loaded: [Deck]
                if selectedFormat == .masterDuel {
                    loaded = try await MDM.fetch(type: type, from: a, before: next) { count in
                        await MainActor.run { if self.generation == current { self.progress = "Loaded \(count) submissions…" } }
                    }
                } else {
                    progress = "Loading cached card database…"
                    let db = try await YGO.shared.cardDatabase()
                    cardIndex = db.index; cardDataDate = db.fetched
                    loaded = try await YGO.fetch(type:type,format:selectedFormat,from:a,through:b,tier:selectedTier,cards:db.index) { count in
                        await MainActor.run { if self.generation == current { self.progress = "Loaded \(count) \(selectedFormat.rawValue) submissions…" } }
                    }
                }
                guard generation == current, !Task.isCancelled else { return }
                let s = Snapshot(type: type, from: a, through: b, fetched: Date(), decks: loaded, format:selectedFormat.rawValue,eventTier:selectedTier.rawValue)
                snapshot = s
                Task { await self.enrichCards() }
                do { try store?.write(s, name: "latest-snapshot.json") } catch { storageError = "Statistics loaded, but the offline snapshot could not be saved: \(error.localizedDescription)" }
            } catch {
                guard generation == current else { return }
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
            if generation == current { loading = false }
        }
    }
    func cancel() { task?.cancel(); generation = UUID(); loading = false }
    var rolePrefix: String { ((snapshot?.format ?? "Master Duel") == "Master Duel" ? "" : (snapshot?.format ?? "") + ":") + (snapshot?.type.id ?? "") }
    func role(_ card: String) -> CardRole { roles[rolePrefix + ":" + card] ?? .unclassified }
    func setRole(_ card: String, _ role: CardRole) {
        guard snapshot != nil, let store else { storageError = "Local storage is unavailable. Your classification was not saved."; return }
        var updated = roles; updated[rolePrefix + ":" + card] = role
        do { try captureRecovery("Card classifications");try store.write(updated, name: "classifications.json"); roles = updated; storageError = nil }
        catch { storageError = "Classification could not be saved: \(error.localizedDescription)" }
    }
}

struct ContentView: View {
    @StateObject private var model = Model()
    @State private var search = ""
    @State private var cardSearch = ""
    @State private var roleFilter = "All roles"
    @State private var zone = "All zones"
    @State private var mode = AverageMode.all
    @State private var selectedCard: String?
    @State private var tab = "Cards"
    @State private var route = "Explorer"
    @State private var navQuery = ""
    @State private var showJump = false
    @State private var showDeckBrowser = false
    @State private var showDatasetFilters = false
    @State private var presentation = "Gallery"
    @AppStorage("appearance") private var appearance = "Dark"
    @State private var sort = "Inclusion"
    @State private var showHelp = false
    @State private var showAdvanced = false
    @State private var showHidden = false
    private let accent = LabStyle.accent
    var matchingTypes: [DeckType] { model.types.filter { (showHidden || !model.isHidden($0)) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }.sorted { a,b in let x=model.workshop.favorites.contains(normalizedCardName(a.name)),y=model.workshop.favorites.contains(normalizedCardName(b.name));return x == y ? a.name<b.name : x } }
    var rows: [CardStats] {
        let filtered = model.stats.filter {
            (cardSearch.isEmpty || $0.card.name.localizedCaseInsensitiveContains(cardSearch)) &&
            (roleFilter == "All roles" || model.role($0.id).rawValue == roleFilter) &&
            (zone == "All zones" || zone == "Main" && $0.main > 0 || zone == "Extra" && $0.extra > 0 || zone == "Side" && $0.side > 0)
        }
        return filtered.sorted { a, b in
            if sort == "Name" { return a.card.name < b.card.name }
            let av = sort == "Average copies" ? a.average(a.total, sample: model.decks.count, mode: mode) : Double(a.included)
            let bv = sort == "Average copies" ? b.average(b.total, sample: model.decks.count, mode: mode) : Double(b.included)
            return av == bv ? a.card.name < b.card.name : av > bv
        }
    }
    var body: some View {
        HStack(spacing:0) {
            LabNavigation(selection:$route,query:$navQuery,alerts:model.triggeredWatches.count) { showJump=true }
            Rectangle().fill(.primary.opacity(0.07)).frame(width:1)
            VStack(spacing:0) {
            WorkspaceTabs(selection:$route,ids:workspaceTools)
            if route == "Explorer" {
            HStack(spacing:0) {
            deckIndex
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                header
                if showDatasetFilters { filters }
                if let error = model.error { message(error, symbol: "exclamationmark.triangle", color: .orange) }
                if let error = model.cardDataError { message(error, symbol: "info.circle", color: .orange) }
                if let error = model.storageError { message(error, symbol: "externaldrive.badge.exclamationmark", color: .orange) }
                if model.loading {
                    HStack { ProgressView().controlSize(.small); Text(model.progress); Spacer(); Button("Cancel") { model.cancel() } }.padding(14).background(accent.opacity(0.08))
                }
                if model.pending && model.snapshot != nil {
                    message("Showing the previous dataset below. Load the selected deck and dates to update it.", symbol: "clock.arrow.circlepath", color: .orange)
                }
                if let snapshot = model.snapshot {
                    summary(snapshot)
                    HStack {
                        ArchiveTabs(selection:$tab,tabs:["Composition","Source lists","Collection & cost"],values:["Cards","Decks","Collection"])
                        Spacer()
                        Text("\(model.decks.count) LISTS IN THIS SAMPLE").font(.system(size:9,design:.monospaced)).tracking(1).foregroundStyle(.secondary)
                    }.padding(.horizontal,24).padding(.bottom,8)
                    if tab == "Cards" { cardTable } else if tab == "Decks" { deckTable } else { CollectionView(model:model) }
                    footer(snapshot)
                } else if !model.loading {
                    ContentUnavailableView("Choose a deck type", systemImage: "rectangle.stack", description: Text("Use Browse deck types above to select a deck and load its submitted lists."))
                } else { Spacer() }
            }.frame(maxWidth:.infinity,maxHeight:.infinity).background(LabStyle.canvas)
            }
            } else {
                WorkshopView(model:model,tab:$route).frame(maxWidth:.infinity,maxHeight:.infinity)
            }
            }
        }
        .tint(accent)
        .font(.system(size:13))
        .controlSize(.large)
        .buttonStyle(LabControlStyle())
        .textFieldStyle(.roundedBorder)
        .preferredColorScheme(appearance == "System" ? nil : appearance == "Light" ? .light : .dark)
        .frame(minWidth:1240,minHeight:780)
        .toolbar {
            ToolbarItem(placement:.automatic) {
                HStack(spacing:12) {
                    Button { showJump=true } label: { Label("Jump to",systemImage:"magnifyingglass") }.keyboardShortcut("k",modifiers:.command).help("Jump to a workspace (⌘K)")
                    Menu { Picker("Appearance",selection:$appearance) { Text("System").tag("System");Text("Light").tag("Light");Text("Dark").tag("Dark") } } label: {Label("Appearance",systemImage:"circle.lefthalf.filled")}.accessibilityLabel("Appearance").help("Choose light, dark, or system appearance")
                    Button { showHelp=true } label: { Label("Help",systemImage:"questionmark.circle") }.help("Learn about sources, averages, and pricing")
                }
            }
        }
        .background {
            Group {
                Button("Deck explorer"){route="Explorer"}.keyboardShortcut("1",modifiers:.command)
                Button("My decks"){route="Builds"}.keyboardShortcut("2",modifiers:.command)
                Button("Card library"){route="Card search"}.keyboardShortcut("3",modifiers:.command)
                Button("Test hands"){route="Hands & probability"}.keyboardShortcut("4",modifiers:.command)
            }.hidden().accessibilityHidden(true)
        }
        .task {
            var last=Date.distantPast
            while !Task.isCancelled {
                if model.lab.autoRefreshPrices && Date().timeIntervalSince(last)>=900 { await model.refreshWatchedPrices();last=Date() }
                do { try await Task.sleep(for:.seconds(60)) } catch { break }
            }
        }
        .sheet(isPresented: $showJump) { JumpPalette(selection:$route) }
        .sheet(isPresented: $showHelp) { help }
        .sheet(isPresented: $showAdvanced) { AdvancedFiltersView(model:model) }
        .sheet(isPresented:Binding(get:{selectedCard != nil && presentation == "Table"},set:{if !$0{selectedCard=nil}})) {
            if let s=rows.first(where:{$0.id==selectedCard}) { cardDetail(s) }
        }
        .task { await model.catalogue(); await model.enrichCards() }
    }
    var deckBrowser:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack { Text("Choose a deck type").font(.title3.bold());Spacer();Button("Done"){showDeckBrowser=false} }.padding(.horizontal,14).padding(.top,16)
                Picker("Format", selection: Binding(get: { model.format }, set: { model.changeFormat($0); search = ""; selectedCard = nil })) { ForEach(GameFormat.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.padding(.horizontal, 12).disabled(model.loadingTypes)
                TextField("Search deck types", text: $search).textFieldStyle(.roundedBorder).padding(.horizontal, 12)
                HStack { Text("DECK TYPES").font(.caption).tracking(1.5); Spacer(); Text("\(matchingTypes.count)").monospacedDigit() }.foregroundStyle(.secondary).padding(.horizontal, 14)
                List(selection: Binding(get: { model.selectedType }, set: { model.choose($0); selectedCard = nil })) {
                    if search.isEmpty || "All deck types".localizedCaseInsensitiveContains(search) { Text("All deck types").font(.system(size:14,weight:.semibold)).padding(.vertical,5).tag("all") }
                    ForEach(matchingTypes) { type in
                        HStack { if model.workshop.favorites.contains(normalizedCardName(type.name)) { Image(systemName:"star.fill").foregroundStyle(.yellow) };Text(type.name);if model.isHidden(type) { Image(systemName:"eye.slash").foregroundStyle(.secondary) } }.font(.system(size:14)).padding(.vertical,5).tag(type.id)
                            .contextMenu { Button(model.workshop.favorites.contains(normalizedCardName(type.name)) ? "Unfavorite" : "Favorite") { model.favorite(type) };Button(model.isHidden(type) ? "Unhide deck type" : "Hide deck type") { model.setHidden(type,!model.isHidden(type)) } }
                    }
                }.listStyle(.sidebar)
                HStack { Button("Hide selected") { if let type=model.type { model.setHidden(type,true) } }.disabled(model.type==nil || model.type?.id=="all");Spacer();Toggle("Show hidden",isOn:$showHidden).toggleStyle(.checkbox) }.font(.caption).padding(.horizontal,12)
                HStack {
                    Button { Task { await model.catalogue() } } label: { Label("Refresh types", systemImage: "arrow.clockwise") }.disabled(model.loadingTypes)
                    if model.loadingTypes { ProgressView().controlSize(.small) }
                }.font(.caption).padding(12)
        }.frame(width:340,height:600).background(LabStyle.sidebar)
    }
    var workspaceTools:[String] {
        switch route {
        case "Explorer","Card search","What can I build?","Dataset trends","Saved searches":return ["Explorer","Card search","What can I build?","Dataset trends","Saved searches"]
        case "Hands & probability","Advanced probabilities":return ["Hands & probability","Advanced probabilities"]
        case "Collection browser","Shopping list","Price history & alerts","Collection locations":return ["Collection browser","Shopping list","Price history & alerts","Collection locations"]
        case "Import & backup","Recovery":return ["Import & backup","Recovery"]
        default:return ["Builds","Compare","Core & flex","Substitutions","Side plans","Match log","Build history","Share deck"]
        }
    }
    var deckIndex:some View {
        VStack(alignment:.leading,spacing:0) {
            HStack {Text("DECK INDEX").font(.system(size:11,weight:.bold)).tracking(1.5);Spacer();Text("\(matchingTypes.count)").monospacedDigit().foregroundStyle(.secondary)}.padding(.top,24).padding(.bottom,18)
            Picker("Format",selection:Binding(get:{model.format},set:{model.changeFormat($0);search="";selectedCard=nil})){ForEach(GameFormat.allCases,id:\.self){Text($0.rawValue).tag($0)}}.labelsHidden().disabled(model.loadingTypes).padding(.bottom,12)
            LabSearch(title:"Find deck type",text:$search).padding(.bottom,16)
            ScrollViewReader { proxy in ScrollView {
                LazyVStack(alignment:.leading,spacing:3) {
                    indexRow("All deck types",id:"all",favorite:false).id("all")
                    ForEach(matchingTypes){type in
                        indexRow(type.name,id:type.id,favorite:model.workshop.favorites.contains(normalizedCardName(type.name))).id(type.id)
                            .contextMenu {Button(model.workshop.favorites.contains(normalizedCardName(type.name)) ? "Unfavorite" : "Favorite"){model.favorite(type)};Button(model.isHidden(type) ? "Unhide deck type" : "Hide deck type"){model.setHidden(type,!model.isHidden(type))}}
                    }
                }
            }
            .onAppear {if let id=model.selectedType {proxy.scrollTo(id,anchor:.center)}}
            .onChange(of:model.selectedType){_,id in if let id {proxy.scrollTo(id,anchor:.center)}}
            }
            Divider().padding(.vertical,12)
            Toggle("Show hidden",isOn:$showHidden).toggleStyle(.checkbox).font(.system(size:11)).padding(.bottom,12)
            HStack {Button("Hide selected"){if let type=model.type{model.setHidden(type,true)}}.disabled(model.type==nil || model.type?.id=="all");Spacer();Button{Task{await model.catalogue()}}label:{Image(systemName:"arrow.clockwise")}.help("Refresh deck index").accessibilityLabel("Refresh deck index")}.controlSize(.small).padding(.bottom,18)
        }.padding(.horizontal,16).frame(width:208).background(LabStyle.surface.opacity(0.45))
    }
    func indexRow(_ name:String,id:String,favorite:Bool)->some View {
        Button{model.choose(id);selectedCard=nil}label:{HStack(spacing:8){if favorite{Image(systemName:"star.fill").font(.system(size:9)).foregroundStyle(LabStyle.accent)};Text(name).font(.system(size:13,weight:model.selectedType==id ? .semibold : .regular)).lineLimit(1);Spacer(minLength:0);if model.selectedType==id{Circle().fill(LabStyle.accent).frame(width:5,height:5)}}.padding(.horizontal,10).frame(height:36).background(model.selectedType==id ? Color.primary.opacity(0.08) : Color.clear,in:RoundedRectangle(cornerRadius:5)).contentShape(Rectangle())}.buttonStyle(.plain).accessibilityValue(model.selectedType==id ? "Selected" : "").help(name)
    }
    var header:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack(alignment:.center,spacing:16) {
                VStack(alignment:.leading,spacing:7){Text("ARCHETYPE / \(model.format.rawValue.uppercased())").font(.system(size:10,weight:.medium,design:.monospaced)).tracking(1.2).foregroundStyle(accent);Text(model.type?.name ?? "Deck explorer").font(.system(size:38,weight:.semibold)).tracking(-1.3).lineLimit(1).minimumScaleFactor(0.65)}
                Spacer()
                Button{showDatasetFilters.toggle()}label:{Label("Filters",systemImage:"slider.horizontal.3")}.accessibilityValue(showDatasetFilters ? "Expanded" : "Collapsed")
                Button{model.load()}label:{Image(systemName:"arrow.clockwise")}.disabled(model.type==nil || model.loading).keyboardShortcut("r",modifiers:.command).help("Refresh dataset").accessibilityLabel("Refresh dataset")
            }
            HStack(spacing:8){Text("\(Model.day(model.start)) — \(Model.day(model.end))");Text("·");Text(model.filters.source.rawValue);if model.eventTier != .any{Text("· "+model.eventTier.rawValue)};Spacer();if !model.filters.requiredCards.isEmpty || !model.filters.excludedCards.isEmpty{Button("Card filters active"){showAdvanced=true}.buttonStyle(.link)}}.font(.system(size:11)).foregroundStyle(.secondary)
        }.padding(24)
    }
    var filters: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) { Text("SOURCE").font(.caption).foregroundStyle(.secondary); Picker("Source", selection: $model.filters.source) { ForEach(model.format == .masterDuel ? DeckSource.allCases : [.all, .tournaments, .other], id: \.self) { Text(model.format != .masterDuel && $0 == .other ? "Community lists" : $0.rawValue).tag($0) } }.labelsHidden() }.frame(maxWidth: .infinity)
                if model.format == .masterDuel { VStack(alignment: .leading, spacing: 6) { Text("MINIMUM RANK").font(.caption).foregroundStyle(.secondary); Picker("Minimum rank", selection: $model.filters.rank) { ForEach(RankFloor.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.labelsHidden() }.frame(maxWidth: .infinity) } else {
                    VStack(alignment: .leading, spacing: 6) { Text("TOURNAMENT TIER").font(.caption).foregroundStyle(.secondary); Picker("Tournament tier", selection: $model.eventTier) { ForEach(EventTier.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.labelsHidden() }.frame(maxWidth: .infinity)
                }
                DatePicker("From", selection: $model.start, displayedComponents: .date).fixedSize()
                DatePicker("Through", selection: $model.end, in: ...Date(), displayedComponents: .date).fixedSize()
            }
            HStack(spacing: 16) {
                if model.format == .masterDuel { Picker("Rank", selection: $model.filters.exactRank) { Text("All").tag("All"); ForEach(model.availableRanks, id: \.self) { Text($0).tag($0) } }.frame(maxWidth: 220) }
                Picker("Tournament", selection: $model.filters.tournament) { Text("All").tag("All"); ForEach(model.tournaments, id: \.self) { Text($0).tag($0) } }.frame(maxWidth: 300)
                if model.format == .masterDuel { Toggle("Exclude flagged lists", isOn: $model.filters.excludeFlagged).help("Exclude lists marked illegal by the source. Historical lists may be flagged by later banlists.") }
                Spacer(minLength: 0)
                Button("Card filters…") { showAdvanced=true }.font(.callout)
                Button("Reset filters") { model.filters = Filters(); model.eventTier = .any }.font(.callout)
            }
            if !model.filters.requiredCards.isEmpty || !model.filters.excludedCards.isEmpty {
                HStack(alignment:.top) {
                    VStack(alignment:.leading,spacing:4) {
                        if !model.filters.requiredCards.isEmpty { Text("Must include: " + model.filters.requiredCards.joined(separator:" · ")) }
                        if !model.filters.excludedCards.isEmpty { Text("Must exclude: " + model.filters.excludedCards.joined(separator:" · ")) }
                    }.font(.caption).foregroundStyle(accent)
                    Spacer();Button("Clear card filters") { model.filters.requiredCards=[];model.filters.excludedCards=[] }.font(.caption)
                }
            }
        }.padding(18).labSurface().padding(.horizontal, 24).padding(.bottom, 18)
    }
    func summary(_ snapshot: Snapshot) -> some View {
        let decks=model.decks,n=Double(max(1,decks.count))
        return HStack(spacing:16) {
            Text("\(decks.count)").font(.system(size:19,weight:.semibold))+Text(" submitted lists").font(.system(size:12)).foregroundColor(.secondary)
            Rectangle().fill(.primary.opacity(0.16)).frame(width:1,height:24)
            Text("\(model.stats.count)").font(.system(size:19,weight:.semibold))+Text(" unique cards").font(.system(size:12)).foregroundColor(.secondary)
            Spacer()
            Text(String(format:"Main %.1f · Extra %.1f · Side %.1f",Double(decks.flatMap(\.main).reduce(0){$0+$1.amount})/n,Double(decks.flatMap(\.extra).reduce(0){$0+$1.amount})/n,Double(decks.flatMap(\.side).reduce(0){$0+$1.amount})/n)).font(.system(size:10,design:.monospaced)).foregroundStyle(.secondary).help("Average copies per submitted list")
        }.padding(.vertical,14).overlay(alignment:.top){Rectangle().fill(.primary.opacity(0.18)).frame(height:1)}.overlay(alignment:.bottom){Rectangle().fill(.primary.opacity(0.18)).frame(height:1)}.padding(.horizontal,24).padding(.bottom,8)
    }
    var cardTable: some View {
        VStack(spacing: 0) {
            HStack(spacing:12) {
                LabSearch(title:"Find a card",text:$cardSearch).frame(minWidth:150,maxWidth:260)
                Picker("Role",selection:$roleFilter){Text("All roles").tag("All roles");ForEach(CardRole.allCases,id:\.self){Text($0.rawValue).tag($0.rawValue)}}.labelsHidden().frame(width:140)
                Picker("Zone",selection:$zone){ForEach(["All zones","Main","Extra","Side"],id:\.self){Text($0).tag($0)}}.labelsHidden().frame(width:105)
                Spacer()

                Menu {
                    Picker("Layout",selection:$presentation){Text("Gallery").tag("Gallery");Text("Table").tag("Table")}
                    Picker("Sort",selection:$sort){ForEach(["Inclusion","Name","Average copies"],id:\.self){Text($0).tag($0)}}
                    Picker("Average over",selection:$mode){ForEach(AverageMode.allCases,id:\.self){Text($0.rawValue).tag($0)}}
                } label:{Label("View",systemImage:"rectangle.grid.2x2")}.help("Gallery or table, sort order, and average denominator")
            }.padding(.horizontal,24).padding(.bottom,14)
            if model.decks.isEmpty {
                ContentUnavailableView("No matching decks", systemImage: "line.3.horizontal.decrease.circle", description: Text(model.format == .masterDuel ? "Broaden the dates, source, or rank filters. Minimum rank filters also exclude tournaments without a recorded ladder rank." : "Broaden the dates, archetype, source, or tournament tier. Load dataset after changing dates or tiers."))
            } else if rows.isEmpty {
                ContentUnavailableView("No matching cards", systemImage: "magnifyingglass", description: Text("Try another card name, role, or zone."))
            } else if presentation == "Gallery" {
                HStack(alignment:.top,spacing:0){cardGallery.frame(maxWidth:.infinity,maxHeight:.infinity);if let s=rows.first(where:{$0.id==selectedCard}){Divider();cardPeek(s)}}.frame(maxWidth:.infinity,maxHeight:.infinity)
            } else {
                Table(rows, selection: $selectedCard) {
                    TableColumn("Card") { s in HStack { Text(s.card.name).lineLimit(1); Spacer(); Text(s.card.rarity).font(.caption).foregroundStyle(.secondary) }.help(s.card.name) }.width(min: 210, ideal: 300)
                    TableColumn("Classification") { s in
                        Picker("Classification for \(s.card.name)", selection: Binding(get: { model.role(s.id) }, set: { model.setRole(s.id, $0) })) { ForEach(CardRole.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.labelsHidden()
                    }.width(145)
                    TableColumn("Inclusion") { s in Text(String(format: "%.1f%%", 100 * Double(s.included) / Double(max(1, model.decks.count)))).monospacedDigit().help("\(s.included) of \(model.decks.count) matching decks run this card in any zone") }.width(78)
                    TableColumn("Main avg") { s in number(s.average(s.main, sample: model.decks.count, mode: mode)) }.width(73)
                    TableColumn("Extra avg") { s in number(s.average(s.extra, sample: model.decks.count, mode: mode)) }.width(73)
                    TableColumn("Side avg") { s in number(s.average(s.side, sample: model.decks.count, mode: mode)) }.width(73)
                    TableColumn("Total avg") { s in number(s.average(s.total, sample: model.decks.count, mode: mode)) }.width(73)
                }.alternatingRowBackgrounds()

            }
        }
    }
    var cardGallery:some View {
        ScrollView {
            LazyVGrid(columns:[GridItem(.adaptive(minimum:170,maximum:240),spacing:16)],spacing:22) {
                ForEach(rows) {row in
                    Button {selectedCard=row.id} label: {
                        VStack(alignment:.leading,spacing:0) {
                            ZStack(alignment:.bottomTrailing){
                                Rectangle().fill(.primary.opacity(0.035))
                                CardArtwork(info:model.info(row.card)).padding(12).allowsHitTesting(false).accessibilityHidden(true)
                                Text(String(format:"%.0f%%",100*Double(row.included)/Double(max(1,model.decks.count)))).font(.system(size:11,weight:.bold,design:.monospaced)).padding(.horizontal,8).padding(.vertical,5).background(LabStyle.surface).padding(7)
                            }.frame(height:212).clipShape(RoundedRectangle(cornerRadius:6)).overlay(RoundedRectangle(cornerRadius:6).strokeBorder(selectedCard==row.id ? accent : Color.primary.opacity(0.06),lineWidth:selectedCard==row.id ? 2 : 1))
                            Text(row.card.name).font(.system(size:12,weight:.semibold)).lineLimit(2).frame(height:34,alignment:.topLeading).padding(.top,10)
                            HStack(alignment:.firstTextBaseline){Text(String(format:"%.2f",row.average(row.total,sample:model.decks.count,mode:mode))).font(.system(size:16,weight:.medium,design:.monospaced));Text("avg").font(.system(size:10)).foregroundStyle(.secondary);Spacer();Text("\(model.inventory.owned(row.card.name)) owned").font(.system(size:10)).foregroundStyle(.secondary)}
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("\(row.card.name), \(row.included) of \(model.decks.count) lists, \(model.inventory.owned(row.card.name)) owned. Show card details.").help("View card details and copy distribution")
                }
            }.padding(.horizontal,24).padding(.top,3).padding(.bottom,24)
        }
    }
    func cardPeek(_ s:CardStats)->some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18){
                HStack{Text("CARD DETAILS").font(.system(size:10,weight:.semibold)).tracking(1.2).foregroundStyle(.secondary);Spacer();Button{selectedCard=nil}label:{Image(systemName:"xmark")}.buttonStyle(.plain).help("Close card details").accessibilityLabel("Close card details")}
                CardArtwork(info:model.info(s.card)).frame(height:260).frame(maxWidth:.infinity)
                Text(s.card.name).font(.system(size:19,weight:.semibold)).fixedSize(horizontal:false,vertical:true)
                if let info=model.info(s.card){Text([info.type,info.attribute,info.race].filter{!$0.isEmpty}.joined(separator:" · ")).font(.system(size:11)).foregroundStyle(.secondary);Text(info.description).font(.system(size:12)).lineSpacing(4).textSelection(.enabled)}
                Divider()
                HStack{Text("Inclusion").foregroundStyle(.secondary);Spacer();Text("\(s.included) / \(model.decks.count) lists").monospacedDigit()}.font(.system(size:12))
                HStack{Text("Owned").foregroundStyle(.secondary);Spacer();Text("\(model.inventory.owned(s.card.name)) copies").monospacedDigit()}.font(.system(size:12))
                Picker("Role",selection:Binding(get:{model.role(s.id)},set:{model.setRole(s.id,$0)})){ForEach(CardRole.allCases,id:\.self){Text($0.rawValue).tag($0)}}
                Text("COPY DISTRIBUTION").font(.system(size:10,weight:.semibold)).tracking(1).foregroundStyle(.secondary)
                ForEach(([0]+s.distribution.keys.filter{$0 != 0}.sorted()),id:\.self){n in
                    let count=n==0 ? model.decks.count-s.included : s.distribution[n] ?? 0
                    HStack{Text("\(n)×").frame(width:20,alignment:.leading);GeometryReader{g in Rectangle().fill(accent.opacity(0.7)).frame(width:g.size.width*Double(count)/Double(max(1,model.decks.count)))}.frame(height:4);Text("\(count)").frame(width:24,alignment:.trailing).foregroundStyle(.secondary)}.font(.system(size:11,design:.monospaced))
                }
                Button("Collection & pricing"){tab="Collection";selectedCard=nil}.frame(maxWidth:.infinity)
            }.padding(18)
        }.frame(width:264).background(LabStyle.surface)
    }
    func cardDetail(_ s:CardStats)->some View {
        VStack(alignment:.leading,spacing:20) {
            HStack {LabBadge(text:"CARD INSPECTOR");Spacer();Button("Done"){selectedCard=nil}.keyboardShortcut(.cancelAction)}
            HStack(alignment:.top,spacing:26) {
                CardArtwork(info:model.info(s.card)).frame(width:230,height:335)
                VStack(alignment:.leading,spacing:16) {
                    Text(s.card.name).font(.system(size:25,weight:.bold,design:.rounded))
                    if let info=model.info(s.card) {Text([info.type,info.attribute,info.race].filter{!$0.isEmpty}.joined(separator:" · ")).font(.caption).foregroundStyle(.secondary);HStack {if let atk=info.atk {Text("ATK \(atk)")};if let def=info.def {Text("DEF \(def)")};if let level=info.level {Text("Level / rank \(level)")};if let points=model.points(s.card),model.snapshot?.format=="Genesys" {Text("\(points) pts")}}.font(.caption).foregroundStyle(.secondary);ScrollView {Text(info.description).font(.system(size:14)).lineSpacing(4).textSelection(.enabled)}.frame(height:170)}
                    Picker("Role in this deck",selection:Binding(get:{model.role(s.id)},set:{model.setRole(s.id,$0)})){ForEach(CardRole.allCases,id:\.self){Text($0.rawValue).tag($0)}}
                    Text("\(model.inventory.owned(s.card.name)) copies in your physical collection").font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(spacing:12){LabMetric(title:"Inclusion",value:String(format:"%.1f%%",100*Double(s.included)/Double(max(1,model.decks.count))),note:"\(s.included) of \(model.decks.count) lists",symbol:"chart.pie");LabMetric(title:"Average copies",value:String(format:"%.2f",s.average(s.total,sample:model.decks.count,mode:mode)),note:mode.rawValue,symbol:"rectangle.stack")}
            Text("Copy distribution across all zones").font(.headline)
            HStack(spacing:12) {LabBadge(text:"0× · \(model.decks.count-s.included) decks");ForEach(s.distribution.keys.sorted(),id:\.self){n in LabBadge(text:"\(n)× · \(s.distribution[n] ?? 0) decks")}}
            HStack {Text("Present in Main: \(s.mainIncluded) · Extra: \(s.extraIncluded) · Side: \(s.sideIncluded)");Spacer();if let info=model.info(s.card),let url=URL(string:info.link),url.host=="ygoprodeck.com" {Link("Card reference",destination:url)}}.font(.caption).foregroundStyle(.secondary)
            Text("Artwork is representative and may differ from your chosen printing.").font(.caption).foregroundStyle(.secondary)
        }.padding(28).frame(width:770).background(LabStyle.canvas)
    }
    func number(_ value: Double) -> some View { Text(String(format: "%.2f", value)).monospacedDigit().foregroundStyle(value == 0 ? .secondary : .primary) }
    func inspector(_ s: CardStats) -> some View {
        HStack(alignment:.top,spacing:16) {
            CardArtwork(info:model.info(s.card)).frame(width:108,height:158)
            VStack(alignment: .leading, spacing: 9) {
            HStack { Text(s.card.name).font(.headline); Spacer(); Button("Done") { selectedCard = nil }.keyboardShortcut(.cancelAction) }
            HStack(spacing: 20) {
                Text("Copies across all zones").foregroundStyle(.secondary)
                Text("0×: \(model.decks.count - s.included) decks")
                ForEach(s.distribution.keys.sorted(), id: \.self) { copies in Text("\(copies)×: \(s.distribution[copies] ?? 0) decks") }
            }.font(.caption)
            if let info = model.info(s.card) {
                Text([info.type, info.race, info.attribute, info.archetype].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                Text(info.description).font(.system(size: 13)).lineLimit(4).textSelection(.enabled)
                HStack {
                    if let atk = info.atk { Text("ATK \(atk)") }; if let def = info.def { Text("DEF \(def)") }; if let level = info.level { Text("Level/Rank \(level)") }
                    if let points = model.points(s.card), model.snapshot?.format == "Genesys" { Text("Genesys: \(points) points per copy").foregroundStyle(accent) }
                    Spacer(); if let url = URL(string: info.link), url.host == "ygoprodeck.com" { Link("Card details · YGOPRODeck", destination: url) }
                }.font(.caption)
                if let date=model.cardDataDate { Text("Card data cached \(date.formatted(date:.abbreviated,time:.omitted)) · Tap image to enlarge").font(.caption).foregroundStyle(.secondary) }
            } else { Text("YGOPRODeck details are not available for this card yet.").font(.caption).foregroundStyle(.secondary) }
            Text("Present in main: \(s.mainIncluded) · extra: \(s.extraIncluded) · side: \(s.sideIncluded). Classifications are saved for \(model.snapshot?.type.name ?? "this deck") only.").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(16).background(accent.opacity(0.08))
    }
    var deckTable: some View {
        Table(model.decks) {
            TableColumn("Submitted") { d in Text(d.day).monospacedDigit() }.width(100)
            TableColumn("Player / deck type") { d in VStack(alignment:.leading,spacing:3) { if let url = d.sourceURL { Link(d.author, destination: url) } else { Text(d.author) }; if model.snapshot?.type.id == "all" { Text(d.typeName).font(.caption).foregroundStyle(.secondary) } } }.width(min: 120, ideal: 180)
            TableColumn("Rank / tournament") { d in VStack(alignment: .leading) { Text(d.isTournament ? d.tournament : d.rank.isEmpty ? "Other" : d.rank); if !d.placement.isEmpty { Text(d.placement).font(.caption).foregroundStyle(.secondary) } } }.width(min: 140, ideal: 200)
            TableColumn("Main") { d in Text("\(d.main.reduce(0) { $0 + $1.amount })") }.width(45)
            TableColumn("Extra") { d in Text("\(d.extra.reduce(0) { $0 + $1.amount })") }.width(45)
            TableColumn("Side") { d in Text("\(d.side.reduce(0) { $0 + $1.amount })") }.width(45)
            TableColumn("Source tags / deck name") { d in Text(d.provider == "YGOPRODeck" ? d.title ?? "—" : d.engines.isEmpty ? "—" : d.engines.joined(separator: ", ")).lineLimit(2).help(d.engines.joined(separator: ", ")) }.width(min: 120, ideal: 240)
            TableColumn("Flagged") { d in Text(d.flagged ? "Yes" : "—").foregroundStyle(d.flagged ? .orange : .secondary) }.width(55)
        }.alternatingRowBackgrounds().overlay { if model.decks.isEmpty { ContentUnavailableView("No matching decks", systemImage: "line.3.horizontal.decrease.circle") } }
    }
    func footer(_ s: Snapshot) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Source: \((s.format ?? "Master Duel") == "Master Duel" ? "Master Duel Meta" : "YGOPRODeck") submissions · \(s.eventTier ?? "All events") · Not a win-rate sample")
                Text("Updated \(s.fetched.formatted(date: .abbreviated, time: .shortened)) · Snapshot available offline")
            }.font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("How averages work") { showHelp = true }.font(.caption)
        }.padding(14)
    }
    func message(_ text: String, symbol: String, color: Color) -> some View { Label(text, systemImage: symbol).font(.callout).foregroundStyle(color).padding(.horizontal, 24).padding(.bottom, 12).fixedSize(horizontal: false, vertical: true) }
    var help: some View {
        ScrollView { VStack(alignment: .leading, spacing: 18) {
            Text("Reading the dataset").font(.title2.bold())
            Text("All matching decks: each average divides copies by the full filtered sample, including decks with zero copies. Decks running card: each average divides by decks running that card anywhere in main, extra, or side. The zone averages always add up to the total average.")
            Text("Inclusion is the percentage of matching decks running the card in any zone. Each submitted deck has equal weight; repeated submissions by a player are separate observations. Missing or empty side decks contribute zero copies. Master Duel ladder play has no side deck; source tournament lists may include one.")
            Text("Master + Rating includes Master I–V and explicitly labeled Rating Duels / Top Rating lists. Win streaks and unlabeled tournament results are not assumed to have a Master rank. Source and rank filters intersect.")
            Text("Card filters match exact card names across main, extra, and side. Every included card must be present; any excluded card removes the deck. Select All deck types to search across archetypes. Hidden deck types are a sidebar preference and do not remove lists from All deck types results. Use Show hidden to restore them.")
            Text("Master Duel dates filter submission dates, inclusive, using UTC calendar days. Changing dates or tournament tiers requires Load dataset. Source, rank, and card filters apply immediately to the loaded snapshot. Flagged lists use the source’s illegal flag, which may reflect a newer banlist.")
            Text("YGOPRODeck formats are separate datasets, filtered by archetype tags (which can include hybrids). Its Tier 2+ filter means Competitive events or higher; Tier 3 means Premier events. These are tournament tiers, not deck-strength rankings. Master Duel Meta does not expose these event tiers. YGOPRODeck dates use the source’s date filter; rows retain the relative date supplied by the source. Card details and Genesys points are cached locally for 48 hours; these are current card data, not historical legality checks.")
            Text("Master Duel Meta supplies deck-level engine tags, not a complete card-level classification. Cards start Unclassified. Your choices are saved locally per deck type and card; they are not inferred from a card’s name. Source tags are visible under Source decks. TCG coverage includes Meta, Non-Meta, Fun/Casual, and Tournament Meta categories. OCG coverage is tournament lists; Genesys includes community and tournament lists. GOAT and Edison use their named deck categories. Other categories are not combined into these datasets.")
            Text("Collection & cost tracks physical cards, shared across all deck types and formats. The target rounds average copies per card across main/extra/side (using all matching decks); it is a buying reference, not necessarily a legal decklist. Owned printings retain their own rarity, edition, and condition when you change the target. Prices are English-language, in-stock TCGplayer listings from verified sellers, in USD, excluding shipping and tax. Unpriced copies remain visible; subtotals are not complete valuations. Master Duel collection comparisons are physical paper equivalents, not your in-game account.")
            Text("This app uses an undocumented third-party API. It reports submitted deck composition, not game-wide usage or win rates. Network errors preserve the last successfully loaded snapshot and all saved classifications.")
            HStack { Link("Master Duel Meta", destination: URL(string: "https://www.masterduelmeta.com")!); Spacer(); Button("Done") { showHelp = false }.keyboardShortcut(.defaultAction) }
        }.font(.system(size: 14)).padding(28) }.frame(width: 700, height: 680)
    }
}

#if !TESTING
@main struct DeckLabApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        WindowGroup("Deck Lab") { ContentView() }
            .defaultSize(width: 1460, height: 960)
            .commands { CommandGroup(replacing: .newItem) {} }
    }
}
#endif
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
