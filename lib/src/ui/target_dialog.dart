import 'package:malison/malison.dart';
import 'package:piecemeal/piecemeal.dart';

import '../engine.dart';
import 'game_screen.dart';
import 'input.dart';

/// A callback invoked when a target has been selected.
typedef SelectTarget(Vec target);

// TODO: Support targeting floor tiles and not just actors.

/// Modal dialog for letting the user select a target to perform a [Command] on.
class TargetDialog extends Screen<Input> {
  static const _numFrames = 5;
  static const _ticksPerFrame = 5;

  final GameScreen _gameScreen;
  final num _range;
  final SelectTarget _onSelect;
  final List<Monster> _monsters = <Monster>[];

  int _animateOffset = 0;

  /// The position of the currently targeted [Actor] or `null` if no actor is
  /// targeted.
  Vec get _target {
    if (_gameScreen.target == null) return null;
    return _gameScreen.target.pos;
  }

  bool get isTransparent => true;

  TargetDialog(this._gameScreen, this._range, this._onSelect) {
    // Default to targeting the nearest monster.
    var nearest;
    for (var actor in _gameScreen.game.stage.actors) {
      if (actor is! Monster) continue;
      if (!_gameScreen.game.stage[actor.pos].visible) continue;

      // Must be within range.
      var hero = _gameScreen.game.hero;
      var toMonster = actor.pos - hero.pos;
      if (toMonster > _range) continue;

      _monsters.add(actor);

      if (nearest == null || hero.pos - actor.pos < hero.pos - nearest.pos) {
        nearest = actor;
      }
    }

    if (nearest != null) {
      _gameScreen.target = nearest;
    }
  }

  bool handleInput(Input input) {
    switch (input) {
      case Input.ok:
        if (_target != null) {
          ui.pop();
          _onSelect(_target);
        }
        break;

      case Input.cancel: ui.pop(); break;

      case Input.nw: _changeTarget(Direction.nw); break;
      case Input.n: _changeTarget(Direction.n); break;
      case Input.ne: _changeTarget(Direction.ne); break;
      case Input.w: _changeTarget(Direction.w); break;
      case Input.e: _changeTarget(Direction.e); break;
      case Input.sw: _changeTarget(Direction.sw); break;
      case Input.s: _changeTarget(Direction.s); break;
      case Input.se: _changeTarget(Direction.se); break;
    }

    return true;
  }

  void update() {
    _animateOffset = (_animateOffset + 1) % (_numFrames * _ticksPerFrame);
    if (_animateOffset % _ticksPerFrame == 0) dirty();
  }

  void render(Terminal terminal) {
    var stage = _gameScreen.game.stage;

    // Show the range field.
    var black = new Glyph(" ");
    for (var pos in _gameScreen.cameraBounds) {
      var tile = stage[pos];
      if (!tile.visible) {
        _gameScreen.drawStageGlyph(terminal, pos.x, pos.y, black);
        continue;
      }

      if (!tile.isPassable) continue;
      if (stage.actorAt(pos) != null) continue;
      if (stage.itemAt(pos) != null) continue;

      // Must be in range.
      var toPos = pos - _gameScreen.game.hero.pos;
      if (toPos > _range) {
        _gameScreen.drawStageGlyph(terminal, pos.x, pos.y, black);
        continue;
      }

      // Show the damage ranges.
      var color = Color.yellow;
      if (toPos > _range * 2 / 3) {
        color = Color.darkYellow;
      }

      var glyph = tile.type.appearance[1] as Glyph;
      _gameScreen.drawStageGlyph(terminal, pos.x, pos.y,
          new Glyph.fromCharCode(glyph.char, color));
    }

    if (_target == null) return;

    // Show the path that the bolt will trace, stopping when it hits an
    // obstacle.
    int i = _animateOffset ~/ _ticksPerFrame;
    var reachedTarget = false;
    for (var pos in new Los(_gameScreen.game.hero.pos, _target)) {
      // Note if we made it to the target.
      if (pos == _target) {
        reachedTarget = true;
        break;
      }

      if (stage.actorAt(pos) != null) break;
      if (!stage[pos].isTransparent) break;

      _gameScreen.drawStageGlyph(terminal, pos.x, pos.y,
          new Glyph.fromCharCode(CharCode.bullet,
              (i == 0) ? Color.yellow : Color.darkYellow));
      i = (i + _numFrames - 1) % _numFrames;
    }

    // Only show the reticle if the bolt will reach the target.
    if (reachedTarget) {
      var targetColor = Color.yellow;
      var toTarget = _target - _gameScreen.game.hero.pos;
      if (toTarget > _range * 2 / 3) {
        targetColor = Color.darkYellow;
      }

      _gameScreen.drawStageGlyph(terminal, _target.x - 1, _target.y,
          new Glyph('-', targetColor));
      _gameScreen.drawStageGlyph(terminal, _target.x + 1, _target.y,
          new Glyph('-', targetColor));
      _gameScreen.drawStageGlyph(terminal, _target.x, _target.y - 1,
          new Glyph('|', targetColor));
      _gameScreen.drawStageGlyph(terminal, _target.x, _target.y + 1,
          new Glyph('|', targetColor));
    }
  }

  /// Target the nearest monster in [dir] from the current target. Precisely,
  /// draws a line perpendicular to [dir] and divides the monsters into two
  /// half-planes. If the half-plane towards [dir] contains any monsters, then
  /// this targets the nearest one. Otherwise, it wraps around and targets the
  /// *farthest* monster in the other half-place.
  void _changeTarget(Direction dir) {
    var ahead = [];
    var behind = [];

    var perp = dir.rotateLeft90;
    for (var monster in _monsters) {
      var relative = monster.pos - _target;
      var dotProduct = perp.x * relative.y - perp.y * relative.x;
      if (dotProduct > 0) {
        ahead.add(monster);
      } else {
        behind.add(monster);
      }
    }

    var nearest = _findLowest(ahead,
        (monster) => (monster.pos - _target).lengthSquared);
    if (nearest != null) {
      _gameScreen.target = nearest;
      return;
    }

    var farthest = _findHighest(behind,
        (monster) => (monster.pos - _target).lengthSquared);
    if (farthest != null) {
      _gameScreen.target = farthest;
    }
  }
}

/// Finds the item in [collection] whose score is lowest.
///
/// The score for an item is determined by calling [callback] on it. Returns
/// `null` if the [collection] is `null` or empty.
_findLowest(Iterable collection, num callback(item)) {
  if (collection == null) return null;

  var bestItem;
  var bestScore;

  for (var item in collection) {
    var score = callback(item);
    if (bestScore == null || score < bestScore) {
      bestItem = item;
      bestScore = score;
    }
  }

  return bestItem;
}

/// Finds the item in [collection] whose score is highest.
///
/// The score for an item is determined by calling [callback] on it. Returns
/// `null` if the [collection] is `null` or empty.
_findHighest(Iterable collection, num callback(item)) {
  if (collection == null) return null;

  var bestItem;
  var bestScore;

  for (var item in collection) {
    var score = callback(item);
    if (bestScore == null || score > bestScore) {
      bestItem = item;
      bestScore = score;
    }
  }

  return bestItem;
}
