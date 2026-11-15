# R1 — Turn notifications: design spec (write-up only)

Scope item R1 from `next-version-scope-2026-11-14.md`: a "Your move"
push when an online / Split Screen opponent plays, plus a nudge when
a game sits idle ~24h. This document is the design only — no code was
changed for R1 in the web pass. Inspected 2026-11-14 in the dev copy
of `mzaras11-blip/swish-crossword-battle` @ main: `functions/index.js`,
`firestore.rules`, `SWISH/SWISHApp.swift` (PushManager),
`SWISH/Multiplayer/FirebaseBackend.swift`, `SWISH/Models.swift`, and
the web game (`SWISH/Resources/web/index.html`).

## What exists today

### Token storage — done
- Tokens live on **`users/{uid}.fcmTokens`** (array of FCM
  registration tokens). Nothing else stores tokens.
- Written natively by **PushManager** (`SWISH/SWISHApp.swift`):
  permission is requested once, after the first sign-in state push
  (never cold at first frame); APNs device token →
  `Messaging.apnsToken` → FCM registration token → `updateData` with
  `arrayUnion` on the user doc. Retried on every auth state push, so
  a token that arrives before the profile doc exists still lands.
  `FirebaseBackend.registerFCMToken` does the same write on its
  sign-in path.
- `firestore.rules` allows the client to update only `fcmTokens` and
  `lastSeenAt` on its own user doc — the token write fits the rules
  as written.

### Sending — done (one helper)
- `functions/index.js` **`sendPush(uid, body, data)`**: reads
  `users/{uid}.fcmTokens`, sends via firebase-admin
  `sendEachForMulticast`, notification title always "S.W.I.S.H",
  APNs sound "default", all `data` values stringified, and prunes
  tokens FCM reports as unregistered/invalid.

### Triggers that already fire (in code)
- **Async matches** (`matches/{id}`, server-authoritative, played
  through the native Multiplayer backend): `onMatchUpdated` pushes
  "Your turn in S.W.I.S.H vs <name>" to the new `currentPlayer` on
  every turn change, and a result push when a match finishes.
- `onChallengeCreated` → "<name> challenged you to S.W.I.S.H".
- **Split Screen**: `onTicketCreated` (a matchmaking ticket was
  answered), `onRoomUpdated` (guest joined → host notified),
  `onRoomEventCreated` for `{t:"start"}` events only (game started →
  both players).
- **Local only**: `ReminderManager` (`SWISH/Models.swift`) schedules
  one local notification 24h after last play ("A fresh crossword
  battle is waiting for you"). It is a generic comeback nudge from
  the retired native UI — not tied to any game or opponent.

## What is missing for R1

1. **Split Screen "your move" push.** Split Screen turns are
   committed as `{t:"commit"}` events in `rooms/{code}/events`
   (written through the native live bridge; the web layer receives
   them via `SwishLive.onRemoteCommit`). `onRoomEventCreated`
   ignores commit events, so a player who backgrounds the app
   mid-game is never told the opponent played.
2. **Per-game idle ~24h nudge.** No scheduled function exists
   (nothing in `functions/` imports `onSchedule`). Async matches
   already carry `turnDeadline` (= turn start + 24h) and a further
   24h grace before `resolveForfeit` can end the game, but nothing
   warns the player whose turn it is as the deadline approaches.
3. **Deployment.** None of this is live until deployed:
   `firestore.rules` is still undeployed (Michael's step, per the
   scope doc), and the functions deploy is the same step —
   `firebase deploy --only functions,firestore:rules` — which needs
   the Blaze plan and firebase-tools. Nothing in the repo proves
   deployment state; treat all of it as not-live until that deploy
   runs and is verified.
4. **Tap routing (minor, native).** Pushes carry routing data
   (`matchId`, or `room` + `kind`), and PushManager presents banners
   in the foreground, but there is no
   `UNUserNotificationCenter` did-receive-response handler — a tap
   just opens the app instead of deep-linking into the match/room.
5. **Web-only players.** The web game has no Web Push (no service
   worker, no FCM web-token flow in `index.html`), so pushes reach
   native-app accounts only. Web players rely on the in-app "Your
   Turn" saved-games list, which already exists. Extending push to
   pure-web players is out of R1's scope unless called for.

## Smallest correct design (the delta)

### A. Split Screen turn push — extend `onRoomEventCreated`
- Same trigger: `rooms/{code}/events/{eventId}` onCreate.
- New branch: if `payload.t === "commit"` and the commit is not the
  game-ending one (`payload.over` falsy and room `status` not
  "over"), send to the room player who did **not** author the event
  (compare `event.from` against `room.hostUid` / `room.guestUid`):
  - body: `Your turn — <sender name> played in your Split Screen game`
  - data: `{ room: <code>, kind: "split-turn" }`
- Reuse `sendPush` unchanged. Split Screen commits exactly once per
  turn, so no extra rate limiting or dedupe is needed.

### B. Idle nudge — one scheduled function
- New v2 scheduled export in `functions/index.js`, e.g.
  `exports.nudgeIdleTurns = onSchedule("every 60 minutes", ...)`.
- Query: `matches` where `status == "active"` and
  `turnDeadline <= now + 1h` and the doc's `nudgeTurn` is missing or
  `< turnNumber`. (Firestore will require a composite index for
  `status` + `turnDeadline`; add it to `firestore.indexes.json` in
  the same change.)
- For each match: `sendPush(currentPlayer, "Your turn is waiting in
  S.W.I.S.H vs <opponent name> — play before the clock runs out",
  { matchId, kind: "turn-nudge" })`, then update the match doc with
  `{ nudgeTurn: turnNumber, nudgeAt: <now> }` so each turn is nudged
  at most once.
- Timing: `turnDeadline` is set 24h out on every turn change, so
  this fires ~23–24h into an idle turn — "idle ~24h" as scoped —
  and lands inside the existing 24h forfeit-grace window, making it
  a warning rather than a post-mortem.
- Split Screen rooms are live/synchronous and ephemeral; the idle
  nudge applies to async matches only.

### C. Deploy + verify
- `firebase deploy --only functions,firestore:rules` (+ indexes) on
  Blaze — the same Michael-owned step that already gates
  `firestore.rules`.
- Verify with two signed-in test accounts: (1) async turn-change
  push arrives on the opponent's device; (2) Split Screen commit
  push arrives on a backgrounded device; (3) a match whose
  `turnDeadline` is forced into the nudge window produces exactly
  one nudge; (4) a stale token is pruned by `sendPush`.

### D. Optional follow-up (not required for R1)
- A did-receive-response handler in PushManager that routes taps by
  `data.kind` / `matchId` / `room` into the right game.

## Payload reference (existing convention — keep it)
- `notification`: `{ title: "S.W.I.S.H", body: <string> }`, APNs
  sound `"default"`.
- `data`: all values strings — `{ matchId }` for async matches,
  `{ room, kind }` for Split Screen, `{ matchId, kind: "turn-nudge" }`
  for the idle nudge.
- Token source of truth stays `users/{uid}.fcmTokens`; never store
  tokens on match or room docs.
