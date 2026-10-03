# Deck Lab for macOS

A native SwiftUI app for Apple silicon Macs running macOS 14 or later. No browser, server, subscription, or API key is needed. Open `Deck Lab.app`, or copy it into Applications.

## Version 6.3 manual price updates

Use **Update prices** in Collection & cost to update owned and target printings in the current dataset, or **Update watched prices** in Prices & alerts. Each action fetches only missing, unverified, or stale quotes (24 hours or older). Individual printing updates use the same policy, and repeated requests for the same printing are suppressed while a fetch is running. Fresh quotes keep their original timestamp; a skipped update does not pretend to be a new price check.

Automatic pricing is off for new installations. Existing explicit preferences are preserved; the optional automatic check also fetches only missing or stale quotes. The last successful price update appears above pricing results, while each printing retains its own checked time. This is the newest successful individual quote, not a claim that every card was refreshed together.

TCGplayer HTTP 403 remains unresolved. Manual updates reduce traffic but do not establish that the access denial was a rate limit. Cached quotes remain available and dated.

Validation: all nine suites passed with `./test.sh --skip-pricing-live`, including live Master Duel/YGOPRODeck checks, price-refresh skip/update behavior, and simulated pricing failures. The live TCGplayer probe was explicitly excluded because access remains blocked.

## Version 6.2 pricing reliability

Pricing requests now use one serialized transport for manual, batch, and background checks. Temporary connection failures and selected server errors retry at most twice. Rate limits respect Retry-After, and HTTP 403 pauses requests for five minutes. The app retains last verified quotes, labels quotes older than 24 hours as stale, and suppresses price alerts after failed refreshes or for stale quotes. Failed refresh status persists across restarts. App and command-line requests identify themselves consistently as DeckLab/6.2.

Live pricing remains an external limitation: the explicitly identified client receives HTTP 403. This release improves predictable operation and recovery; it does not claim to fix TCGplayer access. Reliable live pricing needs a supported feed that provides the selected printing, condition, edition and verified-seller status. TCGplayer currently states that new API access is unavailable: https://docs.tcgplayer.com/docs/getting-started . Generic market prices are not substitutes for verified-seller lows.

`./test.sh` includes live provider checks and will fail if live pricing is blocked. `./test.sh --skip-pricing-live` explicitly skips that external pricing probe while retaining pricing calculations and fault-injection tests, plus live deck-provider checks.

## Version 6.1 feature audit

See `feature-audit.html` for the October 3 audit of all 21 workspaces. Eight automated suites pass. This build fixes card-inspector layout, format-independent Genesys point loading, and missing-stat filtering. Native TCGplayer refresh returned HTTP 403 during QA despite successful command-line live checks; cached quotes and explicit errors are preserved. Reopen the app to load the rebuilt version.

## Version 6 workspace redesign

The navigation rail has five areas: Explore, Decks, Test, Collect, and Files. Each area exposes its related tools in a horizontal navigation bar. Command-K still searches all tools; Command-1 through Command-4 open Explorer, My decks, Card library, and Test hands.

Explorer keeps the format selector and searchable deck index visible. Right-click a deck to favorite or hide it, or use Hide selected. Filters opens date, source, tournament tier, and exact-card inclusion/exclusion controls. The gallery uses an adjacent card inspector; View switches to the statistical table and controls sorting and the average denominator. The inspector closes without losing the dataset or card search.

