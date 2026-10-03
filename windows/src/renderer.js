"use strict";
const api = window.deckLab,
  $ = (id) => document.getElementById(id);
const escape = (s) =>
  String(s ?? "").replace(
    /[&<>"']/g,
    (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        c
      ],
  );
const key = (s) =>
  String(s)
    .normalize("NFD")
    .replace(/\p{M}/gu, "")
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]/gu, "");
const money = (c) => "$" + (c / 100).toFixed(2),
  date = (t) => (t ? new Date(t).toLocaleString() : "Never");
let state,
  cards = [],
  types = [],
  view = "explore",
  selectedType = { id: "all", name: "All deck types" },
  selectedBuild = "",
  activeCard = null,
  products = [],
  skus = [];
let query = {
    format: "Master Duel",
    from: new Date(Date.now() - 30 * 86400000).toISOString().slice(0, 10),
    to: new Date().toISOString().slice(0, 10),
    tier: "any",
  },
  required = "",
  excluded = "",
  showHidden = false,
  cardQuery = "",
  cardType = "",
  attribute = "";
let datasetView = localStorage.getItem("datasetView") || "gallery";
const navPaths = {
  explore: "M3 3h7v7H3z M14 3h7v7h-7z M3 14h7v7H3z M14 14h7v7h-7z",
  cards: "M6 3h12v18H6z M9 7h6 M9 11h6 M9 15h4",
  builds: "M3 7l9-4 9 4-9 4z M3 12l9 4 9-4 M3 17l9 4 9-4",
  collection: "M4 8h16v13H4z M3 3h18v5H3z M9 12h6",
  probability: "M4 20V10 M10 20V4 M16 20v-7 M22 20H2",
  files: "M4 4h12l4 4v13H4z M8 4v6h8V4 M8 21v-7h8v7",
};
function icon(id) {
  return `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="${navPaths[id]}"/></svg>`;
}
const nav = [
  ["explore", "Explore decks"],
  ["cards", "Card library"],
  ["builds", "My builds"],
  ["collection", "Collection & prices"],
  ["probability", "Hands & probability"],
  ["files", "Backup & about"],
];
function status(text, error = false) {
  $("status").textContent = text;
  $("status").classList.toggle("error", error);
}
function on(id, event, fn) {
  const el = $(id);
  if (el)
    el.addEventListener(event, async (e) => {
      try {
        await fn(e);
      } catch (error) {
        status(error.message, true);
      }
    });
}
async function busy(button, fn) {
  const old = button?.textContent;
  if (button) {
    button.disabled = true;
    button.textContent = "Working…";
  }
  try {
    return await fn();
  } finally {
    if (button?.isConnected) {
      button.disabled = false;
      button.textContent = old;
    }
  }
}
function select(id, options, value) {
  return `<select id="${id}">${options
    .map((o) => {
      const v = typeof o === "string" ? o : o[0],
        label = typeof o === "string" ? o : o[1];
      return `<option value="${escape(v)}" ${v === value ? "selected" : ""}>${escape(label)}</option>`;
    })
    .join("")}</select>`;
}
function lookup(name, id) {
  return (
    cards.find((c) => id && c.id === String(id)) ||
    cards.find((c) => key(c.name) === key(name))
  );
}
function owned(h) {
  return (
    (h?.unassigned || 0) +
    Object.values(h?.printings || {}).reduce((sum, p) => sum + p.count, 0)
  );
}
function currentBuild() {
  return state.builds.find((d) => d.id === selectedBuild) || state.builds[0];
}
function table(rows, heads) {
  return `<div class="table-wrap"><table><thead><tr>${heads.map((h) => `<th>${h}</th>`).join("")}</tr></thead><tbody>${rows.join("")}</tbody></table></div>`;
}
function cardButton(name, id) {
  return `<button class="link" data-card="${escape(name)}" data-card-id="${escape(id || "")}">${escape(name)}</button>`;
}
async function render() {
  $("navigation").innerHTML = nav
    .map(
      ([id, name], i) =>
        `<button data-view="${id}" class="${view === id ? "active" : ""}" ${view === id ? 'aria-current="page"' : ""}>${icon(id)}<span>${name}</span></button>`,
    )
    .join("");
  document.body.dataset.view = view;
  $("title").textContent = nav.find((n) => n[0] === view)[1];
  if (view === "explore") await explore();
  if (view === "cards") await library();
  if (view === "builds") builds();
  if (view === "collection") collection();
  if (view === "probability") probability();
  if (view === "files") files();
}
async function loadCatalogue() {
  status("Loading deck index…");
  const pack = await api.catalogue(query.format);
  types = pack.data;
  status(
    pack.warning
      ? `Using cached deck index: ${pack.warning}`
      : `${types.length} deck types · index checked ${date(pack.checked)}`,
    !!pack.warning,
  );
}
async function explore() {
  $("content").innerHTML =
    `<div class="toolbar source-controls"><label>Format${select("format", ["Master Duel", "TCG", "OCG", "Genesys", "GOAT", "Edison"], query.format)}</label><label>From<input id="from" type="date" value="${query.from}"></label><label>Through<input id="to" type="date" value="${query.to}"></label><label>Event tier${select(
      "tier",
      [
        ["any", "All events"],
        ["tier-2", "Tier 2+ · Competitive"],
        ["tier-3", "Tier 3 · Premier"],
      ],
      query.tier,
    )}</label><button class="primary" id="fetch-decks">Refresh dataset</button></div>
 <div class="split"><div class="panel deck-index"><div class="index-heading"><span>DECK INDEX</span><span>${types.length}</span></div><input id="deck-types-search" placeholder="Find a deck type" aria-label="Find a deck type"><div class="row section-gap"><button id="hidden">${showHidden ? "Hide hidden" : "Show hidden"}</button><button id="hide-type">Hide selected</button></div><div id="type-index" class="index"></div></div><div class="dataset-column"><details class="card-filters" ${required || excluded ? "open" : ""}><summary>Card filters <span>Include / exclude exact cards</span></summary><div class="toolbar"><label>Must include (separate with ;) <input id="include" value="${escape(required)}" placeholder="Exact card names"></label><label>Must exclude<input id="exclude" value="${escape(excluded)}" placeholder="Exact card names"></label><button id="apply-filters">Apply filters</button></div></details><div id="dataset"></div></div></div>`;
  $("tier").disabled = query.format === "Master Duel";
  renderTypes();
  await dataset();
  on("format", "change", async (e) => {
    query.format = e.target.value;
    selectedType = { id: "all", name: "All deck types" };
    await loadCatalogue();
    if (view === "explore") await explore();
  });
  on("from", "change", (e) => (query.from = e.target.value));
  on("to", "change", (e) => (query.to = e.target.value));
  on("tier", "change", (e) => (query.tier = e.target.value));
  on("deck-types-search", "input", () => renderTypes());
  on("hidden", "click", async () => {
    showHidden = !showHidden;
    await explore();
  });
  on("hide-type", "click", async () => {
    if (selectedType.id === "all") throw Error("Select a deck type first.");
    state = await api.toggle("hidden", query.format + "|" + selectedType.id);
    renderTypes();
  });
  on("fetch-decks", "click", async (e) =>
    busy(e.target, async () => {
      status("Loading complete dataset…");
      await api.decks({ ...query, type: selectedType });
      state = await api.load();
      await dataset();
      status("Dataset saved. Available offline after restart.");
    }),
  );
  on("apply-filters", "click", async () => {
    required = $("include").value;
    excluded = $("exclude").value;
    await dataset();
  });
}
function renderTypes() {
  const text = $("deck-types-search").value.toLowerCase();
  const visible = [{ id: "all", name: "All deck types" }, ...types].filter(
    (t) =>
      t.name.toLowerCase().includes(text) &&
      (showHidden || !state.hidden.includes(query.format + "|" + t.id)),
  );
  $("type-index").innerHTML = visible
    .map(
      (t) =>
        `<button data-type="${escape(t.id)}" class="${t.id === selectedType.id ? "selected" : ""}">${state.favorites.includes(query.format + "|" + t.id) ? "★ " : ""}${escape(t.name)}${state.hidden.includes(query.format + "|" + t.id) ? " · hidden" : ""}</button>`,
    )
    .join("");
}
async function dataset() {
  const snap = state.snapshot;
  if (!snap) {
    $("dataset").innerHTML =
      '<div class="empty welcome"><span class="eyebrow">YOUR NEXT BUILD STARTS HERE</span><h2>Know your deck.<br>Find your edge.</h2><p>Choose a deck type on the left, then refresh<br>to explore card choices across submitted lists.</p><span class="empty-step">01 &nbsp; Choose a format &nbsp; / &nbsp; 02 &nbsp; Select a deck &nbsp; / &nbsp; 03 &nbsp; Explore</span></div>';
    return;
  }
  const rows = await api.aggregate(snap.decks, required, excluded);
  if (view !== "explore" || !$("dataset")) return;
  const totalCopies = rows.reduce((n, r) => n + r.target, 0),
    covered = rows.reduce((n, r) => n + Math.min(r.target, r.owned), 0);
  const art = rows
    .map((r) => lookup(r.name, r.cardId))
    .filter((c) => c?.image)
    .sort(
      (a, b) =>
        Number(key(b.name).includes(key(snap.query.type.name))) -
        Number(key(a.name).includes(key(snap.query.type.name))),
    )
    .slice(0, 3);
  $("dataset").innerHTML = `
  <div class="deck-hero"><div class="hero-copy"><div class="hero-kicker"><span class="live-dot"></span>${escape(snap.query.format)} <span class="hero-divider">/</span> SAVED DATASET</div><h2>${escape(snap.query.type.name)}</h2><p>Study the field.<br>Build your next advantage.</p><div class="hero-actions"><button id="save-average" class="primary">Save average build <span aria-hidden="true">↗</span></button><button id="favorite" aria-label="Favorite selected deck type">☆ Favorite</button></div></div><div class="hero-art" aria-hidden="true">${art.map((c) => `<img src="${escape(c.image)}" alt="">`).join("")}</div></div>
  <div class="dataset-caption"><span>${escape(snap.query.from)} — ${escape(snap.query.to)}</span><span>Updated ${date(snap.checked)}</span></div>
  <div class="metrics dataset-metrics"><div class="metric"><span>Lists in dataset</span><strong>${snap.decks.length}</strong><small>Before card filters</small></div><div class="metric"><span>Unique cards</span><strong>${rows.length}</strong><small>In matching lists</small></div><div class="metric"><span>Collection coverage</span><strong>${totalCopies ? Math.round((100 * covered) / totalCopies) : 0}<em>%</em></strong><small>${covered} / ${totalCopies} target copies</small></div></div>
  <div class="composition-heading"><div><h3>Deck composition</h3><p>Average copies across matching lists · all zones</p></div><div class="segmented" aria-label="Composition view"><button id="gallery-view" aria-pressed="${datasetView === "gallery"}">Gallery</button><button id="table-view" aria-pressed="${datasetView === "table"}">Table</button></div></div>
  ${
    rows.length
      ? datasetView === "table"
        ? table(
            rows.map(
              (r) =>
                `<tr><td>${cardButton(r.name, r.cardId)}</td><td class="num">${(r.inclusion * 100).toFixed(0)}%</td><td class="num">${r.average.toFixed(2)}</td><td class="num">${r.owned}</td><td class="num">${r.missing}</td></tr>`,
            ),
            ["Card", "Included", "Mean", "Owned", "Missing"],
          )
        : `<div class="composition-grid">${rows
            .map((r) => {
              const c = lookup(r.name, r.cardId);
              return `<button class="composition-card" data-card="${escape(r.name)}" data-card-id="${escape(r.cardId || "")}"><div class="card-art">${c?.image ? `<img loading="lazy" src="${escape(c.image)}" alt="${escape(r.name)}">` : '<div class="art-placeholder">DECK LAB</div>'}<span class="copy-badge">${r.average.toFixed(1)}<small> AVG</small></span></div><div class="card-caption"><strong>${escape(r.name)}</strong><div><span>${Math.round(r.inclusion * 100)}% inclusion</span><span class="${r.missing ? "needed" : "covered"}">${r.missing ? `${r.missing} missing` : "Covered"}</span></div><progress value="${Math.min(r.target, r.owned)}" max="${Math.max(1, r.target)}" aria-label="Owned copies toward ${escape(r.name)} target"></progress></div></button>`;
            })
            .join("")}</div>`
      : '<div class="empty"><h3>No matching lists</h3><p>Adjust your include/exclude filters to expand the sample.</p></div>'
  }`;
  for (const mode of ["gallery", "table"])
    on(mode + "-view", "click", async () => {
      datasetView = mode;
      localStorage.setItem("datasetView", mode);
      await dataset();
    });
  on("favorite", "click", async () => {
    state = await api.toggle("favorites", query.format + "|" + selectedType.id);
    renderTypes();
  });
  on("save-average", "click", async () => {
    if (!rows.length) throw Error("No matching cards to save.");
    const d = {
      id: crypto.randomUUID(),
      name: snap.query.type.name + " · average",
      format: snap.query.format,
      main: [],
      extra: [],
      side: [],
    };
    const sample = rows[0].included / rows[0].inclusion;
    for (const r of rows)
      for (const z of ["main", "extra", "side"]) {
        const count = Math.round(r[z] / sample);
        if (count) d[z].push({ name: r.name, cardId: r.cardId, count });
      }
    state = await api["save-build"](d);
    selectedBuild = d.id;
    status("Average build saved. Rounded averages may not form a legal deck.");
  });
}
async function library() {
  $("content").innerHTML =
    `<div class="toolbar"><label>Search name or effect<input id="card-query" value="${escape(cardQuery)}" placeholder="Search cards…"></label><label>Card type${select("card-type", [["", "All types"], "Monster", "Spell", "Trap"], cardType)}</label><label>Attribute${select("attribute", [["", "All attributes"], "DARK", "LIGHT", "EARTH", "WIND", "FIRE", "WATER", "DIVINE"], attribute)}</label><button id="refresh-cards">Refresh card database</button></div><p class="muted">Showing up to 250 matches. Open a card to see its text, edit ownership or add it to a build.</p><div class="grid" id="card-grid"></div>`;
  const results = await api["card-filter"](cards, {
    text: cardQuery,
    type: cardType,
    attribute,
  });
  $("card-grid").innerHTML = results
    .map(
      (c) =>
        `<button class="card-tile" data-card="${escape(c.name)}" data-card-id="${escape(c.id)}"><img loading="lazy" src="${escape(c.image)}" alt="${escape(c.name)}"><span>${escape(c.name)}</span><small>${escape(c.type)} · ${owned(state.collection[key(c.name)])} owned</small></button>`,
    )
    .join("");
  on("card-query", "change", async (e) => {
    cardQuery = e.target.value;
    await library();
  });
  on("card-type", "change", async (e) => {
    cardType = e.target.value;
    await library();
  });
  on("attribute", "change", async (e) => {
    attribute = e.target.value;
    await library();
  });
  on("refresh-cards", "click", async (e) =>
    busy(e.target, async () => {
      const p = await api.cards(true);
      cards = p.data;
      await library();
      status(
        p.warning || `Card database updated ${date(p.checked)}`,
        !!p.warning,
      );
    }),
  );
}
async function showCard(name, id) {
  activeCard = lookup(name, id) || {
    name,
    id: id || "",
    description: "Card information unavailable. Refresh the card database.",
    image: "",
  };
  products = [];
  skus = [];
  const c = activeCard,
    h = state.collection[key(c.name)];
  $("card-detail").innerHTML =
    `<div class="detail"><div>${c.image ? `<img src="${escape(c.image)}" alt="${escape(c.name)}">` : ""}</div><div><p class="eyebrow">CARD DETAILS</p><h2>${escape(c.name)}</h2><span class="pill">${escape(c.type || "")} · ${escape(c.attribute || "")}</span><p>${escape(c.description)}</p><div class="toolbar"><label>Unspecified owned copies<input id="owned-count" type="number" min="0" max="9999" value="${h?.unassigned || 0}"></label><button id="save-owned">Save ownership</button></div><small>Unspecified copies count toward completion but remain unpriced. Avoid counting the same copies here and in a printing.</small><div class="toolbar section-gap"><label>Add to build${select(
      "add-build",
      state.builds.map((d) => [d.id, d.name]),
      selectedBuild,
    )}</label><label>Zone${select("add-zone", ["main", "extra", "side"], "main")}</label><button id="add-card">Add one</button></div><button id="load-printings">Choose printing & condition</button><div id="printing-details" class="section-gap"></div></div></div>`;
  if (!$("card-dialog").open) $("card-dialog").showModal();
  on("save-owned", "click", async () => {
    state = await api.owned(c.name, Number($("owned-count").value));
    status("Shared ownership saved.");
    await render();
  });
  on("add-card", "click", async () => {
    const d = structuredClone(
      state.builds.find((d) => d.id === $("add-build").value),
    );
    if (!d) throw Error("Create a build first.");
    const z = $("add-zone").value,
      e = d[z].find((e) => key(e.name) === key(c.name));
    if (e) e.count++;
    else d[z].push({ name: c.name, cardId: c.id, count: 1 });
    state = await api["save-build"](d);
    status("Card added to " + d.name);
  });
  on("load-printings", "click", async (e) =>
    busy(e.target, async () => {
      const pack = await api.products(c.name);
      products = pack.data;
      if (!products.length) throw Error("No matching printings returned.");
      $("printing-details").innerHTML = `<label>Printing${select(
        "product",
        products.map((p) => [
          String(p.id),
          `${p.rarity} · ${p.set} · ${p.number}`,
        ]),
        String(products[0].id),
      )}</label><div id="sku-details" class="section-gap"></div>`;
      on("product", "change", loadSkus);
      await loadSkus();
      if (pack.warning) status(pack.warning, true);
    }),
  );
}
async function loadSkus() {
  const p = products.find((p) => String(p.id) === $("product").value),
    pack = await api.skus(p.id);
  skus = pack.data;
  if (!skus.length) throw Error("No English conditions available.");
  $("sku-details").innerHTML = `<label>Condition & edition${select(
    "sku",
    skus.map((s, i) => [String(i), `${s.condition} · ${s.edition}`]),
    "0",
  )}</label><label class="section-gap">Copies owned in this printing<input id="printing-count" type="number" min="0" max="9999" value="0"></label><button id="save-printing" class="section-gap">Save printing & set buy target</button><p class="muted">Prices update only when you press Update prices in Collection & prices.</p>`;
  const updateCount = () => {
    const s = skus[Number($("sku").value)],
      id = `${p.id}|${s.condition}|${s.edition}|English`;
    $("printing-count").value =
      state.collection[key(activeCard.name)]?.printings[id]?.count || 0;
  };
  updateCount();
  on("sku", "change", updateCount);
  on("save-printing", "click", async () => {
    const s = skus[Number($("sku").value)];
    state = await api.printing(
      activeCard.name,
      { product: p, ...s },
      Number($("printing-count").value),
    );
    status("Printing and target saved.");
    await render();
  });
  if (pack.warning) status(pack.warning, true);
}
function builds() {
  const d = currentBuild();
  if (d) selectedBuild = d.id;
  $("content").innerHTML = `<div class="toolbar"><label>Saved build${select(
    "build-picker",
    state.builds.map((d) => [d.id, d.name]),
    selectedBuild,
  )}</label><button id="new-build" class="primary">New build</button><button id="import-ydk">Import YDK</button><button id="export-ydk">Export YDK</button></div><div id="build-detail"></div>`;
  on("build-picker", "change", async (e) => {
    selectedBuild = e.target.value;
    builds();
  });
  on("new-build", "click", async () => {
    const d = {
      id: crypto.randomUUID(),
      name: "Untitled build",
      format: "TCG",
      main: [],
      extra: [],
      side: [],
    };
    state = await api["save-build"](d);
    selectedBuild = d.id;
    builds();
  });
  on("import-ydk", "click", async () => {
    const s = await api["import-ydk"]();
    if (s) {
      state = s;
      selectedBuild = s.builds.at(-1).id;
      builds();
      status("YDK imported.");
    }
  });
  on("export-ydk", "click", async () => {
    if (await api["export-ydk"](selectedBuild)) status("YDK exported.");
  });
  if (!d) {
    $("build-detail").innerHTML =
      '<div class="empty">Create a build or import a YDK file.<br>Add cards from the Card library.</div>';
    return;
  }
  const totals = ["main", "extra", "side"].map((z) =>
    d[z].reduce((n, e) => n + e.count, 0),
  );
  const needed = {};
  for (const z of ["main", "extra", "side"])
    for (const e of d[z])
      needed[key(e.name)] = (needed[key(e.name)] || 0) + e.count;
  let missingCopies = 0,
    missingCost = 0,
    unpriced = 0;
  for (const [k, n] of Object.entries(needed)) {
    const h = state.collection[k],
      missing = Math.max(0, n - owned(h)),
      q = state.quotes[h?.target];
    missingCopies += missing;
    if (q?.verified) missingCost += missing * q.cents;
    else unpriced += missing;
  }
  $("build-detail").innerHTML =
    `<div class="toolbar"><label>Name<input id="build-name" value="${escape(d.name)}"></label><label>Format${select("build-format", ["Master Duel", "TCG", "OCG", "Genesys", "GOAT", "Edison"], d.format)}</label><button id="rename-build">Save details</button></div><div class="metrics">${totals.map((n, i) => `<div class="metric"><strong>${n}</strong><span>${["Main", "Extra", "Side"][i]}</span></div>`).join("")}</div><p class="notice">${missingCopies} copies missing across all zones · ${money(missingCost)} cached cost to finish${unpriced ? ` + ${unpriced} unpriced copies` : ""}. Shipping and tax excluded.</p><p class="muted">${totals[0] < 40 || totals[0] > 60 || totals[1] > 15 || totals[2] > 15 ? "Deck size is outside standard 40–60 / 15 / 15 limits. " : ""}This preview does not validate format banlists. Add cards through the Card library.</p>${[
      "main",
      "extra",
      "side",
    ]
      .map(
        (z) =>
          `<h3>${z.toUpperCase()}</h3>${table(
            d[z].map(
              (e, i) =>
                `<tr><td>${cardButton(e.name, e.cardId)}</td><td><input aria-label="Copies of ${escape(e.name)} in ${z}" type="number" min="0" max="99" value="${e.count}" data-entry="${z}|${i}"></td><td>${owned(state.collection[key(e.name)])} owned</td><td>${Math.max(0, needed[key(e.name)] - owned(state.collection[key(e.name)]))} missing</td></tr>`,
            ),
            ["Card", "Copies", "Collection", "Missing across zones"],
          )}`,
      )
      .join("")}`;
  on("rename-build", "click", async () => {
    const next = structuredClone(d);
    next.name = $("build-name").value.trim() || "Untitled build";
    next.format = $("build-format").value;
    state = await api["save-build"](next);
    builds();
    status("Build saved.");
  });
}
function collection() {
  const holdings = Object.values(state.collection),
    quotes = Object.values(state.quotes).filter((q) => q.verified),
    latest = Math.max(0, ...quotes.map((q) => q.checked));
  $("content").innerHTML =
    `<div class="notice">Manual pricing · missing or older than 24 hours only.<br><small>TCGplayer access can return HTTP 403. Cached values remain available; shipping and tax are excluded.</small></div><div class="toolbar"><button class="primary" id="update-prices">Update prices</button><span class="muted">Last successful quote: ${date(latest)}. Individual quotes may be older.</span></div><div class="metrics"><div class="metric"><strong>${holdings.length}</strong><span>Cards tracked</span></div><div class="metric"><strong>${holdings.reduce((s, h) => s + owned(h), 0)}</strong><span>Copies owned</span></div></div>${
      holdings.length
        ? table(
            holdings.map((h) => {
              let value = 0,
                unknown = h.unassigned;
              for (const [id, p] of Object.entries(h.printings)) {
                const q = state.quotes[id];
                if (q?.verified) value += q.cents * p.count;
                else unknown += p.count;
              }
              return `<tr><td>${cardButton(h.name, "")}</td><td class="num">${owned(h)}</td><td>${money(value)}${unknown ? ` + ${unknown} unpriced` : ""}</td><td>${Object.entries(
                h.printings,
              )
                .map(([id, p]) => {
                  const q = state.quotes[id];
                  return `<div>${escape(p.variant.product.rarity)} · ${escape(p.variant.condition)} · ${p.count} owned<br><small>${q ? `${money(q.cents)} · ${date(q.checked)}${Date.now() - q.checked >= 86400000 ? " · stale" : ""}` : "No quote"} ${escape(state.priceErrors[id] || "")}</small></div>`;
                })
                .join("")}</td></tr>`;
            }),
            ["Card", "Owned", "Cached item value", "Printings & last check"],
          )
        : '<div class="empty">Your collection is empty. Open a card in the library to record owned copies.</div>'
    }`;
  on("update-prices", "click", async (e) =>
    busy(e.target, async () => {
      status("Updating missing or stale prices…");
      const result = await api.prices();
      state = result.state;
      collection();
      status(result.message);
    }),
  );
}
function probability() {
  const d = currentBuild();
  if (d) selectedBuild = d.id;
  const saved = state.buckets[d?.id] || [
    { name: "Starters", cards: [] },
    { name: "Extenders", cards: [] },
  ];
  $("content").innerHTML =
    `<div class="two"><div class="panel"><p class="eyebrow">EXACT HYPERGEOMETRIC</p><h2>Find your opening odds</h2><div class="toolbar"><label>Deck size<input type="number" id="population" value="40" min="1" max="200"></label><label>Desired copies<input type="number" id="successes" value="3" min="0"></label><label>Hand size<input type="number" id="hand" value="5" min="0"></label><label>At least<input type="number" id="minimum" value="1" min="0"></label></div><button class="primary" id="calculate">Calculate</button><div id="hyper-result" class="big-result">—</div><p class="muted">Drawing without replacement. Exact probability of opening at least the requested number of copies.</p></div><div class="panel"><p class="eyebrow">BUCKETS & COMBO REQUIREMENTS</p><h2>Open the pieces you need</h2><label>Build${select(
      "combo-build",
      state.builds.map((d) => [d.id, d.name]),
      selectedBuild,
    )}</label><div id="buckets" class="section-gap">${Array.from({ length: 4 }, (_, i) => `<div class="bucket"><label>Bucket ${i + 1} name<input id="bucket-name-${i}" value="${escape(saved[i]?.name || "")}"></label><label>Exact card names · one per line<textarea id="bucket-cards-${i}">${escape((saved[i]?.cards || []).join("\n"))}</textarea></label></div>`).join("")}</div><div class="toolbar"><label>Hand<input type="number" id="combo-hand" value="5" min="0" max="10"></label><label>Requirement${select(
      "combo-mode",
      [
        ["all", "At least one from every bucket"],
        ["any", "At least one from any bucket"],
      ],
      "all",
    )}</label></div><button class="primary" id="combo-calculate">Save buckets & calculate</button><div id="combo-result" class="big-result">—</div><p class="muted">Blank buckets are ignored. Only main-deck copies count. Overlapping buckets may be satisfied by the same card; this measures opening pieces, not whether an in-game combo is legal or executable.</p></div></div>`;
  on("calculate", "click", async () => {
    $("hyper-result").textContent =
      (
        100 *
        (await api.hyper(
          Number($("population").value),
          Number($("successes").value),
          Number($("hand").value),
          Number($("minimum").value),
        ))
      ).toFixed(2) + "%";
  });
  on("combo-build", "change", (e) => {
    selectedBuild = e.target.value;
    probability();
  });
  on("combo-calculate", "click", async () => {
    const buckets = Array.from({ length: 4 }, (_, i) => ({
      name: $("bucket-name-" + i).value.trim(),
      cards: $("bucket-cards-" + i)
        .value.split("\n")
        .map((s) => s.trim())
        .filter(Boolean),
    })).filter((b) => b.cards.length);
    const result = await api.combo(
      selectedBuild,
      buckets.map((b) => b.cards),
      Number($("combo-hand").value),
      $("combo-mode").value,
    );
    state = await api["save-buckets"](selectedBuild, buckets);
    $("combo-result").textContent = (100 * result).toFixed(2) + "%";
    status("Buckets saved to this build.");
  });
}
function files() {
  $("content").innerHTML =
    `<div class="panel"><p class="eyebrow">YOUR LOCAL WORKSPACE</p><h2>Backup & restore</h2><p>Export your Windows collection, builds, saved buckets, hidden types and cached deck snapshot. Restore validates the backup before replacing your workspace and keeps a copy of the previous data.</p><div class="toolbar"><button id="backup" class="primary">Export JSON backup</button><button id="restore">Restore Windows backup</button></div><p class="muted">Windows backups use their own schema. Exchange individual decks with the macOS app using YDK files.</p></div><div class="panel section-gap"><h2>Windows preview 0.2</h2><p>Includes deck exploration across six formats, exact-card include/exclude filters, hidden types and favorites, card artwork and search, shared collection tracking, printing selection, manual price updates, saved builds, YDK exchange, hypergeometric odds and saved combo buckets.</p><p class="muted">The macOS app additionally includes match logs, side plans, build revisions, allocation reservations, trends, shopping aggregation, conditional probability optimization, HTML/PNG sharing and undo history. These tools are not yet ported. Prices depend on external access and may be unavailable.</p></div>`;
  on("backup", "click", async () => {
    if (await api.backup()) status("Backup exported.");
  });
  on("restore", "click", async () => {
    const next = await api.restore();
    if (next) {
      state = next;
      await render();
      status("Backup restored.");
    }
  });
}
document.addEventListener("click", async (e) => {
  try {
    const v = e.target.closest("[data-view]"),
      t = e.target.closest("[data-type]"),
      c = e.target.closest("[data-card]");
    if (v) {
      view = v.dataset.view;
      await render();
    }
    if (t) {
      selectedType = types.find((x) => x.id === t.dataset.type) || {
        id: "all",
        name: "All deck types",
      };
      renderTypes();
    }
    if (c) await showCard(c.dataset.card, c.dataset.cardId);
  } catch (error) {
    status(error.message, true);
  }
});
document.addEventListener("change", async (e) => {
  if (!e.target.dataset.entry) return;
  try {
    const [zone, i] = e.target.dataset.entry.split("|"),
      d = structuredClone(currentBuild());
    d[zone][Number(i)].count = Number(e.target.value);
    d[zone] = d[zone].filter((x) => x.count !== 0);
    state = await api["save-build"](d);
    builds();
  } catch (error) {
    status(error.message, true);
  }
});
$("close-dialog").addEventListener("click", () => $("card-dialog").close());
window.deckLabReady = (async () => {
  state = await api.load();
  if (state.snapshot) {
    query = structuredClone(state.snapshot.query);
    selectedType = query.type;
  }
  await render();
  try {
    const p = await api.cards();
    cards = p.data;
    if (p.warning) status("Using cached cards: " + p.warning, true);
  } catch (e) {
    status(e.message, true);
  }
  try {
    await loadCatalogue();
    if (view === "explore") await explore();
  } catch (e) {
    status(e.message, true);
  }
})();

function applyTheme(theme) {
  document.documentElement.dataset.theme = theme;
  localStorage.setItem("theme", theme);
  $("theme-toggle").textContent = theme === "dark" ? "Light mode" : "Dark mode";
  $("theme-toggle").setAttribute(
    "aria-label",
    `Switch to ${theme === "dark" ? "light" : "dark"} mode`,
  );
}
applyTheme(localStorage.getItem("theme") || "dark");
$("theme-toggle").addEventListener("click", () =>
  applyTheme(
    document.documentElement.dataset.theme === "dark" ? "light" : "dark",
  ),
);
async function quickSearch() {
  view = "cards";
  await render();
  $("card-query")?.focus();
}
$("quick-search").addEventListener("click", () =>
  quickSearch().catch((e) => status(e.message, true)),
);
document.addEventListener("keydown", (e) => {
  if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "k") {
    e.preventDefault();
    if ($("card-dialog").open) $("card-dialog").close();
    quickSearch().catch((error) => status(error.message, true));
  }
});
