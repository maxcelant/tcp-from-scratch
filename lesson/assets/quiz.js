/* TCP From Scratch — self-grading quiz. Renders the question set embedded in
   <script type="application/json" id="quiz-data"> and grades in the browser.
   Zero dependencies, runs offline. Pairs with lesson.js (theme/progress). */
(function () {
  "use strict";

  function el(tag, cls, txt) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (txt != null) e.textContent = txt;
    return e;
  }

  var LETTERS = ["A", "B", "C", "D", "E", "F"];

  function boot() {
    var mount = document.getElementById("quiz");
    var raw = document.getElementById("quiz-data");
    if (!mount || !raw) return;

    var data;
    try { data = JSON.parse(raw.textContent); } catch (e) { return; }
    var questions = (data && data.questions) || [];
    if (!questions.length) return;

    var total = questions.length;
    var graded = 0, correct = 0;

    // Score banner
    var banner = el("div", "quiz-score");
    var bText = el("span", "quiz-score-text", "0 of " + total + " answered");
    var bMeter = el("div", "quiz-score-meter");
    var bFill = el("div", "quiz-score-fill");
    bMeter.appendChild(bFill);
    banner.appendChild(bText);
    banner.appendChild(bMeter);
    mount.appendChild(banner);

    function refresh() {
      bFill.style.width = (graded / total * 100).toFixed(1) + "%";
      if (graded < total) {
        bText.textContent = graded + " of " + total + " answered";
        banner.classList.remove("done");
      } else {
        bText.textContent = "Score: " + correct + " / " + total +
          (correct === total ? " — perfect 🎉" : "");
        banner.classList.add("done");
      }
    }

    questions.forEach(function (q, qi) {
      var card = el("div", "quiz-q");
      var head = el("p", "quiz-qtext");
      head.appendChild(el("span", "quiz-qnum", "Q" + (qi + 1)));
      head.appendChild(document.createTextNode(q.q));
      card.appendChild(head);

      var opts = el("div", "quiz-opts");
      var selected = -1, locked = false;
      var buttons = [];

      (q.options || []).forEach(function (text, oi) {
        var b = el("button", "quiz-opt");
        b.type = "button";
        b.appendChild(el("span", "quiz-opt-key", LETTERS[oi] || "?"));
        b.appendChild(el("span", "quiz-opt-text", text));
        b.addEventListener("click", function () {
          if (locked) return;
          selected = oi;
          buttons.forEach(function (x, xi) {
            x.classList.toggle("selected", xi === oi);
          });
          check.disabled = false;
        });
        buttons.push(b);
        opts.appendChild(b);
      });
      card.appendChild(opts);

      var actions = el("div", "quiz-actions");
      var check = el("button", "quiz-check", "Check");
      check.type = "button";
      check.disabled = true;
      actions.appendChild(check);
      card.appendChild(actions);

      var explain = el("div", "quiz-explain");
      var verdict = el("span", "quiz-verdict");
      explain.appendChild(verdict);
      explain.appendChild(el("span", "quiz-explain-body", q.explain || ""));
      explain.hidden = true;
      card.appendChild(explain);

      check.addEventListener("click", function () {
        if (locked || selected < 0) return;
        locked = true;
        check.disabled = true;
        var right = selected === q.answer;
        buttons.forEach(function (x, xi) {
          x.disabled = true;
          if (xi === q.answer) x.classList.add("correct");
          else if (xi === selected) x.classList.add("incorrect");
        });
        verdict.textContent = right ? "✓ Correct" : "✗ Not quite";
        verdict.classList.add(right ? "ok" : "bad");
        explain.hidden = false;
        graded++;
        if (right) correct++;
        refresh();
      });

      mount.appendChild(card);
    });

    refresh();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else { boot(); }
})();
