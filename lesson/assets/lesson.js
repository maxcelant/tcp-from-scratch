/* TCP From Scratch — lesson interactivity: theme toggle, code highlighting,
   copy buttons, reading-progress bar. Zero dependencies, runs offline. */
(function () {
  "use strict";

  /* ---- Theme ------------------------------------------------------------ */
  var root = document.documentElement;
  var STORE = "tcpfs-theme";

  function systemDark() {
    return window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches;
  }
  function effective() {
    var t = root.getAttribute("data-theme");
    if (t === "dark" || t === "light") return t;
    return systemDark() ? "dark" : "light";
  }
  function applyToggleIcon(btn) {
    if (!btn) return;
    var dark = effective() === "dark";
    btn.textContent = dark ? "☀️" : "🌙";
    btn.setAttribute("aria-label", dark ? "Switch to light theme" : "Switch to dark theme");
    btn.setAttribute("title", dark ? "Light theme" : "Dark theme");
  }
  function initTheme() {
    var saved;
    try { saved = localStorage.getItem(STORE); } catch (e) {}
    if (saved === "dark" || saved === "light") root.setAttribute("data-theme", saved);

    var btn = document.querySelector(".theme-toggle");
    applyToggleIcon(btn);
    if (btn) {
      btn.addEventListener("click", function () {
        var next = effective() === "dark" ? "light" : "dark";
        root.setAttribute("data-theme", next);
        try { localStorage.setItem(STORE, next); } catch (e) {}
        applyToggleIcon(btn);
      });
    }
  }

  /* ---- Reading progress ------------------------------------------------- */
  function initProgress() {
    var fill = document.querySelector(".progress-fill");
    if (!fill) return;
    function update() {
      var h = document.documentElement;
      var max = h.scrollHeight - h.clientHeight;
      var pct = max > 0 ? (h.scrollTop || document.body.scrollTop) / max * 100 : 0;
      fill.style.width = pct.toFixed(1) + "%";
    }
    document.addEventListener("scroll", update, { passive: true });
    window.addEventListener("resize", update);
    update();
  }

  /* ---- Copy buttons ----------------------------------------------------- */
  function initCopy() {
    document.querySelectorAll(".code").forEach(function (block) {
      var btn = block.querySelector(".copy-btn");
      var pre = block.querySelector("pre");
      if (!btn || !pre) return;
      btn.addEventListener("click", function () {
        var text = pre.innerText;
        var done = function () {
          btn.textContent = "copied";
          btn.classList.add("copied");
          setTimeout(function () { btn.textContent = "copy"; btn.classList.remove("copied"); }, 1400);
        };
        if (navigator.clipboard && navigator.clipboard.writeText) {
          navigator.clipboard.writeText(text).then(done, fallback);
        } else { fallback(); }
        function fallback() {
          var ta = document.createElement("textarea");
          ta.value = text; document.body.appendChild(ta); ta.select();
          try { document.execCommand("copy"); done(); } catch (e) {}
          document.body.removeChild(ta);
        }
      });
    });
  }

  /* ---- Lightweight syntax highlighting ---------------------------------- */
  var GO_KW = /\b(package|import|func|return|var|const|type|struct|interface|map|chan|go|defer|if|else|for|range|switch|case|default|break|continue|select|fallthrough|goto)\b/;
  var GO_TYPE = /\b(string|byte|rune|bool|error|int|int8|int16|int32|int64|uint|uint8|uint16|uint32|uint64|uintptr|float32|float64|complex64|complex128|any|nil|true|false|iota)\b/;
  var SH_KW = /\b(sudo|go|cd|echo|cat|make|ping|nc|timeout|head|printf|python3|tcpdump|tshark|ip|iptables|base64|wc|for|do|done|if|then|fi|while)\b/;

  function esc(s) {
    return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  }

  // Tokenize a single line into highlighted HTML. `lang` controls keyword sets.
  function hl(line, lang) {
    var out = "";
    var i = 0, n = line.length;
    while (i < n) {
      var c = line[i];

      // comments
      if (lang === "go" && c === "/" && line[i + 1] === "/") {
        out += '<span class="tok-com">' + esc(line.slice(i)) + "</span>"; break;
      }
      if ((lang === "bash" || lang === "shell" || lang === "text") && c === "#" &&
          (i === 0 || /\s/.test(line[i - 1]))) {
        out += '<span class="tok-com">' + esc(line.slice(i)) + "</span>"; break;
      }
      if (lang === "c" && c === "/" && line[i + 1] === "*") {
        var end = line.indexOf("*/", i + 2);
        var stop = end === -1 ? n : end + 2;
        out += '<span class="tok-com">' + esc(line.slice(i, stop)) + "</span>"; i = stop; continue;
      }
      if (lang === "c" && c === "/" && line[i + 1] === "/") {
        out += '<span class="tok-com">' + esc(line.slice(i)) + "</span>"; break;
      }

      // strings
      if (c === '"' || c === "'" || c === "`") {
        var q = c, j = i + 1;
        while (j < n && line[j] !== q) { if (line[j] === "\\") j++; j++; }
        j = Math.min(j + 1, n);
        out += '<span class="tok-str">' + esc(line.slice(i, j)) + "</span>"; i = j; continue;
      }

      // numbers (incl hex)
      if (/[0-9]/.test(c) && (i === 0 || /[^\w]/.test(line[i - 1]))) {
        var m = /^(0x[0-9a-fA-F]+|\d+\.?\d*)/.exec(line.slice(i));
        if (m) { out += '<span class="tok-num">' + esc(m[0]) + "</span>"; i += m[0].length; continue; }
      }

      // identifiers / keywords
      if (/[A-Za-z_]/.test(c)) {
        var w = /^[A-Za-z_][A-Za-z0-9_]*/.exec(line.slice(i))[0];
        var cls = "";
        if (lang === "go") {
          if (GO_KW.test(w)) cls = "tok-kw";
          else if (GO_TYPE.test(w)) cls = "tok-type";
          else if (line[i + w.length] === "(") cls = "tok-fn";
        } else if (lang === "bash" || lang === "shell") {
          if (SH_KW.test(w) && (i === 0 || /[\s|;&]/.test(line[i - 1]))) cls = "tok-kw";
        }
        out += cls ? '<span class="' + cls + '">' + esc(w) + "</span>" : esc(w);
        i += w.length; continue;
      }

      out += esc(c); i++;
    }
    return out;
  }

  function initHighlight() {
    document.querySelectorAll(".code").forEach(function (block) {
      var lang = (block.getAttribute("data-lang") || "text").toLowerCase();
      if (lang === "none") return;
      var code = block.querySelector("pre code") || block.querySelector("pre");
      if (!code || code.dataset.hl) return;
      var lines = code.textContent.replace(/\n$/, "").split("\n");
      code.innerHTML = lines.map(function (l) { return hl(l, lang); }).join("\n");
      code.dataset.hl = "1";
    });
  }

  function boot() {
    initTheme();
    initProgress();
    initCopy();
    initHighlight();
  }
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else { boot(); }
})();
