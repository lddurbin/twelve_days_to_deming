#!/usr/bin/env python3
"""Throwaway spike for #825: find emphasis the PDF has and the .qmd lost.

NOT a production checker. Kept only so the numbers in
docs/emphasis-detection-spike.md can be reproduced.

PDF side: `pdftohtml -xml` tags each text run <b>/<i> from the embedded
font's own style. QMD side: pandoc AST Strong/Emph (plus raw <em>/<strong>).
The two word streams are aligned per day with difflib, and every aligned
word whose emphasis disagrees is reported as a run: lost (PDF emphasised,
site plain), added (site emphasised, PDF plain) or swapped (bold vs italic).

usage: emphasis-spike-825.py <day-num> [--json out.json]
       CONTENT=<dir> overrides content/days (e.g. a pre-fix git archive)
"""
import collections, difflib, glob, html, json, os, re, subprocess, sys, unicodedata

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
CONTENT = os.environ.get("CONTENT", REPO + "/content/days")
LETTER = dict(zip(range(1, 13), "DEFGHIJKLMNO"))
# Classes whose CSS already renders bold/italic (assets/styles/main.css)
STYLED = {"principle_callout", "aside_callout", "deming_quote", "foreman-remark",
          "activity_afterthought", "text-highlight-red", "table-cell-highlight",
          "callout-emphasis", "centered-bold-callout", "analysis_box_title",
          "major_activity_title", "foreman-transcript-context"}
SPLIT = re.compile(r"[\s—–/]+")


def norm(w):
    w = unicodedata.normalize("NFKD", w).lower()
    return re.sub(r"[^a-z0-9]", "", w)


# ---------------------------------------------------------------- PDF
def pdf_words(day):
    pdf = glob.glob(f"{REPO}/12-Days-to-Deming/PDFs/{LETTER[day]}.Day.{day}.*.pdf")[0]
    x = subprocess.run(["pdftohtml", "-xml", "-i", "-q", "-stdout", pdf],
                       capture_output=True, text=True, errors="replace").stdout
    specs = {m[1]: (int(m[2]), m[3], m[4]) for m in re.finditer(
        r'<fontspec id="(\d+)" size="(\d+)" family="([^"]+)" color="([^"]+)"', x)}
    chars = []  # (char, style, page, fontid)
    size_count = collections.Counter()
    for page in re.finditer(r'<page number="(\d+)".*?</page>', x, re.S):
        pno = int(page[1])
        prev = None
        for m in re.finditer(r'<text top="(\d+)" left="(\d+)" width="(\d+)" height="\d+" font="(\d+)">(.*?)</text>', page[0]):
            top, left, width, fid, inner = int(m[1]), int(m[2]), int(m[3]), m[4], m[5]
            # runs may mix styles inside one element: <i>DemDim</i> Chapter 18
            segs, bo, it = [], False, False
            for tok in re.split(r"(</?[bi]>|<[^>]+>)", inner):
                if tok in ("<b>", "</b>", "<i>", "</i>"):
                    if tok[1] == "/": 
                        if tok[2] == "b": bo = False
                        else: it = False
                    elif tok[1] == "b": bo = True
                    else: it = True
                elif tok and not tok.startswith("<"):
                    segs.append((html.unescape(tok), ("b" if bo else "") + ("i" if it else "")))
            text = "".join(t for t, _ in segs)
            size_count[specs[fid][0]] += len(text)
            if prev is not None:
                ptop, pright = prev
                if abs(top - ptop) > 4:
                    # line break: join end-of-line hyphenation
                    if chars and chars[-1][0] == "-" and text[:1].islower():
                        chars.pop()
                    else:
                        chars.append((" ", "", pno, fid, None))
                elif left - pright > 2:
                    chars.append((" ", "", pno, fid, None))
            for t, style in segs:
                for c in t:
                    # bbox of the element, for visual verification
                    chars.append((c, style, pno, fid, (top, left, width)))
            prev = (top, left + width)
        chars.append((" ", "", pno, None, None))
    body = size_count.most_common(1)[0][0]
    words, cur = [], []

    def flush():
        if not cur:
            return
        raw = "".join(ch[0] for ch in cur)
        n = norm(raw)
        if n:
            letters = [ch[1] for ch in cur if ch[0].isalnum()]
            b = sum("b" in s for s in letters) * 2 > len(letters)
            i = sum("i" in s for s in letters) * 2 > len(letters)
            fid = collections.Counter(ch[3] for ch in cur).most_common(1)[0][0]
            box = next((ch[4] for ch in cur if ch[4]), None)
            size, fam, color = specs[fid]
            words.append(dict(n=n, raw=raw, page=cur[0][2], b=b, i=i, font=fid, box=box,
                              blue=color.lower() != "#000000", size=size, body=body))
        cur.clear()
    for ch in chars:
        if SPLIT.fullmatch(ch[0]):
            flush()
        else:
            cur.append(ch)
    flush()
    return words


