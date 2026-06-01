import 'package:flutter/material.dart';

import 'category_metadata.dart';

extension MediaFormatUi on MediaFormat {
  String get description => switch (this) {
        MediaFormat.vinyl => 'Discogs + scan EAN (vinyles)',
        MediaFormat.cd => 'Discogs ou MusicBrainz',
        MediaFormat.cassette => 'K7 · saisie ou recherche',
      };

  IconData get icon => switch (this) {
        MediaFormat.vinyl => Icons.album,
        MediaFormat.cd => Icons.album_outlined,
        MediaFormat.cassette => Icons.surround_sound_outlined,
      };

  Color get color => switch (this) {
        MediaFormat.vinyl => Colors.teal,
        MediaFormat.cd => Colors.cyan.shade700,
        MediaFormat.cassette => Colors.brown,
      };
}
