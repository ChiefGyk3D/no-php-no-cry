// Same behavior as before; this line only changes the file bytes so the edge refetches it under the current _headers (issue 272).
(function () {
  var d = document, r = d.querySelector(".share"), st = r.querySelector(".share-status"),
    k = "mastodonServer", ch = r.querySelector("[data-share=server]");
  function say(t) { st.textContent = t; }
  function good(v) { try { return /^([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+([a-z]{2,}|xn--[a-z0-9-]+)$/.test(v) && new URL("https://" + v).host === v; } catch (e) { return false; } }
  function get() { var v = ""; try { v = localStorage.getItem(k) || ""; if (v && !good(v)) { localStorage.removeItem(k); v = ""; } } catch (e) {} return v; }
  function server(ask) {
    var v = get();
    if (ask || !v) {
      v = (prompt("Your Mastodon server, for example example.social", v) || "").trim().toLowerCase().replace(/^https?:\/\//, "").replace(/\/.*$/, "");
      if (!good(v)) { if (v) say("That is not a server name."); return ""; }
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
