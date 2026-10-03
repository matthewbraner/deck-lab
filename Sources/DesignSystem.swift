import SwiftUI

enum LabStyle {
    static let accent = Color(nsColor:NSColor(name:nil){$0.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua ? NSColor(red:0.78,green:0.92,blue:0.49,alpha:1) : NSColor(red:0.28,green:0.39,blue:0.10,alpha:1)})
    static let action = Color(red:0.31,green:0.43,blue:0.14)
    static let violet = Color(red:0.57,green:0.62,blue:0.82)
    static let canvas = Color(nsColor:NSColor(name:nil){$0.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua ? NSColor(white:0.09,alpha:1) : NSColor(white:0.965,alpha:1)})
    static let surface = Color(nsColor:NSColor(name:nil){$0.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua ? NSColor(white:0.125,alpha:1) : .white})
    static let sidebar = Color(nsColor:NSColor(name:nil){$0.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua ? NSColor(white:0.065,alpha:1) : NSColor(white:0.925,alpha:1)})
}
struct SurfaceModifier:ViewModifier {
    @Environment(\.colorSchemeContrast) var contrast
    func body(content:Content)->some View {content.background(LabStyle.surface,in:RoundedRectangle(cornerRadius:3)).overlay(RoundedRectangle(cornerRadius:3).strokeBorder(Color.primary.opacity(contrast == .increased ? 0.5 : 0.08),lineWidth:1))}
}
extension View {func labSurface()->some View{modifier(SurfaceModifier())}}
struct LabSearch:View {
    var title:String
    @Binding var text:String
    var body:some View {HStack(spacing:9){Image(systemName:"magnifyingglass").foregroundStyle(.secondary);TextField(title,text:$text).textFieldStyle(.plain).accessibilityLabel(title);if !text.isEmpty{Button{ text="" }label:{Image(systemName:"xmark.circle.fill")}.buttonStyle(.plain).accessibilityLabel("Clear \(title)").help("Clear search")}}.padding(.horizontal,12).frame(height:38).background(.primary.opacity(0.045),in:RoundedRectangle(cornerRadius:3)).overlay(RoundedRectangle(cornerRadius:3).strokeBorder(.primary.opacity(0.10)))}
}
struct LabBadge:View {
    var text:String
    var color:Color = LabStyle.accent
    var body:some View {Text(text).font(.system(size:11,weight:.semibold)).padding(.horizontal,9).padding(.vertical,5).background(color.opacity(0.13),in:Capsule()).foregroundStyle(.primary).accessibilityLabel(text)}
}
struct LabMetric:View {
    var title:String
    var value:String
    var note:String
    var symbol:String="chart.bar"
    var color:Color=LabStyle.accent
    var body:some View {VStack(alignment:.leading,spacing:9){HStack{Text(title).font(.system(size:12,weight:.medium)).foregroundStyle(.secondary);Spacer();Image(systemName:symbol).foregroundStyle(color)};Text(value).font(.system(size:29,weight:.semibold,design:.rounded)).monospacedDigit();Text(note).font(.system(size:11)).foregroundStyle(.secondary).lineLimit(2)}.padding(16).frame(maxWidth:.infinity,alignment:.leading).labSurface().accessibilityElement(children:.combine)}
}
struct LabTool:Identifiable {
    var id:String
    var title:String
    var symbol:String
    var subtitle:String
    var group:String
    static let groups=["DISCOVER","BUILD & TEST","COLLECTION","WORKSPACE"]
    static let all:[LabTool]=[
        .init(id:"Explorer",title:"Deck explorer",symbol:"square.grid.2x2",subtitle:"Discover lists. Find your next deck.",group:"DISCOVER"),
        .init(id:"Card search",title:"Card library",symbol:"rectangle.on.rectangle",subtitle:"Find the right card by name, effect, or stats.",group:"DISCOVER"),
        .init(id:"What can I build?",title:"Build recommendations",symbol:"sparkles",subtitle:"Find decks within reach of your collection.",group:"DISCOVER"),
        .init(id:"Dataset trends",title:"Meta trends",symbol:"chart.line.uptrend.xyaxis",subtitle:"Track changes across saved datasets.",group:"DISCOVER"),
        .init(id:"Builds",title:"My decks",symbol:"rectangle.stack",subtitle:"Your ideas, your lists, your next build.",group:"BUILD & TEST"),
        .init(id:"Hands & probability",title:"Test hands & combos",symbol:"hand.draw",subtitle:"Draw hands, define buckets, and test your combos.",group:"BUILD & TEST"),
        .init(id:"Advanced probabilities",title:"Probability studio",symbol:"function",subtitle:"Compare builds, calculate conditional odds, and optimize ratios.",group:"BUILD & TEST"),
        .init(id:"Compare",title:"Compare decks",symbol:"rectangle.split.2x1",subtitle:"See what changes between two saved builds.",group:"BUILD & TEST"),
        .init(id:"Core & flex",title:"Core & flex",symbol:"square.stack.3d.up",subtitle:"Identify common cards and flexible packages.",group:"BUILD & TEST"),
        .init(id:"Substitutions",title:"Substitutions",symbol:"arrow.triangle.swap",subtitle:"Create groups of alternatives and try cards you own.",group:"BUILD & TEST"),
        .init(id:"Side plans",title:"Sideboard plans",symbol:"arrow.left.arrow.right",subtitle:"Prepare your swaps before the match.",group:"BUILD & TEST"),
        .init(id:"Match log",title:"Match journal",symbol:"book.closed",subtitle:"Record results and learn from each match.",group:"BUILD & TEST"),
        .init(id:"Collection browser",title:"My collection",symbol:"tray.2",subtitle:"Every printing, condition, and owned copy in one place.",group:"COLLECTION"),
        .init(id:"Shopping list",title:"Shopping list",symbol:"cart",subtitle:"Know which cards you need and what they cost.",group:"COLLECTION"),
        .init(id:"Price history & alerts",title:"Prices & alerts",symbol:"chart.xyaxis.line",subtitle:"Follow your selected printings and price targets.",group:"COLLECTION"),
        .init(id:"Collection locations",title:"Storage locations",symbol:"shippingbox",subtitle:"Find your cards in binders, boxes, and assembled decks.",group:"COLLECTION"),
        .init(id:"Share deck",title:"Export & share",symbol:"square.and.arrow.up",subtitle:"Create a card-art image or a printable deck list.",group:"WORKSPACE"),
        .init(id:"Build history",title:"Deck history",symbol:"clock.arrow.circlepath",subtitle:"Revisit saved versions of your builds.",group:"WORKSPACE"),
        .init(id:"Saved searches",title:"Saved searches",symbol:"bookmark",subtitle:"Return to your favorite explorer filters.",group:"WORKSPACE"),
        .init(id:"Import & backup",title:"Import & backup",symbol:"square.and.arrow.down",subtitle:"Bring in lists and keep a portable copy of your data.",group:"WORKSPACE"),
        .init(id:"Recovery",title:"Undo & recovery",symbol:"arrow.uturn.backward",subtitle:"Restore a recent edit or a saved snapshot.",group:"WORKSPACE")]
    static func find(_ id:String)->LabTool{all.first{$0.id==id} ?? all[0]}
}
struct LabNavigation:View {
    @Binding var selection:String
    @Binding var query:String
    var alerts:Int
    var jump:()->Void
    let destinations=[("Explorer","Explore","square.grid.2x2"),("Builds","Decks","rectangle.stack"),("Hands & probability","Test","function"),("Collection browser","Collect","tray.2"),("Import & backup","Files","archivebox")]
    var section:Int {
        switch selection {
        case "Explorer","Card search","What can I build?","Dataset trends","Saved searches":return 0
        case "Builds","Compare","Core & flex","Substitutions","Side plans","Match log","Build history","Share deck":return 1
        case "Hands & probability","Advanced probabilities":return 2
        case "Collection browser","Shopping list","Price history & alerts","Collection locations":return 3
        default:return 4
        }
    }
    var body:some View {
        VStack(spacing:8) {
            ZStack {RoundedRectangle(cornerRadius:12).fill(LabStyle.accent);Image(systemName:"rectangle.stack.fill").font(.system(size:23,weight:.semibold)).foregroundStyle(LabStyle.sidebar)}.frame(width:42,height:42).padding(.top,22).padding(.bottom,25).accessibilityLabel("Deck Lab")
            ForEach(destinations.indices,id:\.self) {i in
                Button {selection=destinations[i].0} label:{
                    VStack(spacing:7){Image(systemName:destinations[i].2).font(.system(size:20,weight:.medium));Text(destinations[i].1).font(.system(size:10,weight:.medium))}
                        .frame(width:64,height:64).foregroundStyle(section==i ? LabStyle.accent : .secondary)
                        .background(section==i ? LabStyle.accent.opacity(0.10) : .clear,in:RoundedRectangle(cornerRadius:10))
                }.buttonStyle(.plain).help(destinations[i].1).accessibilityLabel(destinations[i].1).accessibilityValue(section==i ? "Selected" : "")
            }
            Spacer()
            Button(action:jump){VStack(spacing:7){Image(systemName:"magnifyingglass").font(.system(size:19));Text("⌘ K").font(.system(size:10,design:.monospaced))}.frame(width:60,height:60)}.buttonStyle(.plain).foregroundStyle(.secondary).help("Find any tool (Command K)").accessibilityLabel("Find any tool")
            Circle().fill(alerts>0 ? .orange : LabStyle.accent).frame(width:6,height:6).padding(.bottom,22).help(alerts>0 ? "Price alerts available" : "Local workspace")
        }.frame(width:80).background(LabStyle.sidebar)
    }
}
struct WorkspaceTabs:View {
    @Binding var selection:String
    var ids:[String]
    var body:some View {
        ScrollView(.horizontal,showsIndicators:false) {
            HStack(spacing:24) {ForEach(ids,id:\.self){id in Button{selection=id}label:{Text(LabTool.find(id).title).font(.system(size:12,weight:selection==id ? .semibold : .regular)).foregroundStyle(selection==id ? .primary : .secondary).padding(.vertical,16).overlay(alignment:.bottom){Rectangle().fill(selection==id ? LabStyle.accent : .clear).frame(height:2)}}.buttonStyle(.plain).accessibilityValue(selection==id ? "Selected" : "")}}
        }.padding(.horizontal,24).background(LabStyle.sidebar.opacity(0.5)).overlay(alignment:.bottom){Divider()}
    }
}
struct JumpPalette:View {
    @Binding var selection:String
    @Environment(\.dismiss) var dismiss
    @State var query=""
    @FocusState var focused:Bool
    var results:[LabTool]{LabTool.all.filter{query.isEmpty || ($0.title+" "+$0.subtitle).localizedCaseInsensitiveContains(query)}}
    var body:some View{VStack(alignment:.leading,spacing:16){HStack{Text("Where would you like to go?").font(.title3.bold());Spacer();Button("Close"){dismiss()}.keyboardShortcut(.cancelAction)};LabSearch(title:"Search tools, decks, collection…",text:$query).focused($focused).onSubmit{if let first=results.first{selection=first.id;dismiss()}};ScrollView{LazyVStack(spacing:6){ForEach(results){tool in Button{selection=tool.id;dismiss()}label:{HStack(spacing:14){Image(systemName:tool.symbol).foregroundStyle(LabStyle.accent).frame(width:28);VStack(alignment:.leading,spacing:3){Text(tool.title).font(.headline);Text(tool.subtitle).font(.caption).foregroundStyle(.secondary)};Spacer();Image(systemName:"arrow.up.left").foregroundStyle(.secondary)}.padding(12).frame(maxWidth:.infinity,alignment:.leading).labSurface()}.buttonStyle(.plain)}}};if results.isEmpty{ContentUnavailableView.search(text:query)}}.padding(24).frame(width:580,height:550).background(LabStyle.canvas).onAppear{focused=true}}
}

