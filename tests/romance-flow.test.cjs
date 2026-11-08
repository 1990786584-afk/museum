const assert = require("node:assert/strict");
const test = require("node:test");
const { MARKERS, bouquetURL, stageFromSearch, render } = require("../romance/flow.js");

test("first and second gifts remain distinct valid shareable markers", () => {
  assert.notEqual(MARKERS.before, MARKERS.after);
  for (const phase of ["before", "after"]) {
    const marker = MARKERS[phase];
    assert.match(marker, /^\[花束:/);
    assert.match(marker, /\|To:念念\|From:Finnian\|寄语:/);
    assert.ok(marker.endsWith("]"));
    assert.equal(decodeURIComponent(bouquetURL(phase).split("#")[1]), marker);
    assert.ok(bouquetURL(phase).startsWith("https://frycarrot.github.io/CyberFlowerShop/#"));
    const quantities = [...marker.matchAll(/(玫瑰|勿忘我|紫风信子|向日葵|绣球花)\d×(\d+)/g)];
    assert.ok(quantities.length >= 2);
    assert.equal(quantities.reduce((n, match) => n + Number(match[2]) * (match[1] === "绣球花" ? 2 : 1), 0), 10);
  }
});
test("only known flow stages are shown", () => {
  assert.equal(stageFromSearch(""), "before");
  assert.equal(stageFromSearch("?stage=invite"), "invite");
  assert.equal(stageFromSearch("?stage=date"), "date");
  assert.equal(stageFromSearch("?stage=after"), "after");
  assert.equal(stageFromSearch("?stage=unknown"), "before");
});
test("live private date uses native Ephemera route; public website uses demo", () => {
  for (const live of [true, false]) {
    const section = ["before", "invite", "date", "after"].map(name => ({
      name, hidden: null, getAttribute() { return this.name; }
    }));
    const nodes = {
      firstBouquet: {}, lastBouquet: {}, dateFrame: {}, acceptDate: { href: "?stage=date" }
    };
    const document = {
      querySelectorAll() { return section; },
      getElementById(id) { return nodes[id]; }
    };
    assert.equal(render(document, { search: "?stage=invite" }, live), "invite");
    assert.deepEqual(section.map(e => e.hidden), [true, false, true, true]);
    assert.equal(nodes.acceptDate.href, live ? "../dates/" : "?stage=date");
  }
});
