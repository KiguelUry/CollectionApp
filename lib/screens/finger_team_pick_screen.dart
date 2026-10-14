import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Jeu du doigt (tactile) ou tirage par noms (PC / web).
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

  /// Sur web / desktop : mode noms par défaut (pas de multi-touch fiable).
  late bool _useNamesMode;

  int _playerCount = 4;
  int _teamCount = 2;
  final _pointers = <int, Offset>{};
  final _pointerColors = <int, Color>{};
  Map<int, int>? _teamByPointer;
  Timer? _holdTimer;
  int _countdown = 0;
  bool _revealed = false;
  late AnimationController _pulse;

  late List<TextEditingController> _nameControllers;
  List<List<String>>? _namedTeams;

  @override
  void initState() {
    super.initState();
    _useNamesMode = kIsWeb ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
    _nameControllers = List.generate(4, (_) => TextEditingController());
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _pulse.dispose();
    for (final c in _nameControllers) {
      c.dispose();
    }
    super.dispose();
  }

  int get _perTeam =>
      _teamCount <= 0 ? 0 : (_playerCount / _teamCount).floor();

  void _syncNameFields() {
    while (_nameControllers.length < _playerCount) {
      _nameControllers.add(TextEditingController());
    }
    while (_nameControllers.length > _playerCount) {
      _nameControllers.removeLast().dispose();
    }
  }

  void _fullReset() {
    _holdTimer?.cancel();
    _teamByPointer = null;
    _revealed = false;
    _countdown = 0;
    _pointers.clear();
    _pointerColors.clear();
    _namedTeams = null;
  }

  void _onPointerDown(PointerDownEvent e) {
    if (_useNamesMode) return;
    if (_revealed) {
      setState(_fullReset);
    }
    setState(() {
      _pointers[e.pointer] = e.localPosition;
      _pointerColors[e.pointer] =
          _palette[_pointers.length % _palette.length];
    });
    _maybeStartCountdown();
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (_useNamesMode || !_pointers.containsKey(e.pointer)) return;
    setState(() => _pointers[e.pointer] = e.localPosition);
  }

  void _onPointerUp(PointerUpEvent e) {
    if (_useNamesMode) return;
    // Après révélation : on laisse les pastilles jusqu'à « Rejouer »
    // ou un nouveau doigt (qui reset). Les up ne doivent pas laisser
    // d'orphelins si pas encore révélé.
    if (_revealed) return;
    setState(() {
      _pointers.remove(e.pointer);
      _pointerColors.remove(e.pointer);
      _countdown = 0;
    });
    _holdTimer?.cancel();
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
        _assignFingerTeams();
      } else {
        setState(() => _countdown--);
        HapticFeedback.lightImpact();
      }
    });
  }

  void _assignFingerTeams() {
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

  void _drawNamedTeams() {
    final names = _nameControllers
        .map((c) => c.text.trim())
        .where((n) => n.isNotEmpty)
        .toList();
    if (names.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Entre au moins 2 noms')),
      );
      return;
    }
    final shuffled = List<String>.from(names)..shuffle(Random());
    final teams = List.generate(_teamCount, (_) => <String>[]);
    for (var i = 0; i < shuffled.length; i++) {
      teams[i % _teamCount].add(shuffled[i]);
    }
    HapticFeedback.mediumImpact();
    setState(() {
      _namedTeams = teams;
      _revealed = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Jeu du doigt'),
        actions: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                icon: Icon(Icons.touch_app_outlined, size: 16),
                label: Text('Doigts'),
              ),
              ButtonSegment(
                value: true,
                icon: Icon(Icons.badge_outlined, size: 16),
                label: Text('Noms'),
              ),
            ],
            selected: {_useNamesMode},
            onSelectionChanged: (s) {
              setState(() {
                _useNamesMode = s.first;
                _fullReset();
                if (_useNamesMode) _syncNameFields();
              });
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _useNamesMode
                      ? 'Entre les prénoms, puis tire les équipes'
                      : 'Posez $_playerCount doigts · $_teamCount équipe${_teamCount > 1 ? 's' : ''}'
                          '${_perTeam > 0 ? ' de ~$_perTeam' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (!_useNamesMode) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Quand tout le monde a le doigt posé, comptage puis tirage.',
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _Stepper(
                      label: _useNamesMode ? 'Places' : 'Joueurs',
                      value: _playerCount,
                      min: 2,
                      max: 12,
                      onChanged: (v) {
                        setState(() {
                          _playerCount = v;
                          if (_teamCount > _playerCount) {
                            _teamCount = _playerCount;
                          }
                          _fullReset();
                          if (_useNamesMode) _syncNameFields();
                        });
                      },
                    ),
                    _Stepper(
                      label: 'Équipes',
                      value: _teamCount,
                      min: 2,
                      max: max(2, _playerCount),
                      onChanged: (v) {
                        setState(() {
                          _teamCount = v;
                          _fullReset();
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _useNamesMode ? _buildNamesBody(scheme) : _buildFingerBody(),
          ),
          if (_revealed)
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.tonal(
                onPressed: () => setState(_fullReset),
                child: const Text('Rejouer'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFingerBody() {
    return Listener(
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
              pulse: _pulse.value,
              countdown: _countdown,
              need: _playerCount,
              revealed: _revealed,
            ),
            child: const SizedBox.expand(),
          );
        },
      ),
    );
  }

  Widget _buildNamesBody(ColorScheme scheme) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        for (var i = 0; i < _nameControllers.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TextField(
              controller: _nameControllers[i],
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Joueur ${i + 1}',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _drawNamedTeams,
          icon: const Icon(Icons.casino_outlined),
          label: const Text('Tirer les équipes'),
        ),
        if (_namedTeams != null) ...[
          const SizedBox(height: 20),
          for (var t = 0; t < _namedTeams!.length; t++)
            Card(
              color: _palette[t % _palette.length].withValues(alpha: 0.2),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: _palette[t % _palette.length],
                  child: Text(
                    '${t + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                title: Text(
                  'Équipe ${t + 1}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  _namedTeams![t].isEmpty
                      ? '—'
                      : _namedTeams![t].join(' · '),
                ),
              ),
            ),
        ],
      ],
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
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 6),
        IconButton(
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          onPressed: value > min ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        Text(
          '$value',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
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
  final double pulse;
  final int countdown;
  final int need;
  final bool revealed;

  _FingerArenaPainter({
    required this.pointers,
    required this.colors,
    required this.teams,
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
          ? _FingerTeamPickScreenState._palette[
              team % _FingerTeamPickScreenState._palette.length]
          : (colors[e.key] ?? Colors.white);
      final r = 28.0 + (revealed ? 10 : 8 * pulse);
      canvas.drawCircle(
        e.value,
        r,
        Paint()
          ..color = color.withValues(alpha: 0.85)
          ..style = PaintingStyle.fill,
      );
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
        tp.paint(canvas, e.value - Offset(tp.width / 2, tp.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FingerArenaPainter oldDelegate) => true;
}
