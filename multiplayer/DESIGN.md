# S.W.I.S.H Async Multiplayer — Design

Turn-based online play like Kryss: real humans, **asynchronous** (long turn
windows, no live connection). The server only does work when a turn is
submitted, which keeps it cheap.

**Hard rule, non-negotiable:** bots are never disguised as humans. When no
human opponent is found, the app offers a game against a clearly-labeled
**CPU** opponent. No fake usernames, no fake activity.

## 1. Backend choice

Firebase (Google), all managed, generous free tier:

| Piece | Firebase product | What it does |
|---|---|---|
| Accounts | Authentication | Anonymous sign-in, upgradeable to Apple Sign-In later |
| Data | Cloud Firestore | Profiles, matchmaking tickets, matches, turns, challenges |
| Game logic | Cloud Functions (Node.js) | Matchmaking, puzzle dealing, turn validation + scoring, forfeits |
| Notifications | Cloud Messaging (FCM) | "Your turn" / challenge / forfeit pushes |

Why async is cheap: there are no persistent connections and no game servers
to keep warm. A Cloud Function runs for a second or two on each turn
submission, then sleeps. Firestore stores a few small documents per match.
Early scale fits comfortably in the free tier.

## 2. Accounts, usernames, profiles

- **Sign-in:** Firebase Anonymous Auth on first launch. No email, no
  password, zero friction. The anonymous account can later be *linked* to
  Apple Sign-In (one line of SDK code) so the profile survives reinstalls.
- **Username:** player picks one at first multiplayer use. Rules: 3–16
  characters, letters/numbers/underscore only, case-insensitive uniqueness.
  Claimed via a `usernames/{lowercased}` document written in a transaction —
  first writer wins, so two players can never grab the same name.
- **Profile** (`users/{uid}`):
  - `uid`, `username`, `createdAt`
  - `wins`, `losses`, `draws` — **written only by Cloud Functions** when a
    match finishes. Clients can never edit their own record (anti-cheat).
  - `fcmTokens[]` — device push tokens, updated by the client on launch.
  - `lastSeenAt` — for "active" sorting later.

Firestore rules: a player can read any public profile, but can only write
their own `fcmTokens`, `username` (once, via the claim flow), and
`lastSeenAt`.

## 3. Matchmaking (play a random opponent)

Goal: tap "Play Online", wait a short time, get a human or a labeled CPU.

1. Client writes a ticket to `matchmaking/{uid}`:
   `{ uid, username, createdAt, status: "waiting" }`, then listens for its
   ticket to be updated.
2. A Cloud Function triggers on ticket creation: it queries for the oldest
   other `waiting` ticket, and in a transaction marks both tickets
   `status: "matched"` and creates `matches/{matchId}` (see §5).
3. Client timeout: **30 seconds**. If no match arrives, the client deletes
   its ticket and shows: *"No players waiting right now — play the CPU
   instead?"* with the opponent labeled **CPU** and a difficulty picker.
   This is the honest backfill. It reuses the existing local AI
   (`Difficulty` easy/normal/hard in `Models.swift`); the game runs fully
   offline exactly like today's solo mode.
