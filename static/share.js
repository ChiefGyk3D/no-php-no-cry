(function () {
  var d = document, r = d.querySelector(".share"), st = r.querySelector(".share-status"),
    k = "mastodonServer", ch = r.querySelector("[data-share=server]");
  function say(t) { st.textContent = t; }
  function get() { try { return localStorage.getItem(k) || ""; } catch (e) { return ""; } }
  function server(ask) {
    var v = get();
    if (ask || !v) {
      v = (prompt("Your Mastodon server, for example example.social", v) || "").trim().toLowerCase().replace(/^https?:\/\//, "").replace(/\/.*$/, "");
      if (!/^[a-z0-9-]+(\.[a-z0-9-]+)+(:\d+)?$/.test(v)) { if (v) say("That is not a server name."); return ""; }
      try { localStorage.setItem(k, v); } catch (e) {}
    }
    ch.hidden = !v;
    return v;
  }
  function copy(u) {
    function manual() { prompt("Copy this link", u); }
    if (navigator.clipboard && window.isSecureContext) navigator.clipboard.writeText(u).then(function () { say("Link copied."); }, manual);
    else manual();
  }
  [].forEach.call(r.querySelectorAll("button[hidden]"), function (b) { b.hidden = false; });
  ch.hidden = !get();
  r.addEventListener("click", function (e) {
    var b = e.target.closest("button"), t = b && b.getAttribute("data-share"), v;
    if (t === "copy") copy(b.getAttribute("data-url"));
    else if (t === "server") server(true);
    else if (t === "mastodon" && (v = server(false))) window.open("https://" + v + "/share?text=" + encodeURIComponent(b.getAttribute("data-text")), "_blank", "noopener,noreferrer");
  });
})();
