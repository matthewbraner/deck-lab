"use strict";
const { key } = require("./core.cjs");
const categories = {
  TCG: [
    "Meta Decks",
    "Non-Meta Decks",
    "Fun/Casual Decks",
    "Tournament Meta Decks",
  ],
  OCG: ["Tournament Meta Decks OCG"],
  Genesys: ["Genesys Decks", "Tournament Meta Decks (Genesys)"],
  GOAT: ["Goat Format Decks"],
  Edison: ["Edison Format Decks"],
};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
class Providers {
  constructor(store, fetcher = fetch) {
    this.store = store;
    this.fetcher = fetcher;
    this.priceQueue = Promise.resolve();
    this.blockedUntil = 0;
  }
  async request(url, body) {
    const r = await this.fetcher(url, {
      signal: AbortSignal.timeout(60000),
      headers: {
        Accept: "application/json",
        ...(body ? { "Content-Type": "application/json" } : {}),
      },
      ...(body ? { method: "POST", body: JSON.stringify(body) } : {}),
    });
    let json;
    try {
      json = await r.json();
    } catch {
      throw Error(`Provider returned HTTP ${r.status} with unreadable data.`);
    }
    if (
      r.status === 400 &&
      json.error === "No decks matching your query were found in the database."
    )
      return [];
    if (!r.ok)
      throw Error(
        `Provider returned HTTP ${r.status}. Your previous data is preserved.`,
      );
    return json;
  }
  async cached(name, loader, force = false) {
    const old = await this.store.read(name);
    if (old && !force && Date.now() - old.checked < 86400000)
      return { ...old, cached: true };
    try {
      const pack = { checked: Date.now(), data: await loader() };
      await this.store.write(name, pack);
      return pack;
    } catch (e) {
      if (old) return { ...old, cached: true, warning: e.message };
      throw e;
    }
  }
  async cards(force = false) {
    return this.cached(
      "cards-cache.json",
      async () => {
        const raw = await this.request(
          "https://db.ygoprodeck.com/api/v7/cardinfo.php?misc=yes",
        );
        if (!Array.isArray(raw.data)) throw Error("Unexpected card database.");
        return raw.data.map((c) => ({
          id: String(c.id),
          name: c.name,
          description: c.desc,
          type: c.type,
          race: c.race,
          attribute: c.attribute || "",
          level: c.level,
          atk: c.atk,
          def: c.def,
          archetype: c.archetype || "",
          image: c.card_images?.[0]?.image_url || "",
          aliases: (c.card_images || []).map((i) => String(i.id)),
          formats: c.misc_info?.[0]?.formats || [],
        }));
      },
      force,
    );
  }
  async catalogue(format) {
    if (format === "Master Duel")
      return this.cached("md-types-cache.json", async () => {
        const raw = await this.request(
          "https://www.masterduelmeta.com/api/v1/deck-types?limit=0&fields=name",
        );
        if (!Array.isArray(raw)) throw Error("Unexpected deck index.");
        return raw
          .map((d) => ({ id: d._id, name: d.name }))
          .sort((a, b) => a.name.localeCompare(b.name));
      });
    return this.cached("ygo-types-cache.json", async () => {
      const raw = await this.request(
        "https://db.ygoprodeck.com/api/v7/archetypes.php",
      );
      if (!Array.isArray(raw)) throw Error("Unexpected archetypes.");
      return raw.map((d) => ({ id: d.archetype_name, name: d.archetype_name }));
    });
  }
  async decks(query) {
    const { format, type, from, to, tier } = query;
    if (
      !["Master Duel", ...Object.keys(categories)].includes(format) ||
      !type?.id ||
      !/^\d{4}-\d{2}-\d{2}$/.test(from) ||
      !/^\d{4}-\d{2}-\d{2}$/.test(to) ||
      from > to
    )
      throw Error("Choose a format, deck type and valid date range.");
    const cards = (await this.cards()).data,
      index = new Map(
        cards.flatMap((c) => [...[c.id, ...c.aliases].map((id) => [id, c])]),
      ),
      names = new Map(cards.map((c) => [key(c.name), c]));
    const result = [],
      seen = new Set();
    const append = (page) => {
      let fresh = 0;
      for (const d of page)
        if (!seen.has(d.id)) {
          seen.add(d.id);
          result.push(d);
          fresh++;
        }
      if (page.length && !fresh)
        throw Error(
          "Provider repeated a page; incomplete results were discarded.",
        );
    };
    if (format === "Master Duel") {
      const before = new Date(to + "T00:00:00Z");
      before.setUTCDate(before.getUTCDate() + 1);
      const cutoff = new Date(
        Math.min(before.getTime(), Date.now()),
      ).toISOString();
      let offset = 0;
      while (true) {
        const params = new URLSearchParams({
          "created[$gte]": from,
          "created[$lt]": cutoff,
          sort: "-created",
          limit: "200",
          skip: String(offset),
          fields: "-notes",
        });
        if (type.id !== "all") params.set("deckType", type.id);
        const raw = await this.request(
          "https://www.masterduelmeta.com/api/v1/top-decks?" + params,
        );
        if (!Array.isArray(raw))
          throw Error("Unexpected Master Duel deck data.");
        if (!raw.length) break;
        const page = raw.map((d) => {
          if (
            !d._id ||
            !d.created ||
            d.created < from ||
            d.created >= cutoff ||
            (type.id !== "all" && d.deckType?._id !== type.id)
          )
            throw Error("Source did not honor deck/date filters.");
          const zones = {};
          for (const z of ["main", "extra", "side"])
            zones[z] = (d[z] || []).map((e) => {
              if (!e.card?.name || !Number.isInteger(e.amount) || e.amount < 0)
                throw Error("Invalid card entry.");
              return {
                name: e.card.name,
                cardId: names.get(key(e.card.name))?.id || "",
                count: e.amount,
              };
            });
          return {
            id: d._id,
            name: d.deckType?.name || type.name,
            date: d.created.slice(0, 10),
            rank: d.rankedType?.name || "",
            tournament: d.customTournamentName || d.tournamentType?.name || "",
            format,
            ...zones,
          };
        });
        append(page);
        offset += raw.length;
        await sleep(150);
      }
    } else {
      for (const category of categories[format]) {
        let offset = 0;
        while (true) {
          const params = new URLSearchParams({
            _sft_category: category,
            from,
            to,
            offset: String(offset),
          });
          if (type.id !== "all") params.set("_sft_post_tag", type.name);
          if (["tier-2", "tier-3"].includes(tier))
            params.set("tournament", tier);
          const raw = await this.request(
            "https://ygoprodeck.com/api/decks/getDecks.php?" + params,
          );
          if (!Array.isArray(raw))
            throw Error(raw.error || "Unexpected deck data.");
          if (!raw.length) break;
          const page = raw.map((d) => {
            if (
              !Number.isInteger(d.deckNum) ||
              !categories[format].includes(d.format)
            )
              throw Error(
                "Source returned a deck outside the selected format.",
              );
            const zones = {};
            for (const z of ["main", "extra", "side"]) {
              const ids = JSON.parse(d[z + "_deck"] || "[]");
              if (!Array.isArray(ids)) throw Error("Invalid deck zone.");
              const counts = new Map();
              for (const id of ids) {
                if (!/^\d+$/.test(String(id)))
                  throw Error("Invalid card passcode.");
                const c = index.get(String(id)),
                  canonical = c?.id || String(id);
                const e = counts.get(canonical) || {
                  cardId: canonical,
                  name: c?.name || `Unknown card #${id}`,
                  count: 0,
                };
                e.count++;
                counts.set(canonical, e);
              }
              zones[z] = [...counts.values()];
            }
            return {
              id: "ygo:" + d.deckNum,
              name: d.deck_name || type.name,
              date: d.submit_date,
              format,
              tournament:
                d.tournamentName ||
                (d.format.startsWith("Tournament") ? d.format : ""),
              ...zones,
            };
          });
          append(page);
          offset += raw.length;
          if (raw.length < 20) break;
          await sleep(150);
        }
      }
    }
    return { query, checked: Date.now(), decks: result };
  }
  async priceRequest(path, body) {
    const job = this.priceQueue
      .catch(() => {})
      .then(async () => {
        if (Date.now() < this.blockedUntil)
          throw Error(
            `TCGplayer requests paused until ${new Date(this.blockedUntil).toLocaleTimeString()}. Cached prices preserved.`,
          );
        try {
          for (let attempt = 0; attempt < 3; attempt++) {
            const r = await this.fetcher(
              "https://mp-search-api.tcgplayer.com" + path,
              {
                method: body ? "POST" : "GET",
                headers: {
                  Accept: "application/json",
                  "User-Agent": "DeckLab-Windows/0.1",
                  "Content-Type": "application/json",
                },
                ...(body ? { body: JSON.stringify(body) } : {}),
                signal: AbortSignal.timeout(30000),
              },
            );
            if (r.status === 403) {
              this.blockedUntil = Date.now() + 300000;
              throw Error(
                "TCGplayer denied access (HTTP 403). Requests paused for five minutes; cached quotes preserved.",
              );
            }
            const h = r.headers.get("retry-after"),
              delay = h
                ? Number.isFinite(Number(h))
                  ? Math.max(0, Number(h) * 1000)
                  : Math.max(0, Date.parse(h) - Date.now())
                : 1000 * 2 ** attempt;
            if (r.status === 429) {
              if (delay > 8000 || attempt === 2) {
                this.blockedUntil =
                  Date.now() + Math.max(60000, delay || 60000);
                throw Error(
                  "TCGplayer rate limit (HTTP 429). Cached quotes preserved.",
                );
              }
            }
            if (
              (r.status === 429 || [500, 502, 503, 504].includes(r.status)) &&
              attempt < 2 &&
              delay <= 8000
            ) {
              await sleep(Math.max(350, delay));
              continue;
            }
            if (!r.ok)
              throw Error(
                `TCGplayer HTTP ${r.status}. Cached quotes preserved.`,
              );
            const d = await r.json();
            if (d.errors?.length)
              throw Error("TCGplayer could not return this request.");
            return d;
          }
        } finally {
          await sleep(350);
        }
      });
    this.priceQueue = job;
    return job;
  }
  async products(name) {
    if (typeof name !== "string" || name.length < 2 || name.length > 200)
      throw Error("Select a card first.");
    return this.cached("printings-" + key(name) + ".json", async () => {
      let offset = 0,
        out = [],
        seen = new Set();
      while (true) {
        const body = {
          algorithm: "revenue_dismax",
          from: offset,
          size: 50,
          filters: {
            term: { productLineName: ["yugioh"] },
            range: {},
            match: {},
          },
          listingSearch: {
            context: { cart: {} },
            filters: {
              term: { sellerStatus: "Live", channelId: 0 },
              range: { quantity: { gte: 1 } },
              exclude: { channelExclusion: 0 },
            },
          },
          context: { cart: {}, shippingCountry: "US" },
          settings: { useFuzzySearch: false, didYouMean: {} },
          sort: {},
        };
        const raw = await this.priceRequest(
            "/v1/search/request?" +
              new URLSearchParams({ q: JSON.stringify(name), isList: "false" }),
            body,
          ),
          g = raw.results?.[0];
        if (!Array.isArray(g?.results) || !Number.isInteger(g.totalResults))
          throw Error("Unexpected printing search.");
        if (!g.results.length) break;
        let fresh = 0;
        for (const d of g.results) {
          if (seen.has(d.productId)) continue;
          seen.add(d.productId);
          fresh++;
          if (d.sealed || key(d.productName?.split(" (")[0]) !== key(name))
            continue;
          out.push({
            id: d.productId,
            name: d.productName,
            rarity: d.rarityName || "Unknown",
            set: d.setName || "",
            number: d.customAttributes?.number || "",
          });
        }
        if (!fresh) throw Error("Repeated printing page.");
        offset += g.results.length;
        if (offset >= g.totalResults) break;
      }
      return out;
    });
  }
  async skus(productId) {
    if (!Number.isInteger(productId) || productId < 1)
      throw Error("Invalid printing.");
    return this.cached("skus-" + productId + ".json", async () => {
      const raw = await this.priceRequest(`/v2/product/${productId}/details`);
      if (!Array.isArray(raw.skus))
        throw Error("No printing conditions returned.");
      return [
        ...new Map(
          raw.skus
            .filter((s) => s.language === "English")
            .map((s) => [
              s.condition + "|" + s.variant,
              { condition: s.condition, edition: s.variant },
            ]),
        ).values(),
      ];
    });
  }
  async quote(v) {
    let offset = 0,
      best = null,
      seen = new Set();
    while (true) {
      const raw = await this.priceRequest(
          `/v1/product/${v.product.id}/listings`,
          {
            filters: {
              term: {
                sellerStatus: "Live",
                channelId: 0,
                language: ["English"],
                condition: [v.condition],
                printing: [v.edition],
              },
              range: { quantity: { gte: 1 } },
              exclude: { channelExclusion: 0 },
            },
            context: { shippingCountry: "US", cart: {} },
            sort: { field: "price", order: "asc" },
            from: offset,
            size: 50,
            aggregations: ["listingType"],
          },
        ),
        g = raw.results?.[0];
      if (!Array.isArray(g?.results) || !Number.isInteger(g.totalResults))
        throw Error("Unexpected listings response.");
      if (!g.results.length) break;
      let added = 0;
      for (const d of g.results) {
        if (seen.has(d.listingId)) continue;
        seen.add(d.listingId);
        added++;
        if (
          d.productId !== v.product.id ||
          d.verifiedSeller !== true ||
          d.language !== "English" ||
          d.condition !== v.condition ||
          d.printing !== v.edition ||
          d.quantity <= 0 ||
          !Number.isFinite(d.price) ||
          d.price < 0
        )
          continue;
        const q = {
          cents: Math.round(d.price * 100),
          shippingCents: Math.round((d.shippingPrice || 0) * 100),
          seller: d.sellerName,
          checked: Date.now(),
          verified: true,
          condition: v.condition,
          edition: v.edition,
        };
        if (
          !best ||
          q.cents < best.cents ||
          (q.cents === best.cents && q.shippingCents < best.shippingCents)
        )
          best = q;
      }
      if (!added) throw Error("Repeated listings page.");
      offset += g.results.length;
      if (offset >= g.totalResults) break;
    }
    if (!best) throw Error("No matching in-stock verified-seller listing.");
    return best;
  }
}
module.exports = { Providers, categories };
