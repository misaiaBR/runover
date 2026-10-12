import 'package:flutter/material.dart';

import '../../widgets/offer_row.dart';
import '../models.dart';
import '../palette.dart';
import '../trail_metrics.dart';
import 'season_pass_coin_stack.dart';

/// Cartão de uma recompensa da trilha: faixa grátis (laranja, em cima) e faixa
/// do passe (violeta, embaixo).
///
/// A linguagem visual diz o estado sem cadeado gigante — com 30 níveis, uma
/// fileira de cadeados vira ruído:
/// - **bloqueado**: véu escuro sobre a faixa, arte esmaecida e selo de lacre;
/// - **requer passe**: faixa violeta com contorno dourado e selo do passe;
/// - **resgatável**: borda acesa, brilho esverdeado e etiqueta "Resgatar";
/// - **resgatado**: faixa mais escura, selo de visto e "Resgatado".
///
/// Tocar o cartão **seleciona** a recompensa: quem resgata é o botão do painel
/// de destaque, que mostra a prévia grande do item. O cartão não faz as duas
/// coisas ao mesmo tempo — um toque que escolhesse e gastasse pontos ao mesmo
/// tempo não daria para desfazer.
///
/// O cartão inteiro é a área de toque e o nome do item nunca é cortado com
/// reticências: quando falta espaço, o bloco de texto encolhe junto.
class SeasonPassRewardCard extends StatelessWidget {
  const SeasonPassRewardCard({
    super.key,
    required this.reward,
    required this.state,
    required this.level,
    required this.premium,
    required this.metrics,
    required this.selected,
    required this.onSelect,
  });

  final Reward reward;
  final RewardState state;
  final int level;
  final bool premium;

  /// Medidas da trilha (tamanho do cartão e escala da tipografia).
  final TrailMetrics metrics;

  /// O cartão da recompensa aberta no painel de destaque.
  final bool selected;

  final VoidCallback onSelect;

  static const double _radius = 12;

  bool get _sealed => state == RewardState.locked;

  bool get _claimable => state == RewardState.claimable;

  @override
  Widget build(BuildContext context) {
    final status = switch (state) {
      RewardState.claimed => 'Resgatado',
      RewardState.claimable => 'Resgatar',
      // O cartão bloqueado já diz o nível no topo e o nó da trilha diz os
      // pontos que abrem aquele nível: uma terceira etiqueta só repetiria.
      RewardState.locked => '',
      RewardState.needsPass => 'Requer passe',
    };
    return Semantics(
      button: true,
      label:
          '${reward.title}, '
          '${state == RewardState.locked ? 'bloqueada' : status}, '
          '${selected ? 'selecionada' : 'tocar para ver a recompensa'}',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(_radius),
          onTap: onSelect,
          child: Container(
            width: metrics.cardInnerWidth,
            height: metrics.cardHeight,
            decoration: BoxDecoration(
              gradient: trailGradient(premium: premium),
              borderRadius: BorderRadius.circular(_radius),
              border: Border.all(
                color: selected
                    ? Colors.white
                    : (_claimable ? trailReached : Colors.white.withValues(alpha: .22)),
                width: selected ? 3 : 1,
              ),
              boxShadow: _claimable
                  ? [
                      BoxShadow(
                        color: trailReached.withValues(alpha: 0.55),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Stack(
              children: [
                Positioned.fill(child: _content(context, status)),
                if (_sealed)
                  // O véu é o "lacre": a faixa continua colorida por baixo,
                  // então dá para ver o que vem — só não está liberado.
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.46),
                        borderRadius: BorderRadius.circular(_radius),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, String status) {
    final s = metrics.scale;
    return Padding(
      padding: EdgeInsets.fromLTRB(4, 6 * s, 4, 5 * s),
      child: Column(
        children: [
          Text(
            'NÍVEL $level',
            maxLines: 1,
            style: TextStyle(
              fontSize: 9.5 * s,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6 * s,
              height: 1.1,
              color: Colors.white.withValues(alpha: 0.92),
              shadows: const [Shadow(color: Colors.black26, offset: Offset(0, 1))],
            ),
          ),
          SizedBox(height: 2 * s),
          // Ocupa a sobra e encolhe o texto quando não cabe: o nome do item
          // nunca termina em "…".
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: metrics.cardInnerWidth - 8,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      reward.label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      style: TextStyle(
                        fontSize: 11.5 * s,
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                        color: Colors.white,
                        shadows: const [
                          Shadow(color: Colors.black38, offset: Offset(0, 1)),
                        ],
                      ),
                    ),
                    if (reward.subLabel != null)
                      Text(
                        reward.subLabel!,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 10 * s,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                          color: trailAccent,
                        ),
                      ),
                    SizedBox(height: 2 * s),
                    _art(metrics),
                  ],
                ),
              ),
            ),
          ),
          _StatusTag(
            text: status,
            state: state,
            fontSize: 10 * s,
            maxWidth: metrics.cardInnerWidth - 6,
          ),
        ],
      ),
    );
  }

  /// Arte da recompensa: dracmas em pilha, cosmético na escala pequena do
  /// cartão, e o ícone do servidor quando o catálogo não conhece o item.
  Widget _art(TrailMetrics metrics) {
    final s = metrics.scale;
    final opacity = _sealed || state == RewardState.claimed ? 0.72 : 1.0;
    final child = switch (reward.item) {
      final item when item != null => ShopPreview(item: item, scale: 0.52 * s),
      _ when reward.coins > 0 => SeasonPassCoinStack(
        coins: reward.coins,
        size: 58 * s,
      ),
      _ => Icon(reward.icon, size: 34 * s, color: Colors.white),
    };
    return Opacity(opacity: opacity, child: child);
  }
}

/// Etiqueta de estado na base do cartão.
///
/// Uma linha só, com o texto reduzido quando não cabe: "Requer passe" é o
/// rótulo de um botão, e cortado ele deixa de ser uma instrução.
class _StatusTag extends StatelessWidget {
  const _StatusTag({
    required this.text,
    required this.state,
    required this.fontSize,
    required this.maxWidth,
  });

  final String text;
  final RewardState state;
  final double fontSize;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) {
      // Reserva a mesma altura das outras etiquetas: as faixas alinham nó por
      // nó, cartão por cartão.
      return SizedBox(height: fontSize * 1.5);
    }
    final style = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      height: 1.15,
      letterSpacing: 0.4,
      color: switch (state) {
        RewardState.claimable => trailReachedInk,
        RewardState.needsPass => trailAccent,
        RewardState.claimed => Colors.white,
        RewardState.locked => Colors.white.withValues(alpha: 0.7),
      },
    );
    final label = FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        state == RewardState.claimed ? '✓ $text' : text,
        maxLines: 1,
        style: style,
      ),
    );
    final filled = state == RewardState.claimable;
    final outlined = state == RewardState.needsPass;
    if (!filled && !outlined) {
      return SizedBox(height: fontSize * 1.5, child: Center(child: label));
    }
    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2 * (fontSize / 10)),
      decoration: BoxDecoration(
        color: filled ? trailReached : null,
        border: outlined ? Border.all(color: trailAccent, width: 1.2) : null,
        borderRadius: BorderRadius.circular(9),
      ),
      child: label,
    );
  }
}
