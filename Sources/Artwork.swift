import SwiftUI
import AppKit

actor ArtworkCache {
    static let shared = ArtworkCache()
    private var active: [String:Task<Data,Error>] = [:]
    func image(_ id: String, source: String?) async throws -> Data {
        guard Int(id) != nil else { throw DataError.message("No card image is available.") }
        let folder = try LocalStore().directory.appendingPathComponent("card-images",isDirectory:true)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let file = folder.appendingPathComponent(id + ".jpg")
        if FileManager.default.fileExists(atPath:file.path) { return try Data(contentsOf:file) }
        if let task=active[id] { return try await task.value }
        let task=Task<Data,Error> {
            let address=source ?? "https://images.ygoprodeck.com/images/cards/\(id).jpg"
            guard let url=URL(string:address),url.scheme=="https",url.host=="images.ygoprodeck.com" else { throw DataError.message("The card image source is unavailable.") }
            let (data,response)=try await URLSession.shared.data(from:url)
            guard (response as? HTTPURLResponse)?.statusCode==200,response.mimeType?.hasPrefix("image/")==true else { throw DataError.message("Card image could not be loaded.") }
            try data.write(to:file,options:.atomic)
            return data
        }
        active[id]=task
        defer { active[id]=nil }
        return try await task.value
    }
}

struct CardArtwork: View {
    let info: CardInfo?
    @State private var image: NSImage?
    @State private var failure = false
    @State private var enlarged = false
    var body: some View {
        Group {
            if let image {
                Button { enlarged=true } label: { Image(nsImage:image).resizable().aspectRatio(contentMode:.fit) }.buttonStyle(.plain)
                    .help("Enlarge card image")
                    .popover(isPresented:$enlarged) {
                        VStack(spacing:8) { Image(nsImage:image).resizable().aspectRatio(contentMode:.fit).frame(width:330,height:480);Text("YGOPRODeck artwork · Selected printing may differ").font(.caption).foregroundStyle(.secondary) }.padding(14)
                    }
            } else if failure || info==nil {
                VStack(spacing:8) { Image(systemName:"photo").font(.title);Text("No image").font(.caption) }.frame(maxWidth:.infinity,maxHeight:.infinity).foregroundStyle(.secondary)
            } else { ProgressView().frame(maxWidth:.infinity,maxHeight:.infinity) }
        }
        .accessibilityLabel("Card image for \(info?.name ?? "selected card")")
        .task(id:info?.id) {
            image=nil;failure=false
            guard let info else { return }
            do { let data=try await ArtworkCache.shared.image(info.id,source:info.imageURL);guard !Task.isCancelled else { return };image=NSImage(data:data);failure=image==nil }
            catch { if !Task.isCancelled { failure=true } }
        }
    }
}
