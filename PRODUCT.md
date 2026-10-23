# Product

<!-- impeccable:product-schema 1 -->

## Platform

android

Flutter app, tuned first for an Android phone held in landscape; the same build also ships to
iOS, Windows desktop and the web. It is a game with its own visual language, not a Material app:
Material governs only the platform guarantees (system Back works, insets, 48 dp touch targets).

## Users

One player (the owner, plus friends later) who already knows the board game Unmatched and wants
to play it on a phone against the computer, in short sessions, holding the phone sideways with
both thumbs. Later: two to five people on the same phone hotspot (LAN), then online.

## Product Purpose

A personal-use, fan-made digital version of Restoration Games' *Unmatched*: pick a hero, a map and
a mode, and play a full rules-accurate match against AI opponents. Success: a match plays start
to finish with every card resolving exactly as printed, and the player always knows what to do
next without reading the rulebook.

## Positioning

39 heroes scripted card by card against the printed cards, every mode (1v1, 2v2, 3v3,
free-for-all 2–5) and four AI levels, playable offline on a phone. The rules engine is pure Dart
and every decision is an index answer, so LAN/online can be added without touching the rules.

## Operating Context

- Played in landscape on a phone (portrait is locked out), in sessions of 10–30 minutes.
- The real game's flow: two actions per turn (maneuver, scheme, attack); combat reveals two
  cards, resolves IMMEDIATELY / DURING / damage / AFTER COMBAT effects.
- Hidden information matters: opponents' hands and deck order are never shown.

## Capabilities and Constraints

- Engine in `lib/engine/` (pure Dart, no Flutter imports); UI in `lib/ui/`.
- Modes: 1v1, 2v2, 3v3, free-for-all 2–5. AI: Easy / Medium / Hard / Insane. AI heroes random.
- LAN and Online appear in the main menu marked "Coming soon".
- Match fighters are drawn as glowing coloured orbs (hero large, sidekicks small), not images,
  until the owner's 3D models exist. Menus and hero select use the 2D art.
- Camera: pinch/scroll zoom, pan, dramatic push-in during combat.
- Graphics settings Low / Medium / High; target 60 fps on mid-range phones.
- Decks shuffled with `Random.secure()`.

## Brand Commitments

- Look and feel follows *Unmatched: Digital Edition* (reference screenshots in
  `../examples/`): charcoal table, hexagonal buttons, angled name plates in each hero's colour,
  thin off-white line ornament, green hex confirm button, heart health badges. Confirmed by the
  owner on 2026-10-23.
- Fonts: Saira Condensed (titles), Barlow Semi Condensed (text), both bundled (OFL).
- Fan project: no Restoration Games logo is reproduced; the name "Unmatched" is used as the
  app title for personal use.

## Evidence on Hand

- Card faces for all 39 heroes: `assets/cards/<hero>/NN.webp` (600×832).
- Hero avatar, identity card, card back, miniature render and sidekick tokens:
  `assets/heroes/<hero>/`.
- 13 maps with zones and links: `assets/data/maps.json`. Hero and card data:
  `assets/data/heroes.json`.
- Original synthesized music (menu, battle) and SFX: `assets/audio/`.
- No map artwork exists; boards are drawn in code from the map data.

## Product Principles

1. The player always knows whose turn it is, what they may do, and what a choice will cost before
   they commit to it.
2. Rules accuracy beats spectacle; spectacle (camera push-in, glow, sparks) is scaled by the
   graphics setting and never delays a decision.
3. Never reveal hidden information.
4. Thumb-first: every action reachable in landscape with both thumbs, nothing important under
   the hand fan.

## Accessibility & Inclusion

Touch targets at least 48 dp; text on the board readable at phone size; colour is never the
only signal (selection also uses rings/motion, teams also use labels).
