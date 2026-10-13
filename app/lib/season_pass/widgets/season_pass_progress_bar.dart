import 'package:flutter/material.dart';

import '../../format.dart';
import '../../widgets/runover_ui.dart';
import '../models.dart';
import '../palette.dart';

/// Barra de progresso do nível atual, logo abaixo do cabeçalho da temporada.
///
/// Os dois números são acumulados (como o servidor os soma), mas a barra mede
/// só o trecho do nível atual — é ela que responde "quanto falta para o próximo
/// cartão acender".
///
/// A superfície e as tintas vêm do tema: a barra veste o painel do passe (escuro
/// ou claro) e o trilho vazio usa `Pal.track`, como as outras barras do app. Só
/// o verde do preenchimento e o dourado do nível são fixos — e o dourado passa
/// por `legibleInk`, que o queima no tema claro. As fontes de pontos não moram
/// mais aqui, elas estão no "Como ganhar pontos" do painel de destaque.
class SeasonPassProgressBar extends StatelessWidget {
  const SeasonPassProgressBar({super.key, required this.season});

  final Season season;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: pal.panel,
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
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: legibleInk(trailAccent, context),
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
                    backgroundColor: pal.track,
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
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: pal.heading,
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
            style: TextStyle(fontSize: 11.5, color: pal.muted),
          ),
        ],
      ),
    );
  }
}
