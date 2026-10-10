import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/centered_content.dart';
import '../widgets/insignia.dart';
import '../widgets/profile_activity.dart';
import 'app_footer.dart';

/// Os três modos de ver o catálogo: agrupado pelas categorias do servidor,
/// ordenado pelo que está mais perto de sair, ou só o que já foi ganho.
enum BadgesView { grouped, closest, earned }

/// Insígnias: as conquistas que o mural publica, ganhas e por ganhar.
class BadgesScreen extends StatefulWidget {
  const BadgesScreen({super.key});

  @override
  State<BadgesScreen> createState() => _BadgesScreenState();
}

class _BadgesScreenState extends State<BadgesScreen> {
  Future<List<Insignia>>? _badges;
  BadgesView _view = BadgesView.grouped;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _badges ??= context.read<AppState>().api.getBadges();
  }

  void _retry() {
    final next = context.read<AppState>().api.getBadges();
    setState(() {
      _badges = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Insígnias')),
      body: FutureBuilder<List<Insignia>>(
        future: _badges,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || snapshot.data == null) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Não foi possível carregar suas insígnias.'),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _retry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Tentar novamente'),
                  ),
                ],
              ),
            );
          }
          final badges = snapshot.data!;
          final earned = badges.where((b) => b.earned).toList();
          final locked = _byCloseness(badges);
          final next = locked.isEmpty ? null : locked.first;
          return CenteredContent(
            maxWidth: 720,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              children: [
                _SummaryCard(earned: earned.length, total: badges.length),
                // A mais perto de sair só existe enquanto há o que alcançar.
                if (next != null) ...[
                  const SizedBox(height: 16),
                  _NextBadgeCard(badge: next),
                ],
                const SizedBox(height: 16),
                _ViewPicker(
                  view: _view,
                  onSelect: (view) => setState(() => _view = view),
                ),
                const SizedBox(height: 20),
                ..._content(badges, locked, earned),
                const AppFooter(),
              ],
            ),
          );
        },
      ),
    );
  }

  /// O corpo muda com o chip: categorias, mais próximas ou só as ganhas.
  List<Widget> _content(
    List<Insignia> badges,
    List<Insignia> locked,
    List<Insignia> earned,
  ) {
    switch (_view) {
      case BadgesView.grouped:
        return [
          for (final group in _groups(badges)) ...[
            _CategoryHeader(group: group),
            const SizedBox(height: 12),
            BadgeGrid(badges: group.badges),
            const SizedBox(height: 24),
          ],
        ];
      case BadgesView.closest:
        if (locked.isEmpty) {
          return const [_EmptyNote('Nada bloqueado: você já ganhou todas.')];
        }
        return [BadgeGrid(badges: locked)];
      case BadgesView.earned:
        if (earned.isEmpty) {
          return const [_EmptyNote('Você ainda não ganhou nenhuma insígnia.')];
        }
        return [BadgeGrid(badges: earned, earnedLabel: _earnedWithDate)];
    }
  }
}

/// Na aba das ganhas, o card diz quando cada uma entrou no mural.
String _earnedWithDate(Insignia badge) {
  final date = badge.earnedAt;
  return date == null ? 'Ganha' : 'Ganha em ${badgeDateLabel(date)}';
}

/// Bloco de uma categoria na resposta, na ordem em que o servidor o mandou.
class _BadgeGroup {
  const _BadgeGroup({required this.key, required this.badges});

  final String key;
  final List<Insignia> badges;

  int get earned => badges.where((b) => b.earned).length;
}

/// Agrupa pelas categorias da resposta, sem reordenar nada: a ordem do
/// catálogo é do servidor.
List<_BadgeGroup> _groups(List<Insignia> badges) {
  final order = <String>[];
  final byKey = <String, List<Insignia>>{};
  for (final badge in badges) {
    if (!byKey.containsKey(badge.category)) {
      order.add(badge.category);
      byKey[badge.category] = [];
    }
    byKey[badge.category]!.add(badge);
  }
  return [for (final key in order) _BadgeGroup(key: key, badges: byKey[key]!)];
}

/// As bloqueadas, da mais perto de sair para a mais longe.
///
/// Empate de proporção vai para o limiar menor: faltar 1 de 5 está mais ao
/// alcance que faltar 5 de 25. Persistindo o empate, decide o id — a ordem da
/// lista não pode depender de como a ordenação interna varreu o vetor.
List<Insignia> _byCloseness(List<Insignia> badges) {
  final locked = badges.where((b) => !b.earned).toList();
  locked.sort((a, b) {
    final byRatio = badgeRatio(b).compareTo(badgeRatio(a));
    if (byRatio != 0) return byRatio;
    final byThreshold = a.threshold.compareTo(b.threshold);
    if (byThreshold != 0) return byThreshold;
    return a.id.compareTo(b.id);
  });
  return locked;
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.earned, required this.total});

  final int earned;
  final int total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ProfileCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Ganhas · $earned de $total',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          // O aviso vai embaixo do placar, e não ao lado dele: na largura do
          // celular os dois não cabem numa linha, e em texto grande a linha
          // virava uma coluna apertada.
          Text(
            'O mural do perfil mostra as que você ganhou',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          BadgeProgressBar(
            ratio: total == 0 ? 0 : earned / total,
            color: RunoverColors.route,
            height: 7,
          ),
        ],
      ),
    );
  }
}

/// A insígnia mais perto de sair, em card grande logo abaixo do resumo.
class _NextBadgeCard extends StatelessWidget {
  const _NextBadgeCard({required this.badge});

  final Insignia badge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = badgeCategoryStyle(badge.category);
    return ProfileCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BadgeEmblem(
            icon: badgeIcon(badge.icon),
            color: style.color,
            size: 56,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  badge.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  badge.description,
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                BadgeProgressBar(ratio: badgeRatio(badge), color: style.color),
                const SizedBox(height: 6),
                Text(
                  badgeProgressLabel(badge),
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                _CategoryChip(label: 'Bloqueada · ${style.label}'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Título da categoria com a cor dela e o placar de ganhas.
class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader({required this.group});

  final _BadgeGroup group;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = badgeCategoryStyle(group.key);
    return Row(
      children: [
        Icon(style.icon, size: 18, color: style.color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            style.label,
            style: TextStyle(
              color: style.color,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Text(
          '${group.earned} de ${group.badges.length} ganhas',
          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// Os três modos, nos mesmos pills arredondados usados pelas abas do ranking.
class _ViewPicker extends StatelessWidget {
  const _ViewPicker({required this.view, required this.onSelect});

  final BadgesView view;
  final ValueChanged<BadgesView> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final option in BadgesView.values)
          _ViewPill(
            label: switch (option) {
              BadgesView.grouped => 'Por categoria',
              BadgesView.closest => 'Mais próximas',
              BadgesView.earned => 'Ganhas',
            },
            selected: option == view,
            onTap: () => onSelect(option),
          ),
      ],
    );
  }
}

class _ViewPill extends StatelessWidget {
  const _ViewPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? scheme.primary.withValues(alpha: .14)
                : scheme.surfaceContainerHighest,
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: accent,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.onSurfaceVariant.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Text(text, style: TextStyle(color: scheme.onSurfaceVariant)),
    );
  }
}
