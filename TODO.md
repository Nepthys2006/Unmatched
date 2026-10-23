# Unmatched — fixes & to-do

Last updated: 2026-10-24. For the full engine/API reference see `HANDOFF.md`.

**To resume:** open Claude Code in this folder (`Unmatched/unmatched_game`) and say
*"read TODO.md and continue"*. Nothing is running in the cloud.

---

## Where things stand

| Part | Status |
|---|---|
| Rules engine (`lib/engine/`) | ✅ Done |
| All 39 heroes, every card | ✅ Done, checked against the printed cards |
| Modes: 1v1, 2v2, 3v3, free-for-all 2–5 | ✅ Done |
| AI: Easy / Medium / Hard / Insane | ✅ Done |
| Flutter UI: loading, username, menu, setup, hero select, VS, match, results, settings | ✅ Playable end to end |
| **3D maps** (the 12 models from `3D Map/models`) | ✅ In the match; Settings → Battlefield → 3D map / Flat 2D |
| Tests | ✅ 104 engine + 32 widget tests passing (whole matches in every mode, 3 screen sizes) |
| Checked in a browser | ✅ Chrome (desktop and phone-sized): 1v1, 2v2, 3v3 on the 3D maps |
| Android / iOS / Windows app | ⚠️ Not run on a device yet (no phone or Visual Studio on this PC) |

## How the 3D board works

- `assets/maps3d/<map>.glb`: the 12 models from `3D Map/models`, without the Fighters group
  (the game draws its own pieces), textures as WebP and meshopt-compressed: 146 MB → 44 MB.
  `assets/maps3d/<map>.webp` are the map-picker thumbnails (from `3D Map/screenshots`).
- `assets/web3d/`: a Three.js r170 page (bundled, works offline) that draws the map, the
  glowing orbs, highlights, tokens, hit numbers and the combat camera. The match screen
  (`lib/ui/board3d/`) sends it the board state as JSON and gets taps back.
  Web: an iframe. Android/iOS: the system WebView. Windows: WebView2. The app serves the
  page to itself on 127.0.0.1 only.
- Pentacle Ruins (5-player) has no model, so it stays 2D. If the 3D map can't load, the match
  falls back to the 2D board and says so.
- Speed: ~190 meshes merged into a few draw calls per material, frames drawn only when something
  moves, shadows redrawn only when pieces move, lower resolution on phones, and a governor that
  lowers resolution further if frames run long. Low quality turns shadows off.

## Done this session (2026-10-24)

- 3D maps in the match, with a Settings switch (3D map / Flat 2D) and 3D thumbnails in map select.
- **Bug fixed:** over the hand limit by exactly one card, there was no way to discard. One tap now
  discards it (regression test added).
- **Fewer confirmations:** only attacks ask "Are you sure?". Moving, picking fighters/spaces,
  defending, boosting and skipping happen on the first tap. Long-press or right-click a card to
  read it without playing it.
- **Combat:** both cards centred side by side, with the steps in order between them
  (Reveal → Immediately → During combat → Damage → After combat), the effect being resolved,
  and the result as VICTORY / DEFEAT from your side. The hand slides down during combat so the
  fighters stay visible; the camera frames them under the cards.
- **Defeats announced:** a banner when any fighter is defeated ("Defeat: your hero has fallen",
  "Enemy sidekick down"...). The end screen shows VICTORY or DEFEAT.

## Earlier fixes (all done)

### Card data errors corrected (checked against the printed card images)
- **Michelangelo – Nunchaku:** text said "Bruce Lee's attacks"; real card says "Michelangelo's attacks".
- **Achilles – Brothers In Arms:** was marked Patroclus-only; it's usable by ANY fighter.
- **Loki – Shapeshifter:** BOOST was 3; real card is **2**.
- **Loki – all 4 TRICK cards:** had BOOST 0; tricks have **no** BOOST (can't be used to boost).
- **Krang – IQ of 968, Pan-dimensional Portal:** BOOST is a die roll ("?"), now handled.
- **Blackbeard – Plunder, Scourge of the Seven Seas:** schemes had a value of 0; removed.
- Typos in "used by" fixed: Allice → Alice, The Potter → The Porter, Djkstra → Dijkstra,
  plus Harpy / Dr. Jekyll / Mr. Hyde labels.
- Titania's six glamour cards were missing from the data; added from research.

All data corrections live in `tool/card_fixes.json`.

### Engine bugs found by the tests and fixed
- Invisible Man / Ancient Leshen returning from "vanish" could land on an occupied space.
- Ongoing schemes could lose track of the card when played (card count mismatch).
- Doctor Strange's Mists of Munnopor and Black Widow's missions could briefly lose cards.
- Bonus attacks (Relentless Assault, Volley, Tricked You) could be "returned to hand" as if real cards.
- Card titles with accents (RAGNARÖK) weren't matched to their effects.
- Each hero can now have only one ongoing scheme at a time (official rule).

---

## To-do

- [ ] Run on an Android phone: frame rate, touch (one finger pans, two fingers zoom/rotate the 3D map)
- [ ] Run on Windows desktop (needs Visual Studio with "Desktop development with C++")
- [ ] iPhone build (needs a Mac)
- [ ] Dev-only flags for testing: `--dart-define=QUICKMATCH=<map>[:players]` jumps straight into a
      match; `--dart-define=AUTOPLAY=true` lets an AI play your seat. Never use in real builds.

## Open questions for you

- **Krang's Die of Ultimate Destruction:** the real faces aren't published anywhere I could find.
  Currently assumed **blank, 1, 1, 2, 2, 3** (`dieFaces` in `lib/engine/hero_script.dart`).
  Tell me the real faces if you have the die.
- **Repo is public** — your card scans are visible to anyone. Make it private in GitHub
  Settings → General if you prefer.

## Later (not started)

- LAN play over a phone hotspot (the engine is ready: choices are just numbers, easy to send)
- Online play
- The other 31 heroes from `heroes.json` (70 total)
- Your 3D models in place of the orbs
