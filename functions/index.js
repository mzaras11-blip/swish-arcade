// S.W.I.S.H async multiplayer — Cloud Functions (Node 20)
//
// Server-authoritative game logic. The client NEVER decides an outcome:
//   - matchmaking pairs waiting tickets and deals the puzzle + racks
//   - submitTurn validates every placement and recomputes ALL scoring
//   - forfeits (voluntary + deadline) are applied here
//   - win/loss records are written here — clients cannot touch them
//   - push notifications go out on turn changes, challenges, match end
//
// Deploy (separate step, needs firebase-tools + Blaze for scheduled fns):
//   firebase deploy --only functions,firestore:rules

const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const fs = require("fs");
const path = require("path");

initializeApp();
const db = getFirestore();
const messaging = getMessaging();

// Tunables (mirror MPConfig in the app)
const TURN_DEADLINE_HOURS = 24;
const FORFEIT_GRACE_HOURS = 24;
const TICKET_STALE_MIN = 5;
const MAX_PENDING_CHALLENGES = 5;
const CHALLENGE_EXPIRY_HOURS = 24;

// ---------------------------------------------------------------- puzzles

let puzzleCache = null;
function loadPuzzles() {
  if (puzzleCache) return puzzleCache;
  const dir = path.join(__dirname, "puzzles");
  puzzleCache = fs.readdirSync(dir)
    .filter((f) => f.endsWith(".json"))
    .map((f) => JSON.parse(fs.readFileSync(path.join(dir, f), "utf8")));
  if (!puzzleCache.length) throw new Error("No puzzles bundled in functions/puzzles/");
  return puzzleCache;
}

// ------------------------------------------------------------ letter bag
// Weighted English distribution — mirrors letterBag in Models.swift.

const BAG = (() => {
  const weights = [
    ["E", 12], ["A", 9], ["I", 9], ["O", 8], ["N", 6], ["R", 6],
    ["T", 6], ["L", 4], ["S", 4], ["U", 4], ["D", 4], ["G", 3],
    ["B", 2], ["C", 2], ["M", 2], ["P", 2], ["F", 2], ["H", 2],
    ["V", 2], ["W", 2], ["Y", 2], ["K", 1], ["J", 1], ["X", 1],
    ["Q", 1], ["Z", 1],
  ];
  const bag = [];
  for (const [letter, n] of weights) for (let i = 0; i < n; i++) bag.push(letter);
  return bag;
})();

function dealRack(n = 5) {
  const rack = [];
  for (let i = 0; i < n; i++) rack.push(BAG[Math.floor(Math.random() * BAG.length)]);
  return rack;
}

// ------------------------------------------------------------ board math

function wordCells(puzzle, wi) {
  const w = puzzle.words[wi];
  const cells = [];
  for (let i = 0; i < w.a.length; i++) {
    cells.push(w.d === "across" ? w.r * puzzle.cols + (w.c + i) : (w.r + i) * puzzle.cols + w.c);
  }
  return cells;
}

const isFilled = (v) => v !== null && v !== undefined;

// ------------------------------------------------------------ match build

function buildMatch(playerIds, usernames) {
  const puzzles = loadPuzzles();
  const puzzle = puzzles[Math.floor(Math.random() * puzzles.length)];
  const now = Timestamp.now();
  const ref = db.collection("matches").doc();
  const data = {
    id: ref.id,
    playerIds,
    usernames,
    puzzle, // full board JSON, identical for both clients
    currentRacks: [dealRack(), dealRack()],
    turnNumber: 0,
    currentPlayer: 0,
    turnDeadline: Timestamp.fromMillis(now.toMillis() + TURN_DEADLINE_HOURS * 3600 * 1000),
    scores: [0, 0],
    completedWords: [],
    filledBy: new Array(puzzle.cells.length).fill(null),
    emptyTurns: 0, // consecutive zero-placement turns (server-side only)
    status: "active",
    winnerIndex: null,
    endReason: null,
    createdAt: now,
    updatedAt: now,
  };
  return { ref, data };
}

