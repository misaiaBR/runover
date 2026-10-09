import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';

/// Peça comum do mural, da vitrine de nível e da tela de insígnias: o
/// servidor manda uma chave de ícone, só o app sabe desenhá-la.
IconData badgeIcon(String key) {
  return switch (key) {
    'run' => Icons.directions_run,
    'flag' => Icons.flag_outlined,
    'route' => Icons.route_outlined,
    'team' => Icons.groups_outlined,
    'level' => Icons.workspace_premium_outlined,
    _ => Icons.verified_outlined,
  };
}

/// "6 de jun. de 2026" a partir da data em que o servidor registrou o ganho.
String badgeDateLabel(DateTime date) {
  const months = [
    'jan.',
    'fev.',
    'mar.',
    'abr.',
    'mai.',
    'jun.',
    'jul.',
    'ago.',
    'set.',
    'out.',
    'nov.',
    'dez.',
  ];
  return '${date.day} de ${months[date.month - 1]} de ${date.year}';
}

/// "3 de 10" / "5,2 de 10 km" — o progresso da regra ainda não cumprida.
String badgeProgressLabel(Insignia badge) {
  final current = badge.progress > badge.threshold
      ? badge.threshold
      : badge.progress;
  return '${_trim(current)} de ${_trim(badge.threshold)}';
}

String _trim(double value) {
  return value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1).replaceAll('.', ',');
}

/// Insígnia como chip: ganha em destaque, bloqueada apagada.
class BadgeChip extends StatelessWidget {
  const BadgeChip({super.key, required this.badge, this.showDate = false});

  final Insignia badge;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = badge.earned
        ? RunoverColors.territory
        : scheme.onSurfaceVariant;
    return Chip(
      backgroundColor: badge.earned
          ? RunoverColors.territory.withValues(alpha: .08)
          : scheme.surfaceContainerHighest,
      avatar: Icon(
        badge.earned ? badgeIcon(badge.icon) : Icons.lock_outline,
        size: 18,
        color: color,
      ),
      label: Text(
        showDate && badge.earnedAt != null
            ? '${badge.name} · ${badgeDateLabel(badge.earnedAt!)}'
            : badge.name,
      ),
    );
  }
}
