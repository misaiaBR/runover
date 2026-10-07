import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:provider/provider.dart';

import '../models.dart';
import '../services/api_client.dart';
import '../services/map_cache.dart';
import '../services/position_refiner.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/crown_icon.dart';
import '../widgets/location_gate.dart';
import '../widgets/territory_style.dart';
import 'notifications_screen.dart';
import 'tracking_screen.dart';

/// RF06/RF07 — mapa interativo com os territórios e seus donos.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _mapController = MapController();
  final _positionRefiner = PositionRefiner();
  List<Territory> _territories = [];
  List<WildSpawn> _wild = [];
  ll.LatLng? _myLocation;
  bool _loading = false;
  bool _locating = false;
  double? _locationAccuracy;
  String? _locationError;
  String? _error;
  bool _needsLocationGate = false;

  static final _defaultCenter = ll.LatLng(-23.6489, -46.8523); // Embu das Artes

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading || _locating) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = context.read<AppState>();
      final api = state.api;
      final pendingRuns = state.retryPendingRuns().catchError(
        (Object _) => false,
      );
      // Estágio 1: pinta na hora com o cache; sem cache, mantém o spinner.
      // Fire-and-forget de propósito: leitura de prefs nunca pode segurar
      // o carregamento (em testes, sem mock, ela nem resolve).
      unawaited(
        MapCache.load().then((cached) {
          if (!mounted || cached == null || cached.isEmpty) return;
          setState(() {
            _territories = cached;
            _loading = false;
          });
          _moveToCached(cached);
        }).catchError((Object _) {}),
      );
      // Estágio 2: territórios frescos e GPS em paralelo, cada um
      // pintando ao chegar — nada espera o outro.
      // TEMP BISECT
      //unawaited_begin
      unawaited(
        api.listTerritories().then((fresh) async {
          if (!mounted) return;
          setState(() => _territories = fresh);
          try {
            await MapCache.save(fresh);
          } catch (_) {}
        }).catchError((Object _) {}),
      );
      final pos = await _resolveLocation();
      final wild = await api
          .wildSpawns(
            pos?.latitude ?? _defaultCenter.latitude,
            pos?.longitude ?? _defaultCenter.longitude,
          )
          .catchError((Object _) => <WildSpawn>[]);
      if (pos != null) {
        unawaited(
          api
              .pingLocation(pos.latitude, pos.longitude)
              .catchError((Object _) {}),
        );
      }
      if (!mounted) return; // RF14/RNF20
      setState(() {
        _wild = wild;
        _myLocation = pos;
        _loading = false;
      });
      // O FlutterMap só existe na árvore depois que _loading vira false acima —
      // mover a câmera antes disso derruba o MapController ("not attached yet").
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (pos != null) {
          _mapController.move(pos, 16);
        } else if (_territories.isNotEmpty) {
          final c = _territories.first.center;
          _mapController.move(ll.LatLng(c.lat, c.lng), 16);
        }
      });
      unawaited(
        pendingRuns.then((submitted) async {
          if (!submitted || !mounted) return;
          try {
            final updatedTerritories = await api.listTerritories();
            if (mounted) {
              setState(() => _territories = updatedTerritories);
            }
          } catch (_) {}
        }),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  void _moveToCached(List<Territory> cached) {
    // Câmera imediata no cache; o GPS reposiciona ao chegar.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final c = cached.first.center;
      try {
        _mapController.move(ll.LatLng(c.lat, c.lng), 16);
      } catch (_) {}
    });
  }

  Future<ll.LatLng?> _resolveLocation() async {
    _locationAccuracy = null;
    _locationError = null;
    _needsLocationGate = false;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _needsLocationGate = true;
        throw ApiException(
          'Ative a localização do dispositivo e tente novamente.',
        );
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _needsLocationGate = true;
        throw ApiException(
          'Permita o acesso à localização nas configurações do navegador ou do aparelho.',
        );
      }
      var pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!pos.latitude.isFinite ||
          !pos.longitude.isFinite ||
          pos.latitude.abs() > 90 ||
          pos.longitude.abs() > 180) {
        throw ApiException(
          'O dispositivo não informou uma localização válida.',
        );
      }
      if (DateTime.now().difference(pos.timestamp) >
          const Duration(minutes: 2)) {
        throw ApiException(
          'A posição recebida está desatualizada. Tente localizar novamente.',
        );
      }
      if (!mounted) return null;
      pos = await _positionRefiner.refine(pos);
      if (pos.accuracy.isFinite && pos.accuracy > 0) {
        _locationAccuracy = pos.accuracy;
      }
      return ll.LatLng(pos.latitude, pos.longitude);
    } on TimeoutException {
      _locationError = 'A localização demorou para responder. Tente novamente.';
    } on ApiException catch (e) {
      _locationError = e.message;
    } catch (_) {
      _locationError =
          'Não foi possível obter sua localização. Verifique a permissão e tente novamente.';
    }
    return null;
  }

  Future<void> _locate() async {
    if (_locating || _loading) return;
    setState(() => _locating = true);
    final pos = await _resolveLocation();
    if (!mounted) return;
    setState(() {
      _myLocation = pos;
      _locating = false;
    });
    if (pos != null) {
      _mapController.move(pos, 16);
      unawaited(
        context
            .read<AppState>()
            .api
            .pingLocation(pos.latitude, pos.longitude)
            .catchError((Object _) {}),
      );
    }
  }

  String get _locationLabel {
    if (_locating) return 'Buscando sua localização…';
    if (_locationError != null) return _locationError!;
    final accuracy = _locationAccuracy;
    if (accuracy == null) {
      return 'Localização estimada. O dispositivo não informou a precisão.';
    }
    final margin = accuracy >= 1000
        ? '${(accuracy / 1000).toStringAsFixed(1)} km'
        : '${accuracy.ceil()} m';
    if (accuracy > 50) {
      return 'Localização aproximada: margem informada de $margin. '
          'Para maior precisão, use o celular com GPS.';
    }
    return 'Localização estimada: margem informada de $margin.';
  }

  Color _statusColor(Territory t, String? myUsername, String? myTeamName) =>
      territoryColor(t, myUsername: myUsername, myTeamName: myTeamName);

  void _openDetail(Territory t) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _TerritorySheet(territory: t),
    );
  }

  void _openWildDetail(WildSpawn w) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _WildSheet(spawn: w),
    );
  }

  Future<void> _startRun() async {
    final conquered = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const TrackingScreen()));
    if (conquered == true) _load();
  }

  @override
  void dispose() {
    _positionRefiner.dispose();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AppState>().profile;
    final heatCircles = [
      for (final t in _territories)
        if (disputeHeat(t, _territories) case final heat when heat > 0)
          for (final (scale, alpha) in const [
            (1.7, 0.06),
            (1.3, 0.10),
            (1.0, 0.14),
          ])
            CircleMarker(
              point: ll.LatLng(t.center.lat, t.center.lng),
              radius: t.radiusM * scale,
              useRadiusInMeter: true,
              color: heatColor(heat).withValues(alpha: alpha),
            ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('RUNOVER!'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            ),
          ),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: RunoverColors.route),
            )
          : _error != null
          ? Center(child: Text(_error!))
          : Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _myLocation ?? _defaultCenter,
                    initialZoom: 16,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.runover.app',
                    ),
                    if (heatCircles.isNotEmpty)
                      CircleLayer(circles: heatCircles),
                    PolygonLayer(
                      polygons: [
                        for (final t in _territories)
                          Polygon(
                            points: t.coordinates
                                .map((p) => ll.LatLng(p.lat, p.lng))
                                .toList(),
                            color: _statusColor(
                              t,
                              profile?.username,
                              profile?.teamName,
                            ).withValues(alpha: 0.12),
                            borderColor: _statusColor(
                              t,
                              profile?.username,
                              profile?.teamName,
                            ),
                            borderStrokeWidth: 3,
                          ),
                      ],
                    ),
                    if (_myLocation != null && _locationAccuracy != null)
                      CircleLayer(
                        circles: [
                          CircleMarker(
                            point: _myLocation!,
                            radius: _locationAccuracy!,
                            useRadiusInMeter: true,
                            color: Colors.blue.withValues(alpha: 0.12),
                            borderColor: Colors.blue.withValues(alpha: 0.45),
                            borderStrokeWidth: 1,
                          ),
                        ],
                      ),
                    MarkerLayer(
                      markers: [
                        for (final t in _territories)
                          Marker(
                            point: ll.LatLng(t.center.lat, t.center.lng),
                            width: 36,
                            height: 36,
                            child: GestureDetector(
                              onTap: () => _openDetail(t),
                              child: CrownIcon(
                                color: _statusColor(
                                  t,
                                  profile?.username,
                                  profile?.teamName,
                                ),
                              ),
                            ),
                          ),
                        for (final w in _wild)
                          Marker(
                            point: ll.LatLng(w.center.lat, w.center.lng),
                            width: 36,
                            height: 36,
                            child: GestureDetector(
                              onTap: () => _openWildDetail(w),
                              child: _WildIcon(rarity: w.rarity),
                            ),
                          ),
                        if (_myLocation != null)
                          Marker(
                            point: _myLocation!,
                            width: 22,
                            height: 22,
                            child: const DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.blue,
                                shape: BoxShape.circle,
                                border: Border.fromBorderSide(
                                  BorderSide(color: Colors.white, width: 3),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                const Positioned(left: 12, bottom: 24, child: _HeatLegend()),
                if (_needsLocationGate && _myLocation == null)
                  Positioned.fill(
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: LocationGate(onGranted: _locate),
                      ),
                    ),
                  ),
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: SafeArea(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                        child: Row(
                          children: [
                            Expanded(child: Text(_locationLabel)),
                            if (_locating)
                              const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            else
                              IconButton(
                                tooltip: 'Atualizar localização',
                                onPressed: _locate,
                                icon: const Icon(Icons.my_location),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _startRun,
        icon: const Icon(Icons.play_arrow),
        label: const Text('Iniciar corrida'),
        backgroundColor: RunoverColors.route,
      ),
    );
  }
}

class _HeatLegend extends StatelessWidget {
  const _HeatLegend();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Disputa', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            Container(
              width: 112,
              height: 8,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                gradient: LinearGradient(
                  colors: [heatColor(0), heatColor(0.5), heatColor(1)],
                ),
              ),
            ),
            const SizedBox(height: 2),
            SizedBox(
              width: 112,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('baixa', style: Theme.of(context).textTheme.labelSmall),
                  Text('alta', style: Theme.of(context).textTheme.labelSmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TerritorySheet extends StatefulWidget {
  final Territory territory;

  const _TerritorySheet({required this.territory});

  @override
  State<_TerritorySheet> createState() => _TerritorySheetState();
}

class _TerritorySheetState extends State<_TerritorySheet> {
  TerritoryDetail? _detail;

  @override
  void initState() {
    super.initState();
    if (!widget.territory.isFree) _loadDetail();
  }

  Future<void> _loadDetail() async {
    try {
      final detail = await context.read<AppState>().api.getTerritory(
        widget.territory.id,
      );
      if (mounted) setState(() => _detail = detail);
    } on ApiException {
      // A ficha abre com os dados da lista se o detalhe falhar.
    }
  }

  static String _date(DateTime d) {
    final local = d.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year}';
  }

  String _paceLabel(int secondsPerKm) =>
      '${secondsPerKm ~/ 60}:${(secondsPerKm % 60).toString().padLeft(2, '0')} min';

  String _durationLabel(int seconds) => '${seconds ~/ 60}min ${seconds % 60}s';

  @override
  Widget build(BuildContext context) {
    final territory = widget.territory;
    final muted = TextStyle(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    final history = _detail?.history ?? const <OwnerHistoryEntry>[];
    final detail = _detail;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(territory.name, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                territory.isFree ? Icons.flag_outlined : Icons.emoji_events,
                color: territory.isFree ? Colors.grey : RunoverColors.route,
                size: 18,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  territory.isFree
                      ? 'Território disponível'
                      : territory.isOwnedByTeam
                      ? 'Dominado pela equipe ${territory.ownerDisplay}'
                      : 'Dominado por @${territory.ownerDisplay}',
                ),
              ),
            ],
          ),
          if (_detail?.conquestAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Desde ${_date(_detail!.conquestAt!)}', style: muted),
            ),
          const SizedBox(height: 4),
          Text(
            'Tamanho aproximado: ~${territory.radiusM.toStringAsFixed(0)}m de raio',
            style: muted,
          ),
          if (detail != null &&
              detail.ownerPaceSecondsPerKm != null &&
              detail.ownerDistanceM != null &&
              detail.ownerDurationSeconds != null) ...[
            const SizedBox(height: 8),
            Text(
              'Marcas a bater: ritmo mais rápido que '
              '${_paceLabel(detail.ownerPaceSecondsPerKm!)}/km, ou mais de '
              '${(detail.ownerDistanceM! / 1000).toStringAsFixed(2)} km em até '
              '${_durationLabel(detail.ownerDurationSeconds!)}.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
          ],
          if (history.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Histórico de donos',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            for (final h in history.take(5))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(Icons.history, size: 16, color: muted.color),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        h.ownerType == 'team'
                            ? 'Equipe ${h.ownerDisplay}'
                            : '@${h.ownerDisplay}',
                      ),
                    ),
                    Text(_date(h.conqueredAt), style: muted),
                  ],
                ),
              ),
            if (history.length > 5)
              Text('e mais ${history.length - 5} antes', style: muted),
          ],
          const SizedBox(height: 12),
          Text(
            territory.isFree
                ? 'Para dominar essa área, corra até ela e feche um laço passando por dentro — '
                      'igual no Strava, ao voltar pro ponto de partida o percurso vira seu.'
                : 'Corra até a área, feche um laço por dentro e vença uma das marcas '
                      'acima no desafio escolhido antes de correr.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _WildIcon extends StatelessWidget {
  final String rarity;

  const _WildIcon({required this.rarity});

  @override
  Widget build(BuildContext context) {
    final color = switch (rarity) {
      'épico' => Colors.purple,
      'raro' => Colors.blue,
      _ => Colors.green,
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.9),
        shape: BoxShape.circle,
        border: const Border.fromBorderSide(
          BorderSide(color: Colors.white, width: 2),
        ),
      ),
      child: const Center(
        child: Text(
          '?',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
    );
  }
}

class _WildSheet extends StatelessWidget {
  final WildSpawn spawn;

  const _WildSheet({required this.spawn});

  String _remaining() {
    final left = spawn.expiresAt.difference(DateTime.now());
    if (left.isNegative) return 'sumindo…';
    if (left.inHours >= 1) return '${left.inHours}h ${left.inMinutes % 60}min';
    return '${left.inMinutes}min';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Território selvagem (${spawn.rarity})',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Some em ${_remaining()} — corra até lá e feche um laço por dentro para ficar com a área.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tamanho aproximado: ~${spawn.radiusM.toStringAsFixed(0)}m de raio',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
