import 'dart:convert';
import 'dart:math';

/// Desafio do dia sorteado para um competidor.
class DailyChallenge {
  const DailyChallenge({
    required this.id,
    required this.title,
    required this.detail,
    required this.unit,
    required this.target,
    required this.rarity,
    required this.kind,
  });

  final String id;
  final String title;
  final String detail;
  final String unit;
  final num target;

  /// Faixa de dificuldade: `comum`, `raro` ou `épico`.
  final String rarity;

  /// Como o progresso é medido: `count`, `distance`, `duration`,
  /// `dawn`, `night` ou `pace`.
  final String kind;
}

/// Resumo das corridas de um competidor em um dia.
class RunDaySummary {
  const RunDaySummary({
    required this.distanceKm,
    required this.minutes,
    required this.count,
    required this.startHours,
    required this.fastestPaceMinKm,
  });

  final num distanceKm;
  final num minutes;
  final int count;
  final List<int> startHours;
  final num? fastestPaceMinKm;
}

/// Progresso de um desafio no dia.
class ChallengeProgress {
  const ChallengeProgress({required this.value, required this.done});

  final num value;
  final bool done;
}

const _pool = <DailyChallenge>[
  DailyChallenge(
    id: 'run-once',
    title: 'Sair do lugar',
    detail: 'Complete a primeira corrida do dia',
    unit: 'corridas',
    target: 1,
    rarity: 'comum',
    kind: 'count',
  ),
  DailyChallenge(
    id: 'km-3',
    title: 'Três quilômetros',
    detail: 'Curta distância para manter o hábito',
    unit: 'km',
    target: 3,
    rarity: 'comum',
    kind: 'distance',
  ),
  DailyChallenge(
    id: 'min-20',
    title: 'Vinte minutos em movimento',
    detail: 'No seu ritmo, sem pressa',
    unit: 'min',
    target: 20,
    rarity: 'comum',
    kind: 'duration',
  ),
  DailyChallenge(
    id: 'km-5',
    title: 'Cinco quilômetros',
    detail: 'A distância clássica de treino',
    unit: 'km',
    target: 5,
    rarity: 'raro',
    kind: 'distance',
  ),
  DailyChallenge(
    id: 'twice',
    title: 'Dupla do dia',
    detail: 'Duas corridas em um só dia',
    unit: 'corridas',
    target: 2,
    rarity: 'raro',
    kind: 'count',
  ),
  DailyChallenge(
    id: 'dawn',
    title: 'Corredor da aurora',
    detail: 'Corra antes das 8h',
    unit: 'corridas',
    target: 1,
    rarity: 'raro',
    kind: 'dawn',
  ),
  DailyChallenge(
    id: 'night',
    title: 'Corredor da noite',
    detail: 'Corra depois das 19h',
    unit: 'corridas',
    target: 1,
    rarity: 'raro',
    kind: 'night',
  ),
  DailyChallenge(
    id: 'min-40',
    title: 'Quarenta minutos',
    detail: 'Sessão longa de aeróbico',
    unit: 'min',
    target: 40,
    rarity: 'raro',
    kind: 'duration',
  ),
  DailyChallenge(
    id: 'pace',
    title: 'Racho afiado',
    detail: 'Ritmo médio abaixo de 6 min/km',
    unit: 'min/km',
    target: 6,
    rarity: 'épico',
    kind: 'pace',
  ),
  DailyChallenge(
    id: 'km-8',
    title: 'Oito quilômetros',
    detail: 'Longão de respeito',
    unit: 'km',
    target: 8,
    rarity: 'épico',
    kind: 'distance',
  ),
];

