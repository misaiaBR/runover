import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../format.dart';
import '../gold.dart';
import '../models.dart';
import '../trail_metrics.dart';
import 'season_pass_hex_node.dart';

/// Cartão de uma recompensa da trilha (faixa grátis em cima, passe embaixo).
///
/// A linguagem visual diz o estado sem depender de um cadeado gigante em cada
/// nível — com 30 níveis, uma fileira de cadeados vira ruído:
/// - **bloqueado**: o próprio ícone da recompensa aparece esmaecido (dá para
///   ver o que vem por aí) atrás de um selo hexagonal, com borda tracejada;
/// - **requer passe**: o ícone vem em dourado esmaecido, selo dourado e borda
///   sólida — o cartão é tocável e abre a confirmação do passe;
/// - **resgatável**: borda e selo cheios, botão "Resgatar" preenchido;
/// - **resgatado**: tudo em cor secundária, com o selo de visto.
///
/// O dourado só aparece no que o jogador já alcançou: a faixa do passe
/// bloqueada não pode parecer disponível.
///
/// O cartão inteiro é a área de toque e o nome do item nunca é cortado com
/// reticências — quando falta espaço, o bloco de texto encolhe junto.
class SeasonPassRewardCard extends StatelessWidget {
  const SeasonPassRewardCard({
    super.key,
    required this.reward,
    required this.state,
    required this.level,
    required this.premium,
    required this.metrics,
    required this.onClaim,
    this.onNeedsPass,
  });

  final Reward reward;
  final RewardState state;
  final int level;
  final bool premium;

  /// Medidas da trilha (tamanho do cartão e escala da tipografia).
  final TrailMetrics metrics;

  final VoidCallback onClaim;

  /// Chamado quando o cartão pede o passe. Sem ele, o cartão fica inerte.
  final VoidCallback? onNeedsPass;

  static const double _radius = 14;

  bool get _sealed => state == RewardState.locked;

  /// Dourado é recompensa de quem já chegou ali — nunca um nível bloqueado.
  bool get _gold => premium && !_sealed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active =
        state == RewardState.claimable || state == RewardState.needsPass;
    final onTap = state == RewardState.claimable
        ? onClaim
        : (state == RewardState.needsPass ? onNeedsPass : null);
    final status = switch (state) {
      RewardState.claimed => 'Resgatado',
      RewardState.claimable => 'Resgatar',
      RewardState.locked => 'Nível $level',
      RewardState.needsPass => 'Requer passe',
    };
    final borderColor = switch (state) {
      RewardState.claimable => scheme.primary,
      RewardState.needsPass => seasonPassGoldBorder,
      // Resgatado guarda a cor da faixa: o dourado de um item do passe não
      // fica bem com o verde do resgate.
      RewardState.claimed => _gold
        ? seasonPassGoldBorder.withValues(alpha: 0.7)
        : scheme.secondary.withValues(alpha: 0.5),
      RewardState.locked => scheme.outlineVariant.withValues(alpha: 0.55),
    };

