import 'package:flutter_test/flutter_test.dart';
import 'package:runover_app/services/territory_loop.dart';

Map<String, dynamic> point(
  double lat,
  double lng, {
  int segment = 0,
  double? accuracy,
}) => {
  'lat': lat,
  'lng': lng,
  'segment': segment,
  'accuracy': ?accuracy,
};

/// ~11,1 m por 0,0001 de latitude.
const step = 0.0001;

void main() {
  test('pede os pontos que faltam antes de falar de laço', () {
    final loop = TerritoryLoop.fromTrack([
      point(0, 0),
      point(step, 0),
    ]);
    expect(loop.enoughPoints, isFalse);
    expect(loop.closed, isFalse);
    expect(loop.label, contains('2 pontos de GPS'));
  });

  test('sem acurácia reportada vale o piso de 30 m', () {
    final loop = TerritoryLoop.fromTrack([
      point(0, 0),
      point(6 * step, 0),
      point(6 * step, 6 * step),
      point(0, 6 * step),
      point(5.5 * step, 0), // ~61 m do início
    ]);
    expect(loop.toleranceM, 30);
    expect(loop.closed, isFalse);
    expect(loop.remainingM, inInclusiveRange(25, 40));
    expect(loop.label, contains('Faltam ~'));
  });

  test('a incerteza dos dois pontos extremos larga o fechamento', () {
    final loop = TerritoryLoop.fromTrack([
      point(0, 0, accuracy: 50),
      point(6 * step, 0),
      point(6 * step, 6 * step),
      point(0, 6 * step),
      point(5.5 * step, 0, accuracy: 50),
    ]);
    expect(loop.toleranceM, inInclusiveRange(65, 75));
    expect(loop.closed, isTrue);
    expect(loop.label, contains('Laço fechado'));
  });

  test('a tolerância tem teto por pior que seja o sinal', () {
    final loop = TerritoryLoop.fromTrack([
      point(0, 0, accuracy: 500),
      point(6 * step, 0),
      point(6 * step, 6 * step),
      point(0, 6 * step),
      point(18 * step, 0, accuracy: 500), // ~200 m do início
    ]);
    expect(loop.toleranceM, 120);
    expect(loop.closed, isFalse);
  });

  test('retomar longe de onde parou quebra o traçado', () {
    final loop = TerritoryLoop.fromTrack([
      point(0, 0),
      point(step, 0),
      point(36 * step, 0, segment: 1), // ~400 m adiante
      point(36 * step, step, segment: 1),
    ]);
    expect(loop.brokenByPause, isTrue);
    expect(loop.closed, isFalse);
    expect(loop.label, contains('retomou'));
  });

  test('retomar no mesmo lugar mantém o laço válido', () {
    final loop = TerritoryLoop.fromTrack([
      point(0, 0),
      point(step, 0),
      point(step + step, 0, segment: 1), // ~11 m: buraco de GPS
      point(step + step, step, segment: 1),
      point(0, step, segment: 1),
      point(0, 0, segment: 1),
    ]);
    expect(loop.brokenByPause, isFalse);
    expect(loop.closed, isTrue);
  });

  test('laço fechado sem área não promete território', () {
    // Ida e volta no mesmo traçado: fecha (gap 0) mas não encerra área nenhuma,
    // e o servidor recusa a conquista por baixo do piso de 100 m².
    final loop = TerritoryLoop.fromTrack([
      point(0, 0),
      point(step, 0),
      point(2 * step, 0),
      point(0, 0),
    ]);
    expect(loop.areaM2, lessThan(TerritoryLoop.minAreaM2));
    expect(loop.closed, isFalse);
    expect(loop.label, contains('pequena demais'));
  });

  test('a área do laço é medida nos metros que o servidor usa', () {
    // Quadrado de ~22 m por ~11 m: o suficiente para ser território.
    final loop = TerritoryLoop.fromTrack([
      point(0, 0),
      point(2 * step, 0),
      point(2 * step, step),
      point(0, step),
      point(0, 0),
    ]);
    expect(loop.areaM2, inInclusiveRange(200, 300));
    expect(loop.closed, isTrue);
    expect(loop.label, contains('Laço fechado'));
  });

  test('acima de 25 km² o laço passa do limite de um território', () {
    final loop = TerritoryLoop.fromTrack([
      point(0, 0),
      point(0.5, 0),
      point(0.5, 0.5),
      point(0, 0.5),
      point(0, 0),
    ]);
    expect(loop.areaM2, greaterThan(TerritoryLoop.maxAreaM2));
    expect(loop.closed, isFalse);
    expect(loop.label, contains('25 km²'));
  });

  test('a velocidade do espelho é a que o servidor mede', () {
    // 8,3 m/s (~30 km/h) é `max_plausible_speed_mps` no backend: um par de
    // pontos acima disso recusa a corrida inteira no envio, então o aparelho
    // precisa medir a mesma coisa no instante em que o ponto chega.
    const base = {
      'lat': 0.0,
      'lng': 0.0,
      'timestamp': '2026-10-13T18:00:00.000Z',
    };
    const andando = {
      'lat': 0.00005, // ~5,6 m em 4 s
      'lng': 0.0,
      'timestamp': '2026-10-13T18:00:04.000Z',
    };
    const trem = {
      'lat': 0.0018, // ~200 m em 5 s
      'lng': 0.0,
      'timestamp': '2026-10-13T18:00:05.000Z',
    };
    expect(maxPlausibleSpeedMps, 8.3);
    expect(
      TerritoryLoop.speedMps(base, andando),
      lessThan(maxPlausibleSpeedMps),
    );
    expect(TerritoryLoop.speedMps(base, trem), greaterThan(30));
    // Sem intervalo utilizável não há velocidade a julgar.
    expect(TerritoryLoop.speedMps(base, base), 0);
  });

  test('o intervalo é fracionário, como no servidor', () {
    // O backend divide pela duração em segundos com casas decimais. Truncar
    // aqui dava velocidade zero a 0,9 s (o ponto passava e o envio morria
    // depois) e velocidade inflada a 1,9 s (parava quem corre de verdade).
    const base = {
      'lat': 0.0,
      'lng': 0.0,
      'timestamp': '2026-10-13T18:00:00.000Z',
    };
    const quaseUmSegundo = {
      'lat': 0.0018, // ~200 m em 0,9 s
      'lng': 0.0,
      'timestamp': '2026-10-13T18:00:00.900Z',
    };
    const quaseDoisSegundos = {
      'lat': 0.000125, // ~13,9 m em 1,9 s = 7,3 m/s: corrida normal
      'lng': 0.0,
      'timestamp': '2026-10-13T18:00:01.900Z',
    };
    expect(
      TerritoryLoop.speedMps(base, quaseUmSegundo),
      greaterThan(maxPlausibleSpeedMps),
    );
    expect(
      TerritoryLoop.speedMps(base, quaseDoisSegundos),
      lessThan(maxPlausibleSpeedMps),
    );
  });
}
