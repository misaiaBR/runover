import 'package:flutter/material.dart';

import 'season_pass_hex_node.dart';

/// Coluna de um nível da trilha: cartão grátis, conector com o nó hexagonal
/// numerado e cartão do passe.
///
/// As medidas ficam aqui para a coluna de rótulos (`SeasonPassLaneLabels`,
/// fora da rolagem horizontal) alinhar com estes mesmos valores na etapa da
/// tela — sem número mágico duplicado.
class SeasonPassLevelColumn extends StatelessWidget {
  const SeasonPassLevelColumn({
    super.key,
    required this.level,
    required this.currentLevel,
    required this.freeCard,
    required this.passCard,
  });

  /// Largura de cada coluna da trilha horizontal.
  static const double cardWidth = 96;

  /// Altura reservada a cada faixa (cabe o cartão de 112 px com respiro).
  static const double cardSlotHeight = 120;

  /// Altura do conector central (linha da trilha + nó do nível).
  static const double railHeight = 48;

  final int level;
  final int currentLevel;
  final Widget freeCard;
  final Widget passCard;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reached = level <= currentLevel;
    final done = level < currentLevel;
    final track = scheme.surfaceContainerHighest;
    return SizedBox(
      width: cardWidth,
      child: Column(
        children: [
          SizedBox(
            height: cardSlotHeight,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: freeCard,
              ),
            ),
          ),
          SizedBox(
            height: railHeight,
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
                SeasonPassHexNode(
                  label: Text(
                    '$level',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: reached
                          ? scheme.onPrimary
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                  color: done
                      ? scheme.secondary
                      : (reached ? scheme.primary : track),
                  size: 32,
                ),
              ],
            ),
          ),
          SizedBox(
            height: cardSlotHeight,
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: passCard,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
