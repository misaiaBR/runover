/// Formatação pt-BR de milhares (`10.000`) para pontos, moedas e saldos.
///
/// Implementação canônica única — não duplique este regex nas telas;
/// importe daqui.
String formatPoints(int n) =>
    n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');

/// Contagem regressiva da temporada ("Termina em 5 d 3 h") — régua única do
/// resumo do passe e do cabeçalho da trilha.
String formatCountdown(Duration left) {
  if (left.isNegative) return 'Temporada encerrada';
  final days = left.inDays;
  final hours = left.inHours % 24;
  if (days > 0) return 'Termina em $days d $hours h';
  final minutes = left.inMinutes % 60;
  if (hours > 0) return 'Termina em $hours h $minutes min';
  return 'Termina em $minutes min';
}
