/* Headless check of the endgame dead-rack fix (item 6).
   Extracts the REAL LETTER_BAG / rand / pick / shuffle /
   openLetterNeeds / drawTiles sources from the shipped index.html
   and runs them against synthetic board states. Also runs the OLD
   drawTiles (pure random) for comparison numbers. */
const fs = require("fs");
const html = fs.readFileSync(process.argv[2], "utf8");

function slice(from, to, name) {
  const a = html.indexOf(from);
  if (a < 0) throw new Error("not found: " + name);
  const b = html.indexOf(to, a);
  if (b < 0) throw new Error("end not found: " + name);
  return html.slice(a, b + to.length);
}

const bagSrc = slice("const LETTER_BAG =", "})();", "LETTER_BAG");
const randSrc = slice("const rand = (n) =>", ";", "rand");
const pickSrc = slice("const pick = (arr) =>", ";", "pick");
const shuffleSrc = slice("function shuffle(a) {", "\n      }", "shuffle");
const needsSrc = slice("function openLetterNeeds()", "\n      }", "openLetterNeeds");
const drawSrc = slice("function drawTiles(n)", "\n      }", "drawTiles");

const run = new Function(`
  let G = null;
  global.__setG = (g) => { G = g; };
  ${bagSrc}
  ${randSrc};
  ${pickSrc};
  ${shuffleSrc}
  ${needsSrc}
  ${drawSrc}
  return { LETTER_BAG, pick, openLetterNeeds, drawTiles };
`);
const { LETTER_BAG, pick, openLetterNeeds, drawTiles } = run();
console.log("LETTER_BAG tiles:", LETTER_BAG.length);

// OLD algorithm (pre-fix), for comparison numbers.
function oldDrawTiles(n) {
  const tiles = [];
  for (let i = 0; i < n; i++) tiles.push(pick(LETTER_BAG));
  return tiles;
}

// Stub game: totalLetterCells letter cells; the last openLetters.length
// of them are unfilled with those solution letters.
function makeGame(openLetters, totalLetterCells) {
  const cells = [];
  const filled = [];
  for (let i = 0; i < totalLetterCells; i++) { cells.push({ k: "l", s: "A" }); filled.push("A"); }
  openLetters.forEach((L, j) => {
    const i = totalLetterCells - 1 - j;
    cells[i] = { k: "l", s: L };
    filled[i] = null;
  });
  return { puzzle: { cells, cols: totalLetterCells, rows: 1 }, filled };
}

function stats(label, game, trials) {
  global.__setG(game);
  const needs = openLetterNeeds();
  let deadNew = 0, deadOld = 0, ge2New = 0, ge2Old = 0;
  for (let t = 0; t < trials; t++) {
    const rack = drawTiles(5).map((x) => x.letter);
    const hit = rack.filter((L) => needs.distinct.has(L)).length;
    if (hit === 0) deadNew++;
    if (hit >= 2) ge2New++;
    const old = oldDrawTiles(5);
    const hitOld = old.filter((L) => needs.distinct.has(L)).length;
    if (hitOld === 0) deadOld++;
    if (hitOld >= 2) ge2Old++;
  }
  console.log(
    label,
    "| open cells:", needs.cells, "distinct:", needs.distinct.size,
    "| NEW dead:", (deadNew / trials * 100).toFixed(2) + "%",
    "OLD dead:", (deadOld / trials * 100).toFixed(2) + "%",
    "| NEW >=2 needed:", (ge2New / trials * 100).toFixed(1) + "%",
    "OLD >=2 needed:", (ge2Old / trials * 100).toFixed(1) + "%"
  );
  return { deadNew, deadOld, ge2New, ge2Old, needs };
}

const T = 20000;
let failures = 0;
function expect(cond, msg) { if (!cond) { console.log("FAIL:", msg); failures++; } }

// S1: late endgame — 10 open cells, needs EEEE AA TT S Z (distinct 5)
let r = stats("S1 endgame(10 cells, 5 distinct)", makeGame(["E","E","E","E","A","A","T","T","S","Z"], 60), T);
expect(r.deadNew === 0, "S1: new draw must never deal a dead rack");
expect(r.ge2New === T, "S1: every rack must carry >=2 needed letters (guarantee)");

// S2: distinct-trigger only — 20 open cells but only 4 distinct letters
r = stats("S2 endgame(20 cells, 4 distinct)", makeGame(["Q","U","I","Z","Q","U","I","Z","Q","U","I","Z","Q","U","I","Z","Q","U","I","Z"], 60), T);
expect(r.deadNew === 0, "S2: new draw must never deal a dead rack");
expect(r.ge2New === T, "S2: guarantee applies via the distinct<=8 leg");

// S3: midgame — 40 open cells, 20 distinct letters: NO guarantee.
// The new draw's distribution must match the old pure-random one.
r = stats("S3 midgame(40 cells, 20 distinct)", makeGame(["A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P","R","S","T","U","A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P","R","S","T","U"], 60), T);
expect(Math.abs(r.ge2New - r.ge2Old) < T * 0.015, "S3: midgame >=2-needed rate must match pure random within 1.5pts (no distortion)");
expect(Math.abs(r.deadNew - r.deadOld) < T * 0.005, "S3: midgame dead rate must match pure random (guarantee off)");

// S4: no game / full board — no crash, 5 tiles.
global.__setG(null);
expect(drawTiles(5).length === 5, "S4: no-game draw returns 5 tiles");
global.__setG(makeGame([], 60));
expect(drawTiles(5).length === 5, "S4b: full-board draw returns 5 tiles");
console.log("S4 no-game/full-board draws OK");

// S5: dealRack free-swap block (logic replicated condition-for-condition
// from the shipped dealRack). Board state chosen so the drawTiles
// guarantee is OFF (>12 open cells AND >8 distinct needed) while dead
// racks are common: 30 open cells over 12 rare/mid letters (~19% of
// the bag), so ~28% of pure-random racks hold nothing playable.
(function () {
  const game = makeGame(["Q","Q","Q","Z","Z","Z","X","X","X","J","J","J","K","K","K","V","V","V","B","B","P","P","Y","Y","W","W","F","F","H","H"], 60);
  global.__setG(game);
  const needs = openLetterNeeds();
  let swaps = 0, toasts = 0, bad = 0;
  for (let t = 0; t < 3000; t++) {
    let rackTiles = drawTiles(5);
    // --- shipped dealRack free-swap block, same conditions ---
    if (needs.distinct.size > 0 && !rackTiles.some((x) => needs.distinct.has(x.letter))) {
      let tries = 0;
      while (tries < 25 && !rackTiles.some((x) => needs.distinct.has(x.letter))) {
        rackTiles = drawTiles(5);
        tries += 1;
      }
      toasts += 1; // showToast("No playable letters — free swap")
      swaps += tries;
    }
    // --- end shipped block ---
    if (!rackTiles.some((x) => needs.distinct.has(x.letter))) bad++;
  }
  console.log("S5 free-swap: 3000 deals vs rare-letter board; dead racks surviving:", bad, "| free re-draws:", swaps, "| toasts:", toasts);
  expect(bad === 0, "S5: no dead rack may survive the free-swap loop");
})();

console.log(failures === 0 ? "ALL CHECKS PASSED" : failures + " CHECK(S) FAILED");
process.exit(failures === 0 ? 0 : 1);