function applyStats(tx, match, winnerIndex) {
  for (let i = 0; i < 2; i++) {
    const field = winnerIndex === null || winnerIndex === undefined
      ? "draws" : winnerIndex === i ? "wins" : "losses";
    tx.update(db.collection("users").doc(match.playerIds[i]), {
      [field]: FieldValue.increment(1),
    });
  }
}

function applyForfeit(tx, mRef, match, loserIndex) {
  const winnerIndex = 1 - loserIndex;
  tx.update(mRef, {
    status: "finished",
    winnerIndex,
    endReason: "forfeit",
    updatedAt: FieldValue.serverTimestamp(),
  });
  applyStats(tx, match, winnerIndex);
}

function requireAuth(request) {
  const uid = request.auth && request.auth.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
  return uid;
}

// ------------------------------------------------------------ matchmaking

exports.onTicketCreated = onDocumentCreated("matchmaking/{uid}", async (event) => {
  const ticket = event.data && event.data.data();
  const uid = event.params.uid;
  if (!ticket || ticket.status !== "waiting") return;

  // NOTE: no orderBy here on purpose — equality-only queries need no
  // composite index. We sort the small result set in memory instead.
  const snap = await db.collection("matchmaking")
    .where("status", "==", "waiting")
    .limit(25)
    .get();
  const cutoff = Date.now() - TICKET_STALE_MIN * 60 * 1000;
  const other = snap.docs
    .map((d) => ({ id: d.id, ...d.data() }))
    .filter((t) => t.uid !== uid && t.createdAt && t.createdAt.toMillis() > cutoff)
    .sort((a, b) => a.createdAt.toMillis() - b.createdAt.toMillis())[0];
  if (!other) return;

  const result = await db.runTransaction(async (tx) => {
    const t1 = await tx.get(db.collection("matchmaking").doc(uid));
    const t2 = await tx.get(db.collection("matchmaking").doc(other.uid));
    if (!t1.exists || !t2.exists) return null;
    if (t1.data().status !== "waiting" || t2.data().status !== "waiting") return null;
    const { ref, data } = buildMatch(
      [uid, other.uid],
      [t1.data().username, t2.data().username]
    );
    tx.set(ref, data);
    tx.update(db.collection("matchmaking").doc(uid), { status: "matched", matchId: ref.id });
    tx.update(db.collection("matchmaking").doc(other.uid), { status: "matched", matchId: ref.id });
    return { matchId: ref.id, playerIds: data.playerIds, usernames: data.usernames };
  });

  if (result) {
    // Tell both players a human opponent was found.
    for (let i = 0; i < 2; i++) {
      await sendPush(
        result.playerIds[i],
        `Match found! Your turn vs ${result.usernames[1 - i]}.`,
        { matchId: result.matchId }
      );
    }
  }
});

// ------------------------------------------------------------ turn submit

