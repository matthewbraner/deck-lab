import SwiftUI
struct BuildHistoryView:View {
    @ObservedObject var model:Model
    @State private var selected=""
    @State private var note=""
    @State private var notice=""
    var build:PersonalBuild? { model.workshop.builds.first{$0.id==selected} }
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            BuildChooser(model:model,selected:$selected)
            Text("Card and format edits automatically preserve the previous version. Add a named checkpoint for a testing milestone. Restoring preserves your current allocation flag and records the version being replaced.").foregroundStyle(.secondary)
            HStack { TextField("Checkpoint notes",text:$note);Button("Save checkpoint") { if let b=build { model.checkpoint(b,note:note.isEmpty ? "Checkpoint" : note);note="" } }.disabled(build==nil) }
            if !notice.isEmpty { Text(notice).foregroundStyle(.teal) }
            ScrollView {
                LazyVStack(alignment:.leading,spacing:10) {
                    ForEach(model.lab.revisions.filter{$0.build.id==selected}.reversed()) { revision in
                        VStack(alignment:.leading,spacing:8) {
                            Text("\(revision.date.formatted()) · \(revision.note)").bold()
                            Text("\(revision.build.name) · \(revision.build.format.rawValue) · \(revision.build.deck.total) cards")
                            if let current=build { Text("\(compareBuilds(revision.build,current).count) card/zone differences from current").font(.caption) }
                            HStack {
                                Button("Restore version") { if let current=build { var b=revision.build;b.allocated=current.allocated;model.putBuild(b);notice="Restored \(revision.note)." } }
                                Button("Save as separate build") { var b=revision.build;b.id=UUID().uuidString;b.name+=" · restored copy";b.allocated=false;model.putBuild(b);notice="Copy saved in Builds." }
                            }
                            if let current=build {
                                DisclosureGroup("Show changes since this version") {
                                    ForEach(compareBuilds(revision.build,current)) { row in Text("\(row.card.name) · \(row.zone.rawValue): \(row.before) → \(row.after)").font(.caption) }
                                }
                            }
                        }.padding(12).frame(maxWidth:.infinity,alignment:.leading).background(.primary.opacity(0.04)).clipShape(RoundedRectangle(cornerRadius:8))
                    }
                }
            }
        }
    }
}
struct MatchLogView:View {
    @ObservedObject var model:Model
    @State private var selected=""
    @State private var opponent=""
    @State private var result="Win"
    @State private var order="Going first"
    @State private var notes=""
    @State private var date=Date()
    @State private var matchupFilter=""
    @State private var orderFilter="All"
    @State private var notice=""
    var records:[MatchRecord] { model.lab.matches.filter{$0.build.id==selected && (matchupFilter.isEmpty || $0.opponent.localizedCaseInsensitiveContains(matchupFilter)) && (orderFilter == "All" || $0.turnOrder==orderFilter)} }
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            BuildChooser(model:model,selected:$selected)
            HStack { TextField("Opponent archetype",text:$opponent);Picker("Result",selection:$result) { ForEach(["Win","Loss","Draw"],id:\.self){Text($0)} }.frame(width:140);Picker("Turn order",selection:$order){ForEach(["Going first","Going second","Unknown"],id:\.self){Text($0)}}.frame(width:210);DatePicker("Date",selection:$date,displayedComponents:.date).frame(width:190) }
            HStack { TextField("Match notes",text:$notes);Button("Log match") { if let build=model.workshop.builds.first(where:{$0.id==selected}) { model.changeLab{$0.matches.append(MatchRecord(date:date,build:build,opponent:opponent.trimmingCharacters(in:.whitespaces),result:result,turnOrder:order,notes:notes))};notes="";notice="Match saved with a snapshot of this build." } }.disabled(selected.isEmpty || opponent.trimmingCharacters(in:.whitespaces).isEmpty) }
            Divider()
            HStack { TextField("Filter matchup",text:$matchupFilter);Picker("Order",selection:$orderFilter){ForEach(["All","Going first","Going second","Unknown"],id:\.self){Text($0)}}.frame(width:220);Button("Export match log") { export() } }
            let wins=records.filter{$0.result=="Win"}.count,losses=records.filter{$0.result=="Loss"}.count,draws=records.filter{$0.result=="Draw"}.count
            Text("\(wins) wins · \(losses) losses · \(draws) draws · \(records.isEmpty ? "—" : percent(Double(wins)/Double(records.count))) win rate (draws included)").font(.headline)
            Text("Your recorded matches only; small or selective samples do not establish matchup strength. Each record retains its played list even after build edits.").font(.caption).foregroundStyle(.secondary)
            if !notice.isEmpty { Text(notice).foregroundStyle(.teal) }
            ScrollView {
                VStack(alignment:.leading,spacing:10) {
                    let grouped=Dictionary(grouping:records,by:{$0.opponent.lowercased()+" · "+$0.turnOrder})
                    ForEach(grouped.keys.sorted(),id:\.self) { key in let values=grouped[key]!;Text("\(key): \(values.filter{$0.result=="Win"}.count)/\(values.count) wins").font(.caption) }
                    DisclosureGroup("Performance by build version") {
                        let versions=Dictionary(grouping:records,by:{$0.build.updated})
                        ForEach(versions.keys.sorted(by:>),id:\.self) { date in let values=versions[date]!;Text("\(date.formatted()) · \(values.filter{$0.result=="Win"}.count)/\(values.count) wins").font(.caption) }
                    }
                    Divider()
                    ForEach(records.sorted{$0.date>$1.date}) { record in
                        DisclosureGroup("\(record.date.formatted(date:.abbreviated,time:.omitted)) · \(record.result) vs \(record.opponent) · \(record.turnOrder)") {
                            VStack(alignment:.leading) { Text(record.notes);Text("Build version: \(record.build.updated.formatted()) · \(record.build.name)");ForEach(record.build.cards){Text("\($0.count)× \($0.card.name) · \($0.zone.rawValue)").font(.caption)} }.frame(maxWidth:.infinity,alignment:.leading)
                        }.padding(8)
                    }
                }
            }
        }
    }
    func export() {
        var lines=["date,opponent,result,turn_order,build,build_version,notes"]
        lines+=records.map { [$0.date.ISO8601Format(),$0.opponent,$0.result,$0.turnOrder,$0.build.name,$0.build.updated.ISO8601Format(),$0.notes].map(csvField).joined(separator:",") }
        do { try saveFile(lines.joined(separator:"\n"),name:"match-log.csv") } catch { notice=error.localizedDescription }
    }
}
struct SidePlansView:View {
    @ObservedObject var model:Model
    @State private var selected=""
    @State private var draft=SidePlan(buildID:"",matchup:"")
    @State private var out=""
    @State private var inc=""
    @State private var count=1
    @State private var zone=BuildZone.main
    @State private var notice=""
    var build:PersonalBuild? { model.workshop.builds.first{$0.id==selected} }
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            BuildChooser(model:model,selected:$selected)
            HStack {
                Menu("Load saved plan") { ForEach(model.lab.sidePlans.filter{$0.buildID==selected}) { p in Button("\(p.matchup) · \(p.turnOrder)"){draft=p;notice=""} } }
                Button("New plan") { draft=SidePlan(buildID:selected,matchup:"");notice="" }
                TextField("Matchup",text:$draft.matchup)
                Picker("When",selection:$draft.turnOrder){Text("Going first").tag("Going first");Text("Going second").tag("Going second")}.frame(width:220)
            }
            TextField("Matchup notes and priorities",text:$draft.notes)
            if let build {
                HStack {
                    Picker("From zone",selection:$zone){Text("Main").tag(BuildZone.main);Text("Extra").tag(BuildZone.extra)}.frame(width:160)
                    Picker("Out",selection:$out){Text("Choose card").tag("");ForEach(build.cards.filter{$0.zone==zone}){Text($0.card.name).tag($0.card.name)}}
                    Picker("In from side",selection:$inc){Text("Choose card").tag("");ForEach(build.cards.filter{$0.zone == .side}){Text($0.card.name).tag($0.card.name)}}
                    Stepper("\(count)",value:$count,in:1...3).frame(width:65)
                    Button("Add swap") { draft.swaps.append(SideSwap(outgoing:out,incoming:inc,zone:zone,count:count)) }.disabled(out.isEmpty || inc.isEmpty)
                }
                List(draft.swaps) { swap in HStack { Text("\(swap.count)× \(swap.outgoing) → \(swap.incoming) (\(swap.zone.rawValue))");Spacer();Button("Remove"){draft.swaps.removeAll{$0.id==swap.id}} } }
                HStack {
                    Button("Save plan") { do { _=try applySidePlan(draft,to:build);draft.buildID=selected;model.changeLab { lab in if let i=lab.sidePlans.firstIndex(where:{$0.id==draft.id}){lab.sidePlans[i]=draft}else{lab.sidePlans.append(draft)} };notice="Plan saved." } catch { notice=error.localizedDescription } }.disabled(draft.matchup.trimmingCharacters(in:.whitespaces).isEmpty)
                    Button("Create post-side build") { do { let b=try applySidePlan(draft,to:build);model.putBuild(b);notice="Created \(b.name). Check legality in Builds." } catch { notice=error.localizedDescription } }.disabled(draft.swaps.isEmpty)
                }
            }
            Text("Swaps exchange equal counts with the Side Deck. Availability is checked against the current build; the original list is preserved. Review format/event sideboarding rules and the resulting build's legality.").font(.caption).foregroundStyle(.secondary)
            if !notice.isEmpty { Text(notice).foregroundStyle(.orange) }
        }.onChange(of:selected){_,id in draft=SidePlan(buildID:id,matchup:"");out="";inc="";notice=""}.onChange(of:zone){_,_ in out=""}
    }
}
