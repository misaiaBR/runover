import 'package:flutter/material.dart';

import '../../format.dart';
import '../models.dart';
import '../palette.dart';

/// Barra de progresso do nível atual, logo abaixo do cabeçalho da temporada.
///
/// Os dois números são acumulados (como o servidor os soma), mas a barra mede
/// só o trecho do nível atual — é ela que responde "quanto falta para o próximo
/// cartão acender".
///
/// O fundo é o roxo da trilha: a barra fica do lado das faixas coloridas e
/// precisa ler igual nelas, no tema claro e no escuro. As fontes de pontos não
/// moram mais aqui, elas estão no "Como ganhar pontos" do painel de destaque.
class SeasonPassProgressBar extends StatelessWidget {
  const SeasonPassProgressBar({super.key, required this.season});

  final Season season;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: trailBoard,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Nível ${season.currentLevel}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: trailAccent,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: season.levelProgress,
                    minHeight: 12,
                    backgroundColor: trailNodeIdle,
                    valueColor: AlwaysStoppedAnimation(trailReached),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${formatPoints(season.points)} / '
                    '${formatPoints(season.pointsForNext)} pts',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            season.pointsToNextLevel > 0
                ? 'Faltam ${formatPoints(season.pointsToNextLevel)} pts para o '
                      'nível ${season.currentLevel + 1}'
                : 'Trilha completa: todos os níveis desta temporada já abriram.',
            style: const TextStyle(fontSize: 11.5, color: Colors.white70),
          ),
        ],
      ),
    );
  }
}
