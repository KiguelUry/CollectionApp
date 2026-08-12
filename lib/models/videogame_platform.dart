import 'package:flutter/material.dart';

/// Plateformes pour filtrer / taguer un jeu vidéo.
enum VideogamePlatform {
  pc('pc', 'PC', Icons.computer_rounded),
  ps5('ps5', 'PlayStation 5', Icons.sports_esports_rounded),
  ps4('ps4', 'PlayStation 4', Icons.sports_esports_outlined),
  xboxSeries('xbox_series', 'Xbox Series', Icons.gamepad_rounded),
  xboxOne('xbox_one', 'Xbox One', Icons.gamepad_outlined),
  switch_('switch', 'Nintendo Switch', Icons.videogame_asset_rounded),
  mobile('mobile', 'Mobile', Icons.smartphone_rounded),
  retro('retro', 'Rétro', Icons.history_rounded),
  other('other', 'Autre', Icons.devices_other_rounded);

  final String id;
  final String label;
  final IconData icon;

  const VideogamePlatform(this.id, this.label, this.icon);

  static VideogamePlatform? fromId(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    for (final p in values) {
      if (p.id == raw) return p;
    }
    return null;
  }

  /// Déduit les plateformes depuis une chaîne RAWG / saisie libre.
  static List<VideogamePlatform> inferFromText(String? text) {
    if (text == null || text.trim().isEmpty) return const [];
    final lower = text.toLowerCase();
    final out = <VideogamePlatform>[];
    void add(VideogamePlatform p) {
      if (!out.contains(p)) out.add(p);
    }

    if (lower.contains('pc') ||
        lower.contains('steam') ||
        lower.contains('windows') ||
        lower.contains('mac') ||
        lower.contains('linux')) {
      add(pc);
    }
    if (lower.contains('playstation 5') || lower.contains('ps5')) add(ps5);
    if (lower.contains('playstation 4') || lower.contains('ps4')) add(ps4);
    if (lower.contains('xbox series') || lower.contains('series x')) {
      add(xboxSeries);
    }
    if (lower.contains('xbox one')) add(xboxOne);
    if (lower.contains('switch')) add(switch_);
    if (lower.contains('ios') ||
        lower.contains('android') ||
        lower.contains('mobile')) {
      add(mobile);
    }
    if (lower.contains('nes') ||
        lower.contains('snes') ||
        lower.contains('n64') ||
        lower.contains('game boy') ||
        lower.contains('dreamcast')) {
      add(retro);
    }
    return out;
  }
}

/// Statut de progression dans un jeu.
enum VideogamePlayStatus {
  backlog('backlog', 'À jouer'),
  playing('playing', 'En cours'),
  completed('completed', 'Terminé'),
  abandoned('abandoned', 'Abandonné');

  final String id;
  final String label;

  const VideogamePlayStatus(this.id, this.label);

  static VideogamePlayStatus fromId(String? raw) {
    for (final s in values) {
      if (s.id == raw) return s;
    }
    return backlog;
  }
}
