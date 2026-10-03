# Deck Lab

**A native macOS workspace for Yu-Gi-Oh! deck research, collection tracking, and opening-hand analysis.**

Built with SwiftUI and AppKit for Apple silicon Macs running macOS 14 or later. Deck Lab brings deck datasets, card previews, your physical collection, and probability tools into one app.

## What you can do

- **Explore decks across formats:** Master Duel, TCG, OCG, Genesys, GOAT, and Edison, with source and date filters, favorites, and hidden deck types.
- **Find the lists you want:** require or exclude specific cards, search card effects and stats, and filter supported tournament datasets by event tier.
- **Understand an average build:** see card inclusion rates, copy distributions, and main, extra, and side deck averages.
- **Track a shared physical collection:** record quantities by printing, rarity, condition, and edition, then compare ownership with deck requirements.
- **Plan your builds:** compare decks, find missing cards, manage allocations, create shopping lists, and keep revisions, substitutions, side plans, and match records.
- **Test opening hands:** use hypergeometric probabilities, named card buckets, AND/OR combo requirements, conditional draws, and simulation.
- **Keep your work portable:** import and export YDK/CSV data, restore JSON backups, and share decks as HTML or PNG.

## Build and run

Requirements: **Apple silicon**, **macOS 14+**, and Apple's **Command Line Tools with Swift**. No third-party Swift packages are required.

```sh
git clone https://github.com/matthewbraner/deck-lab.git
cd deck-lab
./build.sh
open "../Deck Lab.app"
```

The build script creates `Deck Lab.app` beside the repository and applies a local ad-hoc signature. You can copy the app into Applications. This repository provides source; the build is not notarized for public binary distribution.

## Getting started

1. Choose a format and deck type, set your date range, and refresh the dataset.
2. Browse card previews and average copy counts, or filter lists by cards they include or exclude.
3. Save a build and enter your owned copies in the collection tools.
4. Use **Collection & cost → Update prices** or **Prices & alerts → Update watched prices** when you want to check missing or stale quotes.
5. Open the probability tools to define starter/extender buckets and test opening-hand requirements.

Press **Command-K** to find a tool. See the [user guide](docs/user-guide.md) for the full feature reference and version history.

## Pricing status

**Live TCGplayer pricing is currently unreliable: requests can return HTTP 403.** Manual updates reduce traffic but do not resolve or establish the cause of that access denial.

Pricing is manual by default. Updates skip verified quotes checked within 24 hours, retain the last successful check time, and preserve cached values when a request fails. Optional automatic checks follow the same freshness rules. Stale quotes and failed refreshes do not trigger current-price alerts.

When available, prices match the selected English printing, condition, and edition and require an in-stock verified-seller listing. Values are USD item-price estimates; shipping and tax are excluded. A generic market price is not substituted for an unavailable verified-seller low.

## Data sources and scope

| Source | Used for |
| --- | --- |
| [Master Duel Meta](https://www.masterduelmeta.com/) | Master Duel deck types and submitted lists |
| [YGOPRODeck](https://ygoprodeck.com/api-guide/) | Card information, artwork references, and other-format deck datasets |
| [TCGplayer](https://www.tcgplayer.com/) | Printing metadata and attempted verified-seller price checks |

Some deck and marketplace endpoints are undocumented and may change without notice. Tournament tiers classify events, not deck strength. Submitted lists are a sample, not a win-rate or game-wide usage measurement. Physical collection tracking does not sync your Master Duel inventory.

Deck Lab is an independent project and is not affiliated with or endorsed by Konami or these data providers. Card names, artwork, and other third-party content belong to their respective owners.

## Local storage

Your collection, builds, cached datasets, and recovery files are stored under:

```text
~/Library/Application Support/DeckLab/
```

These runtime files are not included in the repository. Network requests retrieve external card, deck, and pricing data; the app does not provide cloud collection sync. Use the in-app backup tools to save or move your collection.

## Tests

```sh
./test.sh --skip-pricing-live
```

This runs all nine suites, including live deck-provider checks, collection and valuation calculations, probability tools, backup/recovery, model integration, and simulated pricing failures. It explicitly excludes the currently blocked live TCGplayer probe. Live deck-provider checks require network access and may be affected by changing source data.

To include the live TCGplayer probe:

```sh
./test.sh
```

Version **6.3** passed the nine-suite run with the pricing probe excluded. See the [feature audit](docs/feature-audit.html) for earlier UI coverage and known limitations.

## Project layout

- `Sources/` — native app, data providers, collection model, and analysis tools.
- `Tests/` — calculation, integration, persistence, and pricing reliability tests.
- `Resources/` — app icon and icon-generation source.
- `docs/` — detailed user guide and feature audit.

## Feedback

[Open an issue](https://github.com/matthewbraner/deck-lab/issues) for a bug or feature request. For bugs, include your macOS version, app version, steps to reproduce, and the displayed error. Redact personal collection details from any logs or screenshots you choose to share.
