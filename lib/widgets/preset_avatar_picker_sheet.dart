import 'package:flutter/material.dart';

import '../utils/preset_avatars.dart';
import 'preset_avatar_image.dart';

Future<String?> showPresetAvatarPickerSheet(BuildContext context) async {
  final assets = await discoverPresetAvatarAssets();
  if (!context.mounted) return null;

  if (assets.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Aucun avatar trouvé. Ajoute des .svg ou .png dans assets/avatars/',
        ),
      ),
    );
    return null;
  }

  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Text(
                'Choisir un avatar',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            Expanded(
              child: GridView.builder(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: assets.length,
                itemBuilder: (context, index) {
                  final path = assets[index];
                  return InkWell(
                    onTap: () => Navigator.pop(ctx, path),
                    borderRadius: BorderRadius.circular(12),
                    child: Column(
                      children: [
                        Expanded(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: PresetAvatarImage(assetPath: path),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          presetAvatarLabel(path),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    ),
  );
}
