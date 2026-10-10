import 'package:flutter/material.dart';

/// Os quatro estados de presença. O servidor guarda a chave e decide o que ela
/// muda (online da equipe, notificações); o app dá nome, cor e explicação.
class PresenceState {
  const PresenceState({
    required this.key,
    required this.label,
    required this.description,
    required this.color,
  });

  final String key;
  final String label;
  final String description;
  final Color color;
}

const presenceDisponivel = PresenceState(
  key: 'disponivel',
  label: 'Disponível',
  description: 'Todos veem que você está por aqui.',
  color: Color(0xFF2ECC71),
);
const presenceAusente = PresenceState(
  key: 'ausente',
  label: 'Ausente',
  description: 'Continua aparecendo como online, mas a resposta demora.',
  color: Color(0xFFF5A524),
);
const presenceNaoIncomodar = PresenceState(
  key: 'nao_incomodar',
  label: 'Não perturbe',
  description: 'Só o risco de perda e os pedidos da equipe chegam até você.',
  color: Color(0xFFE5484D),
);
const presenceInvisivel = PresenceState(
  key: 'invisivel',
  label: 'Invisível',
  description: 'Você some da contagem de online da equipe.',
  color: Color(0xFF8A94A6),
);

/// Ordem da lista do bottom sheet.
const presenceStates = <PresenceState>[
  presenceDisponivel,
  presenceAusente,
  presenceNaoIncomodar,
  presenceInvisivel,
];

/// A chave desconhecida vira "disponível": o pill nunca mostra um estado que
/// o servidor não conhece.
PresenceState presenceOf(String? key) => presenceStates.firstWhere(
  (s) => s.key == key,
  orElse: () => presenceDisponivel,
);

/// Ponto verde do avatar: só aparece com sinal vivo, e nunca para quem é
/// invisível — o servidor já desconta esse caso, o app não inventa o resto.
class PresenceDot extends StatelessWidget {
  const PresenceDot({super.key, required this.visible, this.size = 14});

  final bool visible;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: presenceDisponivel.color,
        border: Border.all(
          color: Theme.of(context).colorScheme.surface,
          width: 2,
        ),
      ),
    );
  }
}

/// O pill do perfil: ● Disponível ⌄. Tocar abre a escolha dos quatro estados.
class PresencePill extends StatelessWidget {
  const PresencePill({
    super.key,
    required this.state,
    required this.onTap,
  });

  final PresenceState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: state.color,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              state.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: state.color,
              ),
            ),
            const Icon(Icons.expand_more, size: 16),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet de escolha: nome, explicação do que o estado faz e o marca do
/// atual. Devolve a chave escolhida, ou null se o corredor fechar sem mudar.
Future<String?> showPresencePicker(BuildContext context, String currentKey) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Text(
              'Mostrar-me como',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
          for (final state in presenceStates)
            ListTile(
              title: Text(state.label),
              subtitle: Text(state.description),
              leading: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: state.color,
                ),
              ),
              trailing: state.key == currentKey
                  ? Icon(Icons.check, color: presenceDisponivel.color)
                  : null,
              onTap: () => Navigator.of(sheetContext).pop(state.key),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
