---
version: 1
slug: "lib-main-dart"
primary_target: "lib/main.dart"
related_targets: ["lib/ui"]
---

# Surface: the whole game app (menus + live match)

Mode: Experience for menus, hero select and VS intro; Operate for the live match screen.
Audience: one Unmatched player on an Android phone in landscape, both thumbs.
Task: set up a match fast (mode, map, AI level, hero), then play it knowing at every moment whose
turn it is and what they may do. Constraints: 60 fps on phones, hidden info never shown, LAN/Online
"Coming soon".
Memorable moment: the VS intro and the combat push-in where both cards flip side by side.

## Direction contract

THESIS: The app is the Digital Edition's table: a charcoal felt-and-stone tabletop where every
control is a cut hexagon or an angled plate. It refuses the generic mobile-game menu (rounded
glossy buttons on a gradient) and the navy+gold admin look the early code had.

OWN-WORLD: Graphite ground (#16171A to #24252A) with faint radial vignette and fine line
ornament in bone (#E8E2D4 at 15-40%). Hexagonal icon buttons with a 1.5px bone outline; angled
parallelogram name plates filled with each hero's colour; green hex confirm (#5BB043); red
attacker / blue defender plates; heart badges for health. Saira Condensed ExtraBold caps for
names, Barlow for text.

STORY: Load (hero art drifts), name yourself, pick Play vs AI, choose mode, map, AI level, hero;
VS slam; play: the prompt bar always says the next step, highlights show what is tappable, a
confirm hex commits.

FIRST VIEWPORT: Main menu: left 55% a stacked fan of three hero minis on a lit plinth glow;
right column the wordmark UNMATCHED in bone caps over a thin deco rule, then a vertical stack of
angled plates (Play vs AI large, LAN and Online with COMING SOON tags, Settings), username plate
bottom-left.

FORM: Brief-pinned world (Unmatched: Digital Edition), first on the list. seed: none (pinned by brief; roll not run)

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance
