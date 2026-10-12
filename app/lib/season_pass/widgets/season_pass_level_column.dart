import 'package:flutter/material.dart';

import '../../format.dart';
import '../palette.dart';
import '../trail_metrics.dart';
import 'season_pass_hex_node.dart';

/// Coluna de um nível da trilha: cartão grátis, nó hexagonal com os pontos que
/// abrem o nível e cartão do passe.
///
/// As medidas vêm de [TrailMetrics] — a coluna de rótulos e a tela usam as
/// mesmas para alinhar as faixas em qualquer densidade de tela.
class SeasonPassLevelColumn extends StatelessWidget {
  const SeasonPassLevelColumn({
    super.key,
    required this.level,
    required this.threshold,
    required this.currentLevel,
    required this.metrics,
    required this.freeCard,
    required this.passCard,
  });

  final int level;

  /// Pontos acumulados que abrem este nível — o número do nó.
  final int threshold;
  final int currentLevel;
  final TrailMetrics metrics;
  final Widget freeCard;
  final Widget passCard;

  @override
  Widget build(BuildContext context) {
    final reached = level <= currentLevel;
    final done = level < currentLevel;
    final current = level == currentLevel;
    final nodeWidth = 54 * metrics.scale;
    final nodeHeight = 32 * metrics.scale;
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
                // Linha da trilha: verde-água até o nível atual, trilho
                // apagado depois.
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 4,
                        color: reached ? trailReached : trailNodeIdle,
                      ),
                    ),
                    Expanded(
                      child: Container(
                        height: 4,
                        color: done ? trailReached : trailNodeIdle,
                      ),
                    ),
                  ],
                ),
                if (current)
                  // Halo no formato do próprio nó: marca onde o jogador está
                  // sem precisar de texto nem de animação.
                  _Hexagon(
                    color: trailAccent.withValues(alpha: 0.35),
                    width: nodeWidth + 12 * metrics.scale,
                    height: nodeHeight + 10 * metrics.scale,
                    child: const SizedBox.shrink(),
                  ),
                _Hexagon(
                  color: current
                      ? trailAccent
                      : (reached ? trailReached : trailNodeIdle),
                  width: nodeWidth,
                  height: nodeHeight,
                  child: Text(
                    formatPoints(threshold),
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 10.5 * metrics.scale,
                      fontWeight: FontWeight.w800,
                      color: current
                          ? trailAccentInk
                          : (reached
                                ? trailReachedInk
                                : trailNodeInk),
                    ),
                  ),
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

/// Hexágono achatado (mais largo que alto) para o nó da trilha: é a forma do
/// [SeasonPassHexClipper], com a altura do trilho.
class _Hexagon extends StatelessWidget {
  const _Hexagon({
    required this.color,
    required this.width,
    required this.height,
    required this.child,
  });

  final Color color;
  final double width;
  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: const SeasonPassHexClipper(),
      child: Container(
        width: width,
        height: height,
        color: color,
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}