# ---------------------------------------------------------------- QMD
def qmd_words(day):
    files = re.findall(r'file: "([^"]+)"', open(f"{REPO}/workflow/validation/day-{day:02d}-manifest.yml").read())
    words = []
    for fn in files:
        path = f"{CONTENT}/day-{day:02d}/{fn}"
        src = re.sub(r"^```\{[^}]*\}", "```", open(path, encoding="utf-8").read(), flags=re.M)
        ast = json.loads(subprocess.run(["quarto", "pandoc", "-f", "markdown", "-t", "json"],
                                        input=src, capture_output=True, text=True).stdout)
        walk_blocks(ast["blocks"], dict(b=False, i=False, ctx=()), words, fn)
    return words


def emit(text, st, out, fname):
    for piece in SPLIT.split(text):
        n = norm(piece)
        if n:
            out.append(dict(n=n, raw=piece, b=st["b"], i=st["i"], ctx=st["ctx"], file=fname))


def push(st, **kw):
    s = dict(st)
    if "ctx" in kw:
        kw["ctx"] = st["ctx"] + tuple(kw["ctx"])
    s.update(kw)
    return s


def walk_inlines(xs, st, out, f):
    st = dict(st)
    for x in xs:
        t, c = x["t"], x.get("c")
        if t == "Str":
            emit(c, st, out, f)
        elif t == "Space" or t == "SoftBreak" or t == "LineBreak":
            out.append(None)
        elif t == "Strong":
            walk_inlines(c, push(st, b=True), out, f)
        elif t == "Emph":
            walk_inlines(c, push(st, i=True), out, f)
        elif t in ("Underline", "Strikeout", "Superscript", "Subscript", "SmallCaps"):
            walk_inlines(c, st, out, f)
        elif t == "Quoted":
            walk_inlines(c[1], st, out, f)
        elif t == "Cite":
            walk_inlines(c[1], st, out, f)
        elif t == "Link":
            walk_inlines(c[1], push(st, ctx=["link"]), out, f)
        elif t == "Image":
            walk_inlines(c[1], push(st, ctx=["image"]), out, f)
        elif t == "Span":
            walk_inlines(c[1], push(st, ctx=[k for k in c[0][1]] or ["span"]), out, f)
        elif t == "Code":
            emit(c[1], push(st, ctx=["code"]), out, f)
        elif t == "Note":
            walk_blocks(c, push(st, ctx=["note"]), out, f)
        elif t == "RawInline":
            tag = re.fullmatch(r"<(/?)(em|i|strong|b)\b[^>]*>", c[1].strip())
            if tag:
                key = "i" if tag[2] in ("em", "i") else "b"
                st[key] = not tag[1]
        elif t == "Math":
            emit(c[1], push(st, ctx=["math"]), out, f)


def walk_blocks(bs, st, out, f):
    for x in bs:
        t, c = x["t"], x.get("c")
        if t in ("Para", "Plain"):
            walk_inlines(c, st, out, f)
        elif t == "Header":
            walk_inlines(c[2], push(st, ctx=["header"]), out, f)
        elif t == "Div":
            walk_blocks(c[1], push(st, ctx=list(c[0][1]) or ["div"]), out, f)
        elif t == "BlockQuote":
            walk_blocks(c, push(st, ctx=["blockquote"]), out, f)
        elif t in ("BulletList",):
            for item in c:
                walk_blocks(item, push(st, ctx=["list"]), out, f)
        elif t == "OrderedList":
            for item in c[1]:
                walk_blocks(item, push(st, ctx=["list"]), out, f)
        elif t == "LineBlock":
            for line in c:
                walk_inlines(line, st, out, f)
        elif t == "Table":
            # [attr, caption, colspecs, head, bodies, foot]
            walk_table(c, push(st, ctx=["table"]), out, f)
        elif t == "Figure":
            walk_blocks(c[2], st, out, f)
        # CodeBlock / RawBlock / HorizontalRule skipped


