import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Jeu du doigt : chacun pose un doigt → équipes aléatoires.
class FingerTeamPickScreen extends StatefulWidget {
  const FingerTeamPickScreen({super.key});

  @override
  State<FingerTeamPickScreen> createState() => _FingerTeamPickScreenState();
}

class _FingerTeamPickScreenState extends State<FingerTeamPickScreen>
    with TickerProviderStateMixin {
  static const _palette = [
    Color(0xFFE53935),
    Color(0xFF1E88E5),
    Color(0xFF43A047),
    Color(0xFFFB8C00),
    Color(0xFF8E24AA),
    Color(0xFF00ACC1),
    Color(0xFFFDD835),
    Color(0xFF6D4C41),
  ];

  int _playerCount = 4;
  int _teamCount = 2;
  final _pointers = <int, Offset>{};
  final _pointerColors = <int, Color>{};
  Map<int, int>? _teamByPointer; // pointer → team index
  Timer? _holdTimer;
  int _countdown = 0;
  bool _revealed = false;
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  int get _perTeam =>
      _teamCount <= 0 ? 0 : (_playerCount / _teamCount).floor();

  void _resetResult() {
    _holdTimer?.cancel();
    _teamByPointer = null;
    _revealed = false;
    _countdown = 0;
  }

  void _onPointerDown(PointerDownEvent e) {
    if (_revealed) _resetResult();
    setState(() {
      _pointers[e.pointer] = e.localPosition;
      _pointerColors[e.pointer] =
          _palette[_pointers.length % _palette.length];
    });
    _maybeStartCountdown();
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    setState(() => _pointers[e.pointer] = e.localPosition);
  }

  void _onPointerUp(PointerUpEvent e) {
    if (_revealed) return;
    setState(() {
      _pointers.remove(e.pointer);
      _pointerColors.remove(e.pointer);
    });
    _holdTimer?.cancel();
    setState(() => _countdown = 0);
    _maybeStartCountdown();
  }

  void _onPointerCancel(PointerCancelEvent e) {
    _onPointerUp(
      PointerUpEvent(
        pointer: e.pointer,
        position: e.position,
        timeStamp: e.timeStamp,
      ),
    );
  }

  void _maybeStartCountdown() {
    _holdTimer?.cancel();
    if (_pointers.length < _playerCount) {
      setState(() => _countdown = 0);
      return;
    }
    setState(() => _countdown = 3);
    _holdTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_pointers.length < _playerCount) {
        t.cancel();
        setState(() => _countdown = 0);
        return;
      }
      if (_countdown <= 1) {
        t.cancel();
        _assignTeams();
      } else {
        setState(() => _countdown--);
        HapticFeedback.lightImpact();
      }
    });
  }

  void _assignTeams() {
    HapticFeedback.heavyImpact();
    final ids = _pointers.keys.toList()..shuffle(Random());
    final map = <int, int>{};
    for (var i = 0; i < ids.length; i++) {
      map[ids[i]] = i % _teamCount;
    }
    setState(() {
      _teamByPointer = map;
      _revealed = true;
      _countdown = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Jeu du doigt')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Posez $_playerCount doigts · $_teamCount équipe${_teamCount > 1 ? 's' : ''}'
                  '${_perTeam > 0 ? ' de ~$_perTeam' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'Quand tout le monde a le doigt posé, comptage puis tirage des équipes.',
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _Stepper(
                        label: 'Joueurs',
                        value: _playerCount,
                        min: 2,
                        max: 12,
                        onChanged: (v) {
                          setState(() {
                            _playerCount = v;
                            if (_teamCount > _playerCount) {
                              _teamCount = _playerCount;
                            }
                            _resetResult();
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _Stepper(
                        label: 'Équipes',
                        value: _teamCount,
                        min: 2,
                        max: max(2, _playerCount),
                        onChanged: (v) {
                          setState(() {
                            _teamCount = v;
                            _resetResult();
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _onPointerDown,
              onPointerMove: _onPointerMove,
              onPointerUp: _onPointerUp,
              onPointerCancel: _onPointerCancel,
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) {
                  return CustomPaint(
                    painter: _FingerArenaPainter(
                      pointers: Map.of(_pointers),
                      colors: Map.of(_pointerColors),
                      teams: _teamByPointer,
                      teamCount: _teamCount,
                      pulse: _pulse.value,
                      countdown: _countdown,
                      need: _playerCount,
                      revealed: _revealed,
                    ),
                    child: const SizedBox.expand(),
                  );
                },
              ),
            ),
          ),
          if (_revealed)
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.tonal(
                onPressed: () => setState(_resetResult),
                child: const Text('Rejouer'),
              ),
            ),
        ],
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const _Stepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label, style: const TextStyle(fontSize: 13)),
        const Spacer(),
        IconButton(
          onPressed: value > min ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        Text('$value', style: const TextStyle(fontWeight: FontWeight.w800)),
        IconButton(
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }
}

class _FingerArenaPainter extends CustomPainter {
  final Map<int, Offset> pointers;
  final Map<int, Color> colors;
  final Map<int, int>? teams;
  final int teamCount;
  final double pulse;
  final int countdown;
  final int need;
  final bool revealed;

  _FingerArenaPainter({
    required this.pointers,
    required this.colors,
    required this.teams,
    required this.teamCount,
    required this.pulse,
    required this.countdown,
    required this.need,
    required this.revealed,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0xFF121212);
    canvas.drawRect(Offset.zero & size, bg);

    final hint = TextPainter(
      text: TextSpan(
        text: revealed
            ? 'Équipes tirées !'
            : countdown > 0
                ? '$countdown…'
                : '${pointers.length} / $need doigts',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.55),
          fontSize: countdown > 0 ? 42 : 18,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    hint.paint(
      canvas,
      Offset((size.width - hint.width) / 2, size.height * 0.12),
    );

    for (final e in pointers.entries) {
      final team = teams?[e.key];
      final color = revealed && team != null
          ? _FingerTeamPickScreenState._palette[team %
              _FingerTeamPickScreenState._palette.length]
          : (colors[e.key] ?? Colors.white);
      final r = 28.0 + (revealed ? 10 : 8 * pulse);
      final paint = Paint()
        ..color = color.withValues(alpha: 0.85)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(e.value, r, paint);
      canvas.drawCircle(
        e.value,
        r,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
      if (revealed && team != null) {
        final tp = TextPainter(
          text: TextSpan(
            text: 'E${team + 1}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          e.value - Offset(tp.width / 2, tp.height / 2),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FingerArenaPainter oldDelegate) => true;
}
