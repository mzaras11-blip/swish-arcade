/* Headless checks for Rush mode (Arcade Phase 2).
   Extracts the REAL sources from the shipped index.html — the tile
   draw, the letter-needs scan, lockLetter (with the Rush combo
   multiplier), endGame (the winner decision), and the whole Rush
   section — and exercises them against synthetic board states with
   DOM/effects stubbed. Run: node tools/rush-sim.js <index.html> */
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
const turnSrc = slice("const TURN_SECONDS", ";", "turn consts");
const diffSrc = slice("const DIFFICULTIES = {", "\n      };", "DIFFICULTIES");
const needsSrc = slice("function openLetterNeeds()", "\n      }", "openLetterNeeds");
const drawSrc = slice("function drawTiles(n)", "\n      }", "drawTiles");
const isLetterSrc = slice("const isLetterCell", ";", "isLetterCell");
const isBonusSrc = slice("const isBonus", ";", "isBonus");
const solutionSrc = slice("const solution", ";", "solution");
const emptySrc = slice("function emptyLetterCells()", "\n      }", "emptyLetterCells");
const fullSrc = slice("function isBoardFull()", "}", "isBoardFull");
const remainSrc = slice("function remainingInWord(wi)", "\n      }", "remainingInWord");
const lockSrc = slice("function lockLetter(cell, countsTowardBonus)", "\n      }", "lockLetter");
const endSrc = slice("function endGame()", "\n      }", "endGame");
const rushSrc = slice("/* ================= Rush mode", "/* ================= Rendering", "rush section")
  .replace(/\/\* =+ Rendering[\s\S]*$/, ""); // keep only the Rush section itself

const run = new Function(`
  let G = null;
  let gameSeq = { id: 0 };
  const calls = { record: 0, over: 0, fx: [], toast: [] };
  global.__setG = (g) => { G = g; };
  global.__calls = calls;
  // ---- stubs for everything the real code touches outside itself ----
  const window = {};
  const navigator = {};
  const Haptics = { selection: () => true, impact: () => {} };
  const SFX = { placed() {}, invalid() {}, word() {}, win() {}, lose() {}, select() {}, commit() {} };
  const Fx = { wordComplete(wi, bonus, by) { calls.fx.push([wi, bonus, by]); } };
  const Juice = { noteWord() {}, noteTurn() {} };
  function makeEl() {
    return { hidden: true, textContent: "", innerHTML: "", style: {}, offsetWidth: 0,
      classList: { toggle() {}, add() {}, remove() {} },
      setAttribute() {}, appendChild() {}, querySelector: () => ({ textContent: "" }) };
  }
  const __els = {};
  const $ = (id) => __els[id] || (__els[id] = makeEl());
  const document = { getElementById: $, createElement: () => makeEl(), body: makeEl() };
  function showToast(t) { calls.toast.push(t); }
  function stopTimer() {}
  function renderAll() {}
  function renderHud() {}
  function renderTimer() {}
  function renderAfterMove() {}
  function shakeTile() {}
  function recordGameFinished() { calls.record += 1; }
  function showGameOver() { calls.over += 1; }
  // ---- real code under test ----
  ${bagSrc}
  ${randSrc};
  ${pickSrc};
  ${shuffleSrc}
  ${turnSrc};
  ${diffSrc}
  ${needsSrc}
  ${drawSrc}
  drawTiles.seq = 0;
  ${isLetterSrc};
  ${isBonusSrc};
  ${solutionSrc};
  ${emptySrc}
  ${fullSrc}
  ${remainSrc}
  ${lockSrc}
  ${endSrc}
  ${rushSrc}
  return { rushNewState, rushComboAdvance, rushComboExpire, rushComboBreak,
    rushEnsurePlayable, rushRefillSlot, rushAttemptPlace, rushCpuPlace,
    rushCpuMove, rushTick, rushStart, rushStopClock, rushFinish,
    lockLetter, endGame, drawTiles, openLetterNeeds,
    RUSH_SECONDS, RUSH_COMBO_WINDOW_MS, RUSH_COMBO_MAX, RUSH_CPU_PACE };
`);
const M = run();
const calls = global.__calls;

let failures = 0, checks = 0;
function expect(cond, msg) {
  checks += 1;
  if (!cond) { console.log("FAIL:", msg); failures += 1; }
}

