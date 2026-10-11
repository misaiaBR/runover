import 'package:flutter/material.dart';

import '../models.dart';

/// Cartão de progresso da temporada: nível atual, pontos acumulados até o
/// próximo nível e as fontes de pontos (corrida, território, meta da semana).
///
/// Os números são acumulados (como no card de progresso da equipe), mas a
/// barra e a linha "faltam" medem só o trecho do nível atual.
class SeasonPassProgressCard extends StatelessWidget {
  const SeasonPassProgressCard({super.key, required this.season});

  final Season season;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Os dois números dividem a linha com o banner do passe no
                // layout estreito: cada um encolhe a fonte em vez de
                // transbordar o cartão.
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Nível ${season.currentLevel}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      '${season.points} / ${season.pointsForNext} pts',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: LinearProgressIndicator(
                value: season.levelProgress,
                minHeight: 10,
                backgroundColor: scheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(scheme.primary),
              ),
            ),
            if (season.pointsToNextLevel > 0) ...[
              const SizedBox(height: 8),
              Text(
                'Faltam ${season.pointsToNextLevel} pts para o nível '
                '${season.currentLevel + 1}',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _InfoChip(
                  'Corrida concluída',
                  background: scheme.surfaceContainerHighest,
                ),
                _InfoChip(
                  'Território conquistado',
                  background: scheme.surfaceContainerHighest,
                ),
                _InfoChip(
                  'Meta da semana',
                  background: scheme.surfaceContainerHighest,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip(this.text, {required this.background});

  final String text;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12)),
    );
  }
}
