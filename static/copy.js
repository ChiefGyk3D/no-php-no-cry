// Copy buttons for /support/. Behavior unchanged; the first line changed bytes so the edge refetches under the current _headers (issues 216, 272).
(function () {
  var d = document;
  function legacy(t) {
    var a = d.createElement("textarea"), ok = false;
    a.className = "copy-scratch";
    a.value = t;
    a.setAttribute("readonly", "");
    d.body.appendChild(a);
    a.select();
    try { ok = d.execCommand("copy"); } catch (e) {}
    d.body.removeChild(a);
    return ok;
  }
  d.querySelectorAll("[data-copy]").forEach(function (b) {
    var s = b.parentNode.querySelector(".copy-status"), t;
    function say(m) {
      s.textContent = m;
      clearTimeout(t);
      t = setTimeout(function () { s.textContent = ""; }, 2500);
    }
    b.hidden = false;
    b.addEventListener("click", function () {
      var v = d.getElementById(b.getAttribute("data-copy")).textContent.trim();
      var done = function (ok) { say(ok ? "Copied" : "Copy failed. Select the address instead."); };
      if (navigator.clipboard && window.isSecureContext) {
        navigator.clipboard.writeText(v).then(function () { done(true); }, function () { done(legacy(v)); });
      } else {
        done(legacy(v));
      }
    });
  });
})();
