# unmatched_game

A fan-made, personal-use digital version of the board game Unmatched, in Flutter.
Status and the engine reference: `HANDOFF.md`. What's left to do: `TODO.md`. Every card: `CARDS.md`.

## Getting started

1. Install **Flutter 3.47.1 (stable)** or newer (Dart ^3.13.1) and check it with `flutter doctor`.
   Chrome is enough to run the game. Windows desktop also needs Visual Studio (C++ workload), and
   Android needs Android Studio.
2. Clone and fetch the packages:

   ```sh
   git clone https://github.com/Nepthys2006/Unmatched.git
   cd Unmatched
   flutter pub get
   ```

3. Run it:

   ```sh
   flutter run -d chrome
   ```

   Vs AI and LAN play work without any keys.

### Online play (optional)

Online lobbies need the Supabase keys. **They are not in the repo: never commit `.env`.** Ask the
project owner for the file privately, or copy `.env.example` to `.env` and fill it in. Then pass it
to every run or build (the app reads the keys at compile time, so a `.env` file alone does nothing):

```sh
flutter run -d chrome --dart-define-from-file=.env
```

## Tests

The same set the CI runs:

```sh
flutter test --exclude-tags golden,online $(ls test/*_test.dart | grep -v -e online_test -e fuzz_test -e all_heroes_ui)
```

- `test/online_test.dart` creates and deletes a lobby on the **live** Supabase project, so it is
  skipped unless you ask for it: `flutter test --run-skipped --tags online test/online_test.dart`.
- `test/fuzz_test.dart` (up to 90 minutes) and `test/all_heroes_ui_test.dart` are long; run them on purpose.
- AI changes: measure them with `dart run tool/ai_arena.dart` (see `TODO.md`).

## Contributing

Work on a branch, push it, and open a pull request into `main`:

```sh
git checkout -b fix/<short-name>
# ...changes, then run the tests above...
git push -u origin fix/<short-name>
```
