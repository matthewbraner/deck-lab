import SwiftUI
struct AdvancedFiltersView: View {
    @ObservedObject var model: Model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var include = true
    var suggestions: [String] {
        guard !name.isEmpty else { return [] }
        let all=Set(model.cardIndex.values.map(\.name) + model.stats.map { $0.card.name })
        return Array(all.filter { $0.localizedCaseInsensitiveContains(name) }.sorted().prefix(8))
    }
    func add(_ value: String) {
        let value=value.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        var f=model.filters
        if include {
            if !f.requiredCards.contains(where:{normalizedCardName($0)==normalizedCardName(value)}) { f.requiredCards.append(value) }
            f.excludedCards.removeAll { normalizedCardName($0)==normalizedCardName(value) }
        } else {
            if !f.excludedCards.contains(where:{normalizedCardName($0)==normalizedCardName(value)}) { f.excludedCards.append(value) }
            f.requiredCards.removeAll { normalizedCardName($0)==normalizedCardName(value) }
        }
        model.filters=f;name=""
    }
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            HStack { Text("Advanced card filters").font(.title2.bold());Spacer();Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
            Text("Match exact card names in any zone. Every included card must be present; no excluded card may be present.").foregroundStyle(.secondary)
            HStack {
                Picker("Rule",selection:$include) { Text("Must include").tag(true);Text("Must exclude").tag(false) }.labelsHidden().frame(width:160)
                TextField("Search or enter a card name",text:$name).textFieldStyle(.roundedBorder).onSubmit { add(name) }
                Button("Add") { add(name) }.disabled(name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
            }
            if !suggestions.isEmpty { VStack(alignment:.leading,spacing:6) { ForEach(suggestions,id:\.self) { value in Button(value) { add(value) }.buttonStyle(.borderless) } }.padding(12).frame(maxWidth:.infinity,alignment:.leading).background(Color.primary.opacity(0.035)).clipShape(RoundedRectangle(cornerRadius:8)) }
            ScrollView {
                VStack(alignment:.leading,spacing:12) {
                    ForEach(model.filters.requiredCards,id:\.self) { value in ruleRow(value,positive:true) }
                    ForEach(model.filters.excludedCards,id:\.self) { value in ruleRow(value,positive:false) }
                }.frame(maxWidth:.infinity,alignment:.leading)
            }
            Text("\(model.decks.count) matching decks in the current dataset. These filters update immediately. Select All deck types in the sidebar to search across archetypes; date and source filters still apply.").font(.callout).foregroundStyle(.secondary)
            HStack { Button("Clear card filters") { model.filters.requiredCards=[];model.filters.excludedCards=[] };Spacer();Button("Search all deck types") { model.choose("all");dismiss() }.buttonStyle(.borderedProminent) }
        }.padding(24).frame(width:680,height:570)
    }
    func ruleRow(_ value:String,positive:Bool) -> some View {
        HStack { Image(systemName:positive ? "plus.circle" : "minus.circle").foregroundStyle(positive ? .teal : .orange);Text(value);Spacer();Button("Remove") { if positive { model.filters.requiredCards.removeAll { $0==value } } else { model.filters.excludedCards.removeAll { $0==value } } }.buttonStyle(.borderless) }
    }
}
