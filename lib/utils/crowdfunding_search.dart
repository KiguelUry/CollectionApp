import 'package:url_launcher/url_launcher.dart';

import 'display_text.dart';

/// Recherche web Kickstarter / Gamefound (BGG ne fournit pas le lien direct).
Uri crowdfundingSearchUri(String title) {
  final q = Uri.encodeComponent(
    '${cleanDisplayText(title)} board game kickstarter gamefound',
  );
  return Uri.parse('https://www.google.com/search?q=$q');
}

Future<bool> launchCrowdfundingSearch(String title) async {
  final uri = crowdfundingSearchUri(title);
  if (!await canLaunchUrl(uri)) return false;
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
