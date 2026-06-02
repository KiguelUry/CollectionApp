import 'package:flutter/material.dart';

/// Lego officiel vs maquette / scale model.
enum LegoBuildKind {
  lego,
  maquette;

  String get dbValue => name;

  String get label => switch (this) {
        LegoBuildKind.lego => 'Lego',
        LegoBuildKind.maquette => 'Maquettes',
      };

  String get description => switch (this) {
        LegoBuildKind.lego => 'Sets Lego & Creator',
        LegoBuildKind.maquette => 'Maquettes, scale models, Gunpla…',
      };

  IconData get icon => switch (this) {
        LegoBuildKind.lego => Icons.extension,
        LegoBuildKind.maquette => Icons.precision_manufacturing_outlined,
      };

  Color get color => switch (this) {
        LegoBuildKind.lego => Colors.red,
        LegoBuildKind.maquette => Colors.deepOrange,
      };

  static LegoBuildKind fromDbValue(String? v) {
    if (v == null) return LegoBuildKind.lego;
    return LegoBuildKind.values.firstWhere(
      (e) => e.dbValue == v,
      orElse: () => LegoBuildKind.lego,
    );
  }
}
