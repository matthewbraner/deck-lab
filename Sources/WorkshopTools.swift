import SwiftUI

struct ImportBackupView:View {
    @ObservedObject var model:Model
    @State private var text=""
    @State private var mode="Collection"
    @State private var format=GameFormat.tcg
    @State private var replace=false
    @State private var preview:Inventory?
    @State private var deck:PersonalBuild?
    @State private var backup:WorkshopBackup?
    @State private var notice=""
    @State private var filename="Imported deck"
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Picker("Import",selection:$mode) { Text("Collection CSV / pasted list").tag("Collection");Text("YDK deck").tag("YDK");Text("Deck Lab backup").tag("Backup") }
                Button("Open file…") { do { if let (value,name)=try openTextFile() { text=value;filename=name;clearPreview();notice="File loaded. Preview before applying." } } catch { notice=error.localizedDescription } }
            }
            Text(mode == "Collection" ? "CSV: name,quantity (optional product_id,rarity,set,number,condition,edition). Or paste lines such as 3 Ash Blossom & Joyous Spring. Name-only entries remain unpriced until assigned a printing." : mode == "YDK" ? "YDK uses card passcodes under #main, #extra, and !side. Choose the build format below." : "Backups include saved builds, searches, favorites, hidden types, classifications, collection, cached prices, probability setups, match logs, side plans, revisions, and trends. Restoring replaces those local records after preview.").font(.caption).foregroundStyle(.secondary)
            TextEditor(text:$text).font(.system(.body,design:.monospaced)).frame(minHeight:130,maxHeight:200).border(.secondary.opacity(0.3)).onChange(of:text) { _,_ in clearPreview() }
            HStack {
                if mode == "YDK" { Picker("Format",selection:$format) { ForEach(GameFormat.allCases,id:\.self) { Text($0.rawValue).tag($0) } }.frame(width:200) }
                if mode == "Collection" { Toggle("Replace collection instead of adding",isOn:$replace) }
                Button("Preview import") { inspect() }.buttonStyle(.borderedProminent)
                Spacer()
                Button("Export collection CSV") { do { try saveFile(collectionCSV(model.inventory,names:model.collectionNames),name:"collection.csv") } catch { notice=error.localizedDescription } }
                Button("Export full backup") { exportBackup() }
            }
            if !notice.isEmpty { Text(notice).foregroundStyle(.orange).textSelection(.enabled) }
            if let preview {
                let qty=preview.unassigned.values.reduce(0,+)+preview.quantities.values.reduce(0,+)
                Text("Ready: \(qty) copies · \(preview.unassigned.count) unspecified card entries · \(preview.variants.count) printings. \(replace ? "Existing collection quantities will be replaced." : "Quantities will be added to existing holdings.")").bold()
                ScrollView { VStack(alignment:.leading) {
                    ForEach(preview.unassigned.keys.sorted(),id:\.self) { key in Text("\(preview.unassigned[key]!)× \(preview.displayNames?[key] ?? key)") }
                    ForEach(preview.variants.values.sorted(by:{$0.id<$1.id})) { v in Text("\(preview.quantities[v.id] ?? 0)× \(v.cardName) · \(v.label)") }
                }.frame(maxWidth:.infinity,alignment:.leading) }.frame(maxHeight:130)
                Button(replace ? "Replace collection with preview" : "Add preview to collection") { model.importCollection(preview,replace:replace);if model.storageError==nil { clearPreview();text="";notice="Collection imported." } }
            }
            if let deck {
                Text("\(deck.name): \(deck.deck.total) cards · \(deck.format.rawValue)").bold()
                Button("Save imported build") { model.putBuild(deck);if model.storageError==nil { clearPreview();text="";notice="Build saved. Open Builds to edit and check legality." } }
            }
            if let backup {
                Text("Backup from \(backup.saved.formatted()) · \(backup.workshop.builds.count) builds · \(backup.workshop.searches.count) searches · \(backup.inventory.ownedTotal) owned copies").bold()
                Button("Restore this backup and replace local records") { restore(backup) }
            }
            Spacer()
        }.onChange(of:mode) { _,_ in clearPreview() }.onChange(of:format) { _,_ in clearPreview() }
    }
    func clearPreview() { preview=nil;deck=nil;backup=nil }
    func inspect() {
        clearPreview()
        do {
            switch mode {
            case "Collection":preview=try parseCollection(text,cards:model.cardIndex)
            case "YDK":var b=try parseYDK(text,cards:model.cardIndex,format:format);b.name=filename;deck=b
            default:
                let b=try JSONDecoder().decode(WorkshopBackup.self,from:Data(text.utf8))
                try validateBackup(b);backup=b
            };notice="Preview ready. No changes have been applied."
        } catch { notice=error.localizedDescription }
    }
    func exportBackup() {
        do {
            let b=model.fullBackup
            let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
            try saveFile(String(decoding:encoder.encode(b),as:UTF8.self),name:"deck-lab-backup.json")
        } catch { notice=error.localizedDescription }
    }
    func restore(_ b:WorkshopBackup) {
        do {try model.restoreBackup(b);clearPreview();text="";notice="Backup restored. Undo is available in Recovery."}
        catch {notice=error.localizedDescription}
    }
}
extension Inventory { var ownedTotal:Int { quantities.values.reduce(0,+)+unassigned.values.reduce(0,+) } }
func validateBackup(_ b:WorkshopBackup) throws {
    if let lab=b.lab { try validateLab(lab) }
    if let a=b.advanced {
        guard Set(a.locations.map(\.id)).count==a.locations.count,Set(a.substitutions.map(\.id)).count==a.substitutions.count,a.locations.allSatisfy({$0.count>0 && $0.count<=1_000_000 && !$0.label.isEmpty}),a.substitutions.allSatisfy({!$0.name.isEmpty && $0.cards.count>=2}) else {throw DataError.message("Invalid locations or substitution groups in backup.")}
    }
    guard b.version==1,Set(b.workshop.builds.map(\.id)).count==b.workshop.builds.count,
          Set(b.workshop.searches.map(\.id)).count==b.workshop.searches.count,
          b.inventory.quantities.values.allSatisfy({$0>=0 && $0<=1_000_000}),b.inventory.unassigned.values.allSatisfy({$0>=0 && $0<=1_000_000}),
          b.workshop.builds.allSatisfy({$0.pointCap>=0 && $0.cards.allSatisfy({$0.count>0 && $0.count<=9999})}) else { throw DataError.message("Backup has an unsupported version, duplicate IDs, or invalid quantities.") }
    for (id,v) in b.inventory.variants where id != v.id { throw DataError.message("Backup contains an invalid printing ID.") }
    for id in b.inventory.quantities.keys where b.inventory.variants[id]==nil { throw DataError.message("Backup contains a quantity with no printing.") }
}
