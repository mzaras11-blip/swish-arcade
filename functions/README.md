# S.W.I.S.H Cloud Functions

Server-authoritative async multiplayer plus all push fan-out for
S.W.I.S.H. Entry point: `index.js` (Node 20, firebase-functions v2,
firebase-admin v12). One codebase, deployed as a single unit.

## What lives here

Callable (client-invoked, auth required):

| Function | Purpose |
|---|---|
| `submitTurn` | Validates an async-match turn, recomputes all scoring server-side, writes the turn + match state. |
| `forfeitMatch` | Voluntary forfeit of an async match. |
| `resolveForfeit` | Lazy deadline evaluation (past deadline + grace = forfeit). |
| `sendChallenge` | Creates a challenge under `users/{toUid}/challenges/{cid}` (max 5 pending, duplicates collapse). |
| `respondToChallenge` | Accept (builds the match) or decline a challenge. |

Firestore triggers:

| Function | Trigger | Purpose |
|---|---|---|
| `onTicketCreated` | create `matchmaking/{uid}` | Pairs waiting matchmaking tickets, builds the match, pushes both players. |
| `onChallengeCreated` | create `users/{toUid}/challenges/{cid}` | Push to the challenged player. |
| `onMatchUpdated` | update `matches/{matchId}` | **Your-turn push** when `currentPlayer` changes; match-end pushes (win / loss / tie) to both players. |
| `onRoomUpdated` | update `rooms/{code}` | Push to the host when a guest joins a Split Screen room (`guestUid` appears, state → `live`). |
| `onRoomEventCreated` | create `rooms/{code}/events/{eventId}` | Push to the guest when the host deals the game-start event (`{t:"start"}`). |

All pushes go through the `sendPush` helper in `index.js`: it reads
`users/{uid}.fcmTokens`, sends via FCM (`sendEachForMulticast`, APNs
sound `default`), and prunes tokens FCM reports as not-registered.
The native shells keep `fcmTokens` current (iOS: `PushManager` in
`SWISH/SWISHApp.swift`; Android: `push/PushService.kt`).

There is intentionally **no async-games collection of the web shell's
own**: async friend games are the `matches/{matchId}` documents plus
`users/{uid}/challenges` inboxes above (written only by these
functions — see `firestore.rules`), and `onMatchUpdated` /
`onChallengeCreated` are their push triggers. Split Screen is the
client-run `rooms/` layout, covered by the two room triggers.

## Deploy

Prerequisites (console/account steps, done once, outside this repo):

1. The Firebase project (`swish-crossword-battle`) must be on the
   **Blaze plan**. Cloud Functions (2nd gen) cannot deploy on Spark,
   and Firestore-triggered functions bill under Blaze rules. FCM
   sends themselves are free; expected cost at this scale is ~$0.
2. An **APNs auth key** (.p8) created in the Apple Developer portal
   (Keys → Apple Push Notifications service) and uploaded in the
   Firebase console: Project settings → Cloud Messaging → Apple app
   configuration. Without it, iOS pushes silently go nowhere.
3. `firebase-tools` installed locally: `npm install -g firebase-tools`.

```sh
firebase login
firebase use swish-crossword-battle        # or: --project swish-crossword-battle on each command
cd functions && npm install && cd ..
firebase deploy --only functions           # functions only
firebase deploy --only firestore:rules     # rules only (firestore.rules at repo root)
```

`firebase.json` at the repo root wires both deploy targets (functions
source `functions/`, runtime `nodejs20`; rules file `firestore.rules`).

Verify after deploy: Firebase console → Functions lists all nine
functions; then play one async turn change and one Split Screen game
with a second device and confirm both pushes arrive. Function logs:
`firebase functions:log` or the console's Logs tab.
