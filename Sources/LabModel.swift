import SwiftUI
@MainActor extension Model {
    @discardableResult func saveLab(_ value:LabData) -> Bool {
        guard let store else { storageError="Local storage unavailable.";return false }
        do { try captureRecovery("Lab records");try store.write(value,name:"lab.json");lab=value;storageError=nil;return true } catch { storageError=error.localizedDescription;return false }
    }
    func changeLab(_ change:(inout LabData)->Void) { var next=lab;change(&next);saveLab(next) }
    func checkpoint(_ build:PersonalBuild,note:String) { changeLab { $0.revisions.append(BuildRevision(build:build,note:note)) } }
    func captureTrend(_ name:String) {
        guard let s=snapshot else { return }
        let criteria="\(s.type.name) · \(filters.source.rawValue) · \(filters.rank.rawValue) · \(filters.exactRank) · \(s.eventTier ?? "All events") · \(filters.tournament) · required: \(filters.requiredCards.joined(separator:", ")) · excluded: \(filters.excludedCards.joined(separator:", ")) · exclude flagged: \(filters.excludeFlagged)"
        changeLab { $0.trends.append(TrendSample(name:name.isEmpty ? "\(s.type.name) \(s.from)–\(s.through)" : name,format:GameFormat(rawValue:s.format ?? "Master Duel") ?? .masterDuel,from:s.from,through:s.through,criteria:criteria,decks:decks)) }
    }
    func recordPrice(_ quote:PriceQuote) {
        let previous=suppressRecovery;suppressRecovery=true;defer{suppressRecovery=previous}
        changeLab { next in
            if !(next.priceHistory[quote.variantID] ?? []).contains(where:{$0.checked==quote.checked}) { next.priceHistory[quote.variantID,default:[]].append(quote) }
        }
    }
    var triggeredWatches:[PriceWatch] { lab.watches.filter { watch in guard let quote=quotes[watch.variantID] else { return false };return quote.verified && quote.isFresh && pricingErrors[watch.variantID] == nil && quote.cents<=watch.targetCents } }
    func refreshWatchedPrices() async {
        guard !watchRefreshBusy else { return };watchRefreshBusy=true;defer { watchRefreshBusy=false };watchStatus="Refreshing watched printings…"
        var failed=0, checked=0, skipped=0
        for watch in lab.watches {
            if Task.isCancelled { break }
            guard let variant=inventory.variants[watch.variantID] else { failed+=1;continue }
            guard needsPriceUpdate(variant) else { skipped+=1;continue }
            do { try await updateQuote(variant); checked+=1 } catch { failed+=1;if (error as? TCGServiceError)?.stopsBatch == true { break } }
        }
        watchStatus=Task.isCancelled ? "Price check cancelled. Cached quotes are preserved." : failed>0 ? "Some prices could not refresh. Cached quotes and their timestamps remain visible." : "Updated \(checked) printings; \(skipped) already fresh. \(triggeredWatches.count) at or below target."
    }
}
