import SwiftUI
struct RecoveryPoint:Codable,Identifiable { var id=UUID().uuidString;var date=Date();var reason:String;var file:String { "recovery-\(id).json" } }
struct RecoveryIndex:Codable { var undo:[RecoveryPoint]=[];var redo:[RecoveryPoint]=[];var backups:[RecoveryPoint]=[] }
@MainActor extension Model {
    var fullBackup:WorkshopBackup { WorkshopBackup(workshop:workshop,inventory:inventory,quotes:quotes,roles:roles,lab:lab,hidden:Array(hiddenTypes),advanced:advanced) }
    func captureRecovery(_ reason:String) throws {
        guard !suppressRecovery,let store else{return}
        let point=RecoveryPoint(reason:reason);try store.write(fullBackup,name:point.file)
        var next=recovery;next.undo.append(point);next.undo=Array(next.undo.suffix(20));next.redo=[]
        if next.backups.last.map({!Calendar.current.isDateInToday($0.date)}) ?? true { next.backups.append(point);next.backups=Array(next.backups.suffix(14)) }
        try commitRecovery(next)
    }
    func commitRecovery(_ next:RecoveryIndex) throws {
        guard let store else{return};try store.write(next,name:"recovery-index.json")
        let keep=Set((next.undo+next.redo+next.backups).map(\.file))
        for p in recovery.undo+recovery.redo+recovery.backups where !keep.contains(p.file) { try? FileManager.default.removeItem(at:store.directory.appendingPathComponent(p.file)) }
        recovery=next
    }
    func writeBackup(_ b:WorkshopBackup) throws {
        guard let store else{throw DataError.message("Storage unavailable")}
        try store.write(b.workshop,name:"workshop.json");try store.write(b.inventory,name:"inventory.json");try store.write(b.quotes,name:"tcg-quotes.json");try store.write(b.roles,name:"classifications.json");try store.write(b.hidden,name:"hidden-deck-types.json");try store.write(b.lab ?? LabData(),name:"lab.json");try store.write(b.advanced ?? AdvancedData(),name:"advanced.json")
        workshop=b.workshop;inventory=b.inventory;quotes=b.quotes;roles=b.roles;hiddenTypes=Set(b.hidden);lab=b.lab ?? LabData();advanced=b.advanced ?? AdvancedData()
    }
    func restoreBackup(_ b:WorkshopBackup) throws {
        try validateBackup(b);let old=fullBackup;try captureRecovery("Before restore")
        do { try writeBackup(b) } catch { try? writeBackup(old);throw error }
    }
    func recover(redo:Bool=false) {
        guard let store,let point=(redo ? recovery.redo : recovery.undo).last else{return}
        do {
            guard let b=try store.read(point.file,as:WorkshopBackup.self) else{throw DataError.message("Recovery file missing")};try validateBackup(b)
            let old=fullBackup;let current=RecoveryPoint(reason:point.reason);try store.write(old,name:current.file)
            var next=recovery
            if redo {next.redo.removeLast();next.undo.append(current)} else {next.undo.removeLast();next.redo.append(current)}
            do {try writeBackup(b);try commitRecovery(next)} catch {try? writeBackup(old);throw error}
        } catch {storageError=error.localizedDescription}
    }
    func saveAdvanced(_ value:AdvancedData) {
        do {try captureRecovery("Groups and locations");try store?.write(value,name:"advanced.json");advanced=value} catch {storageError=error.localizedDescription}
    }
}
struct RecoveryView:View {
    @ObservedObject var model:Model
    var body:some View { VStack(alignment:.leading,spacing:16) {
        Text("Recover local edits, imports, and deleted records").font(.headline)
        Text("Keeps the last 20 changes and 14 daily snapshots. Recovery includes builds, collection, groups, locations, searches, and lab records. Export a backup for protection outside this Mac.")
        HStack { Button("Undo last change") {model.recover()}.disabled(model.recovery.undo.isEmpty);Button("Redo") {model.recover(redo:true)}.disabled(model.recovery.redo.isEmpty);Button("Create snapshot") {do {try model.captureRecovery("Manual snapshot")}catch{model.storageError=error.localizedDescription}} }
        List(Array(Dictionary(grouping:model.recovery.backups+model.recovery.undo,by: \.id).compactMap{$0.value.first}).sorted{$0.date>$1.date}) { p in HStack {Text(p.reason);Text(p.date,style:.date);Text(p.date,style:.time);Spacer();Button("Restore") {do{if let b=try model.store?.read(p.file,as:WorkshopBackup.self){try model.restoreBackup(b)}}catch{model.storageError=error.localizedDescription}}} }
    } }
}
