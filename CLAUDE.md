# Project notes for Claude

Read HANDOFF.md first: it has the user requirements, engine API, rules decisions and what is left (the Flutter UI).

- The engine in lib/engine must stay pure Dart (no Flutter imports) and rules-accurate; run the fast tests after any engine change.
- Mobile is landscape only; target 60 fps on mobile, desktop and web.
- Never reveal hidden information (opponent hands, deck order) in the UI.