struct LabQuantity:View {
    var title:String
    @Binding var value:Int
    var maximum=99
    var body:some View {
        HStack(spacing:5) {
            Button {value=max(0,value-1)} label:{Image(systemName:"minus").frame(width:20,height:24)}.disabled(value<=0).accessibilityLabel("Remove one \(title)").help("Remove one copy")
            TextField("Copies",value:Binding(get:{value},set:{value=max(0,min(maximum,$0))}),format:.number).multilineTextAlignment(.center).monospacedDigit().frame(width:40).accessibilityLabel("\(title) quantity")
            Button {value=min(maximum,value+1)} label:{Image(systemName:"plus").frame(width:20,height:24)}.disabled(value>=maximum).accessibilityLabel("Add one \(title)").help("Add one copy")
        }.fixedSize().accessibilityElement(children:.contain)
    }
}

struct ArchiveTabs:View {
    @Binding var selection:String
    var tabs:[String]
    var values:[String]
    var body:some View {HStack(spacing:24){ForEach(tabs.indices,id:\.self){i in Button{selection=values[i]}label:{Text(tabs[i]).font(.system(size:13,weight:selection==values[i] ? .semibold : .regular)).foregroundStyle(selection==values[i] ? .primary : .secondary).padding(.vertical,11).overlay(alignment:.bottom){Rectangle().fill(selection==values[i] ? LabStyle.accent : .clear).frame(height:2)}}.buttonStyle(.plain).accessibilityValue(selection==values[i] ? "Selected" : "")}}}
}

struct LabControlStyle:ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration:Configuration)->some View {
        configuration.label.font(.system(size:12,weight:.medium)).padding(.horizontal,12).frame(minHeight:30)
            .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.55))
            .background(Color.primary.opacity(configuration.isPressed ? 0.12 : 0.055),in:RoundedRectangle(cornerRadius:5))
            .overlay(RoundedRectangle(cornerRadius:5).strokeBorder(Color.primary.opacity(enabled ? 0.10 : 0.04)))
            .contentShape(RoundedRectangle(cornerRadius:5))
    }
}