exports.submitTurn = onCall(async (request) => {
  const uid = requireAuth(request);
  const { matchId, playerIndex, turnNumber, placements } = request.data || {};
  if (!matchId || playerIndex === undefined || turnNumber === undefined || !Array.isArray(placements)) {
    throw new HttpsError("invalid-argument", "Missing turn fields.");
  }

  // Rate limit: one turn per 5 seconds per player.
  const rlRef = db.collection("ratelimits").doc(uid);
  const rl = await rlRef.get();
  const lastTurn = rl.data() && rl.data().lastTurnAt ? rl.data().lastTurnAt.toMillis() : 0;
  if (Date.now() - lastTurn < 5000) {
    throw new HttpsError("resource-exhausted", "Slow down — one turn every 5 seconds.");
  }

  await db.runTransaction(async (tx) => {
    const mRef = db.collection("matches").doc(matchId);
    const mSnap = await tx.get(mRef);
    if (!mSnap.exists) throw new HttpsError("not-found", "Match not found.");
    const m = mSnap.data();

    if (m.status !== "active") throw new HttpsError("failed-precondition", "Match is finished.");
    if (m.playerIds[playerIndex] !== uid) throw new HttpsError("permission-denied", "Not your turn.");
    if (m.currentPlayer !== playerIndex || m.turnNumber !== turnNumber) {
      throw new HttpsError("failed-precondition", "Stale turn — already submitted.");
    }

    // Idempotency: a resubmitted turn returns the current state.
    const turnRef = mRef.collection("turns").doc(String(turnNumber));
    if ((await tx.get(turnRef)).exists) return;

    // Past deadline + grace: the turn is forfeited, not played.
    const nowMs = Date.now();
    if (m.turnDeadline && nowMs > m.turnDeadline.toMillis() + FORFEIT_GRACE_HOURS * 3600 * 1000) {
      applyForfeit(tx, mRef, m, playerIndex);
      return;
    }

    const puzzle = m.puzzle;
    const rack = [...m.currentRacks[playerIndex]];
    const filledBy = [...m.filledBy];
    let turnPoints = 0;
    let blueHit = false;

    for (const p of placements) {
      const cell = puzzle.cells[p.cell];
      if (!cell || cell.k !== "l") throw new HttpsError("invalid-argument", "Not a letter cell.");
      if (isFilled(filledBy[p.cell])) throw new HttpsError("invalid-argument", "Cell already taken.");
      if (typeof p.letter !== "string" || p.letter !== cell.s) {
        throw new HttpsError("invalid-argument", "Letter does not match the solution.");
      }
      const ri = rack.indexOf(p.letter);
      if (ri < 0) throw new HttpsError("invalid-argument", "Letter was not in your rack.");
      rack.splice(ri, 1);
      filledBy[p.cell] = playerIndex;
      turnPoints += 1;
      if (cell.b === true) blueHit = true;
    }

    // Word completions (a placement can finish two words at a crossing).
    const completedWords = [...m.completedWords];
    const wordsDone = [];
    for (let wi = 0; wi < puzzle.words.length; wi++) {
      if (completedWords.includes(wi)) continue;
      if (wordCells(puzzle, wi).every((c) => isFilled(filledBy[c]))) {
        completedWords.push(wi);
        wordsDone.push(wi);
        turnPoints += puzzle.words[wi].a.length;
      }
    }

    // Clean sweep: all 5 tiles placed in one turn.
    if (placements.length === 5) turnPoints += 5;
    // Blue square: the whole turn is doubled.
    if (blueHit && turnPoints > 0) turnPoints *= 2;

    const scores = [...m.scores];
    scores[playerIndex] += turnPoints;

    const empties = puzzle.cells.filter((c, i) => c.k === "l" && !isFilled(filledBy[i])).length;
    const emptyTurns = placements.length === 0 ? (m.emptyTurns || 0) + 1 : 0;
    const stalled = empties < 10 && emptyTurns >= 2;
    const boardFull = empties === 0;

    tx.set(turnRef, {
      playerIndex,
      turnNumber,
      placements,
      scoreDelta: turnPoints,
      wordsCompleted: wordsDone,
      submittedAt: FieldValue.serverTimestamp(),
    });

    if (boardFull || stalled) {
      const winnerIndex = scores[0] === scores[1] ? null : scores[0] > scores[1] ? 0 : 1;
      tx.update(mRef, {
        filledBy, scores, completedWords, emptyTurns,
        status: "finished",
        winnerIndex,
        endReason: "completed",
        updatedAt: FieldValue.serverTimestamp(),
      });
      applyStats(tx, m, winnerIndex);
    } else {
      tx.update(mRef, {
        filledBy, scores, completedWords, emptyTurns,
        currentRacks: [dealRack(), dealRack()],
        currentPlayer: 1 - playerIndex,
        turnNumber: turnNumber + 1,
        turnDeadline: Timestamp.fromMillis(nowMs + TURN_DEADLINE_HOURS * 3600 * 1000),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    tx.set(rlRef, { lastTurnAt: FieldValue.serverTimestamp() }, { merge: true });
  });

  return { ok: true };
});

// ------------------------------------------------------------ forfeits

exports.forfeitMatch = onCall(async (request) => {
  const uid = requireAuth(request);
  const { matchId } = request.data || {};
  if (!matchId) throw new HttpsError("invalid-argument", "Missing matchId.");

  await db.runTransaction(async (tx) => {
    const mRef = db.collection("matches").doc(matchId);
    const mSnap = await tx.get(mRef);
    if (!mSnap.exists) throw new HttpsError("not-found", "Match not found.");
    const m = mSnap.data();
    if (m.status !== "active") throw new HttpsError("failed-precondition", "Match is finished.");
    const loserIndex = m.playerIds.indexOf(uid);
    if (loserIndex < 0) throw new HttpsError("permission-denied", "Not your match.");
    applyForfeit(tx, mRef, m, loserIndex);
  });
  return { ok: true };
});

// Lazy deadline evaluation (called by clients on getMatch; no scheduler).
exports.resolveForfeit = onCall(async (request) => {
  const uid = requireAuth(request);
  const { matchId } = request.data || {};
  if (!matchId) throw new HttpsError("invalid-argument", "Missing matchId.");

  const forfeited = await db.runTransaction(async (tx) => {
    const mRef = db.collection("matches").doc(matchId);
    const mSnap = await tx.get(mRef);
    if (!mSnap.exists) throw new HttpsError("not-found", "Match not found.");
    const m = mSnap.data();
    if (!m.playerIds.includes(uid)) throw new HttpsError("permission-denied", "Not your match.");
    if (m.status !== "active" || !m.turnDeadline) return false;
    if (Date.now() <= m.turnDeadline.toMillis() + FORFEIT_GRACE_HOURS * 3600 * 1000) return false;
    applyForfeit(tx, mRef, m, m.currentPlayer);
    return true;
  });
  return { ok: true, forfeited };
});

// ------------------------------------------------------------ challenges

exports.sendChallenge = onCall(async (request) => {
  const fromUid = requireAuth(request);
  const { toUid } = request.data || {};
  if (!toUid || typeof toUid !== "string") throw new HttpsError("invalid-argument", "Missing player.");
  if (toUid === fromUid) throw new HttpsError("invalid-argument", "You cannot challenge yourself.");

  const me = (await db.collection("users").doc(fromUid).get()).data();
  if (!me || !me.username) throw new HttpsError("failed-precondition", "Claim a username first.");
  const target = await db.collection("users").doc(toUid).get();
  if (!target.exists) throw new HttpsError("not-found", "Player not found.");

  // Anti-spam: max 5 pending outgoing challenges; collapse duplicates.
  const pending = await db.collectionGroup("challenges")
    .where("fromUid", "==", fromUid)
    .where("status", "==", "pending")
    .get();
  const dup = pending.docs.find((d) => d.data().toUid === toUid);
  if (dup) return { ok: true, challengeId: dup.id, duplicate: true };
  if (pending.size >= MAX_PENDING_CHALLENGES) {
    throw new HttpsError("resource-exhausted", "You have too many open challenges.");
  }

  const cRef = db.collection("users").doc(toUid).collection("challenges").doc();
  const now = Timestamp.now();
  await cRef.set({
    id: cRef.id,
    fromUid,
    fromUsername: me.username,
    toUid,
    status: "pending",
    createdAt: now,
    expiresAt: Timestamp.fromMillis(now.toMillis() + CHALLENGE_EXPIRY_HOURS * 3600 * 1000),
  });
  return { ok: true, challengeId: cRef.id };
});

exports.respondToChallenge = onCall(async (request) => {
  const uid = requireAuth(request);
  const { challengeId, accept } = request.data || {};
  if (!challengeId) throw new HttpsError("invalid-argument", "Missing challenge.");

  const cRef = db.collection("users").doc(uid).collection("challenges").doc(challengeId);
  const matchId = await db.runTransaction(async (tx) => {
    const cSnap = await tx.get(cRef);
    if (!cSnap.exists) throw new HttpsError("not-found", "Challenge not found.");
    const c = cSnap.data();
    if (c.toUid !== uid) throw new HttpsError("permission-denied", "Not your challenge.");
    if (c.status !== "pending") throw new HttpsError("failed-precondition", "Challenge already answered.");
    if (c.expiresAt.toMillis() < Date.now()) {
      tx.update(cRef, { status: "expired" });
      throw new HttpsError("failed-precondition", "Challenge expired.");
    }
    if (!accept) {
      tx.update(cRef, { status: "declined" });
      return null;
    }
    const fromUser = (await tx.get(db.collection("users").doc(c.fromUid))).data() || {};
    const toUser = (await tx.get(db.collection("users").doc(uid))).data() || {};
    const { ref, data } = buildMatch(
      [c.fromUid, uid],
      [fromUser.username || "Player", toUser.username || "Player"]
    );
    tx.set(ref, data);
    tx.update(cRef, { status: "accepted", matchId: ref.id });
    return ref.id;
  });

  if (matchId) {
    const m = (await db.collection("matches").doc(matchId).get()).data();
    for (let i = 0; i < 2; i++) {
      await sendPush(m.playerIds[i], `Battle on! Your game vs ${m.usernames[1 - i]} started.`, { matchId });
    }
  }
  return { ok: true, matchId: matchId || null };
});

// ------------------------------------------------------------ push fan-out

async function sendPush(uid, body, data) {
  const u = (await db.collection("users").doc(uid).get()).data() || {};
  const tokens = (u.fcmTokens || []).filter(Boolean);
  if (!tokens.length) return;
  const cleanData = {};
  for (const [k, v] of Object.entries(data || {})) cleanData[k] = String(v);
  const res = await messaging.sendEachForMulticast({
    tokens,
    notification: { title: "S.W.I.S.H", body },
    data: cleanData,
    apns: { payload: { aps: { sound: "default" } } },
  });
  // Drop dead tokens so we stop paying to attempt them.
  const dead = [];
  res.responses.forEach((r, i) => {
    if (!r.success && /not-registered|invalid-registration/i.test(r.error && r.error.code || "")) {
      dead.push(tokens[i]);
    }
  });
  if (dead.length) {
    await db.collection("users").doc(uid).update({
      fcmTokens: FieldValue.arrayRemove(...dead),
    });
  }
}

exports.onChallengeCreated = onDocumentCreated("users/{toUid}/challenges/{cid}", async (event) => {
  const c = event.data && event.data.data();
  if (!c || c.status !== "pending") return;
  await sendPush(c.toUid, `${c.fromUsername} challenged you to a S.W.I.S.H battle!`, {
    challengeId: event.params.cid,
  });
});

exports.onMatchUpdated = onDocumentUpdated("matches/{matchId}", async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();
  if (!after) return;
  if (after.status === "active" && before.currentPlayer !== after.currentPlayer) {
    const idx = after.currentPlayer;
    await sendPush(after.playerIds[idx], `Your turn in S.W.I.S.H vs ${after.usernames[1 - idx]}`, {
      matchId: event.params.matchId,
    });
  }
  if (after.status === "finished" && before.status !== "finished") {
    for (let i = 0; i < 2; i++) {
      const won = after.winnerIndex === i;
      const tied = after.winnerIndex === null || after.winnerIndex === undefined;
      await sendPush(
        after.playerIds[i],
        tied ? `Your match vs ${after.usernames[1 - i]} ended in a tie.`
             : won ? `You beat ${after.usernames[1 - i]} in S.W.I.S.H!`
                   : `${after.usernames[1 - i]} won your S.W.I.S.H match.`,
        { matchId: event.params.matchId }
      );
    }
  }
});

// ------------------------------------------------- Split Screen pushes
//
// Split Screen games are client-run over rooms/{code} + events (no
// callable): the host creates the room, the guest joins (the room doc
// gains guestUid and flips to "live"), and the host deals the game by
// writing a {t:"start"} event. Two push moments fall out of that flow:
//   guest joins  -> tell the host the game is on
//   game starts  -> tell the guest the host dealt the board
// (Your-turn pushes for async matches live in onMatchUpdated above;
// challenge pushes in onChallengeCreated.)

exports.onRoomUpdated = onDocumentUpdated("rooms/{code}", async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();
  if (!before || !after) return;
  const joined = !before.guestUid && !!after.guestUid && after.state === "live";
  if (!joined || !after.hostUid) return;
  await sendPush(after.hostUid,
    `${after.guestName || "A friend"} joined your Split Screen room \u2014 game on!`,
    { room: event.params.code, kind: "split-joined" });
});

exports.onRoomEventCreated = onDocumentCreated("rooms/{code}/events/{eventId}", async (event) => {
  const doc = event.data && event.data.data();
  if (!doc || typeof doc.body !== "string") return;
  let payload = null;
  try { payload = JSON.parse(doc.body); } catch (e) { return; }
  if (!payload || (payload.t !== "start" && payload.t !== "commit")) return;
  const roomSnap = await event.data.ref.parent.parent.get();
  const room = roomSnap.data();
  if (!room || !room.hostUid || !room.guestUid) return;
  if (payload.t === "start") {
    // The host deals the start event; the guest is the recipient.
    if (doc.from !== room.hostUid) return;
    await sendPush(room.guestUid,
      `${room.hostName || "Your friend"} started your Split Screen game!`,
      { room: event.params.code, kind: "split-start" });
    return;
  }
  // payload.t === "commit": a turn was just played. Tell the OTHER
  // player it is their move (a commit is never the game-ending event —
  // game end travels as its own {t:"over"} event). This is the push a
  // backgrounded Split Screen player otherwise never gets.
  if (room.state === "over" || room.state === "ended") return;
  const fromHost = doc.from === room.hostUid;
  const fromGuest = doc.from === room.guestUid;
  if (!fromHost && !fromGuest) return;
  const recipient = fromHost ? room.guestUid : room.hostUid;
  const senderName = (fromHost ? room.hostName : room.guestName) || "Your opponent";
  await sendPush(recipient,
    `Your turn — ${senderName} played in your Split Screen game`,
    { room: event.params.code, kind: "split-turn" });
});

// ------------------------------------------------------------ idle nudge
//
// Async matches carry turnDeadline = turn start + 24h, plus a further
// 24h forfeit grace. Nothing warned the player whose turn it is as the
// deadline approached. This hourly sweep pushes ONE nudge per turn,
// about an hour before the deadline (i.e. ~23h into an idle turn),
// stamped via nudgeTurn so a turn is never nudged twice. Needs the
// composite index in firestore.indexes.json (status + turnDeadline).

exports.nudgeIdleTurns = onSchedule("every 60 minutes", async () => {
  const cutoff = Timestamp.fromMillis(Date.now() + 3600 * 1000);
  const snap = await db.collection("matches")
    .where("status", "==", "active")
    .where("turnDeadline", "<=", cutoff)
    .get();
  for (const docSnap of snap.docs) {
    const m = docSnap.data();
    if (!m.turnDeadline || !Array.isArray(m.playerIds)) continue;
    if (m.nudgeTurn !== undefined && m.nudgeTurn !== null && m.nudgeTurn >= m.turnNumber) continue;
    const idx = m.currentPlayer;
    const uid = m.playerIds[idx];
    if (!uid) continue;
    await sendPush(uid,
      `Your turn is waiting in S.W.I.S.H vs ${m.usernames[1 - idx]} — play before the clock runs out`,
      { matchId: docSnap.id, kind: "turn-nudge" });
    await docSnap.ref.update({
      nudgeTurn: m.turnNumber,
      nudgeAt: FieldValue.serverTimestamp(),
    });
  }
});
