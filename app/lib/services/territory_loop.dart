import 'dart:math' as math;

/// Teto de velocidade que o servidor aceita entre dois pontos do trajeto
/// (`max_plausible_speed_mps`, em `backend/app/core/config.py`): ~30 km/h,
/// generoso para corrida e sprint. Acima disso o movimento é de veículo, e o
/// `POST /runs` recusa a corrida inteira (RNF17). O aparelho percebe no instante
/// em que o ponto chega — não tem sentido gravar para reclamar só no envio.
const double maxPlausibleSpeedMps = 8.3;

/// Espelho das regras de fechamento de laço do backend
/// (`backend/app/geometry.py`). O corredor precisa saber em tempo real se o
/// trajeto vai virar território; se estes números divergirem do servidor, a
/// tela mente.
class TerritoryLoop {
  const TerritoryLoop._({
    required this.points,
    required this.gapM,
    required this.toleranceM,
    required this.pauseJumpM,
    required this.areaM2,
  });

  final int points;
  final double gapM;
  final double toleranceM;
  final double? pauseJumpM;

  /// Área do polígono, nos mesmos metros quadrados que o servidor mede. O laço
  /// fechado precisa de área: sem ela não existe território a conquistar, e a
  /// tela não pode prometer "pode salvar" para um traçado que o servidor recusa.
  final double areaM2;

  static const int minPoints = 4;
  static const double floorToleranceM = 30;
  static const double maxToleranceM = 120;
  static const double maxPauseGapM = 100;
  static const double minAreaM2 = 100;
  static const double maxAreaM2 = 25_000_000;

  /// Avalia o trajeto coletado. Cada ponto é o mapa enviado ao backend:
  /// `lat`, `lng` e, quando houver, `accuracy` (metros) e `segment` (pausas).
  factory TerritoryLoop.fromTrack(List<Map<String, dynamic>> track) {
    if (track.isEmpty) {
      return const TerritoryLoop._(
        points: 0,
        gapM: 0,
        toleranceM: floorToleranceM,
        pauseJumpM: null,
        areaM2: 0,
      );
    }
    var jump = 0.0;
    for (var i = 1; i < track.length; i++) {
      if (_segmentOf(track[i - 1]) == _segmentOf(track[i])) continue;
      jump = math.max(
        jump,
        _distanceM(
          _lat(track[i - 1]),
          _lng(track[i - 1]),
          _lat(track[i]),
          _lng(track[i]),
        ),
      );
    }
    return TerritoryLoop._(
      points: track.length,
      gapM: _distanceM(
        _lat(track.first),
        _lng(track.first),
        _lat(track.last),
        _lng(track.last),
      ),
      toleranceM: _tolerance(
        _accuracyOf(track.first),
        _accuracyOf(track.last),
      ),
      pauseJumpM: jump > 0 ? jump : null,
      areaM2: _areaM2(track),
    );
  }

  /// Mesma projeção equirretangular do `polygon_area_m2` do backend, com o
  /// shoelace do anel: o número mostrado na corrida tem de ser o número que o
  /// servidor mede ao aceitar (ou recusar) o território.
  static double _areaM2(List<Map<String, dynamic>> track) {
    if (track.length < 3) return 0;
    var latSum = 0.0;
    for (final point in track) {
      latSum += _lat(point);
    }
    final mPerDegLat = 111320.0;
    final mPerDegLng =
        111320.0 * math.cos(latSum / track.length * math.pi / 180);
    var sum = 0.0;
    for (var i = 0; i < track.length; i++) {
      final a = track[i];
      final b = track[(i + 1) % track.length];
      sum +=
          (_lng(a) * mPerDegLng) * (_lat(b) * mPerDegLat) -
          (_lng(b) * mPerDegLng) * (_lat(a) * mPerDegLat);
    }
    return sum.abs() / 2;
  }

  /// Intervalo entre dois pontos, em segundos com casas decimais — a mesma base
  /// de tempo do servidor. Zero quando não há intervalo utilizável, para quem
  /// chamar decidir só pelo que é movimento de verdade.
  static double intervalSeconds(
    Map<String, dynamic> from,
    Map<String, dynamic> to,
  ) {
    final t1 = DateTime.tryParse('${from['timestamp']}');
    final t2 = DateTime.tryParse('${to['timestamp']}');
    if (t1 == null || t2 == null) return 0;
    return t2.difference(t1).inMicroseconds / 1000000;
  }

