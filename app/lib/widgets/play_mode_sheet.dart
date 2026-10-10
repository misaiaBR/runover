import 'package:flutter/material.dart';

/// Como jogar a Dominação: a mecânica escolhida antes de sair correndo.
enum PlayMode {
  /// Correr em qualquer lugar e fechar um laço (nasce um território, sem
  /// desafio).
  freeLoop,

  /// Escolher um spawn selvagem no mapa e correr até ele (bônus de pontos).
  huntWild,

  /// Escolher um território dominado e vencer a marca do dono (ritmo ou
  /// distância).
  challenge,
}

/// Abre o "Como quer jogar?" e devolve a mecânica escolhida via [onSelect].
Future<void> showPlayModeSheet(
  BuildContext context, {
  required ValueChanged<PlayMode> onSelect,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Text(
              'Como quer jogar?',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Escolha a mecânica antes de sair correndo.'),
          ),
          _PlayModeTile(
            icon: Icons.route_outlined,
            title: 'Laço livre',
            subtitle:
                'Corra em qualquer lugar e feche um laço: nasce um território '
                'seu. Sem desafio — pontos por área.',
            onTap: () {
              Navigator.of(sheetContext).pop();
              onSelect(PlayMode.freeLoop);
            },
          ),
          _PlayModeTile(
            icon: Icons.explore_outlined,
            title: 'Caçar selvagem',
            subtitle:
                'Spawns somem rápido e valem bônus: escolha um no mapa e '
                'corra até lá.',
            onTap: () {
              Navigator.of(sheetContext).pop();
              onSelect(PlayMode.huntWild);
            },
          ),
          _PlayModeTile(
            icon: Icons.emoji_events_outlined,
            title: 'Desafiar dono',
            subtitle:
                'Escolha um território dominado e vença a marca dele no '
                'ritmo ou na distância.',
            onTap: () {
              Navigator.of(sheetContext).pop();
              onSelect(PlayMode.challenge);
            },
          ),
          const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}

class _PlayModeTile extends StatelessWidget {
  const _PlayModeTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: '$title. $subtitle',
      excludeSemantics: true,
      child: ListTile(
        minVerticalPadding: 12,
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: scheme.primary),
        ),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