/* A 4-cell, 2-word board (AB / CD) in the exact shape newGame builds. */
function makeG(mode) {
  return {
    puzzle: { title: "T", cells: [{ k: "l", s: "A" }, { k: "l", s: "B" }, { k: "l", s: "C" }, { k: "l", s: "D" }],
              words: [{ a: "AB", r: 0, c: 0, d: "across" }, { a: "CD", r: 0, c: 2, d: "across" }] },
    diff: M ? undefined : undefined, diffKey: "normal",
    filled: [null, null, null, null], filledBy: [null, null, null, null],
    completedWords: new Set(), wordCells: [[0, 1], [2, 3]], cellWords: [[0], [0], [1], [1]],
    aiKnown: new Set([0, 1]),
    rack: [], selectedTileId: null, scores: [0, 0], current: 0,
    secondsLeft: 60, turnPlacements: 0, turnPoints: 0, blueHit: false,
    turnCells: new Set(), turnBlueCells: new Set(), turnMoves: [],
    swapsLeft: 3, hintsUsed: 0, bonusHints: 0, cleanTurns: 0, playerTurns: 0, adPowerups: 0,
    swapPicking: false, swapPicked: new Set(), turnNumber: 1, endWarned: false, stallWarned: false,
    forfeited: false, lettersPlaced: [0, 0], wordsCompleted: [0, 0], consecutiveEmptyTurns: 0,
    aiBusy: false, gameOver: false, winner: null, mode, boostsLeft: 2,
    gameSecondsLeft: null, revealed: [], finalLeft: null, chat: [], saveId: null,
    daily: false, dailyKey: "", rush: null
  };
}
const DIFFS = { easy: { solveChance: 0.45, mistakeChance: 0.16, knownFraction: 0.45 },
                normal: { solveChance: 0.55, mistakeChance: 0.15, knownFraction: 0.55 },
                hard: { solveChance: 0.85, mistakeChance: 0.06, knownFraction: 0.85 } };
function freshG(mode) { const g = makeG(mode); g.diff = DIFFS[g.diffKey]; return g; }

// ---------- spec constants ----------
expect(M.RUSH_SECONDS === 180, "spec: match length constant is 180s (3 minutes)");
expect(M.RUSH_COMBO_WINDOW_MS === 5000, "spec: combo window constant is 5000ms");
expect(M.RUSH_COMBO_MAX === 5, "spec: combo cap constant is x5");
expect(M.RUSH_CPU_PACE.easy > M.RUSH_CPU_PACE.normal && M.RUSH_CPU_PACE.normal > M.RUSH_CPU_PACE.hard,
  "cpu pace: easy slowest, hard fastest");

// ---------- T1: combo steps up and caps ----------
(function () {
  const R = M.rushNewState();
  expect(M.rushComboAdvance(R, 0, 1000) === 1 && R.combo[0] === 1, "T1: first placement scores x1");
  expect(M.rushComboAdvance(R, 0, 2000) === 2, "T1: chained placement -> x2");
  expect(M.rushComboAdvance(R, 0, 3000) === 3, "T1: chained placement -> x3");
  expect(M.rushComboAdvance(R, 0, 4000) === 4, "T1: chained placement -> x4");
  expect(M.rushComboAdvance(R, 0, 5000) === 5, "T1: chained placement -> x5");
  expect(M.rushComboAdvance(R, 0, 6000) === 5 && R.chain[0] === 6, "T1: combo caps at x5 while the chain keeps counting");
  expect(R.combo[1] === 1 && R.chain[1] === 0, "T1: the other player's combo is untouched");
  const R2 = M.rushNewState();
  M.rushComboAdvance(R2, 0, 1000);
  expect(M.rushComboAdvance(R2, 0, 6000) === 2, "T1: a placement exactly 5000ms later still chains (window is inclusive)");
})();

