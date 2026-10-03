import Foundation
@main struct Tests {
    static func main() async throws {
        func check(_ v: @autoclosure () -> Bool, _ m:String) { if !v() { fatalError(m) } }
        let product = TCGProduct(id:1,name:"Card A",rarity:"Rare",set:"Test",number:"T-001",indicativeLow:0.01)
        let v = CardVariant(cardName:"Card A",product:product,condition:"Near Mint",edition:"1st Edition")
        var inventory = Inventory(); inventory.variants[v.id] = v; inventory.quantities[v.id] = 2; inventory.targets[v.cardKey] = v.id
        let quote = PriceQuote(variantID:v.id,cents:125,shippingCents:99,seller:"Test",listingID:"1",quantity:4,checked:Date(),condition:v.condition,edition:v.edition,verified:true)
        let card = Card(id:"a",name:"Card A",rarity:"")
        var stats = CardStats(card:card); stats.main=8; stats.included=3
        let t = buildTotals(stats:[stats],sample:3,inventory:inventory,quotes:[v.id:quote],roundUp:false)
        check(t.targetCopies==3 && t.coveredCopies==2 && t.missingCopies==1,"Rounded average and shared ownership")
        check(t.targetCents==375 && t.builtCents==250 && t.missingCents==125,"Printing-specific valuation and missing cost")
        inventory.unassigned[v.cardKey]=5
        let u = buildTotals(stats:[stats],sample:3,inventory:inventory,quotes:[:],roundUp:false)
        check(u.coveredCopies==3 && u.missingCopies==0,"Ownership capped to target")
        check(u.unpricedBuiltCopies==3 && u.unpricedCollectionCopies==7 && u.builtCents==0,"Unknown costs stay unpriced")
        check(collectionKey("Ash Blossom & Joyous Spring")==collectionKey("ash blossom & joyous spring"),"Cross-provider collection identity")
        check(TCG.matches("Ash Blossom & Joyous Spring (Platinum Secret Rare)",card:"Ash Blossom & Joyous Spring"),"Printing suffix matched")
        check(!TCG.matches("Dark Magician Girl",card:"Dark Magician"),"Wrong card excluded")
        let good: [String:Any] = ["productId":1,"verifiedSeller":true,"condition":"Near Mint","printing":"1st Edition","language":"English","quantity":1,"price":1.25]
        check(TCG.eligible(good,variant:v),"Eligible quote")
        var bad=good;bad["verifiedSeller"]=false;check(!TCG.eligible(bad,variant:v),"Nonverified listing excluded")
        bad=good;bad["condition"]="Lightly Played";check(!TCG.eligible(bad,variant:v),"Wrong condition excluded")
        bad=good;bad["quantity"]=0;check(!TCG.eligible(bad,variant:v),"Out of stock excluded")
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:dir) }
        let store=try LocalStore(directory:dir);try store.write(inventory,name:"inventory.json")
        let restored=try store.read("inventory.json",as:Inventory.self)!
        check(restored.owned("Card A")==7 && restored.target("Card A")?.condition=="Near Mint","Collection and printing persistence")
        print("Collection and valuation checks passed.")
        if CommandLine.arguments.contains("--live") {
            let products=try await TCG.shared.search("Banishment of the Darklords")
            check(products.count>=3 && products.allSatisfy { TCG.matches($0.name,card:"Banishment of the Darklords") },"Live product matches")
            let p=products.first { $0.id==679024 }!
            let skus=try await TCG.shared.skus(p)
            check(skus.contains { $0.condition=="Near Mint" && $0.edition=="1st Edition" },"Live condition and edition availability")
            let variant=CardVariant(cardName:"Banishment of the Darklords",product:p,condition:"Near Mint",edition:"1st Edition")
            let live=try await TCG.shared.quote(variant)
            check(live.verified && live.cents>0 && live.quantity>0,"Live verified seller quote")
            print("TCGplayer live: \(products.count) printings; \(skus.count) condition/edition choices; verified NM low $\(String(format:"%.2f",Double(live.cents)/100)) from \(live.seller).")
        }
    }
}
