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
