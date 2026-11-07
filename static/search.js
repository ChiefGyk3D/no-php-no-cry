(function () {
  var d = document, box = d.getElementById("search"), q = d.getElementById("q"),
    st = d.getElementById("search-status"), m = /[?&]q=([^&#]*)/.exec(location.search),
    items = [].map.call(d.querySelectorAll(".search-list li"), function (li) {
      return { li: li, t: li.textContent.toLowerCase() };
    }),
    groups = d.querySelectorAll(".search-group");
  function run() {
    var w = q.value.toLowerCase().split(/\s+/).filter(Boolean), n = 0;
    items.forEach(function (i) {
      var ok = w.every(function (k) { return i.t.indexOf(k) > -1; });
      i.li.hidden = !ok;
      if (ok) n++;
    });
    [].forEach.call(groups, function (g) { g.hidden = !g.querySelector("li:not([hidden])"); });
    st.textContent = !w.length ? "" : n ? n + (n > 1 ? " results" : " result") : "No results";
  }
  box.hidden = false;
  q.addEventListener("input", run);
  q.addEventListener("keydown", function (e) {
    if (e.key === "Escape" || e.key === "Esc") { q.value = ""; run(); }
  });
  if (m) {
    try { q.value = decodeURIComponent(m[1].replace(/\+/g, " ")); } catch (e) {}
    run();
  }
})();