def walk_table(c, st, out, f):
    head = c[3]
    for row in head[1]:
        for cell in row[1]:
            walk_blocks(cell[4], push(st, ctx=["th"]), out, f)
    for body in c[4]:
        for row in body[2] + body[3]:
            for cell in row[1]:
                walk_blocks(cell[4], st, out, f)


# ---------------------------------------------------------------- compare
def compare(day):
    P = pdf_words(day)
    Q = [w for w in qmd_words(day) if w]
    sm = difflib.SequenceMatcher(None, [w["n"] for w in P], [w["n"] for w in Q], autojunk=False)
    pairs = []
    for a, b, size in sm.get_matching_blocks():
        for k in range(size):
            pairs.append((a + k, b + k))
    matched = len(pairs)
    runs, cur = [], None
    for pi, qi in pairs:
        p, q = P[pi], Q[qi]
        pe, qe = p["b"] or p["i"], q["b"] or q["i"]
        kind = ("lost" if pe and not qe else "added" if qe and not pe else
                "swapped" if pe and qe and (p["b"], p["i"]) != (q["b"], q["i"]) else None)
        if kind and cur and cur["kind"] == kind and pi == cur["pi"][-1] + 1 and qi == cur["qi"][-1] + 1:
            cur["pi"].append(pi); cur["qi"].append(qi)
        elif kind:
            cur = dict(kind=kind, pi=[pi], qi=[qi]); runs.append(cur)
        else:
            cur = None
    report = []
    for r in runs:
        ps = [P[i] for i in r["pi"]]; qs = [Q[i] for i in r["qi"]]
        ctx = set(c for q in qs for c in q["ctx"])
        reasons = []
        if ctx & STYLED: reasons.append("css:" + ",".join(sorted(ctx & STYLED)))
        if "header" in ctx: reasons.append("header")
        if "th" in ctx: reasons.append("table-header")
        if "link" in ctx: reasons.append("link")
        notes = (["pdf-blue"] if any(p["blue"] for p in ps) else []) + \
                (["pdf-large"] if any(p["size"] > p["body"] + 1 for p in ps) else [])
        lo, hi = max(0, r["qi"][0] - 8), r["qi"][-1] + 9
        snippet = " ".join(("[" if i == r["qi"][0] else "") + Q[i]["raw"] + ("]" if i == r["qi"][-1] else "")
                           for i in range(lo, min(hi, len(Q))))
        report.append(dict(kind=r["kind"], words=len(ps), text=" ".join(p["raw"] for p in ps),
                           pdf_style="".join(sorted({("b" if p["b"] else "") + ("i" if p["i"] else "") for p in ps})),
                           qmd_style="".join(sorted({("b" if q["b"] else "") + ("i" if q["i"] else "") for q in qs})),
                           page=ps[0]["page"], box=ps[0]["box"], file=qs[0]["file"], ctx=sorted(ctx), explained=reasons, notes=notes,
                           snippet=snippet))
    stats = dict(day=day, pdf_words=len(P), qmd_words=len(Q), matched=matched,
                 pdf_emph_matched=sum(P[a]["b"] or P[a]["i"] for a, _ in pairs),
                 qmd_emph_matched=sum(Q[b]["b"] or Q[b]["i"] for _, b in pairs),
                 both_emph=sum((P[a]["b"] or P[a]["i"]) and (Q[b]["b"] or Q[b]["i"]) for a, b in pairs))
    return stats, report


if __name__ == "__main__":
    day = int(sys.argv[1])
    stats, report = compare(day)
    print(json.dumps(stats))
    for kind in ("lost", "added", "swapped"):
        rs = [r for r in report if r["kind"] == kind]
        unexpl = [r for r in rs if not r["explained"]]
        print(f"\n=== {kind}: {len(rs)} runs, {len(unexpl)} unexplained ===")
        for r in rs:
            flag = "  " if r["explained"] else "* "
            print(f"{flag}p{r['page']:>2} {r['file'][:22]:22} pdf={r['pdf_style'] or '-':3} qmd={r['qmd_style'] or '-':3} "
                  f"{','.join(r['explained'] + r['notes'])[:30]:30} | {r['snippet'][:150]}")
    if "--json" in sys.argv:
        json.dump(dict(stats=stats, report=report), open(sys.argv[sys.argv.index("--json") + 1], "w"), indent=1)
