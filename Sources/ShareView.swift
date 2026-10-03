import SwiftUI
import AppKit
struct ShareDeckView:View {
 @ObservedObject var model:Model
 @State var selected=""
 @State var prices=false
 @State var busy=false
 @State var notice=""
 var body:some View{VStack(alignment:.leading,spacing:16){
 Text("Share a deck").font(.headline)
 Picker("Build",selection:$selected){Text("Choose").tag("");ForEach(model.workshop.builds){Text($0.name).tag($0.id)}}.disabled(busy)
 Toggle("Include selected-printing prices",isOn:$prices).disabled(busy)
 Text("Export a card-art PNG or a self-contained HTML deck list you can open and print. Prices use cached verified seller quotes for your selected printings, excluding shipping and tax. Artwork may differ from the selected printing.")
 HStack{Button("Export image (PNG)"){export(png:true)};Button("Export printable list (HTML)"){export(png:false)}}.disabled(selected.isEmpty || busy)
 if busy{ProgressView("Preparing artwork…")};Text(notice).textSelection(.enabled)
 }}
 func export(png:Bool){guard let b=model.workshop.builds.first(where:{$0.id==selected})else{return};guard b.cards.count<=200 else{notice="Export supports up to 200 distinct entries.";return};busy=true
 Task {var images:[String:Data]=[:];var missing=0
 for row in b.cards{if let info=model.info(row.card),let data=try? await ArtworkCache.shared.image(info.id,source:info.imageURL){images[row.id]=data}else{missing+=1}}
 do{let labels=Dictionary(uniqueKeysWithValues:b.cards.map{row -> (String,String) in
 guard prices,let v=model.inventory.target(row.card.name),let q=model.quotes[v.id],q.verified else{return(row.id,prices ? "Price unavailable" : "")};return(row.id,"\(dollars(q.cents)) each · \(v.label) · checked \(Model.day(q.checked))")})
 let data:Data
 if png {data=try deckPNG(b,images:images,labels:labels)} else{data=Data(deckHTML(b,images:images,labels:labels).utf8)}
 let panel=NSSavePanel();panel.nameFieldStringValue=b.name+(png ? ".png" : ".html");if panel.runModal() == .OK,let url=panel.url{try data.write(to:url,options:.atomic);notice="Exported \(url.lastPathComponent). \(missing) unavailable images use text placeholders."}
 }catch{notice=error.localizedDescription};busy=false}
 }
}
func deckHTML(_ b:PersonalBuild,images:[String:Data],labels:[String:String])->String {
 var html="<!doctype html><html><head><meta charset='utf-8'><title>\(htmlEscape(b.name))</title><style>body{font:14px system-ui;margin:32px;color:#142030}section{display:grid;grid-template-columns:repeat(5,1fr);gap:12px}article{break-inside:avoid}img{width:100%;max-height:230px;object-fit:contain}small{display:block}h2{break-after:avoid}@media print{body{margin:8mm}section{grid-template-columns:repeat(4,1fr)}} </style></head><body><h1>\(htmlEscape(b.name))</h1><p>\(htmlEscape(b.format.rawValue)) · \(b.deck.total) cards</p>"
 for zone in BuildZone.allCases {let rows=b.cards.filter{$0.zone==zone};html+="<h2>\(zone.rawValue) · \(rows.reduce(0){$0+$1.count})</h2><section>";for row in rows {html+="<article>";if let data=images[row.id]{html+="<img alt='\(htmlEscape(row.card.name))' src='data:image/jpeg;base64,\(data.base64EncodedString())'>"};html+="<b>\(row.count) × \(htmlEscape(row.card.name))</b><small>\(htmlEscape(labels[row.id] ?? ""))</small></article>"};html+="</section>"}
 return html+"<p>Deck Lab · YGOPRODeck artwork. Cached verified prices exclude shipping/tax; artwork may differ from printing.</p></body></html>"
}
@MainActor func deckPNG(_ b:PersonalBuild,images:[String:Data],labels:[String:String]) throws ->Data {
 let width=1600,columns=8,cell=194,rowHeight=355
 let zones=BuildZone.allCases.filter{z in b.cards.contains{$0.zone==z}}
 let height=150+zones.reduce(0){sum,z in sum+60+((b.cards.filter{$0.zone==z}.count+columns-1)/columns)*rowHeight}+70
 guard let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:width,pixelsHigh:height,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),let context=NSGraphicsContext(bitmapImageRep:rep)else{throw DataError.message("Cannot create image")}
 NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=context;defer{NSGraphicsContext.restoreGraphicsState()}
 NSColor.white.setFill();NSRect(x:0,y:0,width:width,height:height).fill()
 func text(_ s:String,_ x:Int,_ top:Int,_ w:Int,_ h:Int,_ size:CGFloat){(s as NSString).draw(in:NSRect(x:x,y:height-top-h,width:w,height:h),withAttributes:[.font:NSFont.systemFont(ofSize:size),.foregroundColor:NSColor.black])}
 text(b.name,24,18,1550,55,32);text("\(b.format.rawValue) · \(b.deck.total) cards",24,78,1550,35,20)
 var top=135
 for zone in zones {let rows=b.cards.filter{$0.zone==zone};text("\(zone.rawValue) · \(rows.reduce(0){$0+$1.count})",24,top,1550,40,24);top+=55
 for (i,row) in rows.enumerated(){let x=24+(i%columns)*cell,y=top+(i/columns)*rowHeight
 if let data=images[row.id],let image=NSImage(data:data){image.draw(in:NSRect(x:x,y:height-y-255,width:178,height:255))}
 text("\(row.count) × \(row.card.name)",x,y+260,180,44,14);text(labels[row.id] ?? "",x,y+305,180,48,10)
 };top+=((rows.count+columns-1)/columns)*rowHeight}
 text("Deck Lab · YGOPRODeck artwork · Cached verified prices exclude shipping/tax. Artwork may differ from printing.",24,top+10,1550,40,15)
 guard let data=rep.representation(using:.png,properties:[:])else{throw DataError.message("Cannot encode image")};return data
}
