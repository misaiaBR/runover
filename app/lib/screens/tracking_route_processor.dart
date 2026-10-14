import 'package:geolocator/geolocator.dart';

import '../services/territory_loop.dart';

class TrackingScreenRouteProcessor {
  static const double _maxAccuracyMeters = 50;

  /// Janela do "salto" do GPS: longe demais, rápido demais, e o próximo ponto
  /// volta para o lugar. Ficam públicos porque a tela da corrida julga esse
  /// mesmo par para decidir entre descartar uma leitura torta e parar a
  /// gravação.
  static const double maxJumpMeters = 250;
  static const double jumpWindowSeconds = 5;
  static const double _minRouteSpacingMeters = 12;

  /// Um par acima do teto de velocidade que ainda cabe nesta janela de salto é
  /// leitura torta do GPS, não veículo: 250 m em até 5 s. O intervalo é
  /// fracionário, a mesma base de tempo de `TerritoryLoop.speedMps` e do
  /// servidor — truncar em segundos faria um salto de 0,9 s passar por
  /// movimento normal e um deslocamento de 5,9 s passar por salto.
  static bool looksLikeBadFix(
    Map<String, dynamic> previous,
    Map<String, dynamic> next,
  ) {
    final elapsed = TerritoryLoop.intervalSeconds(previous, next);
    if (elapsed <= 0 || elapsed > jumpWindowSeconds) return false;
    return Geolocator.distanceBetween(
      (previous['lat'] as num).toDouble(),
      (previous['lng'] as num).toDouble(),
      (next['lat'] as num).toDouble(),
      (next['lng'] as num).toDouble(),
    ) >
        maxJumpMeters;
  }

  static bool isUsablePoint(
    Map<String, dynamic> point, {
    double accuracyMeters = _maxAccuracyMeters,
  }) {
    final lat = point['lat'];
    final lng = point['lng'];
    final timestamp = point['timestamp'];
    if (lat is! num || lng is! num) return false;
    final latValue = lat.toDouble();
    final lngValue = lng.toDouble();
    if (!latValue.isFinite || !lngValue.isFinite) return false;
    final accuracy = point['accuracy'];
    if (accuracy is num && accuracy.toDouble() > accuracyMeters) return false;
    if (timestamp is! String || DateTime.tryParse(timestamp) == null) {
      return false;
    }
    return true;
  }

  static List<Map<String, dynamic>> filterTrack(
    List<Map<String, dynamic>> points, {
    double accuracy = _maxAccuracyMeters,
  }) {
    final filtered = <Map<String, dynamic>>[];
    for (final point in points) {
      if (!isUsablePoint(point, accuracyMeters: accuracy)) continue;
      final previous = filtered.isEmpty ? null : filtered.last;
      if (previous != null) {
        final previousTime = DateTime.tryParse(previous['timestamp'] as String);
        final currentTime = DateTime.tryParse(point['timestamp'] as String);
        if (previousTime == null ||
            currentTime == null ||
            !currentTime.isAfter(previousTime)) {
          continue;
        }
        if (looksLikeBadFix(previous, point)) continue;
      }
      filtered.add(Map<String, dynamic>.from(point));
    }
    return filtered;
  }

  static List<Map<String, dynamic>> simplifyTrack(
    List<Map<String, dynamic>> points, {
    double minDistanceMeters = _minRouteSpacingMeters,
  }) {
    if (points.length < 3) return List<Map<String, dynamic>>.from(points);
    final simplified = <Map<String, dynamic>>[
      Map<String, dynamic>.from(points.first),
    ];
    for (var index = 1; index < points.length - 1; index++) {
      final previous = simplified.last;
      final current = points[index];
      final next = points[index + 1];
      final previousLat = (previous['lat'] as num).toDouble();
      final previousLng = (previous['lng'] as num).toDouble();
      final currentLat = (current['lat'] as num).toDouble();
      final currentLng = (current['lng'] as num).toDouble();
      final nextLat = (next['lat'] as num).toDouble();
      final nextLng = (next['lng'] as num).toDouble();
      final distanceToPrevious = Geolocator.distanceBetween(
        previousLat,
        previousLng,
        currentLat,
        currentLng,
      );
      final distanceToNext = Geolocator.distanceBetween(
        currentLat,
        currentLng,
        nextLat,
        nextLng,
      );
      if (distanceToPrevious < minDistanceMeters &&
          distanceToNext < minDistanceMeters) {
        continue;
      }
      simplified.add(Map<String, dynamic>.from(current));
    }
    final last = points.last;
    if (simplified.isEmpty ||
        simplified.last['timestamp'] != last['timestamp']) {
      simplified.add(Map<String, dynamic>.from(last));
    }
    return simplified;
  }
}
