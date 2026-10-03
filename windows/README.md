# Deck Lab for Windows · preview 0.2

A Windows desktop port of Deck Lab, built with Electron. The SwiftUI macOS app remains in the repository root. This first Windows release implements the core workflows; it does not yet have full macOS feature parity.

## Interface update · 0.2

The explorer now opens in an artwork gallery with average-copy badges and owned-copy progress, with a table toggle for detailed comparison. A deck overview, compact index, collapsible card filters and consistent navigation keep the main actions in view. Light/dark mode and gallery/table preferences are saved locally. Press **Control-K** to focus card search. Keyboard focus remains visible, and animations respect reduced-motion preferences.

## Get the Windows installer

1. Open the repository's **Actions → Windows desktop** workflow.
2. Select a successful run for `main`.
3. Download the **Deck-Lab-Windows-x64** artifact and unzip it.
4. Run `Deck-Lab-Windows-0.2.0-x64-Setup.exe`.

The installer targets Windows 10/11 x64. It is not code-signed with a publisher certificate; Windows may display an unknown-publisher prompt. There is no automatic updater in this preview. The installer lets you choose an installation directory and desktop shortcut.

## Build from source

Install Node.js 24 LTS, then run on Windows:

```powershell
cd windows
npm ci
npm run check
npm test
npm run smoke
npm run dist:win
```

The installer is generated in `windows/dist/`. For development, run `npm start`. Electron contains the runtime; users of the packaged app do not need Node.js.

## Included workflows

| Area | Windows preview |
| --- | --- |
| Deck explorer | Master Duel, TCG, OCG, Genesys, GOAT and Edison; date and supported event-tier filters; exact card inclusion/exclusion; hidden types; favorites |
| Card library | Artwork, descriptions, type/attribute and name/effect search; add cards to saved builds |
| Collection | Shared ownership across decks, unspecified copies, rarity/set/condition/edition selections, buy targets |
| Prices | Manual updates only, fresh verified quotes skipped for 24 hours, serialized requests, bounded retries for selected HTTP errors, 403 cooldown, 429 Retry-After handling, explicit cached/unpriced values |
| Builds | Create, rename, change format, add/edit quantities in main/extra/side, save rounded average builds, YDK import/export |
| Probability | Exact hypergeometric calculator and up to four saved card buckets per build with AND/OR opening-hand requirements |
| Files | Atomic local persistence, JSON backup/validated restore, pre-restore safety copy, cached card and deck data |

The Windows preview does **not** yet include the macOS app's match logs, side plans, build revisions, allocation reservations, trend comparisons, aggregated shopping list, conditional probability optimizer, HTML/PNG deck exports, undo history, Genesys point search, or format banlist validation. Average builds are a statistical reference and may not be legal decks.

Combo buckets measure whether the opening hand contains at least one card from every/any bucket. The same card can satisfy overlapping buckets. This does not validate a legal in-game combo sequence or require distinct cards for each role.

## Data and pricing

Deck and card sources match the macOS app. Undocumented provider endpoints can change. Dataset refreshes replace the cached snapshot only after the full fetch succeeds; cached responses show their check time. The explorer labels the loaded dataset separately from pending filter selections.

**TCGplayer HTTP 403 remains unresolved.** The port does not bypass access denials or promise live pricing availability. Card metadata from YGOPRODeck is not substituted for verified-seller lows. Fresh quotes retain their original check time; failure leaves the old quote and quantity intact. Item prices exclude shipping and tax.

## Local data and migration

Windows data is stored in `%APPDATA%\DeckLabWindows\`. The main file is `workspace.json`; provider caches are separate. A restore preserves the prior workspace in `before-restore.json` before replacing it. Runtime data is ignored by Git.

This port uses a separate backup schema. To move **decks** between macOS and Windows, export and import YDK files. Full collection and workspace backups are not cross-compatible yet. Export your Windows backup before moving computers or changing builds.

## Verification

`npm test` covers aggregation, shared ownership, exact-card filtering, hypergeometric probabilities, overlapping buckets, YDK roundtrips, backup rejection, atomic persistence, cached network fallback, pagination, format isolation, price eligibility, rate limits and request serialization. `npm run smoke` opens the actual Electron app with an isolated temporary fixture, verifies renderer startup and the IPC path, and exits. The GitHub workflow runs these on Windows before creating the installer.

The renderer has Node integration disabled, context isolation and sandboxing enabled, restricted IPC methods, and no arbitrary URL or filesystem access. Build dependencies stay outside the packaged app. `npm audit` currently reports an advisory in the builder's transitive HTTP-cache tooling; that dependency is used for development/build downloads, not the application's runtime requests.
