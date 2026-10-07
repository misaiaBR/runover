import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:runover_app/models.dart';
import 'package:runover_app/services/map_cache.dart';

Territory _t(String id) => Territory(
  id: id,
  name: id,
  coordinates: const [
    LatLngPoint(0, 0),
    LatLngPoint(0, 1),
    LatLngPoint(1, 1),
    LatLngPoint(1, 0),
  ],
  center: const LatLngPoint(0.5, 0.5),
  radiusM: 100,
  status: 'disponivel',
  ownerType: null,
  ownerDisplay: null,
  takeovers: 0,
);

void main() {
  test('round-trip preserva territorios', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await MapCache.load(), isNull);
    await MapCache.save([_t('a'), _t('b')]);
    final loaded = await MapCache.load();
    expect(loaded?.map((t) => t.id), ['a', 'b']);
    expect(loaded?.first.center.lat, 0.5);
  });

  test('cache vencido eh ignorado', () async {
    SharedPreferences.setMockInitialValues({});
    await MapCache.save([_t('a')]);
    final loaded = await MapCache.load(
      now: () => DateTime.now().add(const Duration(hours: 7)),
    );
    expect(loaded, isNull);
  });

  test('json corrompido nao quebra', () async {
    SharedPreferences.setMockInitialValues({
      MapCache.storageKey: '[[[',
      MapCache.savedAtKey: DateTime.now().millisecondsSinceEpoch,
    });
    expect(await MapCache.load(), isNull);
  });
}
