import '../game.dart';
import '../prompt.dart';
import 'ismcts.dart';

/// Cooperative time-slicing runner for Flutter Web: the search yields to the browser's event
/// loop every [frameBudgetMs] so animations stay at 60 FPS.
class WebTimeSlicedIsmctsRunner {
  static Future<List<int>> runSearch({
    required IsmctsEngine engine,
    required Game rootGame,
    required Prompt prompt,
    int frameBudgetMs = 8,
  }) =>
      engine.search(rootGame, prompt, cooperative: true, frameBudgetMs: frameBudgetMs);
}
