/// Texte BGG lisible : balises, retours à la ligne et entités HTML.
String cleanBggText(String? html) {
  if (html == null || html.isEmpty) return '';
  var s = html
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]*>'), ' ');
  s = _decodeEntities(s);
  s = s
      .replaceAll('\r\n', '\n')
      .replaceAll(RegExp(r'[ \t]+\n'), '\n')
      .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
  return s;
}

String _decodeEntities(String input) {
  return input.replaceAllMapped(RegExp(r'&(#x?[0-9a-fA-F]+|[a-zA-Z]+);'), (m) {
    final token = m.group(1)!;
    if (token.startsWith('#x') || token.startsWith('#X')) {
      final code = int.tryParse(token.substring(2), radix: 16);
      return code == null ? m.group(0)! : String.fromCharCode(code);
    }
    if (token.startsWith('#')) {
      final code = int.tryParse(token.substring(1));
      return code == null ? m.group(0)! : String.fromCharCode(code);
    }
    return switch (token) {
      'amp' => '&',
      'lt' => '<',
      'gt' => '>',
      'quot' => '"',
      'apos' => "'",
      'nbsp' => ' ',
      'ndash' => '–',
      'mdash' => '—',
      'hellip' => '…',
      'rsquo' => '’',
      'lsquo' => '‘',
      'rdquo' => '”',
      'ldquo' => '“',
      _ => m.group(0)!,
    };
  });
}