/// Chave do dia no fuso local: `2026-10-04`.
String dayKey(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// Tempo que falta para a meia-noite local, quando o sorteio troca.
String timeUntilMidnight(DateTime now) {
  final left = DateTime(now.year, now.month, now.day + 1).difference(now);
  if (left.inHours >= 1) {
    return '${left.inHours}h ${left.inMinutes % 60}min';
  }
  return '${left.inMinutes}min';
}

/// Sorteia os desafios do dia de um competidor.
///
/// A seed mistura o apelido com a data local, então cada usuário recebe
/// um conjunto único e estável por 24h, sem nada armazenado: o mesmo
/// sorteio é recalculado a cada abertura. Um dos desafios é sempre
/// personalizado pelo histórico da semana.
List<DailyChallenge> drawDailyChallenges({
  required String username,
  required DateTime date,
  required num weeklyKm,
  required num longestKm,
  int count = 3,
}) {
  // O personalizado ocupa a última vaga: sem vagas, não há sorteio.
  if (count <= 0) return const [];
  final seed = _seedFrom('${username.trim().toLowerCase()}|${dayKey(date)}');
  final picked = _shuffled(_pool, seed).take(count - 1).toList();
  picked.add(_personalized(weeklyKm: weeklyKm, longestKm: longestKm));
  return picked;
}

/// Agrupa as corridas de um competidor em um dia, no fuso local.
RunDaySummary summarizeDay(List<Map<String, dynamic>> runs, DateTime date) {
  var distanceM = 0.0;
  var seconds = 0.0;
  final startHours = <int>[];
  num? fastestPace;
  for (final run in runs) {
    final started = DateTime.tryParse('${run['started_at']}');
    if (started == null) continue;
    final local = started.toLocal();
    if (local.year != date.year ||
        local.month != date.month ||
        local.day != date.day) {
      continue;
    }
    final distance = (run['distance_m'] as num?)?.toDouble() ?? 0.0;
    final duration = (run['duration_seconds'] as num?)?.toDouble() ?? 0.0;
    distanceM += distance;
    seconds += duration;
    startHours.add(local.hour);
    // Ritmo só vale em trecho com tamanho de volta (400 m): 10 m de ruído
    // de GPS dariam um "pace épico" sem correr de verdade.
    if (distance >= 400 && duration > 0) {
      final pace = duration / 60 / (distance / 1000);
      if (fastestPace == null || pace < fastestPace) fastestPace = pace;
    }
  }
  return RunDaySummary(
    distanceKm: distanceM / 1000,
    minutes: seconds / 60,
    count: startHours.length,
    startHours: startHours,
    fastestPaceMinKm: fastestPace,
  );
}

/// Mede o progresso de um desafio contra as corridas do dia.
ChallengeProgress measure(DailyChallenge challenge, RunDaySummary summary) {
  return switch (challenge.kind) {
    'count' => ChallengeProgress(
      value: summary.count,
      done: summary.count >= challenge.target,
    ),
    'distance' => ChallengeProgress(
      value: summary.distanceKm,
      done: summary.distanceKm >= challenge.target,
    ),
    'duration' => ChallengeProgress(
      value: summary.minutes,
      done: summary.minutes >= challenge.target,
    ),
    'dawn' => ChallengeProgress(
      value: summary.startHours.any((h) => h < 8) ? 1 : 0,
      done: summary.startHours.any((h) => h < 8),
    ),
    'night' => ChallengeProgress(
      value: summary.startHours.any((h) => h >= 19) ? 1 : 0,
      done: summary.startHours.any((h) => h >= 19),
    ),
    'pace' => ChallengeProgress(
      value: summary.fastestPaceMinKm ?? 0,
      done:
          summary.fastestPaceMinKm != null &&
          summary.fastestPaceMinKm! < challenge.target,
    ),
    _ => ChallengeProgress(value: 0, done: false),
  };
}

/// Desafio único: o alvo acompanha a média diária e o longão da semana.
DailyChallenge _personalized({required num weeklyKm, required num longestKm}) {
  final base = max(weeklyKm / 7, longestKm / 2);
  final target = min(15, max(3, (base + 1.5).ceilToDouble()));
  return DailyChallenge(
    id: 'personal',
    title: 'Longão pessoal',
    detail: 'Um passo além da sua média diária — feito para você',
    unit: 'km',
    target: target,
    rarity: 'épico',
    kind: 'distance',
  );
}

int _seedFrom(String text) {
  var hash = 0x811C9DC5;
  for (final byte in utf8.encode(text)) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash;
}

List<T> _shuffled<T>(List<T> items, int seed) {
  final result = List<T>.of(items);
  var state = seed | 1;
  for (var i = result.length - 1; i > 0; i--) {
    state = _nextState(state);
    final j = state % (i + 1);
    final tmp = result[i];
    result[i] = result[j];
    result[j] = tmp;
  }
  return result;
}

int _nextState(int state) {
  state ^= state << 13;
  state &= 0xFFFFFFFF;
  state ^= state >>> 17;
  state ^= state << 5;
  return state & 0xFFFFFFFF;
}
