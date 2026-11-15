/* Headless checks for Rush PvP (build 5 — Rush as a selectable
   game type in the Online/Friends flows).
   Extracts the REAL sources from the shipped index.html — tile
   draws, newGame, lockLetter, endGame, and the whole Rush section
   including the build-5 PvP block (seeded stream, race clock,
   score exchange, finalize/forfeit rules) — and exercises them
   against two synthetic clients with the room transport stubbed.
   The "same puzzle" half of the fairness pair is by construction
   (the host sends the puzzle object itself, like Split Screen's
   start) and is not simulated here; the seeded tile stream, the
   sync/finalize protocol and the winner rules are.
   Run: node tools/rush-pvp-sim.js <index.html> */
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
const colsSrc = slice("const COLS = 8", ";", "COLS");
const turnSrc = slice("const TURN_SECONDS", ";", "turn consts");
const maxSrc = slice("const MAX_SWAPS", ";", "max consts");
const blitzSrc = slice("const BLITZ_SECONDS", ";", "blitz const");
const diffSrc = slice("const DIFFICULTIES = {", "\n      };", "DIFFICULTIES");
const mulberrySrc = slice("function mulberry32(a) {", "\n      }", "mulberry32");
const needsSrc = slice("function openLetterNeeds()", "\n      }", "openLetterNeeds");
const drawSrc = slice("function drawTiles(n)", "\n      }", "drawTiles");
const dealSrc = slice("function dealRack() {", "\n      }", "dealRack");
const newGameSrc = slice("function newGame(puzzle, diffKey, mode) {", "\n      }", "newGame");
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
  const calls = { record: 0, over: 0, toast: [], sent: [] };
  global.__setG = (g) => { G = g; };
  global.__getG = () => G;
  global.__calls = calls;
  // ---- fake timers: capture, never fire on their own ----
  const __timeouts = [];
  function setTimeout(fn, ms) { __timeouts.push({ fn, ms }); return __timeouts.length; }
  function clearTimeout(id) { if (id && __timeouts[id - 1]) __timeouts[id - 1] = null; }
  let __intSeq = 0;
  function setInterval() { __intSeq += 1; return __intSeq; }
  function clearInterval() {}
  function __fireTimeout(i) { const t = __timeouts[i]; if (t && t.fn) { __timeouts[i] = null; t.fn(); } }
  // ---- stubs for everything the real code touches outside itself ----
  const SwishLive = {
    sendRack() {},
    gameEnded() {},
    rushPvpSend(payload) { calls.sent.push(JSON.parse(JSON.stringify(payload))); },
    peerLabel() { return "Peer"; }
  };
  const window = { SwishLive };
  const navigator = {};
  const Haptics = { selection: () => true, impact: () => {} };
  const SFX = { placed() {}, invalid() {}, word() {}, win() {}, lose() {}, select() {}, commit() {} };
  const Fx = { wordComplete() {} };
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
  function startTimer() {}
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
  ${colsSrc};
  ${turnSrc};
  ${maxSrc};
  ${blitzSrc};
  ${diffSrc}
  ${mulberrySrc}
  ${needsSrc}
  ${drawSrc}
  drawTiles.seq = 0;
  ${dealSrc}
  ${newGameSrc}
  ${isLetterSrc};
  ${isBonusSrc};
  ${solutionSrc};
  ${emptySrc}
  ${fullSrc}
  ${remainSrc}
  ${lockSrc}
  ${endSrc}
  ${rushSrc}
  return { rushPvpStream, rushPvpSetup, rushPvpTick, rushPvpSendScore,
    rushPvpReceiveScore, rushPvpReceiveOver, rushPvpLocalFinish, rushPvpOppLeft,
    rushPvpFinalize, rushPvpStartClock, rushPvpStopClock,
    rushAttemptPlace, rushRefillSlot, rushEnsurePlayable, rushFinish,
    newGame, drawTiles, LETTER_BAG,
    RUSH_SECONDS, RUSH_PVP_COUNTDOWN_MS, RUSH_PVP_GRACE_MS,
    __timeouts, __fireTimeout };
