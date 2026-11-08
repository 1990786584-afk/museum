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
  assert.equal(stageFromSearch("?stage=invite"), "date"); // Legacy link skips removed page.
  assert.equal(stageFromSearch("?stage=date"), "date");
  assert.equal(stageFromSearch("?stage=after"), "after");
  assert.equal(stageFromSearch("?stage=unknown"), "before");
});
test("after the first bouquet, no extra invitation page is interposed", () => {
  const html = require("node:fs").readFileSync(require("node:path").join(__dirname, "../romance/index.html"), "utf8");
  assert.match(html, /id="goToDate"[^>]*href="\?stage=date"[^>]*>花收好了/);
  assert.doesNotMatch(html, /data-stage="invite"/);
  assert.match(html, /data-stage="date"/);
  assert.match(html, /id="dateFrame"/);
});
test("native goes to standalone Ephemera; browser preview shows full Ephemera home and keeps exit gift", () => {
  for (const nativeHost of [true, false]) {
    const sections = ["before", "date", "after"].map(name => ({
      name, hidden: null, getAttribute() { return this.name; }
    }));
    const nodes = { firstBouquet: {}, lastBouquet: {}, dateFrame: {}, goToDate: { href: "?stage=date" } };
    const doc = {
      body: { dataset: {} },
      querySelectorAll() { return sections; },
      getElementById(id) { return nodes[id]; }
    };
    assert.equal(render(doc, { search: "" }, nativeHost), "before");
    assert.equal(nodes.goToDate.href, nativeHost ? "../dates/" : "?stage=date");
    assert.deepEqual(sections.map(s => s.hidden), [false, true, true]);
    assert.equal(render(doc, { search: "?stage=date" }, nativeHost), "date");
    assert.equal(nodes.dateFrame.src, "../dates/");
    assert.equal(doc.body.dataset.activeStage, "date");
    assert.deepEqual(sections.map(s => s.hidden), [true, false, true]);
    assert.equal(render(doc, { search: "?stage=after" }, nativeHost), "after");
    assert.ok(nodes.lastBouquet.src.includes("#"));
  }
});
