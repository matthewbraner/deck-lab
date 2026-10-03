import SwiftUI
import Charts
struct TrendsView:View {
    @ObservedObject var model:Model
    @State private var name=""
    @State private var left=""
    @State private var right=""
    @State private var query=""
    var a:TrendSample? { model.lab.trends.first{$0.id==left} }
    var b:TrendSample? { model.lab.trends.first{$0.id==right} }
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Text("Load a date range in the explorer, capture it here, then repeat for another range. Captures retain the filtered source lists and criteria; later refreshes do not change them.").foregroundStyle(.secondary)
            HStack { TextField("Dataset label",text:$name);Button("Capture current filtered dataset") { model.captureTrend(name);name="";if left.isEmpty {left=model.lab.trends.last?.id ?? ""}else{right=model.lab.trends.last?.id ?? ""} }.disabled(model.decks.isEmpty || model.pending || model.loading) }
            HStack {
                Picker("Earlier",selection:$left){Text("Choose").tag("");ForEach(model.lab.trends){Text($0.name).tag($0.id)}}
                Picker("Later",selection:$right){Text("Choose").tag("");ForEach(model.lab.trends){Text($0.name).tag($0.id)}}
            }
            if let a,let b {
                if a.format != b.format { Text("Select datasets from the same format for a meaningful comparison.").foregroundStyle(.orange) }
                else {
                    Text("\(a.name): \(a.decks.count) lists → \(b.name): \(b.decks.count) lists · \(a.format.rawValue)").bold()
                    if a.from<=b.through && b.from<=a.through { Text("Date ranges overlap; these samples may share lists.").font(.caption).foregroundStyle(.orange) }
                    DisclosureGroup("Source filters and sample dates") { Text("\(a.from)–\(a.through): \(a.criteria)\n\(b.from)–\(b.through): \(b.criteria)").font(.caption).textSelection(.enabled) }
                    TextField("Filter changed cards",text:$query)
                    ScrollView {
                        VStack(alignment:.leading,spacing:12) {
                            let changes=trendChanges(a.decks,b.decks).filter{query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)}
                            Chart(Array(changes.prefix(10))) { c in BarMark(x:.value("Percentage-point change",c.change*100),y:.value("Card",c.name)).foregroundStyle(c.change>=0 ? Color.teal : Color.orange) }.frame(height:260)
                            Text("Inclusion changes (percentage points), not win rates").font(.headline)
                            ForEach(changes) { c in
                                HStack { Text(c.name).frame(maxWidth:.infinity,alignment:.leading);Text("\(percent(c.oldRate)) → \(percent(c.newRate))").monospacedDigit().frame(width:180);Text(String(format:"%+.1f pp",c.change*100)).frame(width:70);Text(String(format:"%.2f → %.2f copies",c.oldCopies,c.newCopies)).font(.caption).frame(width:150) }
                            }
                            Divider();Text("Optional package trends").font(.headline)
                            Text("Groups detected by identical co-occurrence in either dataset. Rates below require every card in the group to appear in a list.").font(.caption).foregroundStyle(.secondary)
                            ForEach(packageRows(a,b),id:\.0) { row in Text(row.1).font(.callout) }
                        }.padding(4)
                    }
                }
            } else { ContentUnavailableView("Compare two captured datasets",systemImage:"chart.xyaxis.line",description:Text("Use matching archetype and source filters to isolate changes over time.")) }
        }.onAppear{left=model.lab.trends.first?.id ?? "";right=model.lab.trends.last?.id ?? ""}
    }
    func packageRows(_ a:TrendSample,_ b:TrendSample)->[(String,String)] {
        let all=commonPackages(a.decks)+commonPackages(b.decks)
        let packages=Dictionary(all.map{($0.cards.joined(separator:"|"),$0.cards)},uniquingKeysWith:{$1})
        func rate(_ cards:[String],_ decks:[Deck])->Double {
            let keys=Set(cards.map(collectionKey));let count=decks.filter{keys.isSubset(of:Set(($0.main+$0.extra+$0.side).filter{$0.amount>0}.map{collectionKey($0.card.name)}))}.count
            return Double(count)/Double(max(1,decks.count))
        }
        return packages.keys.sorted().map { key in let cards=packages[key]!;return (key,"\(cards.joined(separator:" + ")): \(percent(rate(cards,a.decks))) → \(percent(rate(cards,b.decks)))") }
    }
}