    return Semantics(
      button: active,
      label: '${reward.title}, $status',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(_radius),
          onTap: onTap,
          child: Container(
            width: metrics.cardInnerWidth,
            height: metrics.cardHeight,
            decoration: BoxDecoration(
              color: _gold ? seasonPassGoldBg : scheme.surface,
              borderRadius: BorderRadius.circular(_radius),
              // A borda tracejada é o "lacre": desenhada por fora do
              // `Border.all`, que só sabe fazer linha contínua.
              border: _sealed
                  ? null
                  : Border.all(color: borderColor, width: active ? 1.5 : 1),
            ),
            child: _sealed
                ? CustomPaint(
                    painter: _DashedRRectPainter(
                      color: borderColor,
                      radius: _radius,
                    ),
                    child: _content(context, scheme, status),
                  )
                : _content(context, scheme, status),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, ColorScheme scheme, String status) {
    final s = metrics.scale;
    final tint = _gold ? seasonPassGold : scheme.primary;
    return Padding(
      padding: EdgeInsets.fromLTRB(4, 6 * s, 4, 6 * s),
      child: Column(
        children: [
          SizedBox(
            height: 30 * s,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  reward.icon,
                  size: 26 * s,
                  // Esmaecido em vez de escondido atrás de um cadeado: o
                  // jogador vê o que o nível entrega. Resgatado também perde
                  // força — já foi seu.
                  color: _sealed
                      ? scheme.onSurfaceVariant.withValues(alpha: 0.45)
                      : (state == RewardState.claimed
                            ? tint.withValues(alpha: 0.6)
                            : tint),
                ),
                Positioned(
                  right: 1,
                  bottom: 0,
                  child: _Seal(state: state, gold: _gold, size: 17 * s),
                ),
              ],
            ),
          ),
          SizedBox(height: 3 * s),
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
                    if (reward.itemName != null && reward.coins > 0)
                      Text(
                        '+${formatPoints(reward.coins)} dracmas',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11 * s,
                          fontWeight: FontWeight.w600,
                          height: 1.15,
                          color: _sealed
                              ? scheme.onSurfaceVariant
                              : (_gold ? seasonPassOnGoldDim : tint),
                        ),
                      ),
                    Text(
                      reward.itemName ?? reward.title,
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      style: TextStyle(
                        fontSize: 12 * s,
                        height: 1.15,
                        color: _sealed
                            ? scheme.onSurfaceVariant
                            : scheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(height: 3 * s),
          _StatusPill(
            text: status,
            state: state,
            gold: _gold,
            fontSize: 11 * s,
            maxWidth: metrics.cardInnerWidth - 6,
          ),
        ],
      ),
    );
  }
}

/// Selo do canto do cartão: o lacre hexagonal da trilha.
///
/// Mostra o estado com um glifo de 10 px em vez de tomar o cartão inteiro.
class _Seal extends StatelessWidget {
  const _Seal({required this.state, required this.gold, required this.size});

  final RewardState state;
  final bool gold;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color, ink) = switch (state) {
      RewardState.locked => (
        Icons.lock_outline,
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
      ),
      RewardState.needsPass => (
        Icons.workspace_premium_outlined,
        seasonPassGoldBorder,
        seasonPassGold,
      ),
      RewardState.claimed => (
        Icons.check_rounded,
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
      ),
      RewardState.claimable => (
        Icons.emoji_events_outlined,
        scheme.primary,
        scheme.onPrimary,
      ),
    };
    return SeasonPassHexNode(
      label: Icon(icon, size: size * .62, color: ink),
      color: gold && state == RewardState.claimable ? seasonPassGold : color,
      size: size,
    );
  }
}

/// Etiqueta de estado na base do cartão.
///
/// Uma linha só, com o texto reduzido quando não cabe: "Requer passe" é o
/// rótulo de um botão, e cortado ele deixa de ser uma instrução.
class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.text,
    required this.state,
    required this.gold,
    required this.fontSize,
    required this.maxWidth,
  });

  final String text;
  final RewardState state;
  final bool gold;
  final double fontSize;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final filled = state == RewardState.claimable;
    final outlined = state == RewardState.needsPass;
    final style = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      height: 1.15,
      color: switch (state) {
        RewardState.claimable => gold ? seasonPassOnGold : scheme.onPrimary,
        RewardState.needsPass => seasonPassGold,
        RewardState.claimed => scheme.secondary,
        RewardState.locked => scheme.onSurfaceVariant,
      },
    );
    final label = FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(text, maxLines: 1, style: style),
    );
    if (!filled && !outlined) return SizedBox(height: fontSize * 1.4, child: label);
    // Contorno dourado no "Requer passe": é um convite ao toque, não um
    // botão já pago.
    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: filled ? (gold ? seasonPassGold : scheme.primary) : null,
        border: outlined ? Border.all(color: seasonPassGoldBorder) : null,
        borderRadius: BorderRadius.circular(10),
      ),
      child: label,
    );
  }
}

/// Borda tracejada do cartão lacrado: linha contínua pareceria com o resto, e
/// o tracejado é o que faz o nível bloqueado parecer "ainda fechado".
class _DashedRRectPainter extends CustomPainter {
  const _DashedRRectPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  static const double _dash = 5;
  static const double _gap = 4;
  static const double _stroke = 1.3;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = _stroke / 2;
    final rect = Offset(inset, inset) &
        Size(size.width - _stroke, size.height - _stroke);
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      );
    final paint = Paint()
      ..color = color
      ..strokeWidth = _stroke
      ..style = PaintingStyle.stroke;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + _dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRectPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
