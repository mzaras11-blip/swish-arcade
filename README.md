# S.W.I.S.H - Crossword Battle ARCADE

The ARCADE edition of S.W.I.S.H: identical functionality to the S.W.I.S.H
game, re-presented in the cartoon ad-video look. Bundle ID
com.swishgame.arcade. See ARCADE-BUILD-NOTES.md for what changed and the
wrap-time checklist.

# S.W.I.S.H – Crossword Battle (Solve Words. Intercept. Score High.)

A turn-based competitive crossword battle game for iOS, in the genre of
Kryss: two players share one Scandinavian-style (arrowword) crossword grid.
Each turn you get 5 letter tiles and 60 seconds — tap a tile, then tap the
square where you think it belongs. Correct letters lock in for both players.

All puzzles, clues, art, and code are original — written from scratch for
this game.

## Gameplay

- **A brand-new puzzle every game** — S.W.I.S.H generates a fresh
  Scandinavian-style arrowword on the spot for every game, from an original
  498-word/clue database plus a layout engine (`PuzzleGenerator.swift`) that
  assembles the grid, clue cells, and blue bonus squares at runtime.
  Generation runs on a background thread with a `PuzzlePool` prefetch buffer,
  so starting a game feels instant. The 12 bundled JSON puzzles remain as an
  offline fallback.
- **Shared board** — you and your opponent (CPU or a friend, pass-and-play)
  work the same crossword. Placed letters stay for both players.
- **5 tiles, 60 seconds per turn.** Wrong guesses bounce back, no penalty.
- **Scoring:** +1 per correct letter, +word-length bonus for completing a
  word, +5 for using all 5 tiles in a turn, and landing a correct letter on
  a **blue square doubles your entire turn**.
- **Clues live inside the grid** (arrowword style). Tap any clue square to
  read the full clue.
- **AI opponent** with Easy / Normal / Hard — difficulty is chosen openly by
  the player, never rigged behind the scenes.

## Monetization (ad logic)

- **Rewarded ads:** "Hint (📺 ad)" button — watch an ad to reveal one correct
  letter (max 3 per game). Fully player-initiated.
- **Rewarded continue:** on the game-over screen, the loser is offered
  "continue +5" — watch an ad to start the rematch with a 5-point head start.
  The honest version of Block Blast's revive ad: nothing is rigged, the
  comeback is bought openly.
- **Interstitials:** shown after every 2nd finished game. Never mid-game,
  never blocking a turn.
- **Banner:** small banner on the main menu.
- **Remove Ads (in-app purchase):** one-time non-consumable via StoreKit 2
  (`StoreManager.swift`). Kills interstitials and banners, and makes hints
  and the continue head-start free — no ads, ever.

Powered by `AdManager` (`SWISH/AdManager.swift`) using Google AdMob. The app
ships with Google's official **test** ad units, so it runs and shows test ads
immediately. Without the AdMob SDK linked, clearly-labeled **simulated** ads
appear so the whole flow is testable with zero setup.

### Going live with real ads

1. In Xcode: **File > Add Package Dependencies**, add
   `https://github.com/googleads/swift-package-manager-google-mobile-ads`
   (product `GoogleMobileAds`).
2. Create an AdMob account, register the app, and replace the test IDs:
   - `AdManager.swift`: `rewardedAdUnitID`, `interstitialAdUnitID`,
     `bannerAdUnitID`
   - `Info.plist`: `GADApplicationIdentifier` (your AdMob app ID)
3. The `#if canImport(GoogleMobileAds)` blocks switch to real ads
   automatically — no code changes needed.

### Going live with the Remove Ads purchase

1. In App Store Connect, create an in-app purchase:
   - Type: **Non-consumable**
   - Product ID: `com.swishgame.app.remove_ads` (must match
     `StoreManager.removeAdsID` exactly)
   - Price: pick a tier (e.g. $4.99)
2. Sign the **Paid Apps** agreement in App Store Connect (required before any
   IAP works, including in sandbox testing).
3. For testing: create a sandbox Apple ID in App Store Connect and sign into
   it on your test device. The app's store section handles the
   not-configured case gracefully until then.

## Project structure

```
SWISH.xcodeproj/            hand-generated Xcode project (see tools/gen_pbxproj.py)
SWISH/
  SWISHApp.swift            @main entry
  Models.swift              puzzle data, tiles, difficulty, game mode
  GameViewModel.swift       all game logic: turns, timer, scoring, AI, hints
  PuzzleGenerator.swift     runtime arrowword generator + prefetch pool
  AdManager.swift           AdMob wrapper (rewarded / interstitial / banner)
  StoreManager.swift        StoreKit 2 Remove-Ads purchase
  GameView.swift            board, rack, tiles, mock-ad screen
  Views.swift               menu, how-to-play, game over
  Info.plist
  Assets.xcassets/          app icon + accent color
  Resources/words.json      498 original words/clues for the generator
  Resources/puzzles/        12 pre-generated puzzles (offline fallback)
tools/
  gen_puzzles.py            arrowword puzzle generator (original word/clue list)
  validate.py               puzzle integrity checker
  gen_pbxproj.py            regenerates the .xcodeproj project file
web-demo/                   playable browser demo of the same game
```

## Build & run

Requirements: a Mac with Xcode 16+, iOS 17+ device or simulator.

1. Open `SWISH.xcodeproj` in Xcode.
2. Select the **SWISH** target > Signing & Capabilities: choose your Team
   (free Apple ID works for running on your own device).
3. Set your own **Bundle Identifier** (e.g. `com.yourname.swish`).
4. Press Run.

If you add/remove source files, regenerate the project:
`python3 tools/gen_pbxproj.py` (it scans the hardcoded file list in the script).

To make more puzzles: `python3 tools/gen_puzzles.py 12` then
`python3 tools/validate.py`. Drop the JSONs into
`SWISH/Resources/puzzles/` and re-run `gen_pbxproj.py`.

## Publishing to the App Store

1. Enroll in the **Apple Developer Program** ($99/year) — required to
   submit apps. Only the account holder can do this.
2. In Xcode, set your Team and a unique Bundle ID.
3. **Product > Archive**, then **Distribute App > App Store Connect**.
4. In App Store Connect: create the app record, fill in the listing
   (screenshots, description, age rating questionnaire), add your real
   AdMob IDs (above), and submit for review.
5. Review usually takes 24–72 hours.

Ideas for v2: online multiplayer (needs a game server), daily puzzle,
"Remove Ads" in-app purchase (StoreKit 2), more puzzle packs.

## A note on the Block Blast video

This game's ad system was designed *after* watching the viral breakdown of
Block Blast's monetization — and deliberately **excludes** its manipulative
parts:

- ❌ No secret difficulty rigging ("death algorithm") to manufacture ad views
- ❌ No covert device/behavior data collection to score players' "ad value"
- ❌ No hidden score inflation after revives
- ✅ Difficulty is chosen openly by the player (Easy/Normal/Hard)
- ✅ Ads are player-initiated (rewarded hints) or between games (interstitials)

Deceptive patterns risk App Store rejection/removal and regulatory trouble —
and players hate them when exposed. The honest mechanics above capture what
actually earns: rewarded ads at moments of high intent.
