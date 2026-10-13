import 'package:flutter/material.dart';

import '../palette.dart';
import '../trail_metrics.dart';
import '../../widgets/runover_ui.dart';

/// Rótulos das faixas, fixos à esquerda da trilha.
///
/// Cada rótulo veste o gradiente da própria faixa — é a cor que separa as duas
/// no mock, e aqui ela ganha nome: "Grátis" em cima, "Passe" embaixo.
///
/// Não rola com a trilha: a tela o coloca fora do scroll horizontal. As
/// alturas vêm de [TrailMetrics] para os rótulos alinharem com os cartões em
/// qualquer densidade de tela.
class SeasonPassLaneLabels extends StatelessWidget {
  const SeasonPassLaneLabels({super.key, required this.metrics});

  static const double width = 58;

  final TrailMetrics metrics;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Column(
      children: [
        SizedBox(
          height: metrics.cardSlotHeight,
          child: Center(child: _pill('Grátis', premium: false)),
        ),
        SizedBox(height: metrics.railHeight, child: const Center(child: _Rail())),
        SizedBox(
          height: metrics.cardSlotHeight,
          child: Center(child: _pill('Passe', premium: true)),
        ),
      ],
    ),
  );

  Widget _pill(String text, {required bool premium}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6 * metrics.scale, vertical: 5),
      decoration: BoxDecoration(
        gradient: trailGradient(premium: premium),
        borderRadius: BorderRadius.circular(999),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          text,
          maxLines: 1,
          style: TextStyle(
            color: Colors.white,
            fontSize: 11.5 * metrics.scale,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }
}

/// Continuação do trilho sob a coluna de rótulos: liga a faixa fixa ao primeiro
/// nó da trilha. Usa `Pal.track`, o mesmo trilho das outras barras do app.
class _Rail extends StatelessWidget {
  const _Rail();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: SeasonPassLaneLabels.width,
    child: Container(height: 4, color: Pal.of(context).track),
  );
}
