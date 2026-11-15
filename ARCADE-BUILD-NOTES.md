# SWISH ARCADE — build notes (2026-11-14)

App: **S.W.I.S.H - Crossword Battle ARCADE** · Bundle ID `com.swishgame.arcade` ·
Version 1.0, build 1 · Project copied from the S.W.I.S.H project
(`~/workspace/swish-next-dev`, web build 15) and re-presented. Functionality is
the S.W.I.S.H game's, unchanged; all work below is presentation, branding, and
the loading/mascot/music gaps.

## Native shell
- `project.pbxproj`: bundle ID → `com.swishgame.arcade` (2 configs).
- `Info.plist`: CFBundleDisplayName / CFBundleName → full name; version 1.0,
  build 1. (App Store *listing* name is the shortened "S.W.I.S.H - Crossword
  ARCADE" — handled in App Store Connect, not here.)
- App icon: Michael's poster-crop `swish-arcade-icon-1024.png` (md5
  d938d95f…) in `AppIcon.appiconset`, byte-identical to the source file.
- `Mascot.imageset`: image swapped to the poster-mascot crop (512×482 PNG).
- `codemagic.yaml`: BUNDLE_ID → com.swishgame.arcade; workflow unchanged.
- Swift branding: push-notification title (Models.swift) and the native
  settings title (Views.swift) → full name. All bridges (share, review, ads,
  push, auth, music) untouched.
- GoogleService-Info.plist, GADApplicationIdentifier, Google sign-in URL
  scheme, music.wav: **kept from S.W.I.S.H on purpose** (see wrap-time list).

## Web core (`SWISH/Resources/web/index.html`, 578,194 B, md5 76c20092…)
- **ARCADE skin**: a second `<style>` block after the base stylesheet —
  variable-level re-skin (deep-purple energy palette in both color schemes)
  plus hero-component overrides in the Rush-v1/ad-video system: gradient
  wordmark with CROSSWORD BATTLE + ARCADE pill, VS scoreboard bars (blue you /
  maroon CPU, gold scores, leader crown), gold board frame with dark navy
  cells and glossy owner tiles, gold rack tray with chunky bobbing tiles,
  chunky press-down buttons, violet glass panels/modals, animated menu
  gradient, drifting energy glows behind the game screen, Rush combo bar in
  the v1 orange→pink→purple gradient. Shop themes still override via their
  higher-specificity `[data-theme]` variable rules.
- **Mascot**: the old blue tile-character PNG data URI (3 uses: start screen,
  loading screen, pointer companion) replaced with a poster-mascot crop
  (560×538 WebP, ~45 KB — the web file shrank ~604 KB). The matchmaking
  mascot copies its src from the start-screen image, so it follows too.
  Companion enlarged to 58px with a wiggle; start-screen mascot enlarged to
  148px with the base bob animation.
- **Loading screen**: full-name wordmark (S.W.I.S.H / CROSSWORD BATTLE /
  ARCADE) + an animated gradient progress bar added to the base loader; the
  base `hideLoading()` still drives the real timing.
- **Mascot reactions** (add-on `<script>`, presentation only): companion and
  menu mascot bounce on any button tap; on a player win (`#overTitle`
  `.winner-you`) the companion celebrates. Driven purely by DOM events /
  a MutationObserver — no game state touched.
- **Music**: the web WebAudio `Music` module's arrangement replaced with an
  original energetic groove (driving octave bass, pentatonic lead plucks,
  noise hats, sparkle; 32 steps × 0.20 s). Same API, same STORE settings,
  same mute/volume controls, same native-bridge delegation in the app
  (native path still plays the bundled music.wav via MusicBridge).
- **Branding**: all user-facing "S.W.I.S.H" strings → the full name
  (toasts, share texts/cards, invite text, delete-account copy, tutorial
  copy, footer, aria labels). Share cards keep the composed wordmark
  ("S.W.I.S.H" title + "CROSSWORD BATTLE · ARCADE" sub-line). NOT changed:
  localStorage keys (`swish.web.v1`, `swish.web.autosave.v1`), Firebase
  paths/config, `APP_STORE_URL` (still the S.W.I.S.H store link — wrap-time),
  download filenames (`swish-board.png`, `swish-result.png`).
