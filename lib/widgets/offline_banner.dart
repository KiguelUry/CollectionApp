import 'package:flutter/material.dart';

import '../services/offline_mode.dart';

/// Bandeau discret « Mode hors-ligne » sous l'AppBar / en haut du Scaffold.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: OfflineMode.instance,
      builder: (context, _) {
        if (!OfflineMode.instance.active) return const SizedBox.shrink();
        return Material(
          color: const Color(0xFF311B92),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.wifi_off_rounded, size: 16, color: Colors.white),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Mode hors-ligne — consultation locale',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.1,
                        height: 1.15,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => OfflineMode.instance.setOnline(),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('OK'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
