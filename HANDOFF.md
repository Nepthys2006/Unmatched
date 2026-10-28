# Unmatched (fan game) — handoff

A fan-made, personal-use digital version of the board game **Unmatched** (Restoration Games), built in
**Flutter** for mobile (landscape), desktop and web. Look and feel target: *Unmatched: Digital Edition*.

## Status (2026-10-24)

| Area | State |
|---|---|
| Rules engine (`lib/engine/`) | **Done.** Pure Dart, no Flutter imports. |
| All 70 heroes scripted | **Done.** Every card checked against the printed card image. See `CARDS.md`. |
| Tests (`test/`) | **110 passing.** ~18k simulated games, 12M invariant checks. |
| Game modes in engine | **Done.** 1v1, 2v2, 3v3, free-for-all 3–5 players. |
| AI (`lib/engine/ai.dart`) | **Done.** Easy / Medium / Hard / Insane. Answers the same prompts a human does. Measure changes with `dart run tool/ai_arena.dart` (see TODO.md). |
| Assets | **Done.** Card faces, backs, identity cards, avatars, minis, sidekick tokens, fonts, original synthesized music + SFX. |
| Flutter UI (`lib/ui/`) | **Playable end to end**, every mode. See TODO.md for what's left. |
| Maps (`assets/maps/`, `assets/data/maps.json`) | **Done.** 47 printed-style 2D boards (the 32 official maps + 15 own, 5 of them 3v3). Built by `tool/build_maps.py`. The 3D view (`lib/ui/board3d/`) is no longer used. |
| 3D fighters (`assets/web3d/board.js`, `assets/web3d/figures.json`) | **Done.** Each fighter is its miniature render sculpted into a rounded relief (sidekicks: their token as a domed coin) on a podium in the player's colour, turned to face the camera, with a shield badge (portrait, name, HP). Falls back to the orb if its picture is missing. |

## The user's requirements for the UI (all still to build)

1. **Loading screen** with hero images (2D art, no 3D models).
2. **Username prompt** on first launch (only the username for now), saved locally.
3. **Main menu**: *Play vs AI*; *LAN* (join over a phone hotspot) and *Online* buttons present but marked **Coming soon**; Settings.
4. **Match setup**: mode **1v1, 2v2, 3v3, free-for-all 2–5**; the **user picks the map or hits a Random map button**; AI difficulty **Easy / Medium / Hard / Insane**; the user **picks their hero**, **AI heroes are random**.
5. **Hero select** shows for each hero: **avatar, identity (character) card, sidekick token(s), miniature PNG**, plus stats/ability. Cool, polished theme.
6. **Live match**: fighters drawn as **glowing coloured orbs** (hero bigger, sidekicks smaller) so they are easy to spot — *not* images for now. Zone-coloured spaces, paths.
7. **Camera**: pinch/scroll **zoom in/out**, **pan/scroll** the map, plus a dramatic **camera push-in / pan during combat** ("intense duel").
8. **Guidance UI**: a clear **"Your turn" banner**; **highlight** selectable fighters, destination spaces, attack targets, playable cards; **confirmation dialogs** before committing (e.g. *"Attack with this card?"*, *"Discard this card to BOOST your movement?"*, *"Are you sure?"*). The user should always know what to do next.
9. **Cards**: tapping a card **enlarges it** so it is readable. Hand fanned at the bottom like the digital edition.
10. **Combat presentation**: both cards revealed side by side, value breakdown (base, boosts, modifiers), damage, winner.
11. **Battle music**: thrilling 1v1 background music in matches (`assets/audio/battle.wav`), menu music (`menu.wav`), SFX (card, hit, whoosh, step, reveal, victory, click, heal).
12. **Graphics settings**: quality presets (e.g. Low/Medium/High: glow, particles, camera effects, animation speed), music/SFX volume.
13. **Mobile is landscape only.** Smooth ~**60 fps** on mobile, desktop, web.
14. **Anti-cheat**: decks shuffled with `Random.secure()` (already done in `Game` when no seed is given). Never show hidden cards.

Reference screenshots of the real digital edition were in the user's local `examples/` folder (not in
this repo): dark navy UI, gold accents, hero portraits in corner panels with health dials, hand of cards
fanned along the bottom edge, action buttons (Maneuver / Scheme / Attack) on the side.

## How the engine plugs into a UI

* `GameData.fromJson(heroes.json, maps.json)` (load both from `assets/data/`).
* `Game(data:, map:, heroIds: [...], teams: [...], agents: [...], presenter:)` then `await game.run()`.
  * Seats are in **turn order**; teams alternate (`teams: [0,1,0,1]` for 2v2, `[0,1,0,1,0,1]` for 3v3,
    omit for 1v1/FFA). Seat *i* starts on start space *i+1*. FFA 5 players needs a map with 5 starts
    (only `star` / "Pentacle Ruins").
  * Leave `seed` null in real games (secure shuffle).