Design research included the [Lusion v3 Awwwards entry](https://www.awwwards.com/sites/lusion-v3), the current [Lusion site](https://lusion.co/), and [TBMX WebTrader's Red Dot entry](https://www.red-dot.org/project/tbmx-webtrader-85147). The current Lusion site is a later presentation, not a claim that the 2023 award applies to today's exact layout. These references informed restrained navigation, a clear dominant content area, and adjacent working panels. Their artwork and branding are not included in Deck Lab.

## Use

1. Choose a format and search/select a deck type in the sidebar.
2. Choose an inclusive date range and click the **Refresh dataset** arrow. Master Duel dates use UTC submission days; YGOPRODeck uses its own date filtering and returns relative source dates.
3. Master Duel supports ranked ladder, tournament, event, minimum-rank, exact-rank, and tournament-name filters. Other formats support community/tournament sources and YGOPRODeck's **Tier 2+ Competitive** and **Tier 3 Premier** event filters. These are tournament tiers, not deck-strength ratings. Load again after changing event tiers.
4. Review every observed card, its inclusion rate, and average main/extra/side/total copies. Choose whether the denominator is all matching decks or only decks running that card in any zone. Select a row for the copy distribution and YGOPRODeck card details, including current Genesys points when viewing Genesys.
5. Assign **Engine**, **Non-engine**, or **Unclassified**. Choices persist per deck type and format on this Mac. The APIs do not provide a complete reliable engine classification for every card.
6. Use **Source lists** to inspect individual lists and open their original pages.

## Data and limitations

- Master Duel deck submissions: Master Duel Meta's undocumented `/api/v1/deck-types` and `/api/v1/top-decks` endpoints.
- Other-format deck submissions: YGOPRODeck's undocumented site deck-search endpoint `/api/decks/getDecks.php`. Uses the site's archetype tags, including hybrid decks, not a name substring guess.
- Card information: documented [YGOPRODeck v7 API](https://ygoprodeck.com/api-guide/), including descriptions, stats, card types, archetypes, and Genesys points. Card databases are cached locally for 48 hours. Card details and points reflect the current cache, not historical rules on the selected date.
- Genesys includes community and tournament categories. TCG includes Meta, Non-Meta, Fun/Casual, and Tournament Meta categories. OCG is tournament lists. GOAT/Edison use their named categories. The UI never pools Master Duel decks into another format.
- Master Duel Meta does not expose YGOPRODeck's tournament-tier classification. These filters are available for YGOPRODeck datasets only.
- Each submitted deck has equal weight. A player's separate submissions remain separate observations. These data are not game-wide usage or win-rate estimates.
- Missing side decks count as zero. Master Duel ladder has no side deck, while tournament/other-format submissions can include side decks.
- All source pages are fetched until exhausted; duplicate IDs are counted once. A failed fetch preserves the prior complete dataset and labels it as the previous dataset when appropriate. APIs can change without notice.
- Unknown YGOPRODeck passcodes remain in the statistics, labeled with their passcodes, rather than being silently omitted.
- Relative YGOPRODeck dates are the source labels captured at the snapshot's update time.

Saved classifications, the latest successful deck snapshot, catalogues, and card caches are in `~/Library/Application Support/DeckLab/`. The app makes read-only requests to Master Duel Meta and YGOPRODeck. It does not upload classifications.

## Build and test

Requires Apple's Command Line Tools and Swift. No third-party packages.

```sh
./build.sh
./test.sh
```

`build.sh` produces `../Deck Lab.app` and signs it locally. It is an Apple silicon build for this Mac, not a notarized public distribution.

The tests cover copy aggregation, zero-copy denominators, duplicate entries, zone totals, rank/source filters, saved data round trips, cross-provider card lookup, format isolation, Genesys points, and live Tier 2+/Tier 3 queries.

## Physical collection and TCGplayer prices

Open **Collection & cost**, then **Manage…** on any card. Choose the TCGplayer printing (rarity, set, and collector number), condition, and edition. English-language conditions/editions come from the product's actual SKU catalogue. Record owned quantities for each printing. Quantities are shared across deck types and formats, while engine classifications remain deck-specific. Unspecified copies can be recorded before assigning printings; they count toward completion but are not valued.

**Use for target & update price** selects the version you intend to buy. It does not alter any owned printing. **Update prices** refreshes missing or stale quotes for the selected target and owned printings for cards in the dataset.

The buy target rounds each card's average total copies across main/extra/side, using all matching decks. Choose nearest whole copy or always round up. This is an average-based buying reference, not necessarily a legal decklist. Copies owned beyond the target do not increase completion. For the built-so-far value, the selected printing is allocated first, followed by other owned printings in stable ID order; unspecified copies remain unpriced.

Prices use TCGplayer's public marketplace listing service via native URLSession. Every eligible listing is checked for product, English language, selected condition and edition, positive stock, and `verifiedSeller: true`. All result pages are examined before selecting the minimum item price. This is distinct from YGOPRODeck's general price field. Product matches exclude similarly named cards. Product and SKU metadata are cached for 24 hours; quotes retain their exact fetch timestamp and refresh on request. No credentials or purchases are required.

Deck costs are USD item-price estimates, excluding shipping and tax. They do not guarantee that a single seller has enough copies or that the price remains available. Missing quotes remain explicitly unpriced. Partial amounts are subtotals, not complete valuations. Holdings retain their own printing/condition price even if a different target printing is selected.

Inventory and target selections are in `inventory.json`; quotes are in `tcg-quotes.json`, alongside the existing local data. Master Duel collection comparisons refer to physical equivalents, not your in-game inventory.

### Card previews and advanced search
Select a statistics row to see card artwork; click the image to enlarge it. The collection editor also previews the card. Artwork is cached locally and may differ from a selected printing.

Use **Card filters…** to require or exclude exact card names across main, extra, and side decks. Multiple required cards use AND matching. Select **All deck types** to search across archetypes within the selected format and dates.

Select a deck type and choose **Hide selected**, or right-click it and choose **Hide**. This preference persists across launches and formats. Enable **Show hidden** to restore a type. Hidden types are omitted from the sidebar; their lists remain eligible for All deck types searches.

## My workshop (version 2.0)

Open **My workshop** in the sidebar:

- **Builds:** create an empty build, save a rounded average, copy a source list, or edit an imported YDK. Counts are editable separately for Main, Extra, and Side; lowering a count to zero removes it. Add cards through database search. Names, format, copies, chosen printings, and reservations persist locally. The average is a starting point and may not be a legal or coherent deck.
- **What can I build?:** ranks saved builds and currently loaded source lists by collection completion or cost to finish. Load **All deck types** to expand the candidates. Budget filtering excludes candidates with unpriced missing copies. It uses selected verified-seller quotes, excluding shipping/tax; it does not silently use an unrelated cheapest printing. Reservations can reduce available quantities.
- **Core & flex:** adjustable inclusion threshold (80% default). Optional cards appearing in exactly the same source lists at least twice are displayed as possible packages. These are co-occurrence statistics, not synergy claims.
- **Compare:** choose saved builds, source lists, or the current average. Differences retain zones. Purchase estimates sum positive total-copy differences, so moving a card between zones does not create a purchase. The estimate uses the From deck only, without crediting other collection copies or resale proceeds.
- **Import & backup:** preview collection CSV or pasted quantity/name lines, then add or replace. CSV supports `name,quantity,product_id,rarity,set,number,condition,edition`. Names with commas require CSV quotes. Printing fields preserve exact English holdings; name-only entries are unpriced. YDK imports validate all passcodes before saving, and exports preserve all three zones. Full JSON backups include builds, searches, favorites, hidden types, classifications, inventory, and quotes; a pre-restore copy is retained locally.
- **Saved searches:** saves fixed date ranges, format, type, source, tier, rank, and include/exclude filters. Load reapplies and refreshes the dataset. Right-click sidebar deck types to favorite them; favorites sort first.

**Physical allocation:** mark a saved build Assembled to reserve its card quantities. Multiple builds can request the same cards; any shortage is shown explicitly. This is card-level allocation across printings, not tracking individually serialized physical copies. Your ownership counts remain unchanged.

**Legality:** checks sizes, zones, combined copy limits, card-pool metadata, and Genesys points against an editable cap (100 by default). Refresh rules loads current YGOPRODeck TCG/OCG/GOAT limits and Genesys points plus Master Duel Meta's released-card limits. Edison uses the fixed official March 2010 Advanced list. Missing metadata is reported as incomplete, never a clean legality pass. Historical event variations and shared-name effects require manual review. Provider timestamps are shown; refreshing data is necessary after changes.

Rules references: [Konami Genesys](https://www.yugioh-card.com/en/genesys/), [official March 2010 list](https://img.yugioh-card.com/en/downloads/alt_format/2010-03-01.pdf), [YGOPRODeck API](https://ygoprodeck.com/api-guide/).

## Testing, collecting, and probabilities (version 3.0)

Choose tools from the **Workspace** menu in My workshop:

- **Hands & probability → Test hands:** shuffle and draw physical Main Deck copies without replacement; draw subsequent cards from the same shuffle. Card artwork can be enlarged. This models cards seen, not effect resolution or legal combo sequencing.
- **Buckets:** save up to 12 overlapping groups per build. Select card names to include every Main Deck copy of those cards; label groups as Starter, Extender, Brick, Interaction, or Custom. Bucket membership does not change the build.
- **Hypergeometric:** exact probability of exactly, at least, or at most a number of bucket hits, expected hits, a distribution chart, and nearby copy-ratio comparisons. The hypothetical ratio control never edits your deck. It uses `C(K,k) C(N-K,n-k) / C(N,n)` for a uniform shuffle without replacement.
- **Combos:** define named routes with minimum/maximum counts for each bucket. Requirements within a route use AND; “Any saved route” uses OR. Distinct-copy mode allocates separate physical cards to minimum requirements, so a card belonging to two buckets cannot fill two slots. With that mode off, one card can satisfy both presence checks. Maximums always constrain the total number drawn from a bucket. Exact grouped multivariate enumeration handles overlap and unions jointly. Calculations above the complexity limit stop with an explanation; choose Monte Carlo for 30,000 random draws and a 95% Wilson interval. Supported calculations use Main Deck sizes 1–100 and hands 0–10. Notes can record the intended sequence, but the calculator does not validate effects, timing, searches, costs, or interruptions.
- **Side plans:** save matchup notes and going-first/second swaps. Equal quantities move between Main/Extra and Side, with available-copy validation. Create a separate post-side build and check its legality before use.
- **Match log:** save results, opponent archetype, turn order, date, notes, and a snapshot of the played build. Filter summaries by matchup/order, inspect performance by build version, and export CSV. Win rate is wins divided by all logged results, including draws; it is your sample, not population win-rate data.
- **Build history:** card/format edits preserve previous versions automatically. Add named checkpoints, inspect differences, restore a version, or save a separate copy. Allocation status is preserved on restore.
- **Shopping list:** combine saved builds using either maximum per-card requirements (one reusable pool) or summed quantities (simultaneous builds). Owned inventory is subtracted once; copies reserved in other assembled builds can be excluded. Exact selected-printing product links and CSV export are included. Missing prices are explicit, and quote availability may not cover every requested copy at the same price.
- **Collection browser:** browse owned cards independently of the current dataset, filter by rarity/set/condition, and manage quantities/printings. Extras are copies above the greater of your keep count and assembled reservations. This is a trade-candidate aid, not a recommendation to sell.
- **Price history & alerts:** quotes are recorded whenever refreshed. Set per-printing targets and check manually or opt into 15-minute checks while Deck Lab is running. Alerts appear inside the app and on the My workshop button. The app does not run checks when closed or send external/system notifications. Quote history starts with locally collected observations; no past market prices are invented.
- **Dataset trends:** capture the current filtered dataset with its dates and source criteria, then compare two captures in the same format. Shows card inclusion percentage-point changes, mean copies, and optional-package inclusion. Overlapping dates are flagged. Keep source/archetype filters comparable when interpreting changes.

Full backups now include bucket/route setups, revisions, matches, side plans, price history/watches, and trend captures. Older version-2 backups remain readable; they have no lab records to restore.

## Version 4 — Advanced workshop tools

Open **My workshop** and choose a workspace:

- **Card search** combines name/effect text, card type, attribute, race, level, ATK/DEF bounds, and maximum Genesys points. Blank numeric fields are ignored. Missing stats do not satisfy active numeric filters. Click a card to see artwork/text and add it to required/excluded deck filters.
- **Advanced probabilities** compares saved builds using the reference build’s buckets and combo routes. Define these first under Hands & probability. Bucket rows show at-least-one odds; Calculate computes the exact OR of all reference routes, respecting overlapping buckets and distinct-copy requirements. Conditional draws removes known cards from the Main Deck and calculates only the next draws.
- **Optimize ratios**, inside Advanced probabilities, exhaustively varies 0–3 copies of up to seven unlocked existing Main Deck card types. Other cards and zones stay fixed. Choose a 40–60 card target and optional USD cost-to-finish cap. Missing prices fail the budget constraint. Incomplete rules are excluded unless explicitly allowed. The search stops with an error if it exceeds 2,000 eligible candidates or an exact calculation exceeds its complexity limit; it never labels partial results optimal. Save creates a separate build. Its objective is your defined combo probability, not measured tournament performance.
- **Substitutions** stores groups you define with exact card names, one per line. Choose an owned alternative and save a separate build; review its legality in Builds. Groups express your own judgment of interchangeability. Shared owned copies are checked against the target build; assembled-build reservations still need review.
- **Collection locations** places quantities of individual printings (or unspecified copies) in named storage locations. Unplace / move returns copies to the unlocated pool for reassignment. This never increases owned quantities. Reducing ownership below located quantities displays a conflict.
- **Share deck** exports a PNG card grid or portable printable HTML with embedded card art. Open HTML in a browser and print. Optional prices use cached verified quotes for selected printings, with conditions and check dates. Unknown prices remain marked unavailable. Artwork is representative and may differ from the selected printing. Export supports 200 distinct entries.
- **Recovery** provides persistent undo/redo for local collection, build, lab, group, location, classification, hidden-type, and saved-search changes. Keeps 20 changes and up to 14 daily snapshots; manually create a snapshot before larger changes. A restore can itself be undone. Price-refresh history does not fill the undo queue. Export a full JSON backup under Import & backup for storage outside this Mac. Backups now include substitutions and locations; older backups remain readable and restore those newer fields as empty.

Right-click a build in the Builds list to delete it; Recovery can undo the deletion. All these tools use the shared physical collection, including when viewing Master Duel lists.

## Version 5 — A redesigned Mac workspace

The workshop tools now live in a persistent sidebar, grouped into Discover, Build & Test, Collection, and Workspace. The names are shorter and clearer: My decks, Card library, Probability studio, Match journal, and Undo & recovery retain the same underlying features and saved records.

- Use **Jump to…** or **Command-K** to search every workspace. Return opens the first match; Escape closes the palette.
- **Command-1** opens Deck explorer, **Command-2** My decks, **Command-3** Card library, and **Command-4** Test hands & combos.
- Click the deck title or **Browse deck types** in the explorer to select an archetype, switch formats, favorite/hide types, or show hidden types.
- **Filters** expands source, tournament, date, rank, and card filtering controls. **Command-R** refreshes the selected dataset while in the explorer.
- The explorer opens in an artwork gallery. Switch to **Table** for dense numeric comparison. Selecting a card opens a dedicated detail sheet with card text, role, ownership, and copy distribution.
- Card library now has an artwork grid, searchable names/effects, an expandable stat filter panel with persistent field labels, and an adjacent card inspector.
- **Appearance** in the toolbar offers Dark, Light, and System. The app uses semantic text colors, increased-contrast surface borders, labeled native controls, and no motion-dependent interactions.
- Existing builds, collection records, location allocations, price targets, and backups keep their existing storage format. No data migration is required.

The app also has a new native icon, larger controls, clearer section headers, and consistent spacing/surfaces across all tools.


## Version 5.1 — Collector’s workbench

Replaces the dashboard tile treatment with a warmer editorial layout: charcoal and copper, a typographic masthead, a deck-title spread with real card artwork, one compact dataset strip, and unboxed card rows. Composition, source lists, and collection use underlined tabs. Gallery/table mode, sorting, and the average denominator are under **Display options**. All existing data, tools, keyboard shortcuts, and appearance choices remain available.
