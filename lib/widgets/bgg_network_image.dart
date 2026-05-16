import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Images BGG (cf.geekdo-images.com) : sur le web, Flutter charge
/// les octets via XHR et échoue sans CORS (statusCode: 0).
/// [WebHtmlElementStrategy.prefer] utilise une balise &lt;img&gt; HTML,
/// ce que le navigateur autorise pour l'affichage.
class BggNetworkImage extends StatelessWidget {
  final String url;
  final BoxFit fit;

  const BggNetworkImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      fit: fit,
      webHtmlElementStrategy: kIsWeb
          ? WebHtmlElementStrategy.prefer
          : WebHtmlElementStrategy.never,
      errorBuilder: (context, error, stackTrace) => _placeholder(),
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return _placeholder(
          child: Center(
            child: CircularProgressIndicator(
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded /
                      loadingProgress.expectedTotalBytes!
                  : null,
            ),
          ),
        );
      },
    );
  }

  Widget _placeholder({Widget? child}) {
    return Container(
      color: Colors.grey.shade200,
      child: child ??
          const Center(
            child: Icon(Icons.casino, color: Colors.grey, size: 40),
          ),
    );
  }
}
