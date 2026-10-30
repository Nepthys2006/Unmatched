import '../game.dart';
import '../prompt.dart';
import 'ismcts.dart';

/// Desktop / mobile runner.
///
/// A [Game] holds scripts and closures that cannot be sent to another isolate, so the search runs
/// on the calling isolate in ~8 ms slices that yield to the event loop and keep the UI at 60 FPS.
class IsolateIsmctsRunner {
  static Future<List<int>> runSearch({
    required IsmctsEngine engine,
    required Game game,
    required Prompt prompt,
  }) =>
      engine.search(game, prompt, cooperative: true);
}
