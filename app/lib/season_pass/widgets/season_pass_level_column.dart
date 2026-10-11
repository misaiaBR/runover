import 'package:flutter/material.dart';

import '../trail_metrics.dart';
import 'season_pass_hex_node.dart';

/// Coluna de um nível da trilha: cartão grátis, conector com o nó hexagonal
/// numerado e cartão do passe.
///
/// As medidas vêm de [TrailMetrics] — a coluna de rótulos e a tela usam as
/// mesmas para alinhar as faixas em qualquer densidade de tela.
class SeasonPassLevelColumn extends StatelessWidget {
  const SeasonPassLevelColumn({
    super.key,
    required this.level,
    required this.currentLevel,
    required this.metrics,
    required this.freeCard,
    required this.passCard,
  });

  final int level;
  final int currentLevel;
  final TrailMetrics metrics;
  final Widget freeCard;
  final Widget passCard;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reached = level <= currentLevel;
    final done = level < currentLevel;
    final current = level == currentLevel;
    final track = scheme.surfaceContainerHighest;
    final nodeSize = 32 * metrics.scale;
    return SizedBox(
      width: metrics.cardWidth,
      child: Column(
        children: [
          SizedBox(
            height: metrics.cardSlotHeight,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: freeCard,
              ),
            ),
          ),
          SizedBox(
            height: metrics.railHeight,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Linha da trilha: cor secundária até o nível atual, trilho
                // apagado depois.
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 4,
                        color: reached ? scheme.secondary : track,
                      ),
                    ),
                    Expanded(
                      child: Container(
                        height: 4,
                        color: done ? scheme.secondary : track,
                      ),
                    ),
                  ],
                ),
                if (current)
                  // Halo no formato do próprio nó: marca onde o jogador está
                  // sem precisar de texto nem de animação.
                  SeasonPassHexNode(
                    label: const SizedBox.shrink(),
                    color: scheme.primary.withValues(alpha: 0.3),
                    size: nodeSize + 10 * metrics.scale,
                  ),
                SeasonPassHexNode(
                  label: Text(
                    '$level',
                    style: TextStyle(
                      fontSize: 13 * metrics.scale,
                      fontWeight: FontWeight.w600,
                      color: reached
                          ? scheme.onPrimary
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                  color: done
                      ? scheme.secondary
                      : (reached ? scheme.primary : track),
                  size: nodeSize,
                ),
              ],
            ),
          ),
          SizedBox(
            height: metrics.cardSlotHeight,
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: passCard,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