// ---------- T2: window expiry ----------
(function () {
  const R = M.rushNewState();
  M.rushComboAdvance(R, 0, 1000);
  M.rushComboAdvance(R, 0, 2000); // x2, lastAt 2000
  expect(M.rushComboExpire(R, 0, 7000) === false && R.combo[0] === 2, "T2: exactly 5000ms idle does not expire the combo");
  expect(M.rushComboExpire(R, 0, 7001) === true && R.combo[0] === 1 && R.chain[0] === 0, "T2: 5001ms idle expires the combo to x1");
  expect(M.rushComboAdvance(R, 0, 7100) === 1, "T2: the first placement after expiry starts a new chain at x1");
})();

// ---------- T3: combo break ----------
(function () {
  const R = M.rushNewState();
  M.rushComboAdvance(R, 1, 1000);
  M.rushComboAdvance(R, 1, 1500);
  expect(R.combo[1] === 2, "T3: setup — CPU combo at x2");
  M.rushComboBreak(R, 1);
  expect(R.combo[1] === 1 && R.chain[1] === 0, "T3: break resets combo and chain immediately");
})();

// ---------- T4: instant refill + never-dead rack ----------
(function () {
  const g = freshG("rush");
  g.filled = ["A", "B", null, null]; g.filledBy = [0, 0, null, null]; // needs: C, D
  global.__setG(g);
  const rack = [201, 202, 203, 204, 205].map((id) => ({ id, letter: "A", used: false }));
  M.rushRefillSlot(rack, 2);
  expect(rack[2].id !== 203 && rack[2].used === false, "T4: the placed slot is instantly replaced with a fresh, unused tile");
  expect(rack.some((t) => t.letter === "C" || t.letter === "D"), "T4: after refill the rack holds a letter the board still needs");
  // T4b: rushEnsurePlayable on its own, midgame-shaped board (20 open
  // cells, 10 distinct needs — outside every drawTiles guarantee leg
  // that could mask it), rack full of a letter nobody needs.
  const cells = [], filled = [];
  for (let i = 0; i < 60; i++) { cells.push({ k: "l", s: "A" }); filled.push("A"); }
  // open the last 20 cells with the 10 need letters x2
  const needsLetters = ["B", "C", "D", "F", "G", "H", "J", "K", "L", "M"];
  needsLetters.forEach((L, k) => { cells[40 + k] = { k: "l", s: L }; filled[40 + k] = null; cells[50 + k] = { k: "l", s: L }; filled[50 + k] = null; });
  const g2 = freshG("rush");
  g2.puzzle = { title: "T", cells, words: [] }; g2.filled = filled; g2.filledBy = filled.map(() => null);
  global.__setG(g2);
  const rack2 = [301, 302, 303, 304, 305].map((id) => ({ id, letter: "W", used: false }));
  M.rushEnsurePlayable(rack2);
  expect(needsLetters.includes(rack2[0].letter), "T4b: a fully dead rack is forced to carry a needed letter");
})();

// ---------- T5: real placement flow (player) ----------
(function () {
  const g = freshG("rush");
  g.rush = M.rushNewState();
  g.rack = [{ id: 101, letter: "A", used: false }, { id: 102, letter: "B", used: false },
            { id: 103, letter: "E", used: false }, { id: 104, letter: "F", used: false },
            { id: 105, letter: "G", used: false }];
  global.__setG(g);
  M.rushAttemptPlace(101, 0);
  expect(g.filled[0] === "A" && g.filledBy[0] === 0, "T5: correct tile locks in, credited to the player");
  expect(g.scores[0] === 1, "T5: first placement of a chain scores 1 x1 = 1");
  expect(g.rack[0].id !== 101 && g.rack[0].used === false, "T5: the used slot refilled instantly");
  M.rushAttemptPlace(102, 1);
  expect(g.rush.combo[0] === 2, "T5: immediate second placement chains to x2");
  expect(g.scores[0] === 7, "T5: x2 letter (2) + x2 word bonus (2x2=4) on top of 1 = 7");
  expect(calls.fx.length === 1 && calls.fx[0][1] === 4 && calls.fx[0][2] === 0,
    "T5: word-complete effect received the multiplied bonus (4) for the player");
  g.rack[0] = { id: 9999, letter: "Z", used: false };
  M.rushAttemptPlace(9999, 2); // solution is C — wrong
  expect(g.filled[2] === null && g.scores[0] === 7, "T5: a wrong tile scores nothing and does not lock");
  expect(g.rush.combo[0] === 1 && g.rush.chain[0] === 0, "T5: a wrong tile breaks the combo");
  expect(g.rack[0].used === false, "T5: the wrong tile stays in the rack");
})();

