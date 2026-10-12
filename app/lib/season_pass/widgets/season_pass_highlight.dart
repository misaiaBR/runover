import 'package:flutter/material.dart';

import '../../format.dart';
import '../../widgets/cosmetics.dart';
import '../../widgets/offer_row.dart';
import '../models.dart';
import '../palette.dart';
import 'season_pass_coin_stack.dart';

/// Painel de destaque da recompensa selecionada na trilha.
///
/// É onde a recompensa fica grande e legível — o cartão da trilha tem 92 px de
/// largura e não conta a história inteira. O painel também é o único lugar da
/// tela onde se resgata ou se ativa o passe: tocar um cartão só seleciona, para
/// um toque distraidado nunca gastar um resgate.
///
/// O botão muda com o estado da recompensa, e cada estado tem a sua verdade:
/// - resgatável: "Resgatar";
/// - requer passe: "Ativar passe" com o preço e a linha de que é só visual;
/// - bloqueado: a frase com os pontos que abrem o nível, sem botão;
/// - resgatado: o visto, sem botão.
class SeasonPassHighlightPanel extends StatelessWidget {
  const SeasonPassHighlightPanel({
    super.key,
    required this.level,
    required this.threshold,
    required this.lane,
    required this.reward,
    required this.state,
    required this.premiumPriceCoins,
    required this.onClaim,
    required this.onActivatePass,
  });

  final int level;

  /// Pontos acumulados que abrem o nível — a frase de "quando chega".
  final int threshold;
  final RewardLane lane;
  final Reward reward;
  final RewardState state;

  /// Preço do passe na temporada; 0 = o servidor não informou.
  final int premiumPriceCoins;
  final VoidCallback onClaim;
  final VoidCallback onActivatePass;

  bool get _needsPass => state == RewardState.needsPass;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        gradient: trailGradient(premium: lane == RewardLane.pass),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: trailAccent, width: 1.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: trailAccent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'RECOMPENSA DO NÍVEL $level',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.7,
                  color: trailAccentInk,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Center(child: _art()),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              _title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                height: 1.15,
                color: Colors.white,
              ),
            ),
          ),
          if (reward.itemName != null && reward.coins > 0) ...[
            const SizedBox(height: 2),
            Text(
              '${reward.subLabel} dracmas',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: trailAccent,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            _description,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 12),
          _action(),
          if (_needsPass) ...[
            const SizedBox(height: 8),
            const Text(
              'Só itens visuais: nada que dê vantagem no mapa ou no ranking.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, height: 1.3, color: Colors.white70),
            ),
          ],
          const SizedBox(height: 10),
          _sourcesButton(context),
        ],
      ),
    );
  }

  /// Nome grande: o cosmético manda, e a dracma acompanha quando é só moeda.
  String get _title {
    final itemName = reward.itemName;
    if (itemName != null) return itemName;
    if (reward.coins > 0) return '${reward.label} dracmas';
    return reward.title;
  }

  /// Descrição do que a recompensa entrega. O cosmético usa a mesma frase da
  /// loja ([cosmeticHint]); a pilha de dracmas diz onde ela é gasta.
  String get _description {
    final item = reward.item;
    if (item != null) return cosmeticHint(item.category);
    if (reward.coins > 0) return 'Dracmas para gastar no Mercado.';
    return 'Recompensa exclusiva desta temporada.';
  }

  /// Prévia da recompensa: o item real, a pilha de dracmas, ou o ícone que o
  /// servidor deu quando o catálogo não conhece o item.
  Widget _art() {
    final child = switch (reward.item) {
      final item when item != null => ShopPreview(item: item, scale: 1.05),
      _ when reward.coins > 0 => SeasonPassCoinStack(
        coins: reward.coins,
        size: 74,
      ),
      _ => Icon(reward.icon, size: 48, color: trailAccent),
    };
    final dim = state == RewardState.locked || state == RewardState.claimed;
    return Opacity(
      opacity: dim ? 0.72 : 1,
      child: Container(
        height: 96,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Center(child: child),
      ),
    );
  }

  /// A linha de ação do estado — só existe botão quando há o que fazer.
  Widget _action() {
    return switch (state) {
      RewardState.claimable => _goldButton('Resgatar', onClaim),
      RewardState.needsPass => _goldButton(
        premiumPriceCoins > 0
            ? 'Ativar passe · ${formatPoints(premiumPriceCoins)} dracmas'
            : 'Ativar passe',
        onActivatePass,
      ),
      RewardState.claimed => _line(
        Icons.check_circle,
        'Já resgatada nesta temporada.',
      ),
      RewardState.locked => _line(
        Icons.hourglass_empty,
        'Nível $level abre com ${formatPoints(threshold)} pts.',
      ),
    };
  }

  Widget _goldButton(String label, VoidCallback onPressed) {
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: trailAccent,
        foregroundColor: trailAccentInk,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
      ),
      onPressed: onPressed,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(label, maxLines: 1),
      ),
    );
  }

  Widget _line(IconData icon, String text) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 17, color: Colors.white70),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: Colors.white70,
            ),
          ),
        ),
      ],
    );
  }

  Widget _sourcesButton(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: BorderSide(color: Colors.white.withValues(alpha: 0.55)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
      ),
      onPressed: () => showSeasonPointsGuide(context),
      icon: const Icon(Icons.help_outline, size: 18),
      label: const Text('Como ganhar pontos'),
    );
  }
}

/// Fila de "como ganhar pontos" do painel de destaque.
///
/// As três fontes são as que o servidor soma para a temporada, e o rodapé é a
/// regra da temporada: ela vira no dia 1 e o resgate não feito expira com ela.
void showSeasonPointsGuide(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Como ganhar pontos',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: Theme.of(sheetContext).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'A temporada conta os pontos que você já faz no jogo:',
              style: TextStyle(
                fontSize: 12.5,
                color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            for (final source in _sources)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Icon(
                      source.icon,
                      size: 20,
                      color: Theme.of(sheetContext).colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        source.label,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Text(
              'Cada nó da trilha mostra os pontos acumulados que abrem aquele '
              'nível. A temporada vira no dia 1 e o resgate não feito expira '
              'junto com ela.',
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _PointSource {
  const _PointSource(this.label, this.icon);

  final String label;
  final IconData icon;
}

const _sources = [
  _PointSource('Corrida concluída', Icons.directions_run),
  _PointSource('Território conquistado', Icons.flag),
  _PointSource('Meta da semana', Icons.calendar_month),
];
