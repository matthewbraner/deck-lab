const { test } = require("node:test"),
  assert = require("node:assert/strict");
const c = require("../src/core.cjs");
const deck = {
  id: "a",
  name: "A",
  main: [
    { name: "Alpha", cardId: "1", count: 3 },
    { name: "Beta", cardId: "2", count: 1 },
    { name: "Other", cardId: "3", count: 36 },
  ],
  extra: [],
  side: [],
};
test("averages include zero-copy lists and collection is shared by card name", () => {
  const other = { ...deck, main: [{ name: "Beta", cardId: "2", count: 2 }] };
  const rows = c.aggregate([deck, other], {
    alpha: { unassigned: 1, printings: { a: { count: 1 } } },
  });
  const a = rows.find((r) => r.name === "Alpha");
  assert.equal(a.average, 1.5);
  assert.equal(a.included, 1);
  assert.equal(a.owned, 2);
  assert.equal(a.missing, 0);
});
test("exact include/exclude filters inspect all zones", () => {
  assert.equal(c.filterDecks([deck], "alpha", "alph").length, 1);
  assert.equal(c.filterDecks([deck], "Alpha", "Beta").length, 0);
  assert.equal(c.filterDecks([deck], "Alpha;Beta", "").length, 1);
});
test("freshness boundary, failed verification and future dates", () => {
  const now = 1e9;
  assert(c.fresh({ verified: true, checked: now - 1 }, now));
  assert(!c.fresh({ verified: true, checked: now - 86400000 }, now));
  assert(!c.fresh({ verified: false, checked: now }, now));
  assert(!c.fresh({ verified: true, checked: now + 1 }, now));
});
test("hypergeometric matches known result and boundary cases", () => {
  assert(Math.abs(c.hypergeometric(40, 3, 5) - 0.3375506072874494) < 1e-12);
  assert.equal(c.hypergeometric(40, 40, 5), 1);
  assert.equal(c.hypergeometric(40, 0, 5), 0);
  assert.equal(c.hypergeometric(40, 3, 0, 0), 1);
  assert.throws(() => c.hypergeometric(40, 41, 5));
});
test("combo calculator treats overlapping bucket membership exactly", () => {
  assert(
    Math.abs(
      c.comboProbability(deck, [["Alpha"]], 5) - c.hypergeometric(40, 3, 5),
    ) < 1e-12,
  );
  assert.equal(
    c.comboProbability(deck, [["Alpha"], ["Alpha"]], 5),
    c.comboProbability(deck, [["Alpha"]], 5),
  );
  const p = c.comboProbability(deck, [["Alpha"], ["Beta"]], 5);
  const expected =
    1 -
    c.choose(37, 5) / c.choose(40, 5) -
    c.choose(39, 5) / c.choose(40, 5) +
    c.choose(36, 5) / c.choose(40, 5);
  assert(Math.abs(p - expected) < 1e-12);
  assert(
    Math.abs(
      c.comboProbability(deck, [["Alpha"], ["Beta"]], 5, "any") -
        c.hypergeometric(40, 4, 5),
    ) < 1e-12,
  );
});
test("YDK preserves zones and aliases round-trip", () => {
  const d = c.parseYdk("#main\n10\n1\n#extra\n2\n!side\n3", [
    { id: "1", name: "Alpha", aliases: ["10"] },
    { id: "2", name: "Beta" },
    { id: "3", name: "Other" },
  ]);
  assert.equal(d.main[0].count, 2);
  const again = c.parseYdk(c.toYdk(d));
  assert.deepEqual(
    again.main.map((e) => [e.cardId, e.count]),
    [["1", 2]],
  );
  assert.equal(again.extra[0].cardId, "2");
  assert.equal(again.side[0].cardId, "3");
  assert.throws(() => c.parseYdk("not a deck"));
});
test("backup validation rejects corrupt and negative quantities", () => {
  assert.equal(c.validateState(c.emptyState()).schema, 1);
  assert.throws(() => c.validateState({ schema: 2 }));
  const s = c.emptyState();
  s.collection.alpha = { unassigned: -1, printings: {} };
  assert.throws(() => c.validateState(s));
});
