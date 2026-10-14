import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../widgets/centered_content.dart';

class RunDetailScreen extends StatelessWidget {
  final Map<String, dynamic> run;
  const RunDetailScreen({super.key, required this.run});

  /// A caçada tem de aparecer no recibo: o spawn some do mapa para todo mundo
  /// quando o laço o cobre, e sem uma linha dizendo isso o corredor não sabe se
  /// pegou o que foi correr atrás.
  static String _capturedLabel(int captured) => captured == 1
      ? 'Fechou 1 território selvagem.'
      : 'Fechou $captured territórios selvagens.';

  @override
  Widget build(BuildContext context) {
    final track = run['track'] as List? ?? [];
    final groups = <int, List<ll.LatLng>>{};
    for (final p in track) {
      groups
          .putIfAbsent(p['segment'] ?? 0, () => [])
          .add(
            ll.LatLng(
              (p['lat'] as num).toDouble(),
              (p['lng'] as num).toDouble(),
            ),
          );
    }
    final claim = run['claim'];
    final pace = run['pace_seconds_per_km'] as int?;
    final seconds = run['duration_seconds'] as int;
    return Scaffold(
      appBar: AppBar(title: const Text('Resumo da corrida')),
      body: CenteredContent(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
          Text(run['name'], style: Theme.of(context).textTheme.headlineSmall),
          Text(
            DateTime.parse(
              run['started_at'],
            ).toLocal().toString().split('.').first,
          ),
          const SizedBox(height: 12),
          if (track.isNotEmpty)
            SizedBox(
              height: 260,
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: groups.values.first.first,
                  initialZoom: 16,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.runover.runover_app',
                  ),
                  PolylineLayer(
                    polylines: [
                      for (final points in groups.values)
                        Polyline(
                          points: points,
                          color: Colors.deepOrange,
                          strokeWidth: 4,
                        ),
                    ],
                  ),
                  const RichAttributionWidget(
                    attributions: [
                      TextSourceAttribution('OpenStreetMap contributors'),
                    ],
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          Text(
            '${((run['distance_m'] as num) / 1000).toStringAsFixed(2)} km',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          Text('Tempo em trechos ativos: ${seconds ~/ 60}min ${seconds % 60}s'),
          Text(
            pace == null
                ? 'Ritmo indisponível'
                : 'Ritmo médio: ${pace ~/ 60}:${(pace % 60).toString().padLeft(2, '0')} /km',
          ),
          const SizedBox(height: 16),
          if (claim != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      claim['challenge_won'] == false
                          ? 'Desafio perdido — o território segue com ${claim['territory']['owner_display']}'
                          : 'Território conquistado: ${claim['territory']['name']}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (claim['challenge_won'] != null)
                      Text(
                        claim['challenge_won'] == true
                            ? 'Venceu o desafio de ${claim['challenge'] == 'distance' ? 'distância' : 'ritmo'}.'
                            : 'Não venceu a marca do dono no desafio de ${claim['challenge'] == 'distance' ? 'distância' : 'ritmo'}.',
                      ),
                    Text(
                      '+${claim['points_awarded']} pontos • ${(claim['area_m2'] as num).toStringAsFixed(0)} m²',
                    ),
                    if ((claim['spawns_captured'] as int? ?? 0) > 0)
                      Text(_capturedLabel(claim['spawns_captured'] as int)),
                    Text(
                      'Nível ${claim['new_level']}${claim['leveled_up'] == true ? ' — subiu de nível!' : ''}',
                    ),
                  ],
                ),
              ),
            )
          else
            Text(run['claim_error'] ?? 'Corrida registrada sem conquista.'),
          const SizedBox(height: 16),
          const Text(
            'Percurso completo visível somente para você. Veja suas metas e medalhas na aba Corridas.',
          ),
          ],
        ),
      ),
    );
  }
}