`);
const M = run();
const calls = global.__calls;

let failures = 0, checks = 0;
function expect(cond, msg) {
  checks += 1;
  if (!cond) { console.log("FAIL:", msg); failures += 1; }
}
const rackSig = (g) => JSON.stringify(g.rack.map((t) => [t.id, t.letter]));

/* A 96-cell puzzle in the exact shape generatePuzzle returns:
   AB across at r0c0 (cells 0,1), CD across at r0c2 (cells 2,3),
   everything else black. Needs are A, B, C, D in board order. */
function makePuzzle() {
  const cells = [];
  for (let i = 0; i < 96; i++) cells.push({ k: "x", s: null, ca: null, cd: null, b: false });
  cells[0] = { k: "l", s: "A", ca: null, cd: null, b: false };
  cells[1] = { k: "l", s: "B", ca: null, cd: null, b: false };
  cells[2] = { k: "l", s: "C", ca: null, cd: null, b: false };
  cells[3] = { k: "l", s: "D", ca: null, cd: null, b: false };
  return { title: "Rush", cols: 8, rows: 12, cells,
           words: [{ a: "AB", r: 0, c: 0, d: "across" }, { a: "CD", r: 0, c: 2, d: "across" }] };
}
/* One racer client: real newGame + real rushPvpSetup, live room set. */
function makeClient(seed, startAt) {
  M.newGame(makePuzzle(), "normal", "rush");
  const g = global.__getG();
  g.live = { room: "TEST", host: true, rush: true };
  M.rushPvpSetup(seed, startAt);
  return g;
}

// ---------- P1: the shared stream is deterministic ----------
(function () {
  const a = M.rushPvpStream(123456), b = M.rushPvpStream(123456), c = M.rushPvpStream(123457);
  const sa = a.draw(200), sb = b.draw(200), sc = c.draw(200);
  expect(JSON.stringify(sa) === JSON.stringify(sb), "P1: same seed -> identical 200-tile sequence (ids + letters)");
  expect(JSON.stringify(sa) !== JSON.stringify(sc), "P1: a different seed -> a different sequence");
  expect(sa.every((t, i) => t.id === i + 1), "P1: tile ids run 1..n in draw order");
  const bag = new Set(M.LETTER_BAG);
  expect(sa.every((t) => bag.has(t.letter) && !t.used), "P1: every stream tile is a fresh LETTER_BAG letter");
  const a2 = M.rushPvpStream(42), b2 = M.rushPvpStream(42);
  expect(JSON.stringify(a2.draw(5)) === JSON.stringify(b2.draw(5)), "P1: opening racks from the same seed are identical");
})();

// ---------- P2: two clients, one seed -> identical race setup ----------
(function () {
  const A = makeClient(777, 1000000);
  const sigA = rackSig(A);
  const B = makeClient(777, 1000000);
  expect(rackSig(B) === sigA, "P2: both racers are dealt the identical opening rack");
  expect(A.mode === "rush" && !!A.rush && !!A.rushPvp, "P2: setup installs rush + rushPvp state");
  expect(A.rushPvp.seed === 777 && A.rushPvp.startAt === 1000000, "P2: seed and startAt are recorded on the race state");
  expect(A.rack.length === 5 && A.rack.every((t) => !t.used), "P2: opening rack is 5 fresh tiles");
  const C = makeClient(778, 1000000);
  expect(rackSig(C) !== sigA, "P2: a different room seed deals a different rack");
})();

// ---------- P3: refills stay in lockstep on both phones ----------
(function () {
  const A = makeClient(4242, 1000000);
  const B = makeClient(4242, 1000000);
  for (let k = 0; k < 3; k++) {
    global.__setG(A); M.rushRefillSlot(A.rack, 0);
    global.__setG(B); M.rushRefillSlot(B.rack, 0);
    expect(rackSig(A) === rackSig(B), "P3: racks still identical after refill " + (k + 1));
  }
  // and the refills really are the stream's next draws, in order
  const ref = M.rushPvpStream(4242);
  ref.draw(5); // opening rack
  global.__setG(A);
  const before = A.rack[1].id;
  M.rushRefillSlot(A.rack, 1);
  const expected = ref.drawTile();
  expect(A.rack[1].letter === expected.letter || A.rack[0].letter === "A",
    "P3: a refill draws the stream's next tile (unless the never-dead guarantee rewrote slot 0)");
  expect(A.rack[1].id !== before, "P3: the refilled slot holds a fresh tile");
})();

// ---------- P4: the never-dead guarantee is deterministic and consumes no stream ----------
(function () {
  const A = makeClient(777, 1000000); // stream seq now at 5 (opening rack)
  A.rack = [901, 902, 903, 904, 905].map((id) => ({ id, letter: "Z", used: false }));
  global.__setG(A);
  M.rushEnsurePlayable(A.rack);
  expect(A.rack[0].letter === "A", "P4: a dead PvP rack is guaranteed the first needed letter (board order)");
  expect(A.rack[0].id === 6, "P4: the guarantee tile takes the stream's next id (no letter drawn)");
  const ref = M.rushPvpStream(777);
  ref.draw(5);
  const expected = ref.drawTile();
  M.rushRefillSlot(A.rack, 1);
  expect(A.rack[1].letter === expected.letter, "P4: the next refill still matches the shared stream — the guarantee did not desync it");
})();

// ---------- P5: countdown refuses placements; after GO a placement lands ----------
(function () {
  const A = makeClient(99, Date.now() + 60000); // race starts a minute from now
  global.__setG(A);
  const cellFor = { A: 0, B: 1, C: 2, D: 3 };
  const tile = A.rack.find((t) => cellFor[t.letter] !== undefined);
  expect(!!tile, "P5: setup — the opening rack holds a playable tile for this board");
  if (tile) {
    M.rushAttemptPlace(tile.id, cellFor[tile.letter]);
    expect(A.filled[cellFor[tile.letter]] === null && A.scores[0] === 0,
      "P5: before startAt a placement is refused (shared countdown)");
  }
  A.rushPvp.startAt = Date.now() - 1000; // the race has begun
  M.rushPvpTick(Date.now());
  expect(A.rushPvp.went === true, "P5: the tick flips the race to GO at startAt");
  const tile2 = A.rack.find((t) => cellFor[t.letter] !== undefined && !t.used);
  if (tile2) {
    const slotId = tile2.id;
    M.rushAttemptPlace(tile2.id, cellFor[tile2.letter]);
    expect(A.filled[cellFor[tile2.letter]] === tile2.letter && A.scores[0] >= 1,
      "P5: after GO a correct placement locks in and scores");
    expect(A.rack.every((t) => t.id !== slotId || t.used === false), "P5: the placed slot was refilled from the stream");
  } else {
    expect(false, "P5: setup — a playable tile exists after GO");
  }
})();

// ---------- P6: score sync payloads (on change, final always sent) ----------
(function () {
  const A = makeClient(5150, 1000000);
  global.__setG(A);
  const n0 = calls.sent.length;
  M.rushPvpSendScore(false);
  expect(calls.sent.length === n0 + 1, "P6: the first sync sends the zero state");
  const p0 = calls.sent[calls.sent.length - 1];
  expect(p0.t === "rushScore" && p0.score === 0 && p0.combo === 1 && p0.letters === 0 && p0.words === 0 && p0.final === false,
    "P6: payload shape is {t:'rushScore', score, combo, letters, words, final}");
  M.rushPvpSendScore(false);
  expect(calls.sent.length === n0 + 1, "P6: an unchanged state is not re-sent (throttle by change)");
  A.scores[0] = 7; A.lettersPlaced[0] = 3; A.wordsCompleted[0] = 1; A.rush.combo[0] = 3;
  M.rushPvpSendScore(false);
  const p1 = calls.sent[calls.sent.length - 1];
  expect(calls.sent.length === n0 + 2 && p1.score === 7 && p1.letters === 3 && p1.words === 1 && p1.combo === 3,
    "P6: a changed state sends the new totals");
  M.rushPvpSendScore(true);
  const p2 = calls.sent[calls.sent.length - 1];
  expect(p2.final === true && p2.score === 7, "P6: the final report always sends, flagged final");
})();

// ---------- P7: the final exchange decides the race ----------
(function () {
  // peer final first, then my clock runs out
  const A = makeClient(31, 1000000);
  const B = makeClient(31, 1000000);
  A.scores[0] = 10; A.lettersPlaced[0] = 6; A.wordsCompleted[0] = 2;
  global.__setG(A); M.rushPvpSendScore(true);
  const pA = calls.sent[calls.sent.length - 1];
  global.__setG(B);
  M.rushPvpReceiveScore(pA);
  expect(B.scores[1] === 10 && B.lettersPlaced[1] === 6 && B.wordsCompleted[1] === 2,
    "P7: a peer report mirrors score/letters/words onto side 1");
  expect(B.gameOver === false, "P7: the peer finishing does not end my race early");
  B.scores[0] = 12;
  const recBefore = calls.record, overBefore = calls.over;
  M.rushPvpTick(1000000 + (M.RUSH_SECONDS + 1) * 1000); // my clock runs out
  expect(B.gameOver === true && B.winner === 0, "P7: both finals in -> higher score wins (12 beats 10)");
  expect(calls.record === recBefore + 1 && calls.over === overBefore + 1,
    "P7: the finish runs the standard bookkeeping + game-over screen exactly once");

  // a draw is a draw
  const A2 = makeClient(32, 1000000);
  const B2 = makeClient(32, 1000000);
  A2.scores[0] = 9;
  global.__setG(A2); M.rushPvpSendScore(true);
  const pA2 = calls.sent[calls.sent.length - 1];
  global.__setG(B2);
  M.rushPvpReceiveScore(pA2);
  B2.scores[0] = 9;
  M.rushPvpLocalFinish();
  expect(B2.gameOver === true && B2.winner === null, "P7: equal finals are a tie");

  // I finish first: grace wait, then decide on the last known score
  const B3 = makeClient(33, 1000000);
  global.__setG(B3);
  M.rushPvpReceiveScore({ t: "rushScore", score: 4, combo: 2, letters: 2, words: 0, final: false });
  B3.scores[0] = 5;
  const t0 = M.__timeouts.length;
  M.rushPvpLocalFinish();
  expect(B3.gameOver === false, "P7: finishing first waits for the peer's final");
  const grace = M.__timeouts.slice(t0).find((t) => t && t.ms === M.RUSH_PVP_GRACE_MS);
  expect(!!grace, "P7: the grace timer is armed at RUSH_PVP_GRACE_MS (" + M.RUSH_PVP_GRACE_MS + "ms)");
  M.__fireTimeout(M.__timeouts.indexOf(grace));
  expect(B3.gameOver === true && B3.winner === 0, "P7: after the grace wait the last known score decides (5 beats 4)");
})();

// ---------- P8: leave / forfeit / over-ack paths ----------
(function () {
  // peer leaves while ahead on points: I still win
  const B = makeClient(41, 1000000);
  global.__setG(B);
  M.rushPvpReceiveScore({ t: "rushScore", score: 8, combo: 1, letters: 5, words: 1, final: false });
  B.scores[0] = 3;
  M.rushPvpOppLeft();
  expect(B.gameOver === true && B.oppLeft === true && B.winner === 0,
    "P8: a mid-race leave is a forfeit win for the player who stayed, whatever the scoreboard says");

  // the peer's "over" ack completes my pending finish with their real final
  const B2 = makeClient(42, 1000000);
  global.__setG(B2);
  B2.scores[0] = 5;
  M.rushPvpLocalFinish();
  expect(B2.gameOver === false, "P8: setup — waiting on the peer after my finish");
  M.rushPvpReceiveOver({ scores: [11, 3] });
  expect(B2.gameOver === true && B2.scores[1] === 11 && B2.winner === 1,
    "P8: the over-ack supplies the peer's final (11) and the race is decided honestly (I lose)");
})();

// ---------- P9: solo Rush is untouched by the PvP branches ----------
(function () {
  const cells = [], filled = [], filledBy = [];
  for (let i = 0; i < 96; i++) { cells.push({ k: "x", s: null, b: false }); filled.push(null); filledBy.push(null); }
  cells[0] = { k: "l", s: "C", b: false }; cells[1] = { k: "l", s: "D", b: false };
  filled[0] = "C"; filledBy[0] = 0; filled[1] = "D"; filledBy[1] = 0;
  // board still needs nothing at 0,1 — reopen them:
  filled[0] = null; filledBy[0] = null; filled[1] = null; filledBy[1] = null;
  const g = {
    puzzle: { title: "T", cells, words: [{ a: "CD", r: 0, c: 0, d: "across" }] },
    diff: { solveChance: 0.55, mistakeChance: 0.15, knownFraction: 0.55 }, diffKey: "normal",
    filled, filledBy, completedWords: new Set(), wordCells: [[0, 1]], cellWords: [[0], [0]],
    aiKnown: new Set([0]), rack: [], selectedTileId: null, scores: [0, 0], current: 0,
    secondsLeft: 60, turnPlacements: 0, turnPoints: 0, blueHit: false,
    turnCells: new Set(), turnBlueCells: new Set(), turnMoves: [],
    swapsLeft: 3, hintsUsed: 0, bonusHints: 0, cleanTurns: 0, playerTurns: 0, adPowerups: 0,
    swapPicking: false, swapPicked: new Set(), turnNumber: 1, endWarned: false, stallWarned: false,
    forfeited: false, lettersPlaced: [0, 0], wordsCompleted: [0, 0], consecutiveEmptyTurns: 0,
    aiBusy: false, gameOver: false, winner: null, mode: "rush", boostsLeft: 2,
    gameSecondsLeft: null, revealed: [], finalLeft: null, chat: [], saveId: null,
    daily: false, dailyKey: "", rush: null, live: null
  };
  global.__setG(g);
  const rack = [201, 202, 203, 204, 205].map((id) => ({ id, letter: "A", used: false }));
  M.rushRefillSlot(rack, 2);
  expect(rack[2].id !== 203 && rack[2].used === false, "P9: solo refill still replaces the slot instantly (no rushPvp)");
  expect(rack.some((t) => t.letter === "C" || t.letter === "D"), "P9: solo never-dead guarantee still applies");
  g.rush = { secondsLeft: 0, elapsedMs: 0, lastTick: 0, combo: [1, 1], chain: [0, 0], lastAt: [0, 0], cpuRack: [], cpuTimer: null, paused: false };
  M.rushFinish();
  expect(g.gameOver === true, "P9: solo rushFinish still goes straight to endGame");
})();

console.log(checks + " checks, " + failures + " failed");
console.log(failures === 0 ? "ALL CHECKS PASSED" : failures + " CHECK(S) FAILED");
process.exit(failures === 0 ? 0 : 1);