  /// Velocidade média que o servidor calcularia entre dois pontos do trajeto.
  /// Microssegundos, não segundos inteiros: o backend divide pela duração
  /// fracionária, e truncar aqui daria velocidade zero a um intervalo de 0,9 s
  /// (o ponto passaria e o envio seria recusado depois) e velocidade inflada a
  /// 1,9 s (a corrida pararia sem motivo).
  static double speedMps(Map<String, dynamic> from, Map<String, dynamic> to) {
    final seconds = intervalSeconds(from, to);
    if (seconds <= 0) return 0;
    return _distanceM(_lat(from), _lng(from), _lat(to), _lng(to)) / seconds;
  }

  static double _tolerance(double? startAccuracy, double? endAccuracy) {    if (startAccuracy == null || endAccuracy == null) return floorToleranceM;
    final uncertainty = math.sqrt(
      math.max(0, startAccuracy) * math.max(0, startAccuracy) +
          math.max(0, endAccuracy) * math.max(0, endAccuracy),
    );
    return uncertainty.clamp(floorToleranceM, maxToleranceM);
  }

  static double? _accuracyOf(Map<String, dynamic> point) {
    final value = point['accuracy'];
    if (value is! num) return null;
    final meters = value.toDouble();
    return meters.isFinite ? meters : null;
  }

  static int _segmentOf(Map<String, dynamic> point) =>
      (point['segment'] as num?)?.toInt() ?? 0;

  static double _lat(Map<String, dynamic> point) =>
      (point['lat'] as num).toDouble();

  static double _lng(Map<String, dynamic> point) =>
      (point['lng'] as num).toDouble();

  static double _distanceM(double lat1, double lng1, double lat2, double lng2) {
    // Mesmo haversine do backend: a distância exibida tem de ser a distância
    // que o servidor mede ao decidir o fechamento.
    const radius = 6371000.0;
    final p1 = lat1 * math.pi / 180;
    final p2 = lat2 * math.pi / 180;
    final dPhi = (lat2 - lat1) * math.pi / 180;
    final dLambda = (lng2 - lng1) * math.pi / 180;
    final a =
        math.pow(math.sin(dPhi / 2), 2) +
        math.cos(p1) * math.cos(p2) * math.pow(math.sin(dLambda / 2), 2);
    return 2 *
        radius *
        math.asin(math.sqrt(math.min(1, math.max(0, a)).toDouble()));
  }

  bool get enoughPoints => points >= minPoints;

  /// Maior distância entre uma pausa e a retomada que o traçado ainda aceita.
  bool get brokenByPause => (pauseJumpM ?? 0) > maxPauseGapM;

  /// Área suficiente para ser território, e dentro do teto de um laço.
  bool get hasTerritoryArea => areaM2 >= minAreaM2 && areaM2 <= maxAreaM2;

  bool get closed =>
      enoughPoints && !brokenByPause && gapM <= toleranceM && hasTerritoryArea;

  /// Quantos metros faltam para o laço fechar; zero quando já está fechado.
  double get remainingM => closed ? 0 : math.max(0, gapM - toleranceM);

  /// Texto curto do painel de corrida.
  String get label {
    if (!enoughPoints) {
      return 'Faltam ${minPoints - points} pontos de GPS para fechar o território.';
    }
    if (brokenByPause) {
      return 'Você retomou a ~${(pauseJumpM ?? 0).round()}m de onde parou: '
          'o território precisa de um traçado contínuo.';
    }
    if (gapM > toleranceM) {
      return 'Faltam ~${remainingM.round()}m para voltar ao ponto de partida e fechar o laço.';
    }
    if (areaM2 < minAreaM2) {
      return 'O laço fechou, mas a área é pequena demais para virar território '
          '(~${areaM2.round()} m² de um mínimo de ${minAreaM2.round()} m²). '
          'Amplie o trajeto.';
    }
    if (areaM2 > maxAreaM2) {
      return 'O laço fechou, mas a área passou de '
          '${(maxAreaM2 / 1000000).round()} km² — o limite de um território.';
    }
    return 'Laço fechado. Pode salvar que o território é seu.';
  }
}
