#!/usr/bin/env python3
"""Render quiz-NN.html pages from quizzes.json and wire navigation.

Deterministic templater: every quiz page shares identical structure; only the
title, lesson number, embedded question JSON, and prev/next nav differ. Also
injects a 'take the quiz' CTA into each lesson page (idempotent).

Run from repo root:  python3 .quiz-build/render_quizzes.py
"""
import json
import os
import sys

# nn -> (lesson html filename, human title). Titles match the lesson <h1>/index.
LESSONS = [
    ("00", "00-intro.html",              "Intro & Setup"),
    ("01", "01-tun-device.html",         "Opening a TUN device"),
    ("02", "02-ipv4-parse.html",         "Parsing IPv4 headers"),
    ("03", "03-checksum.html",           "The Internet checksum"),
    ("04", "04-ipv4-marshal-icmp.html",  "Serializing IPv4 + ICMP echo"),
    ("05", "05-tcp-header.html",         "TCP header parse/serialize"),
    ("06", "06-tcb-state-machine.html",  "TCB & state machine"),
    ("07", "07-passive-open.html",       "Passive open: SYN → SYN/ACK"),
    ("08", "08-handshake-complete.html", "Completing the handshake"),
    ("09", "09-receiving-data.html",     "Receiving data + ACKing"),
    ("10", "10-sending-data.html",       "Sending data"),
    ("11", "11-retransmission.html",     "Retransmission (RTO)"),
    ("12", "12-active-open.html",        "Active open (client)"),
    ("13", "13-fin-teardown.html",       "FIN teardown"),
    ("14", "14-capstone.html",           "Speak HTTP/1.0"),
]

REPO = os.path.dirname(os.path.abspath(os.path.join(__file__, "..")))
LDIR = os.path.join(REPO, "lesson")


def esc(s):
    return (s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))


def by_nn(nn):
    for t in LESSONS:
        if t[0] == nn:
            return t
    return None


PAGE = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Lesson {nn} Quiz — {title} · TCP From Scratch</title>
<link rel="stylesheet" href="assets/lesson.css">
<script>(function(){{try{{var t=localStorage.getItem("tcpfs-theme");if(t==="dark"||t==="light")document.documentElement.setAttribute("data-theme",t);}}catch(e){{}}}})();</script>
</head>
<body>
<header class="topbar">
  <a class="brand" href="index.html">TCP From Scratch</a>
  <div class="topbar-right">
    <span class="lesson-counter">Quiz {nn} / 14</span>
    <button class="theme-toggle" type="button" aria-label="Toggle theme">🌙</button>
  </div>
</header>
<div class="progress-rail"><div class="progress-fill"></div></div>

<main class="lesson">
<article>
  <p class="eyebrow">Lesson {nn} · Self-check</p>
  <h1>{title} — quiz</h1>
  <p class="lead">Check your understanding of lesson {nn}. Pick an answer, hit <strong>Check</strong>, and read the explanation. Nothing is recorded — it's a self-check before you move on, not the <code>/validate-step</code> gate.</p>
  <div id="quiz"></div>
  <script type="application/json" id="quiz-data">{data}</script>
</article>
</main>

<nav class="lesson-nav">
  <a class="prev" href="{lesson_file}"><span class="dir">← Re-read lesson</span><span class="ttl">{nn} · {title}</span></a>
  {next}
</nav>

<footer class="site">TCP From Scratch · build a TCP/IP stack in Go, one lesson at a time</footer>

<script src="assets/lesson.js"></script>
<script src="assets/quiz.js"></script>
</body>
</html>
"""


def render_next(nn):
    i = int(nn)
    if i < 14:
        nxt = by_nn("%02d" % (i + 1))
        return ('<a class="next" href="%s"><span class="dir">Next lesson →</span>'
                '<span class="ttl">%s · %s</span></a>' % (nxt[1], nxt[0], esc(nxt[2])))
    return ('<a class="next" href="index.html"><span class="dir">Done →</span>'
            '<span class="ttl">Back to all lessons</span></a>')


def embed(questions):
    # Safe JSON-in-HTML: prevent </script> from closing the tag early.
    return json.dumps({"questions": questions}, ensure_ascii=False).replace("</", "<\\/")


CTA_MARK = 'class="quiz-cta"'


def inject_cta(nn):
    meta = by_nn(nn)
    path = os.path.join(LDIR, meta[1])
    with open(path, encoding="utf-8") as f:
        html = f.read()
    if CTA_MARK in html:
        return "skip (already wired)"
    cta = ('  <div class="quiz-cta">Think you\'ve got it? '
           '<a href="quiz-%s.html">Take the lesson %s quiz →</a></div>\n' % (nn, nn))
    if "</article>" not in html:
        return "skip (no </article>)"
    html = html.replace("</article>", cta + "</article>", 1)
    with open(path, "w", encoding="utf-8") as f:
        f.write(html)
    return "wired"


def main():
    data_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "quizzes.json")
    with open(data_path, encoding="utf-8") as f:
        payload = json.load(f)
    quizzes = {q["nn"]: q["questions"] for q in payload["quizzes"]}

    for nn, fname, title in LESSONS:
        qs = quizzes.get(nn, [])
        if not qs:
            print("  !! lesson %s: NO questions — skipping page" % nn)
            continue
        page = PAGE.format(nn=nn, title=esc(title), data=embed(qs),
                           lesson_file=fname, next=render_next(nn))
        out = os.path.join(LDIR, "quiz-%s.html" % nn)
        with open(out, "w", encoding="utf-8") as f:
            f.write(page)
        status = inject_cta(nn)
        print("  quiz-%s.html  (%d Qs)  cta:%s" % (nn, len(qs), status))


if __name__ == "__main__":
    main()