* **Every decision** is a `Prompt` (`lib/engine/prompt.dart`) answered by an `Agent` with the indices
  chosen. Implement a `HumanAgent` whose `decide()` returns a `Future` completed by the UI. `Ask` tells
  you how to present it: `action`, `card`, `cards` (min..max), `fighter`, `space`, `path` (a board
  edge, value `(int,int)`), `option`, `yesNo`, `number`. `Prompt.optional` + `skipLabel` = show a skip
  button. `Prompt.intent` hints what it's for (harm/help/moveOwn/attackCard/defenseCard/boost…).
  `Prompt.subject` is the `Fighter`/`Combat`/`Side`/`Token` concerned (e.g. which fighter is moving).
* **Every change** is a `GameEvent` (`lib/engine/events.dart`) passed to `presenter` *after* the state
  changed; `await` inside the presenter to pace animations. Useful ones: `TurnStarted`, `FighterMoved`
  (path list), `Swapped`, `Damaged`, `Healed`, `Defeated`, `Returned`, `CombatStarted`, `CardsRevealed`,
  `PhaseChanged`, `EffectResolving`, `Canceled`, `ValuesChanged`, `CombatResolved`, `CombatEnded`,
  `SchemePlayed`, `Boosted`, `CardsDrawn`, `CardMoved`, `Revealed`, `StatusChanged`, `GameOver`.
  Each has a `log` string for the game log.
* Value breakdown for a combat card: `game.valueOf(side)` → `(total, lines)`.
* Hero status chips (Alice BIG, Rage 2, coils…): `player.script.status()`.
* Board: `game.board` (spaces with `x,y`, zones, links), tokens in `game.board.tokens`
  (`fog` on a space, `foot` on a path). `game.reachable(fighter, n)` gives move destinations + paths.
* Card image: `card.def.image` (`assets/cards/<hero>/NN.webp`, 600×832). Hero art:
  `hero.avatar`, `hero.mini`, `hero.back`, `hero.identity`, `hero.token(fighterId)`.
* LAN/online later: because the engine is deterministic given the seed and prompt answers are just
  indices, a network agent can be added without touching the rules.

## Rules decisions & sources

Rulebook (all sets) + official rulings collected by The Unmatched Club (general rulings, rule changes)
and set rulebooks (rulespal.com). Notable:
* Defender's effects resolve first; attacker wins only if the attack dealt ≥1 combat damage.
* Winner checked after AFTER COMBAT effects; if everyone falls, the active player's side wins.
* "Value is X instead" overwrites earlier boosts; a card is "canceled" only if it had an effect.
* Bonus attacks (Relentless Assault, Volley, Tricked You): same attacker/defender, no range recheck,
  defender may defend, none if either fighter is defeated.
* Team play: alternate A1 B1 A2 B2…; a player continues while they have any fighter. FFA: a defeated
  hero's player is out (sidekicks removed); first-turn attack restriction implemented.
* Ongoing schemes: one per hero, discard condition checked at end of the owner's turn.

**Unverified assumption:** Krang's *Die of Ultimate Destruction* faces are not published anywhere
found; `HeroScript.dieFaces = [0,1,1,2,2,3]` in `lib/engine/hero_script.dart`. Ask the user for the
real faces.

Data corrections made against the printed cards live in `tool/card_fixes.json`.

## Layout

```
lib/engine/        rules engine (defs, state, game, combat, events, prompt, hero_script, ai)
lib/engine/heroes/ one file per set; registry.dart maps hero id -> script
lib/ui/            screens, match screen, HUD, 2D board, settings, audio
lib/ui/board3d/    3D board controller + web view hosts (web iframe, Android/iOS WebView, Windows WebView2)
assets/data/       heroes.json (39 heroes, 484 cards), maps.json (13 boards)
assets/cards/      card faces per hero
assets/heroes/     avatar, mini, back, identity, sidekick tokens per hero; figure[-n].webp (3D board, tool/make_figures.py)
assets/audio/      battle.wav, menu.wav, sfx
assets/maps3d/     the 12 3D map models (.glb, meshopt + WebP) and their thumbnails
assets/web3d/      the Three.js page that draws the 3D board (three.js r170 bundled)
assets/fonts/      Saira Condensed (titles), Barlow Semi Condensed (text) — OFL
tool/              asset builders (need the user's local card scans; not needed for UI work)
test/              engine_core_test, heroes_*_test, fuzz_test (fuzz takes ~11 min)
```

## Commands

```
flutter pub get
flutter analyze
flutter test test/engine_core_test.dart test/heroes_bol_test.dart test/heroes_cobble_witcher_test.dart   # fast
flutter test test/fuzz_test.dart      # slow (~11 min), plays thousands of games
flutter run -d chrome                 # or windows / an Android device
flutter build web
```
