import 'package:flutter_test/flutter_test.dart';
import 'package:runover_app/services/daily_challenges.dart';

void main() {
  final day = DateTime(2026, 10, 4, 15, 30);

  test('the draw is stable for the same competitor all day', () {
    final morning = drawDailyChallenges(
      username: 'marina',
      date: DateTime(2026, 10, 4, 6),
      weeklyKm: 18,
      longestKm: 7,
    );
    final night = drawDailyChallenges(
      username: 'marina',
      date: DateTime(2026, 10, 4, 23, 59),
      weeklyKm: 18,
      longestKm: 7,
    );
    expect(morning.map((c) => c.id), night.map((c) => c.id));
  });

  test('each competitor gets a unique draw', () {
    List<String> draw(String user) => drawDailyChallenges(
      username: user,
      date: day,
      weeklyKm: 10,
      longestKm: 5,
      count: 10,
    ).where((c) => c.id != 'personal').map((c) => c.id).toList();

    expect(draw('ana'), isNot(draw('bruno')));
    expect(draw('carla'), isNot(draw('diego')));
    expect(draw('elena'), isNot(draw('farah')));
  });

  test('the draw rotates after 24h', () {
    List<String> draw(DateTime date) => drawDailyChallenges(
      username: 'marina',
      date: date,
      weeklyKm: 18,
      longestKm: 7,
      count: 10,
    ).where((c) => c.id != 'personal').map((c) => c.id).toList();

    expect(draw(DateTime(2026, 10, 5, 0, 1)), isNot(draw(day)));
  });

  test('one slot is personalized from the competitor history', () {
    final light = drawDailyChallenges(
      username: 'marina',
      date: day,
      weeklyKm: 0,
      longestKm: 0,
    ).last;
    final heavy = drawDailyChallenges(
      username: 'marina',
      date: day,
      weeklyKm: 140,
      longestKm: 20,
    ).last;
    expect(light.id, 'personal');
    expect(light.target, 3);
    expect(heavy.id, 'personal');
    expect(heavy.target, 15);
  });

  test('summarizeDay aggregates only the runs of the day', () {
    final runs = [
      {
        'started_at': DateTime(2026, 10, 4, 7, 30).toUtc().toIso8601String(),
        'distance_m': 5000,
        'duration_seconds': 1500,
      },
      {
        'started_at': DateTime(2026, 10, 4, 20, 15).toUtc().toIso8601String(),
        'distance_m': 3000,
        'duration_seconds': 1080,
      },
      {
        'started_at': DateTime(2026, 10, 3, 10, 0).toUtc().toIso8601String(),
        'distance_m': 8000,
        'duration_seconds': 2400,
      },
    ];
    final summary = summarizeDay(runs, DateTime(2026, 10, 4));
    expect(summary.count, 2);
    expect(summary.startHours, [7, 20]);
    expect(summary.distanceKm, closeTo(8, 1e-9));
    expect(summary.minutes, closeTo(43, 1e-9));
    expect(summary.fastestPaceMinKm, closeTo(5, 1e-9));
  });

  test('measures every challenge kind against the day summary', () {
    final summary = summarizeDay([
      {
        'started_at': DateTime(2026, 10, 4, 7, 30).toUtc().toIso8601String(),
        'distance_m': 5000,
        'duration_seconds': 1500,
      },
      {
        'started_at': DateTime(2026, 10, 4, 20, 15).toUtc().toIso8601String(),
        'distance_m': 3000,
        'duration_seconds': 1080,
      },
    ], DateTime(2026, 10, 4));

    DailyChallenge ch(String kind, num target) => DailyChallenge(
      id: 't',
      title: '',
      detail: '',
      unit: '',
      target: target,
      rarity: 'comum',
      kind: kind,
    );

    expect(measure(ch('count', 2), summary).done, isTrue);
    expect(measure(ch('count', 3), summary).done, isFalse);
    expect(measure(ch('distance', 8), summary).done, isTrue);
    expect(measure(ch('distance', 9), summary).done, isFalse);
    expect(measure(ch('duration', 40), summary).done, isTrue);
    expect(measure(ch('duration', 44), summary).done, isFalse);
    expect(measure(ch('dawn', 1), summary).done, isTrue);
    expect(measure(ch('night', 1), summary).done, isTrue);
    expect(measure(ch('pace', 6), summary).done, isTrue);
    expect(measure(ch('pace', 4), summary).done, isFalse);
  });

  test('counts down to the next local midnight', () {
    expect(timeUntilMidnight(DateTime(2026, 10, 4, 22, 0)), '2h 0min');
    expect(timeUntilMidnight(DateTime(2026, 10, 4, 23, 59)), '1min');
    expect(dayKey(DateTime(2026, 1, 5)), '2026-01-05');
  });

  test('pace ignores GPS-noise stubs below one lap', () {
    // 50 m em 15 s dariam 5 min/km — ritmo "épico" sem correr de verdade.
    final summary = summarizeDay([
      {
        'started_at': DateTime(2026, 10, 4, 7, 30).toUtc().toIso8601String(),
        'distance_m': 50,
        'duration_seconds': 15,
      },
    ], DateTime(2026, 10, 4));
    expect(summary.fastestPaceMinKm, isNull);
  });

  test('draw with no slots returns empty instead of throwing', () {
    expect(
      drawDailyChallenges(
        username: 'marina',
        date: DateTime(2026, 10, 4),
        weeklyKm: 10,
        longestKm: 5,
        count: 0,
      ),
      isEmpty,
    );
  });
}
