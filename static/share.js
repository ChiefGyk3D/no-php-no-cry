(function () {
  var r = document.querySelector(".share"), q = function (s) { return r.querySelector(s); }, st = q(".share-status"), p = q(".share-picker"),
    h = q(".share-host"), m = q(".share-rem"), u = q(".share-url"), c, t;
  function z() { st.textContent = ""; }
  function say(x) { st.textContent = x; clearTimeout(t); t = setTimeout(z, 5000); }
  function good(v) { try { return /^([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+([a-z]{2,}|xn--[a-z0-9-]+)$/.test(v) && new URL("https://" + v).host === v; } catch (e) { return false; } }
  function a(n) { return c.getAttribute(n); }
  function shut() { p.hidden = true; c.focus(); }
  function go() {
    var v = h.value.trim().toLowerCase(), s = a("data-share"), e = encodeURIComponent;
    if (!good(v)) { say("Enter only a host name, such as example.social."); h.focus(); return; }
    try { m.checked ? localStorage.setItem(s + "Server", v) : localStorage.removeItem(s + "Server"); } catch (x) {}
    window.open("https://" + v + (s == "lemmy" ? "/create_post?title=" + e(a("data-title")) + "&url=" + e(a("data-url")) : "/share?text=" + e(a("data-text"))), "_blank", "noopener,noreferrer");
    shut();
  }
  function copy(b) {
    function no() { u.hidden = false; u.focus(); u.select(); say("Copy failed. The link is selected: press Ctrl+C."); }
    if (navigator.clipboard && window.isSecureContext) navigator.clipboard.writeText(b.getAttribute("data-url")).then(function () { say("Link copied"); }, no);
    else no();
  }
  [].forEach.call(r.querySelectorAll("button[hidden]"), function (b) { b.hidden = false; });
  m.addEventListener("change", function () { try { m.checked || localStorage.removeItem(a("data-share") + "Server"); } catch (x) {} });
  r.addEventListener("click", function (e) {
    var b = e.target.closest("button"), s = b && b.getAttribute("data-share"), v = "";
    if (s == "copy") copy(b); else if (s == "go") go(); else if (s == "x") shut();
    else if (s) {
      c = b; p.hidden = false; q(".share-name").textContent = a("data-name");
      try { v = localStorage.getItem(s + "Server"); } catch (x) {}
      h.value = good(v) ? v : ""; m.checked = !!h.value; h.focus();
    }
  });
  r.addEventListener("input", z);
  r.addEventListener("keydown", function (e) {
    if (e.key == "Escape" && !p.hidden) shut(); else if (e.key == "Enter" && e.target == h) go();
  });
})();
