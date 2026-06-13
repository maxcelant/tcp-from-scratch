/* TCP From Scratch — interactive lesson widgets. Each <div class="interactive"
   data-widget="NAME"> in a lesson is hydrated by the matching builder below.
   Zero dependencies, theme-aware, runs offline. */
(function () {
  "use strict";

  function el(tag, cls, txt) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (txt != null) e.textContent = txt;
    return e;
  }

  var WIDGETS = {};

  /* ===================================================================
     tcp-fsm — the RFC 793 §3.2 connection state machine, clickable.
     Fire the events valid from the current state, or run a scenario,
     and watch the state move. Mirrors the ASCII diagram in lesson 06.
     =================================================================== */

  // phase -> css hue token (matches the static .fsm legend)
  var PHASE = {
    start: "slate", hs: "blue", data: "green", closing: "amber", linger: "violet",
  };

  var STATES = {
    "CLOSED":       { phase: "start"  },
    "LISTEN":       { phase: "hs"     },
    "SYN-SENT":     { phase: "hs"     },
    "SYN-RECEIVED": { phase: "hs"     },
    "ESTABLISHED":  { phase: "data"   },
    "FIN-WAIT-1":   { phase: "closing"},
    "FIN-WAIT-2":   { phase: "closing"},
    "CLOSING":      { phase: "closing"},
    "CLOSE-WAIT":   { phase: "closing"},
    "LAST-ACK":     { phase: "closing"},
    "TIME-WAIT":    { phase: "linger" },
  };

  // current -> list of {on: trigger, send: action, to: nextState}
  var EDGES = {
    "CLOSED": [
      { on: "passive open",  send: "(start listening)", to: "LISTEN" },
      { on: "active open",   send: "send SYN",          to: "SYN-SENT" },
    ],
    "LISTEN": [
      { on: "recv SYN",      send: "send SYN/ACK",      to: "SYN-RECEIVED" },
      { on: "app: close",    send: "—",            to: "CLOSED" },
    ],
    "SYN-SENT": [
      { on: "recv SYN/ACK",  send: "send ACK",          to: "ESTABLISHED" },
      { on: "recv SYN",      send: "send ACK (simul.)", to: "SYN-RECEIVED" },
      { on: "app: close",    send: "—",            to: "CLOSED" },
    ],
    "SYN-RECEIVED": [
      { on: "recv ACK",      send: "—",            to: "ESTABLISHED" },
      { on: "app: close",    send: "send FIN",          to: "FIN-WAIT-1" },
    ],
    "ESTABLISHED": [
      { on: "app: close",    send: "send FIN",          to: "FIN-WAIT-1" },
      { on: "recv FIN",      send: "send ACK",          to: "CLOSE-WAIT" },
    ],
    "FIN-WAIT-1": [
      { on: "recv ACK of FIN", send: "—",          to: "FIN-WAIT-2" },
      { on: "recv FIN",      send: "send ACK",          to: "CLOSING" },
      { on: "recv FIN+ACK",  send: "send ACK",          to: "TIME-WAIT" },
    ],
    "FIN-WAIT-2": [
      { on: "recv FIN",      send: "send ACK",          to: "TIME-WAIT" },
    ],
    "CLOSE-WAIT": [
      { on: "app: close",    send: "send FIN",          to: "LAST-ACK" },
    ],
    "CLOSING": [
      { on: "recv ACK of FIN", send: "—",          to: "TIME-WAIT" },
    ],
    "LAST-ACK": [
      { on: "recv ACK of FIN", send: "—",          to: "CLOSED" },
    ],
    "TIME-WAIT": [
      { on: "timeout: 2·MSL", send: "—",      to: "CLOSED" },
    ],
  };

  // layout rows (mirror the static .fsm grouping)
  var ROWS = [
    ["CLOSED"],
    ["LISTEN", "SYN-SENT", "SYN-RECEIVED"],
    ["ESTABLISHED"],
    ["FIN-WAIT-1", "FIN-WAIT-2", "CLOSING", "CLOSE-WAIT", "LAST-ACK"],
    ["TIME-WAIT"],
  ];

  // preset walk-throughs: ordered list of triggers to auto-fire from CLOSED
  var SCENARIOS = [
    { name: "Server (passive open)", steps: ["passive open", "recv SYN", "recv ACK"] },
    { name: "Client (active open)",  steps: ["active open", "recv SYN/ACK"] },
    { name: "Active close",          steps: ["active open", "recv SYN/ACK", "app: close", "recv ACK of FIN", "recv FIN", "timeout: 2·MSL"] },
    { name: "Passive close",         steps: ["active open", "recv SYN/ACK", "recv FIN", "app: close", "recv ACK of FIN"] },
  ];

  WIDGETS["tcp-fsm"] = function (root) {
    root.classList.add("iw", "iw-fsm");

    var current = "CLOSED";
    var nodes = {};
    var timer = null;

    // --- state diagram ---
    var board = el("div", "iw-fsm-board");
    ROWS.forEach(function (row) {
      var r = el("div", "iw-fsm-row");
      row.forEach(function (name) {
        var n = el("button", "iw-state");
        n.type = "button";
        n.dataset.hue = PHASE[STATES[name].phase];
        n.textContent = name;
        n.title = "Jump to " + name;
        n.addEventListener("click", function () { stop(); go(name, null); });
        nodes[name] = n;
        r.appendChild(n);
      });
      board.appendChild(r);
    });
    root.appendChild(board);

    // --- status line ---
    var status = el("div", "iw-fsm-status");
    root.appendChild(status);

    // --- available transitions ---
    var controls = el("div", "iw-fsm-controls");
    root.appendChild(controls);

    // --- scenarios + reset ---
    var bar = el("div", "iw-fsm-bar");
    bar.appendChild(el("span", "iw-fsm-bar-label", "Run a scenario:"));
    SCENARIOS.forEach(function (sc) {
      var b = el("button", "iw-scenario", sc.name);
      b.type = "button";
      b.addEventListener("click", function () { runScenario(sc); });
      bar.appendChild(b);
    });
    var reset = el("button", "iw-reset", "↺ Reset");
    reset.type = "button";
    reset.addEventListener("click", function () { stop(); go("CLOSED", null); trace.innerHTML = ""; });
    bar.appendChild(reset);
    root.appendChild(bar);

    // --- trace log ---
    var trace = el("ol", "iw-fsm-trace");
    root.appendChild(trace);

    function renderControls() {
      controls.innerHTML = "";
      var edges = EDGES[current] || [];
      if (!edges.length) {
        controls.appendChild(el("span", "iw-fsm-terminal", "Terminal state — nothing fires from here. Reset to start again."));
        return;
      }
      edges.forEach(function (e) {
        var b = el("button", "iw-event");
        b.type = "button";
        b.appendChild(el("span", "iw-event-on", e.on));
        b.appendChild(el("span", "iw-event-send", e.send === "—" ? "no segment sent" : e.send));
        b.appendChild(el("span", "iw-event-to", "→ " + e.to));
        b.addEventListener("click", function () { stop(); fire(e); });
        controls.appendChild(b);
      });
    }

    function setStatus() {
      status.innerHTML = "";
      status.appendChild(el("span", "iw-fsm-status-label", "Current state"));
      var chip = el("span", "iw-state-chip", current);
      chip.dataset.hue = PHASE[STATES[current].phase];
      status.appendChild(chip);
    }

    function go(name, edge) {
      Object.keys(nodes).forEach(function (k) {
        nodes[k].classList.toggle("active", k === name);
      });
      current = name;
      setStatus();
      renderControls();
      // re-trigger the pulse animation
      var n = nodes[name];
      n.classList.remove("pulse");
      void n.offsetWidth;
      n.classList.add("pulse");
    }

    function fire(edge) {
      var from = current;
      go(edge.to, edge);
      var li = el("li", "iw-trace-line");
      li.appendChild(el("span", "iw-trace-from", from));
      var mid = el("span", "iw-trace-evt");
      mid.appendChild(el("span", "iw-trace-on", edge.on));
      if (edge.send !== "—") mid.appendChild(el("span", "iw-trace-send", "/ " + edge.send));
      li.appendChild(mid);
      li.appendChild(el("span", "iw-trace-to", edge.to));
      trace.appendChild(li);
      trace.scrollTop = trace.scrollHeight;
    }

    function runScenario(sc) {
      stop();
      go("CLOSED", null);
      trace.innerHTML = "";
      var i = 0;
      (function next() {
        if (i >= sc.steps.length) { timer = null; return; }
        var want = sc.steps[i++];
        var edge = (EDGES[current] || []).filter(function (e) { return e.on === want; })[0];
        if (!edge) { timer = null; return; }
        fire(edge);
        timer = setTimeout(next, 950);
      })();
    }

    function stop() {
      if (timer) { clearTimeout(timer); timer = null; }
    }

    go("CLOSED", null);
  };

  /* =================================================================== */

  function boot() {
    document.querySelectorAll(".interactive[data-widget]").forEach(function (root) {
      var name = root.getAttribute("data-widget");
      if (WIDGETS[name] && !root.dataset.hydrated) {
        root.dataset.hydrated = "1";
        try { WIDGETS[name](root); } catch (e) { /* leave placeholder */ }
      }
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else { boot(); }
})();
