import SwiftUI
@main struct RecoveryTests {
 @MainActor static func main() throws {
 let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:folder)}
 let m=Model(storeDirectory:folder)
 m.setUnassigned("Test",count:3);precondition(m.inventory.owned("Test")==3)
 m.recover();precondition(m.inventory.owned("Test")==0)
 m.recover(redo:true);precondition(m.inventory.owned("Test")==3)
 var a=AdvancedData();a.locations=[CardLocation(holdingID:"unspecified:test",label:"Binder",count:2)];m.saveAdvanced(a)
 let saved=m.fullBackup
 m.setUnassigned("Test",count:1);precondition(locationIssues(m.advanced,inventory:m.inventory).count==1)
 try m.restoreBackup(saved);precondition(m.inventory.owned("Test")==3 && m.advanced.locations.count==1)
 let b=PersonalBuild(name:"Delete fixture",format:.tcg,cards:[]);m.putBuild(b);var w=m.workshop;w.builds=[];m.saveWorkshop(w);m.recover();precondition(m.workshop.builds.count==1)
 let reloaded=Model(storeDirectory:folder);precondition(reloaded.workshop.builds.count==1 && reloaded.recovery.undo.count>0 && reloaded.advanced.locations.count==1)
 for n in 0..<25{reloaded.setUnassigned("Test",count:n)}
 precondition(reloaded.recovery.undo.count==20 && reloaded.recovery.backups.count==1)
 let files=try FileManager.default.contentsOfDirectory(atPath:folder.path).filter{$0.hasPrefix("recovery-") && $0 != "recovery-index.json"};precondition(files.count<=21)
 let html=deckHTML(b,images:[:],labels:[:]);precondition(html.contains("Delete fixture"))
 let png=try deckPNG(b,images:[:],labels:[:]);precondition(png.prefix(4)==Data([137,80,78,71]))
 print("Recovery tests passed: undo/redo, full restore, deletion recovery, restart persistence, rotation cleanup, HTML/PNG export.")
 }
}
