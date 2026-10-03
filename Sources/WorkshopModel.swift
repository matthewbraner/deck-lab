import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct WorkshopBackup: Codable {
    var version=1
    var saved=Date()
    var workshop:WorkshopData
    var inventory:Inventory
    var quotes:[String:PriceQuote]
    var roles:[String:CardRole]
    var lab:LabData? = nil
    var hidden:[String]
    var advanced:AdvancedData? = nil
}
@MainActor extension Model {
    func saveWorkshop(_ value:WorkshopData) {
        guard let store else { storageError="Local storage unavailable.";return }
        do { try captureRecovery("Builds and saved searches");try store.write(value,name:"workshop.json");workshop=value;storageError=nil }
        catch { storageError=error.localizedDescription }
    }
    func putBuild(_ value:PersonalBuild) {
        var next=workshop;var build=value;build.updated=Date();build.cards=mergeBuildCards(build.cards.filter { $0.count>0 })
        if let i=next.builds.firstIndex(where:{$0.id==build.id}) { let old=next.builds[i];if old.cards != build.cards || old.format != build.format { suppressRecovery=true;checkpoint(old,note:"Before edit");suppressRecovery=false };next.builds[i]=build } else { next.builds.append(build) };saveWorkshop(next)
    }
    func favorite(_ type:DeckType) {
        var next=workshop;let key=normalizedCardName(type.name)
        if next.favorites.contains(key) { next.favorites.remove(key) } else { next.favorites.insert(key) };saveWorkshop(next)
    }
    func saveSearch(_ name:String) {
        guard let type else { return };var next=workshop
        next.searches.append(SavedSearch(name:name.isEmpty ? "\(format.rawValue) · \(type.name)" : name,format:format,type:type,start:start,end:end,tier:eventTier,filters:filters));saveWorkshop(next)
    }
    func applySearch(_ search:SavedSearch) {
        cancel();format=search.format;eventTier=search.tier;start=search.start;end=search.end;filters=search.filters
        types=[search.type];selectedType=search.type.id;load()
        Task { await catalogue() }
    }
    var collectionNames:[String:String] {
        var names=inventory.displayNames ?? [:]
        for info in cardIndex.values { names[collectionKey(info.name)]=info.name }
        for variant in inventory.variants.values { names[variant.cardKey]=variant.cardName }
        return names
    }
    func importCollection(_ incoming:Inventory,replace:Bool) {
        if replace { saveInventory(incoming);return }
        for (id,v) in incoming.variants { if let old=inventory.variants[id],old.cardKey != v.cardKey { storageError="Import uses an existing product ID for a different card. Correct that row before importing.";return } }
        var next=inventory
        for (key,count) in incoming.unassigned { next.unassigned[key,default:0]+=count }
        for (id,variant) in incoming.variants { next.variants[id]=variant;next.quantities[id,default:0]+=incoming.quantities[id] ?? 0 }
        next.displayNames=(next.displayNames ?? [:]).merging(incoming.displayNames ?? [:]) { _,new in new }
        saveInventory(next)
    }
    func refreshRules() async {
        do {
            let db=try await YGO.shared.cardDatabase(force:true);cardIndex=db.index;cardDataDate=db.fetched
            let p=try await YGO.shared.cardDatabase(genesys:true,force:true);genesysIndex=p.index;cardDataError=nil
            let md=try await MDM.rules();try store?.write(md,name:"md-rules.json");masterDuelRules=md
        } catch { cardDataError=error.localizedDescription }
    }
}
@MainActor func saveFile(_ text:String,name:String) throws {
    let panel=NSSavePanel();panel.nameFieldStringValue=name;panel.canCreateDirectories=true
    if panel.runModal() == .OK,let url=panel.url { try text.write(to:url,atomically:true,encoding:.utf8) }
}
@MainActor func openTextFile() throws -> (String,String)? {
    let panel=NSOpenPanel();panel.canChooseDirectories=false;panel.allowsMultipleSelection=false
    guard panel.runModal() == .OK,let url=panel.url else { return nil }
    let data=try Data(contentsOf:url);guard data.count<20_000_000,let text=String(data:data,encoding:.utf8) else { throw DataError.message("Choose a UTF-8 text file smaller than 20 MB.") };return (text,url.deletingPathExtension().lastPathComponent)
}
