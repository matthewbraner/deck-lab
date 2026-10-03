"use strict";
const {
  app,
  BrowserWindow,
  ipcMain,
  dialog,
  session,
  Menu,
} = require("electron");
const fs = require("node:fs/promises"),
  path = require("node:path"),
  os = require("node:os");
const { pathToFileURL } = require("node:url");
const core = require("./core.cjs"),
  { Store } = require("./store.cjs"),
  { Providers } = require("./providers.cjs");
let window, store, providers, state;
const smoke = process.argv.includes("--smoke-test");
const page = pathToFileURL(path.join(__dirname, "index.html")).href;
let mutations = Promise.resolve();
function mutate(fn) {
  const task = mutations
    .catch(() => {})
    .then(async () => {
      const next = structuredClone(state);
      const result = await fn(next);
      await store.save(next);
      state = next;
      return result ?? state;
    });
  mutations = task;
  return task;
}
function handle(name, fn) {
  ipcMain.handle(name, async (event, ...args) => {
    if (event.sender !== window.webContents || event.senderFrame?.url !== page)
      throw Error("Untrusted request.");
    return fn(...args);
  });
}
function printingID(v) {
  if (
    !Number.isInteger(v?.product?.id) ||
    v.product.id < 1 ||
    typeof v.condition !== "string" ||
    typeof v.edition !== "string"
  )
    throw Error("Invalid printing.");
  return `${v.product.id}|${v.condition}|${v.edition}|English`;
}
function register() {
  handle("load", () => state);
  handle("cards", (force) => providers.cards(force === true));
  handle("catalogue", (format) => providers.catalogue(format));
  let loadingDecks = false;
  handle("decks", async (query) => {
    if (loadingDecks) throw Error("A dataset refresh is already running.");
    loadingDecks = true;
    try {
      const snapshot = await providers.decks(query);
      await mutate((s) => {
        s.snapshot = snapshot;
      });
      return snapshot;
    } finally {
      loadingDecks = false;
    }
  });
  handle("aggregate", (decks, yes, no) =>
    core.aggregate(core.filterDecks(decks, yes, no), state.collection),
  );
  handle("card-filter", (cards, query) =>
    cards
      .filter(
        (c) =>
          (!query.text ||
            `${c.name} ${c.description}`
              .toLowerCase()
              .includes(query.text.toLowerCase())) &&
          (!query.type || c.type.includes(query.type)) &&
          (!query.attribute || c.attribute === query.attribute),
      )
      .slice(0, 250),
  );
  handle("owned", (name, count) =>
    mutate((s) => {
      if (
        typeof name !== "string" ||
        !Number.isInteger(count) ||
        count < 0 ||
        count > 9999
      )
        throw Error("Use a whole number from 0 to 9999.");
      const k = core.key(name);
      s.collection[k] ??= { name, unassigned: 0, printings: {}, target: "" };
      s.collection[k].unassigned = count;
    }),
  );
  handle("toggle", (field, value) =>
    mutate((s) => {
      if (!["hidden", "favorites"].includes(field) || typeof value !== "string")
        throw Error("Invalid preference.");
      s[field] = s[field].includes(value)
        ? s[field].filter((x) => x !== value)
        : [...s[field], value];
    }),
  );
  handle("save-build", (deck) =>
    mutate((s) => {
      core.validateState({ ...core.emptyState(), builds: [deck] });
      const at = s.builds.findIndex((d) => d.id === deck.id);
      if (at >= 0) s.builds[at] = deck;
      else s.builds.push(deck);
    }),
  );
  handle("import-ydk", async () => {
    const picked = await dialog.showOpenDialog(window, {
      filters: [{ name: "YGO deck", extensions: ["ydk"] }],
      properties: ["openFile"],
    });
    if (picked.canceled) return null;
    const text = await fs.readFile(picked.filePaths[0], "utf8");
    const deck = core.parseYdk(text, (await providers.cards()).data);
    deck.name = path.basename(picked.filePaths[0], ".ydk");
    return mutate((s) => {
      s.builds.push(deck);
    });
  });
  handle("export-ydk", async (id) => {
    const d = state.builds.find((x) => x.id === id);
    if (!d) throw Error("Select a saved build.");
    const text = core.toYdk(d);
    const pick = await dialog.showSaveDialog(window, {
      defaultPath: "deck.ydk",
      filters: [{ name: "YGO deck", extensions: ["ydk"] }],
    });
    if (!pick.canceled) await fs.writeFile(pick.filePath, text);
    return !pick.canceled;
  });
  handle("backup", async () => {
    const p = await dialog.showSaveDialog(window, {
      defaultPath: "deck-lab-windows-backup.json",
      filters: [{ name: "JSON backup", extensions: ["json"] }],
    });
    if (!p.canceled)
      await fs.writeFile(p.filePath, JSON.stringify(state, null, 2));
    return !p.canceled;
  });
  handle("restore", async () => {
    const p = await dialog.showOpenDialog(window, {
      filters: [{ name: "Windows Deck Lab backup", extensions: ["json"] }],
      properties: ["openFile"],
    });
    if (p.canceled) return null;
    const candidate = core.validateState(
      JSON.parse(await fs.readFile(p.filePaths[0], "utf8")),
    );
    const answer = await dialog.showMessageBox(window, {
      type: "question",
      buttons: ["Cancel", "Restore backup"],
      defaultId: 0,
      cancelId: 0,
      message: "Replace this Windows workspace?",
      detail:
        "The current workspace will first be saved as before-restore.json in your app data folder.",
    });
    if (answer.response !== 1) return null;
    return mutate(async (s) => {
      await store.write("before-restore.json", s);
      Object.keys(s).forEach((k) => delete s[k]);
      Object.assign(s, candidate);
    });
  });
  handle("hyper", (n, k, h, min) => core.hypergeometric(n, k, h, min));
  handle("combo", (id, buckets, hand, mode) => {
    const d = state.builds.find((d) => d.id === id);
    if (!d) throw Error("Choose a saved build.");
    return core.comboProbability(d, buckets, hand, mode);
  });
  handle("save-buckets", (id, buckets) =>
    mutate((s) => {
      if (
        !state.builds.some((d) => d.id === id) ||
        !Array.isArray(buckets) ||
        buckets.length > 4 ||
        !buckets.every(
          (b) =>
            typeof b.name === "string" &&
            Array.isArray(b.cards) &&
            b.cards.every((c) => typeof c === "string"),
        )
      )
        throw Error("Invalid buckets.");
      s.buckets[id] = buckets;
    }),
  );
  handle("products", (name) => providers.products(name));
  handle("skus", (id) => providers.skus(id));
  handle("printing", (name, v, count) =>
    mutate((s) => {
      if (!Number.isInteger(count) || count < 0 || count > 9999)
        throw Error("Use a whole number from 0 to 9999.");
      const id = printingID(v),
        k = core.key(name);
      s.collection[k] ??= { name, unassigned: 0, printings: {}, target: "" };
      s.collection[k].printings[id] = { variant: v, count };
      s.collection[k].target = id;
    }),
  );
  let updating = false;
  handle("prices", async () => {
    if (updating) throw Error("A price update is already running.");
    updating = true;
    let checked = 0,
      skipped = 0,
      failed = 0;
    try {
      const variants = new Map(
        Object.values(state.collection).flatMap((h) =>
          Object.entries(h.printings)
            .filter(([id, p]) => p.count > 0 || id === h.target)
            .map(([id, p]) => [id, p.variant]),
        ),
      );
      for (const [id, v] of variants) {
        if (core.fresh(state.quotes[id])) {
          skipped++;
          continue;
        }
        try {
          const q = await providers.quote(v);
          await mutate((s) => {
            s.quotes[id] = q;
            delete s.priceErrors[id];
          });
          checked++;
        } catch (e) {
          await mutate((s) => {
            s.priceErrors[id] = e.message;
          });
          failed++;
          if (providers.blockedUntil > Date.now()) break;
        }
      }
      return {
        state,
        message: `${checked} updated · ${skipped} already fresh · ${failed} failed. ${variants.size ? "" : "Choose a printing first."}`,
      };
    } finally {
      updating = false;
    }
  });
}
app
  .whenReady()
  .then(async () => {
    const directory = smoke
      ? await fs.mkdtemp(path.join(os.tmpdir(), "deck-lab-smoke-"))
      : path.join(app.getPath("appData"), "DeckLabWindows");
    store = new Store(directory);
    providers = new Providers(store);
    try {
      state = await store.load();
    } catch (e) {
      dialog.showErrorBox(
        "Workspace could not be opened",
        "Existing data was not changed. " + e.message,
      );
      app.exit(1);
      return;
    }
    if (smoke) {
      await store.write("cards-cache.json", {
        checked: Date.now(),
        data: [
          {
            id: "1",
            name: "Test Dragon",
            description: "Smoke fixture",
            type: "Normal Monster",
            attribute: "DARK",
            aliases: [],
            formats: ["TCG"],
            image: "",
          },
        ],
      });
      await store.write("md-types-cache.json", {
        checked: Date.now(),
        data: [{ id: "fixture", name: "Test" }],
      });
    }
    Menu.setApplicationMenu(null);
    window = new BrowserWindow({
      width: 1400,
      height: 940,
      minWidth: 1040,
      minHeight: 700,
      title: "Deck Lab",
      icon: path.join(__dirname, "icon.png"),
      backgroundColor: "#101416",
      show: !smoke,
      webPreferences: {
        preload: path.join(__dirname, "preload.cjs"),
        contextIsolation: true,
        nodeIntegration: false,
        sandbox: true,
      },
    });
    session.defaultSession.setPermissionRequestHandler((_wc, _permission, cb) =>
      cb(false),
    );
    window.webContents.setWindowOpenHandler(() => ({ action: "deny" }));
    window.webContents.on("will-navigate", (event) => event.preventDefault());
    register();
    await window.loadFile(path.join(__dirname, "index.html"));
    if (smoke) {
      try {
        await window.webContents.executeJavaScript("window.deckLabReady");
        const text = await window.webContents.executeJavaScript(
          "document.body.innerText",
        );
        if (!text.includes("Explore decks") || !text.includes("Test"))
          throw Error("Renderer failed to initialize");
        await window.webContents.executeJavaScript(`(async () => {
          document.querySelector('.card-filters summary').click();
          await new Promise(resolve => setTimeout(resolve, 100));
          if (!document.querySelector('.card-filters').open) throw Error('Card filters closed during interaction');
          const input = document.getElementById('include');
          input.value = 'Test Dragon';
          const theme = document.documentElement.dataset.theme;
          document.getElementById('theme-toggle').click();
          await new Promise(resolve => setTimeout(resolve, 100));
          if (document.documentElement.dataset.theme === theme) throw Error('Theme control did not switch');
          if (document.getElementById('include').value !== 'Test Dragon') throw Error('Theme switch discarded filter input');
        })()`);
        await store.save(state);
        console.log(
          "Electron startup, isolated IPC, filter interaction, theme state and persistence smoke test passed.",
        );
        await fs.rm(directory, { recursive: true, force: true });
        app.exit(0);
      } catch (e) {
        console.error(e);
        app.exit(1);
      }
    }
  })
  .catch((e) => {
    console.error(e);
    app.exit(1);
  });
app.on("window-all-closed", () => app.quit());