- Rush mode: untouched logic, presented as the flagship mode (gold Rush
  mode button, v1-style combo bar and score bars while `body.rush-on`).

## Verification (all run against the shipped files)
- `node --check` on both script blocks: OK.
- `tools/validate.py`: 12/12 bundled puzzles OK.
- `tools/deadrack-sim.js`: ALL CHECKS PASSED (identical numbers to base).
- `tools/rush-sim.js`: 48 checks, 0 failed.
- Inventory parity vs base: element IDs 225 = 225 (none missing/added);
  functions 310 → 312 (none missing; added `hat` in the new Music module
  and `bounce` in the add-on script).
- Emoji scan: multiset identical to base — zero new emoji (picture-clue and
  reaction emoji are the base's sanctioned set, unchanged).
- NOT verified: on-screen rendering (headless Chromium is policy-locked on
  this machine) and native compilation (no Xcode here). Michael's TestFlight
  play is the visual gate; the Codemagic unsigned workflow is the first
  compile check.

## Wrap-time list (before this ships as its own product)
1. **Firebase**: ✅ DONE in build 4 — ARCADE has its own iOS app
   registration in the existing project; its GoogleService-Info.plist
   (BUNDLE_ID com.swishgame.arcade) is in the project and the Google
   sign-in URL scheme in Info.plist is ARCADE's own REVERSED_CLIENT_ID.
2. **AdMob**: ✅ DONE in build 4 — ARCADE has its own AdMob app + banner /
   interstitial / rewarded units; GADApplicationIdentifier and the
   AdManager.swift unit IDs are ARCADE's. (AdMob shows the app as
   "Requires review / limited ad serving" until the store listing is
   linked — that lifts once ARCADE is published.)
3. **Invite/share URL**: APP_STORE_URL in the web core still points at the
   S.W.I.S.H App Store page; point it at ARCADE's listing once live.
4. **Store metadata**: listing name already shortened in ASC; consider
   "Battle" in the subtitle. app-store-listing.md in this folder is still
   the S.W.I.S.H listing copy — rewrite for ARCADE.
5. **Push**: APNs/entitlements are inherited; confirm push keys/certificates
   cover the new bundle ID.
6. House promos in the web build promote S.W.I.S.H offers (Remove Ads,
   coin packs) — decide ARCADE's own promo rotation once its IAP exists.
   **IAP alignment (build 4)**: the Remove Ads product ID in code is now
   ARCADE's own — `com.swishgame.arcade.remove_ads`
   (StoreManager.removeAdsID; README go-live section updated to match).
   The ASC product with that exact ID is being created in parallel; the
   inherited S.W.I.S.H ID was a dead purchase under this bundle.

---

# Build 2 (2026-11-15) — icon, avatars, mascot cutout, safe area, dock, music hype

Version stays 1.0; CFBundleVersion 1 → 2. Web core md5 273222a3… (615,503 B).

- **Icon**: AppIcon-1024.png replaced with the v2 art (title pulled inside the
  frame; md5 bd81ed87…). The appiconset has a single 1024 slot — no other
  slots existed to update.
- **Mascot cutout**: the rectangular poster crop is gone. New companion art is
  a transparent-background cutout of the same figure (rembg: union of
  isnet-general-use + u2net mattes over the original RGB, hand-inspected —
  full figure incl. legs and left arm, no background remnants), encoded as
  560×527 WebP with alpha (45,378 B). It replaces the old URI in all three
  placements (start screen, loading screen, pointer companion); the
  matchmaking mascot inherits it via its src copy. The native
  `Mascot.imageset` still holds the rectangular poster crop — unused by the
  web layer; swap it if a native surface ever shows it.
- **Avatars**: two 256×256 WebP assets embedded in the web core. PLAYER =
  mascot face crop from the cutout on the YOU-panel blue; RIVAL = the same
  face hue-shifted (blue fur → orange-red, red cap → deep purple) on the
  CPU-panel maroon. Shown as 34px gold-ringed circles in the score panels'
  name rows: YOU panel = PLAYER, CPU panel = RIVAL (CPU name row is
  row-reversed so its avatar sits on the outer edge). Same panels serve
  normal games, Rush VS bars, and Split Screen (P1 = PLAYER, P2 = RIVAL).
