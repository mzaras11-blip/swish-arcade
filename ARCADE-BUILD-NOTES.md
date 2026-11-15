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
1. **Firebase**: register a separate iOS app for com.swishgame.arcade (in the
   existing project, per the current direction) and drop in its own
   GoogleService-Info.plist; until then the app talks to Firebase as the
   S.W.I.S.H app registration, and the Google sign-in URL scheme in
   Info.plist is S.W.I.S.H's.
2. **AdMob**: create an ARCADE AdMob app + ad units; replace
   GADApplicationIdentifier and the unit IDs in AdManager.swift (currently
   S.W.I.S.H's — ads would credit S.W.I.S.H's account).
3. **Invite/share URL**: APP_STORE_URL in the web core still points at the
   S.W.I.S.H App Store page; point it at ARCADE's listing once live.
4. **Store metadata**: listing name already shortened in ASC; consider
   "Battle" in the subtitle. app-store-listing.md in this folder is still
   the S.W.I.S.H listing copy — rewrite for ARCADE.
5. **Push**: APNs/entitlements are inherited; confirm push keys/certificates
   cover the new bundle ID.
6. House promos in the web build promote S.W.I.S.H offers (Remove Ads,
   coin packs) — decide ARCADE's own promo rotation once its IAP exists.
