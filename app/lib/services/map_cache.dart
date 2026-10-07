import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';

/// Cache dos territórios para pintura imediata do mapa
/// (stale-while-revalidate): o mapa abre com os últimos dados e atualiza
/// em segundo plano, sem spinner bloqueando.
class MapCache {
  static const storageKey = 'runover_map_territories';
  static const savedAtKey = 'runover_map_territories_at';

  /// Validade do cache para centralizar a câmera nele.
  static const maxAge = Duration(hours: 6);

  static Future<List<Territory>?> load({
    SharedPreferences? prefs,
    DateTime Function()? now,
  }) async {
    final store = prefs ?? await SharedPreferences.getInstance();
    final raw = store.getString(storageKey);
    final at = store.getInt(savedAtKey);
    if (raw == null || at == null) return null;
    final age = (now ?? DateTime.now)().difference(
      DateTime.fromMillisecondsSinceEpoch(at),
    );
    if (age > maxAge) return null;
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map(
            (e) => Territory.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(
    List<Territory> territories, {
    SharedPreferences? prefs,
  }) async {
    final store = prefs ?? await SharedPreferences.getInstance();
    await store.setString(
      storageKey,
      jsonEncode(
        territories
            .map(
              (t) => {
                'id': t.id,
                'name': t.name,
                'coordinates': [
                  for (final c in t.coordinates)
                    {'lat': c.lat, 'lng': c.lng},
                ],
                'center': {'lat': t.center.lat, 'lng': t.center.lng},
                'radius_m': t.radiusM,
                'status': t.status,
                'owner_type': t.ownerType,
                'owner_display': t.ownerDisplay,
                'takeovers': t.takeovers,
              },
            )
            .toList(),
      ),
    );
    await store.setInt(savedAtKey, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<void> clear({SharedPreferences? prefs}) async {
    final store = prefs ?? await SharedPreferences.getInstance();
    await store.remove(storageKey);
    await store.remove(savedAtKey);
  }
}
