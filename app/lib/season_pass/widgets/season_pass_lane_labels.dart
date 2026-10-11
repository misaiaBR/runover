import 'package:flutter/material.dart';

import '../gold.dart';
import '../trail_metrics.dart';

/// Rótulos das faixas, fixos à esquerda da trilha ("Grátis" em cima,
/// "Passe" embaixo).
///
/// Não rola com a trilha: a tela a coloca fora do scroll horizontal. As
/// alturas vêm de [TrailMetrics] para os rótulos alinharem com os cartões em
/// qualquer densidade de tela.
class SeasonPassLaneLabels extends StatelessWidget {
  const SeasonPassLaneLabels({super.key, required this.metrics});

  static const double width = 58;

  final TrailMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      child: Column(
        children: [
          SizedBox(
            height: metrics.cardSlotHeight,
            child: Center(
              child: Text(
                'Grátis',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 13 * metrics.scale,
                ),
              ),
            ),
          ),
          SizedBox(height: metrics.railHeight),
          SizedBox(
            height: metrics.cardSlotHeight,
            child: Center(
              child: Text(
                'Passe',
                style: TextStyle(
                  color: seasonPassGold,
                  fontSize: 13 * metrics.scale,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
