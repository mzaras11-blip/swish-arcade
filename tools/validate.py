#!/usr/bin/env python3
"""Validate generated puzzle JSON files."""
import json, glob, sys, os

def validate(p):
    cols, rows = p["cols"], p["rows"]
    cells = p["cells"]
    assert len(cells) == cols * rows, "cell count"
    words = p["words"]
    # solution grid
    sol = [[None]*cols for _ in range(rows)]
    for r in range(rows):
        for c in range(cols):
            cell = cells[r*cols+c]
            if cell["k"] == "l":
                sol[r][c] = cell["s"]
    # every word's cells must match
    for w in words:
        a, r, c, d = w["a"], w["r"], w["c"], w["d"]
        for i, ch in enumerate(a):
            rr, cc = (r, c+i) if d == "across" else (r+i, c)
            assert sol[rr][cc] == ch, f"word {a} mismatch at {(rr,cc)}"
        # clue cell exists
        qr, qc = (r, c-1) if d == "across" else (r-1, c)
        assert cells[qr*cols+qc]["k"] == "c", f"word {a} missing clue cell"
    # every letter cell covered by >=1 word
    covered = [[False]*cols for _ in range(rows)]
    for w in words:
        a, r, c, d = w["a"], w["r"], w["c"], w["d"]
        for i in range(len(a)):
            rr, cc = (r, c+i) if d == "across" else (r+i, c)
            covered[rr][cc] = True
    for r in range(rows):
        for c in range(cols):
            if sol[r][c] and not covered[r][c]:
                return f"uncovered letter at {(r,c)}"
    # every maximal run of 2+ letters must be exactly a placed word
    wset = set()
    for w in words:
        wset.add((w["a"], w["r"], w["c"], w["d"]))
    for r in range(rows):
        c = 0
        while c < cols:
            if sol[r][c] and (c == 0 or not sol[r][c-1]):
                run, cc = "", c
                while cc < cols and sol[r][cc]:
                    run += sol[r][cc]; cc += 1
                if len(run) >= 2 and (run, r, c, "across") not in wset:
                    return f"phantom across run '{run}' at {(r,c)}"
                c = cc
            else:
                c += 1
    for c in range(cols):
        r = 0
        while r < rows:
            if sol[r][c] and (r == 0 or not sol[r-1][c]):
                run, rr = "", r
                while rr < rows and sol[rr][c]:
                    run += sol[rr][c]; rr += 1
                if len(run) >= 2 and (run, r, c, "down") not in wset:
                    return f"phantom down run '{run}' at {(r,c)}"
                r = rr
            else:
                r += 1
    # clue cells: must carry at least one clue
    for cell in cells:
        if cell["k"] == "c":
            assert cell.get("ca") or cell.get("cd"), "empty clue cell"
    return None

d = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "SWISH", "Resources", "puzzles")
ok = True
for f in sorted(glob.glob(os.path.join(d, "*.json"))):
    p = json.load(open(f))
    err = validate(p)
    status = "OK " if not err else "FAIL"
    if err:
        ok = False
    print(f"{status} {os.path.basename(f)}: {len(p['words'])} words" + (f" -- {err}" if err else ""))
sys.exit(0 if ok else 1)