4. Edge cases: both players must have distinct uids (can't match yourself);
   stale tickets (older than 5 minutes) are ignored and cleaned up.

No skill rating at launch — first version matches anyone waiting. Rating can
be added later without changing this flow.

## 4. Friend challenges (play someone you know)

1. **Search:** exact username lookup —
   `usernames/{input.lowercased()}` → uid → public profile. (Prefix search
   can come later; exact match is unambiguous and cheap.)
2. **Challenge:** client writes `users/{toUid}/challenges/{challengeId}`:
   `{ fromUid, fromUsername, status: "pending", createdAt, expiresAt }`
   (expires after 24h). A Cloud Function sends the recipient a push:
   *"<name> challenged you to a S.W.I.S.H battle!"*
3. **Respond:** recipient accepts or declines from an inbox screen.
   - Accept → Cloud Function creates the `matches/{matchId}` doc (same as
     §5) and notifies both players.
   - Decline/expire → challenge doc deleted; challenger gets a push.
4. Anti-spam: max 5 pending outgoing challenges per player; can't challenge
   yourself; challenges to the same player collapse into one.

## 5. Match document model

`matches/{matchId}` — created **only by Cloud Functions**, never by clients:

```
matchId:        string (auto)
playerIds:      [uidA, uidB]          // index 0/1 = player index everywhere
usernames:      [nameA, nameB]        // denormalized for display
puzzle:         Puzzle (full JSON)    // dealt by the server: BOTH clients
                                          // decode the identical board
currentRacks:   [[String]]            // 5 letters per player for this turn
turnNumber:     int                   // increments each turn
currentPlayer:  int                   // 0 or 1 — whose turn it is
turnDeadline:   timestamp             // when the current turn expires
scores:        [int, int]
completedWords: [int]                 // word indices already finished
filledBy:       [int?]                // per cell: which player placed it
status:         "waiting" | "active" | "finished"
winnerIndex:    int?                  // set when finished
endReason:      "completed" | "forfeit" | null
createdAt, updatedAt: timestamps
```

Notes:
- The **full puzzle JSON is embedded** in the match doc. Both clients decode
  it with the existing `Puzzle` Codable struct and feed it straight into
  `GameViewModel`. No seeded-RNG determinism risk, no version skew.
- Racks are dealt server-side per turn from the shared letter distribution
  (`letterBag` weights in `Models.swift`, mirrored in the function).
- `turnDeadline` = now + **24 hours** (tunable in `MPConfig`). Async like
  Kryss: nobody stares at a timer.

Turn history: `matches/{matchId}/turns/{turnNumber}` — `{ playerIndex,
placements: [{cell, letter}], scoreDelta, wordsCompleted, submittedAt }`.
Written only by the Cloud Function after validation. This doubles as the
anti-cheat audit trail and powers rematch replays later.

## 6. Turn submission flow (server-authoritative)

1. During your turn the client plays locally exactly like solo mode
   (5 tiles, undo, swap — all existing UI). Nothing leaves the device yet.
2. On "End Turn" (or when the player passes), the client sends
   `MPTurn { matchId, playerIndex, turnNumber, placements: [{cell, letter}] }`
   to the `submitTurn` Cloud Function. **The client never sends a score.**
3. The function, in a Firestore transaction:
   - Rejects if: not your turn, wrong `turnNumber` (stale/replay), match not
     `active`, past `turnDeadline` (+ grace, see §7), or rate-limited.
   - Validates every placement:
     - cell is a letter cell and currently empty in the match doc,
     - `letter` equals the puzzle solution for that cell,
     - the multiset of letters was actually in the player's dealt rack.
   - Recomputes scoring from scratch using the real rules:
     +1 per correct letter, +word-length bonus for each newly completed
     word, **turn total doubled if any placement hit a blue square**
     (mirrors `GameViewModel.endTurn`).
   - Applies the placements to `filledBy`, updates `scores`,
     `completedWords`, deals the **next player's** 5-tile rack,
     advances `currentPlayer`/`turnNumber`, sets the next `turnDeadline`.
   - Detects game end (board full, or the two-empty-turns rule with <10
     letters left — same rule as local play) → `status: "finished"`,
     sets `winnerIndex`, and updates both players' win/loss records.
4. Function returns the updated `MPMatch`; client refreshes. Loser/winner
   both get a push: *"Your turn in S.W.I.S.H vs <name>"*.

Because scoring is recomputed server-side from the puzzle solution, a hacked
client can only submit *legal* moves — the worst it can do is play well.

## 7. Turn deadlines and forfeits

- Each turn: **24 hours**. A visible countdown in the match list.
- Missed deadline → **24-hour grace period** (life happens; Kryss-style games
  are forgiving). After grace, the match is forfeited: the player whose turn
  it was loses, the other wins.
- Forfeit evaluation is **lazy** (keeps the free tier free): every
  `getMatch`/`submitTurn` call checks deadlines first. No Cloud Scheduler
  needed. (Phase 2 upgrade: a scheduled sweeper for instant forfeit pushes —
  requires the Blaze plan.)
- A player can also forfeit voluntarily from the match screen.

## 8. Push notifications (FCM)

Sent by Cloud Functions on: your turn started, challenge received,
challenge accepted/declined, opponent forfeited, match finished. Payloads
carry only the matchId — the client fetches fresh state on open (never trust
payload data). Quiet hours are a client-side setting later; not v1.

## 9. Anti-cheat basics (v1)

- Server deals the puzzle, the racks, and computes all scoring.
- Clients can only *request* turn submission; the function validates and
  writes.
- Firestore rules: players read matches they're in; write access is limited
  to their own matchmaking ticket, challenge responses, and profile fields
  listed in §2. Match docs and turns are function-only writes.
- Rate limits in the function: max 1 turn submission per 5 seconds per
  player, max 10 matchmaking tickets per hour, max 5 pending challenges.
- Stats (`wins/losses/draws`) are function-written only.

## 10. What this deliberately leaves out (later)

Live real-time play, in-game chat, rematch-from-match screen (recent-games
rematch already exists locally), tournaments, leaderboards, skill rating,
spectating. All fit on top of this model without breaking it.

## 11. Tunables (`MPConfig`)

`matchmakingTimeout = 30s` · `ticketStaleAfter = 5min` ·
`turnDeadlineHours = 24` · `forfeitGraceHours = 24` ·
`maxPendingChallenges = 5` · `challengeExpiryHours = 24`
