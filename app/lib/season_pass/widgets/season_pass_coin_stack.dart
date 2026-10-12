import 'package:flutter/material.dart';

/// Pilha de dracmas desenhada em Flutter — a arte da recompensa que só dá
/// moedas, no lugar de um ícone genérico.
///
/// A altura da pilha acompanha o tamanho do prêmio, então dá para ler a
/// trilha de relance: nível alto, pilha alta.
class SeasonPassCoinStack extends StatelessWidget {
  const SeasonPassCoinStack({super.key, required this.coins, this.size = 56});

  final int coins;
  final double size;

  /// Cada moeda a mais vale [coinsPerCoin] dracmas, com no máximo
  /// [_maxCoins] na pilha — depois disso ela só comeria o cartão.
  static const int _coinsPerCoin = 60;
  static const int _maxCoins = 5;

  @override
  Widget build(BuildContext context) {
    final count = (1 + coins ~/ _coinsPerCoin).clamp(1, _maxCoins);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _CoinStackPainter(coins: count)),
    );
  }
}

/// Uma moeda do passe: face dourada em degradê, borda escura e brilho no topo.
class _CoinStackPainter extends CustomPainter {
  const _CoinStackPainter({required this.coins});

  final int coins;

  static const _face = Color(0xFFFFB21A);
  static const _faceLight = Color(0xFFFFF0A8);
  static const _edge = Color(0xFFB87600);
  static const _outline = Color(0xFF8A5A00);

  @override
  void paint(Canvas canvas, Size size) {
    final rx = size.width * .34;
    final ry = size.height * .11;
    final step = ry * 1.9;
    final centerX = size.width / 2;
    final lastCy = size.height - ry - 2 - (coins - 1) * step;

    for (var i = coins - 1; i >= 0; i--) {
      final cy = size.height - ry - 2 - i * step;
      _coin(canvas, Offset(centerX, cy), rx, ry, shine: i == coins - 1);
    }
    // Aro e brilho só na moeda da frente: é ela que mostra o valor.
    _ring(canvas, Offset(centerX, lastCy), rx * .58, ry * .58);
  }

  void _coin(
    Canvas canvas,
    Offset center,
    double rx,
    double ry, {
    required bool shine,
  }) {
    final rect = Rect.fromCenter(center: center, width: rx * 2, height: ry * 2);
    // Espessura: a elipse escura deslocada para baixo é a lateral da moeda.
    canvas.drawOval(
      Rect.fromCenter(
        center: center.translate(0, ry * .7),
        width: rx * 2,
        height: ry * 2,
      ),
      Paint()..color = _edge,
    );
    canvas.drawOval(
      rect,
      Paint()
        ..shader = const LinearGradient(
              colors: [_faceLight, _face],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            )
            .createShader(rect),
    );
    canvas.drawOval(
      rect,
      Paint()
        ..color = _outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
    if (shine) {
      canvas.drawOval(
        Rect.fromCenter(
          center: center.translate(-rx * .3, -ry * .3),
          width: rx * .7,
          height: ry * .45,
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.6),
      );
    }
  }

  void _ring(Canvas canvas, Offset center, double rx, double ry) {
    canvas.drawOval(
      Rect.fromCenter(center: center, width: rx * 2, height: ry * 2),
      Paint()
        ..color = _outline.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1,
    );
  }

  @override
  bool shouldRepaint(_CoinStackPainter oldDelegate) => oldDelegate.coins != coins;
}