- **Safe area**: #gameScreen top padding is now
  `calc(12px + env(safe-area-inset-top))` — the game header no longer sits
  under the iOS status bar.
- **Companion dock**: while the game screen is up, the pointer companion
  docks straddling the top-right corner of the player's score panel
  (new `dockTL()` in the companion IIFE) instead of trailing the fingertip,
  so it never covers board or rack tiles. Off the game screen it trails
  the pointer as before; tap-bounce and win-spin are untouched.
- **Music hype (Web Audio path)**: STEP_S 0.20 → 0.176 s (~75 → ~85 BPM);
  added a synthesized kick (`kick()`) on every beat, 8th-note hats with an
  offbeat accent (was a lone offbeat hat), and a bass root pulse filling
  the BASS rests. Same MEL/BASS lines, same API, same volumes for melody
  and bass; SFX keep their own bus. NOTE: in the iOS app, music delegates
  to the native bridge playing the bundled music.wav — this pass changes
  the Web Audio groove (browser/web play); the in-app wav is unchanged.
- **Verification**: node --check OK on both script blocks; validate.py
  12/12; deadrack-sim ALL CHECKS PASSED; rush-sim 48/48; music smoke test
  (stubbed Web Audio): kick gaps exactly 0.704 s, bass sounds on every
  step, hats on every 8th. Inventory vs build 1: element IDs 225 = 225
  (none added/removed); functions +2, none removed (dockTL, kick);
  emoji multiset identical (127 = 127, zero new).

## Build 3 (v1.0, CFBundleVersion 3) — in-app music hype

Michael's call after build 2: the hype has to reach the music he actually
hears in the app. One change only — the bundled wav the native bridge
loops (`SWISH/Resources/web/music.wav`, loaded by NativeAudioBridge in
SWISHApp.swift via Bundle.main, subdirectory "web", numberOfLoops = -1).
The native delegation, the web core, and everything else are untouched.

- **Processing (ffmpeg, two passes on the original file)**:
  1. `atempo=1.10` (pitch-preserving tempo up) + gentle compression
     `acompressor=threshold=-20dB:ratio=2:attack=10:release=250`.
  2. Makeup/normalize: `volume=6.5dB` + `alimiter=limit=0.891:level=false`
     (limiter is a safety net at ≈ -1 dBFS).
- **Before → after**:
  - Duration: 30.00 s → 27.25 s (exactly 30 / 1.10).
  - Tempo (envelope-autocorrelation estimate): ≈120 BPM → ≈130 BPM.
  - Peak: -3.1 dBFS → -1.0 dBFS (no clipped samples; nothing ≥ -0.9 dBFS
    plateau — limiter/peak verified in samples, peak sample -1.04 dBFS).
  - Mean level: -16.0 dB → -14.1 dB (+1.9 dB loudness lift, no clipping).
  - Format unchanged: WAV PCM s16le, 22050 Hz, mono; same filename/path,
    so SWISHApp.swift needs no change. 1,323,044 → 1,201,836 bytes.
- **Loop seam**: the original is a silence-bridged loop — it tapers to
  digital zero over its last ~50 ms and starts from ~zero, so the wrap is
  click-free by design. Verified the property survived processing:
  last sample → first sample jump = 0; tail still tapers smoothly to zero
  over the final ~100 ms (10 ms RMS bins descend 1594 → 0) and the head
  ramps up from near zero. No crossfade or trim was needed; no seam fix
  applied beyond preserving the original fade.
- **Verification**: ffprobe decodes the new file cleanly (27.25 s, format
  as above); web core byte-unchanged from build 2 (index.html md5
  273222a359b90948997bac41d0101ca2) and its checks still pass
  (node --check on both script blocks OK; tools/validate.py exit 0).

## Build 4 (v1.0, CFBundleVersion 4) — own AdMob, own Firebase, own IAP ID, video-title wordmark

