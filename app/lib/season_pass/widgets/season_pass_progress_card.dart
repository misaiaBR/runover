import 'package:flutter/material.dart';

import '../models.dart';

/// Cartão de progresso da temporada: nível atual, pontos até o próximo nível
/// e as fontes de pontos (corrida, território, meta da semana).
class SeasonPassProgressCard extends StatelessWidget {
  const SeasonPassProgressCard({super.key, required this.season});

  final Season season;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final value = (season.points / season.pointsForNext)
        .clamp(0.0, 1.0)
        .toDouble();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Nível ${season.currentLevel}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${season.points} / ${season.pointsForNext} pts',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: LinearProgressIndicator(
                value: value,
                minHeight: 10,
                backgroundColor: scheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(scheme.primary),
              ),
            ),
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
