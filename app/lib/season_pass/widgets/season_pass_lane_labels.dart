import 'package:flutter/material.dart';

import '../gold.dart';
import 'season_pass_level_column.dart';

/// Rótulos das faixas, fixos à esquerda da trilha ("Grátis" em cima,
/// "Passe" embaixo).
///
/// Não rola com a trilha: a tela a coloca fora do scroll horizontal. As
/// alturas vêm de [SeasonPassLevelColumn] para os rótulos alinharem com as
/// faixas em qualquer densidade de tela.
class SeasonPassLaneLabels extends StatelessWidget {
  const SeasonPassLaneLabels({super.key});

  static const double width = 58;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      child: Column(
        children: [
          SizedBox(
            height: SeasonPassLevelColumn.cardSlotHeight,
            child: Center(
              child: Text(
                'Grátis',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          ),
          const SizedBox(height: SeasonPassLevelColumn.railHeight),
          SizedBox(
            height: SeasonPassLevelColumn.cardSlotHeight,
            child: const Center(
              child: Text(
                'Passe',
                style: TextStyle(color: seasonPassGold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
