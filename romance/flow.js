/* Bouquet -> original Ephemera -> another bouquet. Keep upstream apps unmodified. */
(function (root) {
  "use strict";

  const FLORIST = "https://frycarrot.github.io/CyberFlowerShop/";
  const MARKERS = Object.freeze({
    before: "[花束:玫瑰5×4,勿忘我1×4,绣球花1×1|包装纸2|丝带3|卡片:心形2|To:念念|From:Finnian|寄语:念念，今天想先送你花，再正式邀请你约会。我们慢慢走，花会开，云里的照片也会等我们。第一次见面时没说完的喜欢，往后的每一年都想好好告诉你。]",
    after: "[花束:玫瑰2×3,勿忘我3×3,向日葵1×2,绣球花3×1|包装纸6|丝带1|卡片:心形1|To:念念|From:Finnian|寄语:约会结束也想送你花。第一束是邀请，第二束是舍不得。谢谢你愿意和我度过这段时间，下一次，我还想继续请你赴约。]"
  });

  function stageFromSearch(search) {
    const stage = new URLSearchParams(search || "").get("stage");
    if (stage === "invite") return "date"; // Old URLs skip the removed intermediate page.
    return ["before", "date", "after"].includes(stage) ? stage : "before";
  }

  function bouquetURL(phase) {
    if (!Object.prototype.hasOwnProperty.call(MARKERS, phase)) throw new Error("Unknown bouquet");
    return FLORIST + "#" + encodeURIComponent(MARKERS[phase]);
  }

  function render(doc, location, nativeHost) {
    const stage = stageFromSearch(location.search);
    doc.body.dataset.activeStage = stage;
    doc.querySelectorAll("[data-stage]").forEach(function (section) {
      section.hidden = section.getAttribute("data-stage") !== stage;
    });
    if (stage === "before") {
      doc.getElementById("firstBouquet").src = bouquetURL("before");
    }
    if (stage === "after") {
      doc.getElementById("lastBouquet").src = bouquetURL("after");
    }
    if (stage === "date") {
      doc.getElementById("dateFrame").src = "../dates/";
    }
    // Native uses the actual standalone Ephemera exhibit; its navigation delegate
    // selects the private original or the public demo. Browser preview retains
    // its immersive Ephemera iframe so she can come back for another bouquet.
    doc.getElementById("goToDate").href = nativeHost ? "../dates/" : "?stage=date";
    return stage;
  }

  const api = { FLORIST, MARKERS, stageFromSearch, bouquetURL, render };
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  if (typeof window !== "undefined" && typeof document !== "undefined") {
    window.addEventListener("DOMContentLoaded", function () {
      render(document, window.location, window.__MUSEUM_IN_APP__ === true);
    });
  }
})(typeof globalThis === "object" ? globalThis : this);
