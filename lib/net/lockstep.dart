/// Lockstep multiplayer: every device runs its own copy of the match with the same seed, and
/// the only thing sent between them is each decision (the indices a seat picked). The engine is
/// deterministic given the seed and the decisions, so every copy plays out the same.
///
/// Decisions are numbered in the order the engine asks for them, which is the same on every
/// device. The host is the authority: it answers for AI seats, checks every remote answer
/// before relaying it, and takes a seat over with AI if its player leaves.
library;

import 'dart:async';

import '../engine/ai.dart';
import '../engine/game.dart';
import '../engine/prompt.dart';

/// An answer to decision [seq], made by [seat].
typedef Answer = ({int seat, List<int> picks});

class Lockstep {
  int _next = 0;
  final Map<int, Answer> _answers = {};
  final Map<int, Completer<Answer>> _waiting = {};
  Object? _failure;

  /// Called with every answer made on this device (to send to the others).
  void Function(int seq, Answer a)? publish;

  /// The number of the next decision.
  int take() => _next++;

  /// A device that joins (or rejoins) a running match is sent every decision made so far; until it
  /// has played through them [replaying] is true: it answers from the log instead of asking the
  /// player again, and the match screen skips the animations.
  int replayTarget = 0;
  bool get replaying => _next < replayTarget;

  /// How many decisions have been answered so far.
  int get answered {
    var n = 0;
    while (_answers.containsKey(n)) {
      n++;
    }
    return n;
  }

  /// Records an answer from the network (or made here). Later copies of the same decision are
  /// ignored: the first one wins.
  void put(int seq, Answer a) {
    if (_answers.containsKey(seq)) return;
    _answers[seq] = a;
    _waiting.remove(seq)?.complete(a);
  }

  Answer? known(int seq) => _answers[seq];

  /// The oldest decision this device is still waiting to hear about (to ask for a re-send).
  int? get oldestWaiting => _waiting.isEmpty ? null : _waiting.keys.reduce((a, b) => a < b ? a : b);

  /// Every known answer from [from] on, in order (to re-send).
  Iterable<(int, Answer)> since(int from) sync* {
    for (var seq = from; _answers.containsKey(seq); seq++) {
      yield (seq, _answers[seq]!);
    }
  }

  // Host only: answers sent in by players, filed by (decision, seat), so nobody can answer a
  // decision that belongs to someone else's seat.
  final Map<(int, int), List<int>> _offers = {};
  final Map<(int, int), Completer<List<int>>> _offerWaits = {};

  void offer(int seq, int seat, List<int> picks) {
    final k = (seq, seat);
    if (_offers.containsKey(k) || _answers.containsKey(seq)) return;
    _offers[k] = picks;
    _offerWaits.remove(k)?.complete(picks);
  }

  Future<List<int>> waitOffer(int seq, int seat) {
    final k = (seq, seat);
    final o = _offers.remove(k);
    if (o != null) return Future.value(o);
    if (_failure != null) return Future.error(_failure!);
    return (_offerWaits[k] ??= Completer<List<int>>()).future;
  }

  Future<Answer> wait(int seq) {
    final a = _answers[seq];
    if (a != null) return Future.value(a);
    if (_failure != null) return Future.error(_failure!);
    return (_waiting[seq] ??= Completer<Answer>()).future;
  }

  /// The connection is gone: every pending wait fails with [error].
  void fail(Object error) {
    _failure = error;
    for (final c in _waiting.values) {
      c.completeError(error);
    }
    for (final c in _offerWaits.values) {
      c.completeError(error);
    }
    _waiting.clear();
    _offerWaits.clear();
  }
}

/// Whether [picks] is a legal answer to [p] (mirrors the checks in [Game.decide]).
bool validPicks(Prompt p, List<int> picks) {
  if (picks.any((i) => i < 0 || i >= p.choices.length)) return false;
  if (picks.toSet().length != picks.length) return false;
  if (picks.isEmpty) return p.optional || p.choices.isEmpty || p.min == 0;
  if (p.ask == Ask.cards) return picks.length >= p.min && picks.length <= p.max;
  return picks.length == 1;
}

/// A seat answered on this device: the person holding it, or (on the host) an AI.
class LocalSeatAgent implements Agent {
  LocalSeatAgent(this.ls, this.seat, this.inner);
  final Lockstep ls;
  final int seat;
  final Agent inner;

  @override
  Future<List<int>> decide(Game game, Prompt prompt) async {
    final seq = ls.take();
    // Catching up after a rejoin: this decision was already made, take the recorded answer.
    if (seq < ls.replayTarget) return (await ls.wait(seq)).picks;
    final picks = await inner.decide(game, prompt);
    final a = (seat: seat, picks: picks);
    ls.put(seq, a);
    ls.publish?.call(seq, a);
    return picks;
  }
}

/// A seat answered on another device. On the host, answers are checked, relayed to everyone,
/// and an AI takes over if the player leaves or sends something illegal.
class RemoteSeatAgent implements Agent {
  RemoteSeatAgent(this.ls, this.seat, {this.host = false, this.onInvalid});
  final Lockstep ls;
  final int seat;

  /// Whether this device is the authority (checks and relays answers). A player's device becomes
  /// the host when the host is lost for good (see [becomeHost]).
  bool host;

  /// Host only: the seat's player sent an illegal answer (the seat is then taken over).
  void Function(int seat)? onInvalid;

  Agent? _takeover;

  /// Completed whenever the role changes, to wake a decision that is waiting under the old one.
  Completer<void> _changed = Completer<void>();
  void _notify() {
    if (!_changed.isCompleted) _changed.complete();
    _changed = Completer<void>();
  }

  /// From now on [ai] answers for this seat, including the decision being waited on. On the host
  /// this is the AI covering a player who left; on a device that has just become the host it
  /// covers the seats the lost host was running.
  void takeOver(Agent ai) {
    _takeover = ai;
    _notify();
  }

  /// This device is now the authority for the seat: wait for the player's answer here instead of
  /// for the old host's relay.
  void becomeHost(void Function(int seat)? onInvalid) {
    host = true;
    this.onInvalid = onInvalid;
    _notify();
  }

  bool get takenOver => _takeover != null;

  @override
  Future<List<int>> decide(Game game, Prompt prompt) async {
    final seq = ls.take();
    if (seq < ls.replayTarget) return (await ls.wait(seq)).picks;
    while (_takeover == null) {
      final changed = _changed.future.then<void>((_) {});
      if (!host) {
        // Wait for the host's relay, unless the role changes meanwhile.
        final a = await Future.any<Answer?>([ls.wait(seq), changed.then((_) => null)]);
        if (a != null) return a.picks;
      } else {
        final picks = await Future.any<List<int>?>([ls.waitOffer(seq, seat), changed.then((_) => null)]);
        if (picks != null) {
          if (validPicks(prompt, picks)) {
            final a = (seat: seat, picks: picks);
            ls.put(seq, a);
            ls.publish?.call(seq, a);
            return picks;
          }
          onInvalid?.call(seat);
          takeOver(AiAgent(level: AiLevel.hard));
        }
      }
    }
    // The answer may have arrived while the seat was being taken over: it stands.
    final known = ls.known(seq);
    if (known != null) return known.picks;
    // Taken over: the AI answers here and the answer goes to everyone.
    final picks = await _takeover!.decide(game, prompt);
    final a = (seat: seat, picks: picks);
    ls.put(seq, a);
    ls.publish?.call(seq, a);
    return picks;
  }
}