// ---------- T6: CPU placement ----------
(function () {
  const g = freshG("rush");
  g.rush = M.rushNewState();
  g.rush.cpuRack = [{ id: 8888, letter: "C", used: false }, { id: 8889, letter: "X", used: false }];
  global.__setG(g);
  M.rushCpuPlace(0, 2);
  expect(g.filled[2] === "C" && g.filledBy[2] === 1, "T6: CPU tile locks in, credited to the CPU");
  expect(g.scores[1] === 1 && g.scores[0] === 0, "T6: CPU scores on its own side at x1");
  expect(g.current === 0, "T6: G.current is restored to the player after the CPU placement");
  expect(g.rush.cpuRack[0].id !== 8888 && g.rush.cpuRack[0].used === false, "T6: CPU rack slot refilled instantly");
  expect(g.rush.combo[1] === 1 && g.rush.chain[1] === 1, "T6: CPU combo chain started");
})();

// ---------- T7: clock runs out -> winner decided ----------
(function () {
  function runOut(scores) {
    const g = freshG("rush");
    g.rush = M.rushNewState();
    g.scores = scores.slice();
    g.rush.lastTick = 1000000;
    g.rush.elapsedMs = (M.RUSH_SECONDS - 1) * 1000;
    global.__setG(g);
    const recBefore = calls.record, overBefore = calls.over;
    M.rushTick(1000000); // 1 second left — still playing
    expect(g.gameOver === false && g.rush.secondsLeft === 1, "T7: at 1s left the match is still live");
    M.rushTick(1002500); // clock crosses zero
    return { g, recBefore, overBefore };
  }
  let r = runOut([10, 4]);
  expect(r.g.gameOver === true && r.g.winner === 0, "T7: higher score at 0:00 wins (player)");
  expect(calls.record === r.recBefore + 1 && calls.over === r.overBefore + 1,
    "T7: timeout runs the standard finish bookkeeping + game-over screen exactly once");
  r = runOut([2, 9]);
  expect(r.g.gameOver === true && r.g.winner === 1, "T7: higher score at 0:00 wins (CPU)");
  r = runOut([6, 6]);
  expect(r.g.gameOver === true && r.g.winner === null, "T7: equal scores at 0:00 are a tie");
  // combo expiry rides the same tick
  const g = freshG("rush");
  g.rush = M.rushNewState();
  g.rush.chain[0] = 3; g.rush.combo[0] = 3; g.rush.lastAt[0] = 5000; g.rush.lastTick = 12000;
  global.__setG(g);
  M.rushTick(12000);
  expect(g.rush.combo[0] === 1 && g.rush.chain[0] === 0, "T7: the match tick expires an idle combo");
})();

// ---------- T8: rushStart smoke ----------
(function () {
  const g = freshG("rush");
  global.__setG(g);
  M.rushStart();
  expect(!!g.rush && g.rush.secondsLeft === M.RUSH_SECONDS, "T8: rushStart creates state with a full clock");
  expect(g.rush.cpuRack.length === 5 && g.rush.cpuRack.every((t) => !t.used), "T8: CPU opening rack dealt, 5 fresh tiles");
  expect(g.rush.cpuRack.some((t) => ["A", "B", "C", "D"].includes(t.letter)), "T8: CPU opening rack is playable on this board");
  M.rushStopClock();
  M.rushStopClock(); // idempotent
  expect(true, "T8: rushStopClock is safe to call twice");
})();

// ---------- T9: turn-mode scoring is untouched ----------
(function () {
  const g = freshG("solo"); // rush stays null
  global.__setG(g);
  M.lockLetter(0, true);
  M.lockLetter(1, true);
  expect(g.scores[0] === 4, "T9: solo scoring unchanged — 1 + 1 + raw word bonus 2 = 4");
  expect(calls.fx[calls.fx.length - 1][1] === 2, "T9: word-complete effect received the raw bonus (2) outside Rush");
})();

console.log(checks + " checks, " + failures + " failed");
console.log(failures === 0 ? "ALL CHECKS PASSED" : failures + " CHECK(S) FAILED");
process.exit(failures === 0 ? 0 : 1);
