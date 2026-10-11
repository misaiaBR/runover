/// Medidas da trilha do Passe de Temporada.
///
/// Uma única fonte de verdade: as colunas de nível, os cartões de recompensa e
/// a coluna de rótulos ("Grátis" / "Passe") precisam alinhar faixa por faixa,
/// e é isso que quebra quando cada um tem seu número mágico.
class TrailMetrics {
  const TrailMetrics({
    required this.cardWidth,
    required this.cardSlotHeight,
    required this.railHeight,
  });

  /// Tamanho base — celular e janelas baixas.
  static const base = TrailMetrics(
    cardWidth: 96,
    cardSlotHeight: 120,
    railHeight: 48,
  );

  /// Passar disso vira mancha de cartões enormes na web.
  static const maxScale = 1.35;

  final double cardWidth;
  final double cardSlotHeight;
  final double railHeight;

  /// Altura total da trilha: faixa grátis + trilho + faixa do passe.
  double get trailHeight => cardSlotHeight * 2 + railHeight;

  /// Altura do cartão de recompensa (a coluna dá o respiro em volta).
  double get cardHeight => cardSlotHeight - 8;

  /// Largura do cartão: a coluna é mais larga que o cartão por causa da borda.
  double get cardInnerWidth => cardWidth - 12;

  /// Cartões de nível 1× para cima: a tipografia acompanha, senão o cartão
  /// crescido fica com letrinha de celular no meio da tela grande.
  double get scale => cardWidth / base.cardWidth;

  /// Amplia a trilha para aproveitar a altura disponível, sem passar de
  /// [maxScale]. Altura insuficiente (ou infinita, como dentro de um
  /// `ListView` vertical) devolve o tamanho base.
  factory TrailMetrics.fitting(double availableHeight) {
    if (!availableHeight.isFinite || availableHeight <= base.trailHeight) {
      return base;
    }
    final scale = (availableHeight / base.trailHeight).clamp(1.0, maxScale);
    return TrailMetrics(
      cardWidth: base.cardWidth * scale,
      cardSlotHeight: base.cardSlotHeight * scale,
      railHeight: base.railHeight * scale,
    );
  }
}
