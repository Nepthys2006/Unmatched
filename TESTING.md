# Testing the Full Screen help on real devices

Emulators cannot do "Add to Home Screen" or the iPad's system behaviour (Split View, Slide Over, Stage
Manager, the home indicator, rounded corners). Run this list on **a real iPhone and a real iPad** before
a release. Everything else is covered by the automated tests (see the bottom).

Build for the test: `flutter build web --release --no-web-resources-cdn`, host the `build/web` folder
over HTTPS (Safari only allows Add to Home Screen, service workers and full screen on HTTPS or
localhost), and open `https://your-host/?debug=1` to get the **DEBUG** tab (bottom left).

| # | Device | Steps | Expected |
|---|--------|-------|----------|
| 1 | iPhone + iPad | Open the page in **Safari** (clear the site's data first: Settings > Safari > Advanced > Website Data). Wait for the main menu. | About a second after the menu appears the help opens by itself, titled **FULL SCREEN ON IPHONE** on the phone and **FULL SCREEN ON IPAD** on the iPad. Step 1 reads "Tap Share in Safari" (iPhone) or "Tap Share in the top bar of Safari" (iPad). Tap **GOT IT**: it closes. Reload: it does **not** come back. |
| 2 | iPad only | Menu or Settings > **Full screen**. | Either the page goes full screen (the label becomes **Exit full screen**) or, if Safari refuses, the help opens. Note which one happens on your iPad and iOS version. Leave full screen with the same button, then swipe down from the top to check the label follows. |
| 2b | iPad only | Settings > **Better full screen: install the app**. | The help opens even though it was dismissed. |
| 3 | iPhone + iPad | Follow the three steps: Share (bottom bar on iPhone, **top right on iPad**) > Add to Home Screen > Add. | An Unmatched icon (navy, not transparent) is on the Home Screen. |
| 4 | iPhone + iPad | Open Unmatched from the Home Screen. | No Safari bars, no help dialog by itself, **no Full Screen button** in the menu or Settings. |
| 5 | iPhone + iPad | Open it once online and let the menu load. Turn on **Airplane mode**, close the app completely, open it again from the Home Screen. Start a match against the AI and finish it. | It opens offline and the match can be played. History shows the match as **Pending**; turn Airplane mode off and it syncs. |
| 6 | iPhone + iPad | Look at all four edges, also turned on its side. | Nothing is hidden behind the notch / Dynamic Island, the rounded corners or the home indicator. |
| 7a | iPhone | Hold it upright. | **TURN YOUR PHONE** covers the screen; turn it sideways and it goes. |
| 7b | iPad | Turn it both ways, also **in the middle of a match**. | **No** rotate screen in either orientation. The layout adapts and the match carries on (same turn, same hand). |
| 8 | iPad | Open Unmatched in **Split View** (half and two-thirds), in **Slide Over**, and in **Stage Manager** if available. Drag the divider / resize the window while a match is running. | Wide enough: it plays. Too narrow (Slide Over, one-third Split View): **MAKE THIS WINDOW LARGER**, never a broken layout; widen it again and the same match is still there. |
| 9 | iPad | In Safari tap **aA** > **Request Mobile Website**, reload; then **Request Desktop Website**, reload. Use the debug panel to read **device kind**. | Both modes say **ipad** and show the iPad title. (Default desktop mode has a "Macintosh" user agent; it is told apart by touch.) |
| 10 | iPad + hardware keyboard | Open the help (step 2b). Press **Esc**. | It closes. Tab moves between its controls without leaving it. |
| 11 | iPhone / iPad | Open the help with Chrome or Firefox for iOS. | Step 1 reads "Tap Share (or the menu) in your browser". |
| 12 | Mac | Open the page in Safari on a Mac. | No help, ever. Debug panel: **device kind mac**. |

Report back: iOS / iPadOS version, device, what step 2 did, anything that differs from "Expected".

## Debug panel

`?debug=1` (or any debug build) shows a **DEBUG** tab. It lists what the page detects (device,
browser, user agent, platform, touch points, standalone, fullscreen support, orientation, window size, safe
area, "would the dialog show right now?"), can pretend to be any of the supported devices, force the
dialog, clear the dismissed flag, shrink the window (portrait, Split View), and **Run self-check**
(PASS / FAIL with a reason). Simulating never touches the real flag, saved matches or a running game.

## Automated tests

| What | Command |
|------|---------|
| Static analysis | `flutter analyze` |
| Unit + widget tests | `flutter test --exclude-tags golden` |
| Golden screenshots (compared on **Windows**, where they were made) | `flutter test --tags golden test/golden` (`--update-goldens` to rewrite) |
| Integration tests in Chrome | `flutter test integration_test/fullscreen_help_test.dart -d chrome` |
| Browser device emulation (Playwright, iPhone/iPad/Pixel/Mac/desktop) | `flutter build web --release --dart-define=DEMO=true --no-web-resources-cdn`, then `cd e2e && npm install && npx playwright install --with-deps webkit chromium && npm test` |
| Music does not restart on a press (menu + battle, real Chromium; needs the extra `build/web_match`, see `e2e/music.spec.mjs`) | `flutter build web --release --dart-define=QUICKMATCH=blossom:2:alice:3 --no-web-resources-cdn --output build/web_match` then `cd e2e && npx playwright test music.spec.mjs` |
| Server SQL (match sync, MMR) | `cd tool/sql_test && npm install && npm test` |

GitHub Actions runs all of these on every push (`.github/workflows/ci.yml`).

Playwright's iPad profiles send an "iPad" user agent, which is not what iPadOS does by default. The
suite therefore also has a custom WebKit profile with a **Macintosh** user agent, touch and
`maxTouchPoints` 5 (the real default iPad), and a real Mac with no touch.