The wrap-time identity swap, plus the wordmark Michael asked for after
playing build 2. Web core md5 3746bfe847a8d75f6d657277af3f52d4.

- **AdMob (ARCADE's own, created 2026-11-15)**: Info.plist
  GADApplicationIdentifier → `ca-app-pub-9461680459080238~3414614247`;
  AdManager.swift → banner `…/6802360769`, interstitial `…/1821817623`,
  rewarded `…/4229002468`. Placements, formats and the house-promo
  rotation are untouched. Project-wide grep: zero occurrences of the old
  app ID or S.W.I.S.H unit IDs remain in code.
- **Firebase (ARCADE's own registration)**: GoogleService-Info.plist
  replaced with the plist registered for com.swishgame.arcade in the
  same project (GOOGLE_APP_ID 1:652966312456:ios:84c11caa3598653425afbd,
  BUNDLE_ID verified com.swishgame.arcade after the swap). Info.plist
  Google sign-in URL scheme → ARCADE's REVERSED_CLIENT_ID
  (com.googleusercontent.apps.652966312456-jcks6p2v085i0bsrsqcc4h31f46pgaa4);
  grep confirms no reference to the old reversed client ID remains.
- **Remove Ads product ID**: `com.swishgame.app.remove_ads` →
  `com.swishgame.arcade.remove_ads` in StoreManager.swift (the only code
  occurrence) and in README.md's go-live section, which documents that
  the ASC product ID must match the code. The `swish_remove_ads`
  UserDefaults keys are internal storage keys, not the product ID —
  unchanged. (app-store-listing.md still names the old ID — that file is
  S.W.I.S.H's own listing doc, where the old ID is correct; it's the
  stale copy flagged in wrap-time item 4.)
- **Wordmark restyle** (menu `.logo` + loading `.load-title`, CSS only in
  the ARCADE skin + a `data-text="S.W.I.S.H"` attribute on each):
  matched to Michael's ad-video title reference
  (~/workspace/goals/s-w-i-s-h-ios-game/files/swish-title-reference-video.jpg).
  Construction: the element's own text is now a solid deep-navy
  (#142069) copy with a 0.15em -webkit-text-stroke — the chunky outline;
  an ::after overlay (content: attr(data-text)) paints the gradient fill
  on top (linear, #ff5a1f top → #ff7d00 → #ff9e00 → #ffb300 → #ffd21f
  bottom), leaving an even navy rim; drop-shadow filters add the blue
  glow (rgba(64,156,255,.55)) and a hard navy depth ledge. The old dull
  olive-brown gradient + brown stroke are gone. "CROSSWORD BATTLE"
  (.logo-sub / .lt-sub) is now white→purple gradient bubble text
  (#ffffff → #e9d5ff → #c084fc → #8b5cf6) with a thin navy stroke,
  riding a gold swoosh (::before: gold gradient ellipse, slight -1.3°
  tilt, tucked under the letters' lower third). The sub spans are
  width: fit-content + auto margins so the swoosh hugs the text width
  instead of the full screen — that was the one fix from the visual
  check below. The ARCADE pill/line under the title is unchanged, as are
  all branding strings.
- **Visual check (new this build)**: rendered in a standalone Chromium
  headless shell (Playwright, installed in a /tmp venv — the managed
  /opt/meta-chromium stays policy-locked) at 420×900 and eyeballed
  against the reference, loading screen + main menu. First pass caught
  the swoosh spanning the full screen width; fixed via fit-content
  above and re-shot. Remaining deltas vs the reference are CSS limits,
  stated plainly: the reference letters are hand-drawn with a slight
  per-letter arc and a pale-blue inner bevel inside the outline; the
  app's are straight-set in the existing rounded display stack with a
  flat navy rim, and the sub keeps the app's all-caps "CROSSWORD
  BATTLE" string. Gradient direction, outline weight/color, glow, and
  the purple-on-gold-swoosh sub all read as the reference treatment.
  Michael's eye on TestFlight remains the deciding gate.
- **Verification**: node --check OK on both script blocks;
  tools/validate.py 12/12 (exit 0); deadrack-sim ALL CHECKS PASSED;
  rush-sim 48 checks, 0 failed. Inventory parity vs build 3: element
  IDs 225 = 225 with identical sorted-ID hash (additive only — the two
  data-text attributes); emoji multiset identical (127, same hash —
  zero new emoji); no JS functions added or removed (CSS + attributes
  only in the web core). Both plists parse; Info.plist CFBundleVersion
  3 → 4, short version stays 1.0.

## Build 5 (v1.0, CFBundleVersion 5) — Rush becomes a game type in Online/Friends

Michael's order (2026-11-15): build Rush vs friends first, then submit
ARCADE for App Store review. His refinement: Rush is a **selectable
game type inside the existing Online/Friends setup flows** — not a
separate door off the Rush menu. Solo Rush vs CPU is untouched.

- **Where the Rush option now lives** (the three entry points):
  1. **Friends tab — room creation.** A game-type segmented control
     (Split Screen / Rush race) sits above "Create a room". Picking
     Rush race relabels the button "Create a Rush race room"; the
     room code flow is unchanged. A guest joining ANY room plays
     whatever type the host picked — the type travels with the race
     start event, so no join-side choice is needed.
  2. **Home — matchmaking.** A second button, "Find a Rush race",
     under "Find a Split Screen match". Matchmaking tickets now
     carry a game type (below), so racers only ever pair with racers.
  3. **In-room Rematch.** After a race, the existing Rematch button
     deals a fresh race in the same room (new puzzle, new seed). The
     game-over "New Match" button also re-queues the same type.
- **The race itself** (web core, new "Rush PvP" block next to the
  Rush section): each racer plays their **own board**. Fairness comes
  from the room: the host generates one puzzle (sent in the clear,
  like Split Screen's start) plus a random seed and a start
  timestamp (now + 5 s). Both phones draw every tile — opening rack
  and all refills — from the identical seeded stream (mulberry32
  over the seed, drawing from the same weighted LETTER_BAG), so both
  racers are offered the exact same tile sequence. The never-dead
  guarantee is stream-safe: it hands out the first letter the board
  still needs (board order — deterministic on both phones) and
  consumes no stream draw. **One clock**: both phones measure the
  same 180 seconds from the shared startAt; placements are refused
  during the countdown; the forfeit-confirm dialog does not pause a
  PvP race (the other phone's clock is running too).
- **Score sync + finish**: `{t:"rushScore"}` events over the room
  stream carry score/combo/letters/words (sent on change, 500 ms
  cadence check) and mirror onto the opponent side of the VS bars —
  the rival panel shows the opponent's **real username + RIVAL
  avatar**, the live badge reads "RUSH RACE", and the results table
  header names them too (restored to "CPU" on exit). Each finisher
  sends a final report; the race is decided when both finals are in,
  or after a 3 s grace wait with the last known score. The peer's
  existing "over" event doubles as a final ack. Winner / loser /
  **draw** titles name the opponent. **Mid-race leave or forfeit =
  win for the player who stayed**, whatever the scoreboard says.
  The ad-revive offer is suppressed in races.
- **Native (SWISHApp.swift)**: only matchmaking changed. The
  matchmake action now passes a `gameType` ("split" default); the
  seeker only claims tickets of the same type, and its own ticket
  records the type. Tickets written by older builds (and by the live
  S.W.I.S.H app, which shares this Firebase project) have no
  gameType and count as "split" — backward compatible, no Firestore
  rules change needed. Room events needed no native change: event
  bodies are relayed opaquely, so the new rushStart / rushScore /
  rushForfeit events ride the existing plumbing and the already
  deployed onRoomEventCreated function.
- **Unchanged, by design**: turn-based online matches, Split Screen
  live games, Daily, solo modes, and solo Rush vs CPU (same code
  paths, guarded by the rushPvp flag). The CPU thinking pause is
  untouched everywhere.
- **Verification**: node --check OK on both script blocks;
  tools/validate.py 12/12 (exit 0); deadrack-sim ALL CHECKS PASSED;
  rush-sim 48 checks, 0 failed (solo Rush untouched); **new
  tools/rush-pvp-sim.js: 42 checks, 0 failed** — shared-seed stream
  determinism (identical 200-tile sequence, ids 1..n), identical
  opening racks + lockstep refills on two clients, guarantee
  determinism with zero stream consumption, countdown placement
  refusal then GO, score-sync payload/dedupe/final rules, finish
  exchange (win, draw, grace-timeout decision, over-ack), and the
  leave/forfeit win. Inventory parity vs build 4: element IDs
  222 → 224 (additive only: #mmRushBtn, #statCpuHead); emoji
  multiset identical (same hash — zero new emoji); JS functions
  266 → 283, all additions, none removed. Web core now 636,709 B,
  md5 4467a6e0…. Info.plist CFBundleVersion 4 → 5, short version
  stays 1.0.
- **Honest limit**: a true two-device live race cannot be tested
  from here — the protocol and rules are simulated headlessly, the
  transport is the same room stream Split Screen already ships on,
  but the first real race is Michael playing build 5 with a friend
  on two phones. That play is the gate.
- **Next**: App Store submission of this build follows (Michael's
  order) — the store description may now claim Rush vs friends.

## Build 6 (2026-11-15) — Emotional avatars + Invite fix (TestFlight-only)

Michael's order (2026-11-15 10:27 ET, picked from options). Build 5
stays the App Store submission in review; build 6 goes to TestFlight
only. Two changes:

- **Emotional avatars**: the two score-panel faces (build 2) are no
  longer static. Four expression variants per face (happy, excited,
  worried, sad) were generated by editing the shipped avatar art
  itself (2x2 expression grids, sliced to 256x256 WebP, ~9-10 KB
  each) — same character, cap, background and gold-ring presentation;
  original art only, no emoji, no stock. A new presentation-only
  add-on script (same DOM-observer pattern as the build 1/2 add-ons;
  no game state read or written) swaps the pictures:
  - a side scores -> that side flashes **happy** (1.5 s);
  - a side takes the lead -> **excited** (2 s), and the side that
    lost the lead flashes **worried**;
  - trailing by 15+ points -> resting face is **worried**;
  - Rush combo reaches x3 -> player **excited**; combo lost from
    x2+ -> brief **worried** flash;
  - game over -> winner **excited**, loser **sad**, tie -> both
    **happy**, held until the modal closes, then back to neutral.
  - Companion mascot: it already spins/celebrates on a win (build 1);
    build 6 adds a loss reaction — a droop animation (tilt down,
    desaturated, ~2.4 s) on a loss. Its face is a small part of a
    full-body cutout, so no clean face-swap variant exists; the
    reaction is animation-based by design.
- **Invite fix**: `APP_STORE_URL` now points at ARCADE's own listing,
  https://apps.apple.com/app/id6834987638. Zero references to the
  S.W.I.S.H store ID (id6824631926) remain in the app web core or the
  docs copy (same one-line fix applied there).
- **Verification**: node --check OK on all 3 script blocks;
  tools/validate.py 12/12 (exit 0); deadrack-sim ALL CHECKS PASSED;
  rush-sim 48 checks, 0 failed; rush-pvp-sim 42 checks, 0 failed.
  Inventory parity vs build 5 (byte-compared against commit 73cc8637):
  element IDs 227 = 227 (none added/removed); emoji multiset
  identical (140 chars, zero new); named JS functions: none removed,
  4 added inside the new add-on IIFE. Expression engine driven
  headlessly against the shipped file with a DOM stub: 16/16 checks
  passed (lead change, scoring flashes, resting worried, combo
  milestones/loss, win/lose game-over holds, modal-close reset,
  companion droop class). Headless Chromium is policy-locked on this
  machine, so the visual check is a PIL composite of the real panel
  colours + gold-ring crop in two states (legible at panel size) —
  Michael's TestFlight play remains the on-device visual gate.
  Web core now 745,947 B, md5 191fb65f509f3546ab324489309b4af7.
  Info.plist CFBundleVersion 5 -> 6, short version stays 1.0.
