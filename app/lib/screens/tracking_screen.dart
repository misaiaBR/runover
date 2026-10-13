import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:provider/provider.dart';

import '../models.dart';
import '../services/run_store.dart';
import '../services/run_sync.dart';
import '../services/api_client.dart';
import '../services/position_refiner.dart';
import '../services/territory_loop.dart';
import '../state/app_state.dart';
import '../widgets/play_mode_sheet.dart';
import '../widgets/runover_ui.dart';
import '../widgets/territory_style.dart';
import 'run_detail_screen.dart';
import 'tracking_route_processor.dart';

/// Resumo legível do log de pausas com motivo.
String _pauseSummary(List<Map<String, String>> pauses) {
  String label(String reason) => switch (reason) {
    'gps' => 'GPS',
    'app' => 'app',
    'limite' => 'limite',
    _ => 'manual',
  };
  String time(String iso) {
    final at = DateTime.tryParse(iso)?.toLocal();
    if (at == null) return '';
    final hh = at.hour.toString().padLeft(2, '0');
    final mm = at.minute.toString().padLeft(2, '0');
    return ' $hh:$mm';
  }

  final parts = pauses.map(
    (p) => '${label(p['reason'] ?? '')}${time(p['at'] ?? '')}',
  );
  return 'Pausas (${pauses.length}): ${parts.join(' · ')}';
}

class TrackingScreen extends StatefulWidget {
  final String? draftId;

  /// Território selvagem escolhido no mapa: vira o alvo visível da corrida.
  final WildSpawn? target;

  /// Mecânica escolhida no "Como quer jogar?". As três são conquista, então
  /// escolher uma delas liga o alternador — a folha promete um território.
  final PlayMode? mode;

  /// Território dominado escolhido em "Desafiar dono": vai ao servidor como
  /// alvo declarado, que só aceita o desafio se o laço passar por dentro dele.
  final Territory? challengeTarget;
  const TrackingScreen({
    super.key,
    this.draftId,
    this.target,
    this.mode,
    this.challengeTarget,
  });
  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen>
    with WidgetsBindingObserver {
  RunDraft? _draft;
  RunStore? _store;
  StreamSubscription<Position>? _subscription;
  final _refiner = PositionRefiner();
  bool _recording = false;
  bool _busy = false;
  bool _starting = false;
  String? _message;
  bool _permissionBlocked = false;
  TeamDetail? _team;
  List<Territory> _territories = [];
  final Set<String> _contested = {};
  List<TerritoryDetail>? _nearbyMarks;
  bool _loadingMarks = false;

  /// O toque em "Desafiar este território" não pegou: havia corrida em
  /// andamento neste aparelho, e o alvo não foi aplicado a ela.
  bool _challengeDeclined = false;
  final _mapController = MapController();
  bool _mapReady = false;
  final _name = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  Future<void> _initialize() async {
    final state = context.read<AppState>();
    state.pingPresence();
    _store = RunStore(state.profile!.id);
    try {
      final drafts = await _store!.list();
      if (!mounted) return;
      final matches = drafts.where(
        (d) => widget.draftId != null ? d.id == widget.draftId : !d.queued,
      );
      final restored = matches.isNotEmpty;
      _draft = restored ? matches.first : RunDraft.create();
      // As três mecânicas do "Como quer jogar?" são conquista: escolhido "Laço
      // livre", o alternador começa ligado (e continua podendo desfazer). Sem
      // isso a folha promete um território que a corrida nem tenta fechar.
      if (!restored &&
          conquestIntended(
            mode: widget.mode,
            target: widget.target,
            challengeTarget: widget.challengeTarget,
          )) {
        _draft!.conquer = true;
      }
      if (!restored) {
        _draft!.targetTerritoryId = widget.challengeTarget?.id;
      } else if (widget.challengeTarget != null && _draft!.track.isEmpty) {
        // Rascunho sem nenhum ponto é o mesmo que corrida nova: o alvo escolhido
        // no mapa vale.
        _draft!
          ..targetTerritoryId = widget.challengeTarget!.id
          ..conquer = true;
      } else if (widget.challengeTarget != null) {
        // Trajeto em andamento não adota alvo: a pessoa estaria declarando
        // desafio contra um território que não percorreu. A tela avisa em vez de
        // deixar o toque sem consequência.
        _challengeDeclined = true;
      }
      _name.text = _draft!.name;
      if (restored) await _store!.save(_draft!);
      if (!mounted) return;
      final track = _draft!.track;
      if (track.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_mapReady) return;
          _mapController.move(
            ll.LatLng(track.last['lat'], track.last['lng']),
            _mapController.camera.zoom,
          );
        });
      }
      setState(() {
        _message = _challengeDeclined
            ? 'Você tem uma corrida em andamento neste aparelho: o desafio '
                  'escolhido não foi aplicado a ela. Salve o percurso antes de '
                  'desafiar.'
            : restored
            ? 'Corrida recuperada. Continue ou salve o percurso já registrado.'
            : 'Toque em Iniciar para registrar seu percurso.';
      });
      try {
        final team = await state.api.getMyTeam();
        if (mounted) setState(() => _team = team);
      } catch (_) {
        /* Running individually also works when team lookup fails. */
      }
      try {
        final territories = await state.api.listTerritories();
        if (!mounted) return;
        setState(() {
          _territories = territories;
          for (final p in _draft?.track ?? const <Map<String, dynamic>>[]) {
            _markContested(p);
          }
        });
      } catch (_) {
        /* Territory lines are optional while running. */
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'Não foi possível abrir o armazenamento local. Tente novamente antes de correr.',
        );
      }
    }
  }

  Future<void> _openSettings() async {
    try {
      final opened = await Geolocator.openAppSettings();
      if (!opened && mounted) {
        setState(
          () => _message =
              'Não foi possível abrir os ajustes. Libere a localização manualmente e tente de novo.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'Não foi possível abrir os ajustes. Libere a localização manualmente e tente de novo.',
        );
      }
    }
  }

  Future<void> _start() async {
    if (_starting || _recording || _draft == null || _draft!.queued) return;
    setState(() => _starting = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw ApiException(
          'Sem sinal de GPS. Ative a localização no emulador ou no aparelho e tente novamente.',
        );
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _permissionBlocked = true;
        throw ApiException(
          'Permita o acesso à localização para registrar a corrida.',
        );
      }
      if (!mounted) return;
      _draft!.beginSegment();
      await _store!.save(_draft!);
      if (!mounted) return;
      setState(() {
        _recording = true;
        _message = null;
        _permissionBlocked = false;
      });
      _subscription =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.bestForNavigation,
              distanceFilter: 2,
            ),
          ).listen(
            _onPosition,
            onError: (Object _) {
              if (_recording) {
                _pause('gps');
              }
              if (mounted) {
                setState(
                  () => _message =
                      'O GPS foi interrompido. Seu percurso está salvo; tente continuar.',
                );
              }
            },
          );
    } catch (e) {
      if (mounted) {
        setState(
          () => _message = e is ApiException
              ? e.message
              : 'Não foi possível iniciar o GPS.',
        );
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  void _onPosition(Position position) {
    if (!_recording || !mounted) return;
    final d = _draft!;
    if (d.track.length >= 10000) {
      _pause('limite');
      setState(
        () => _message = 'Limite de pontos atingido. Salve esta corrida.',
      );
      return;
    }
    if (position.accuracy > 50 ||
        !position.latitude.isFinite ||
        !position.longitude.isFinite) {
      return;
    }
    if (d.track.isNotEmpty &&
        !position.timestamp.isAfter(
          DateTime.parse(d.track.last['timestamp']),
        )) {
      return;
    }
    final candidate = {
      'lat': position.latitude,
      'lng': position.longitude,
      'timestamp': position.timestamp.toUtc().toIso8601String(),
      'segment': d.segment,
      'accuracy': position.accuracy,
    };
    if (!TrackingScreenRouteProcessor.isUsablePoint(
      candidate,
      accuracyMeters: 50,
    )) {
      return;
    }
    setState(() {
      final previous = d.track.isEmpty ? null : d.track.last;
      if (previous != null) {
        final previousTime = DateTime.tryParse(previous['timestamp'] as String);
        final currentTime = DateTime.tryParse(candidate['timestamp'] as String);
        if (previousTime != null &&
            currentTime != null &&
            currentTime.isAfter(previousTime)) {
          final distance = Geolocator.distanceBetween(
            (previous['lat'] as num).toDouble(),
            (previous['lng'] as num).toDouble(),
            (candidate['lat'] as num).toDouble(),
            (candidate['lng'] as num).toDouble(),
          );
          final elapsed = currentTime.difference(previousTime).inSeconds;
          if (elapsed > 0 && distance > 250 && elapsed <= 5) {
            return;
          }
        }
      }
      d.track.add(candidate);
      _markContested(candidate);
    });
    if (_mapReady) {
      _mapController.move(
        ll.LatLng(position.latitude, position.longitude),
        _mapController.camera.zoom,
      );
    }
    if (d.track.length % 10 == 0) _persist();
  }

  bool _isRival(Territory t) {
    final profile = context.read<AppState>().profile;
    return isRivalTerritory(
      t,
      myUsername: profile?.username,
      myTeamName: profile?.teamName,
    );
  }

  void _markContested(Map<String, dynamic> point) {
    final lat = (point['lat'] as num).toDouble();
    final lng = (point['lng'] as num).toDouble();
    for (final t in _territories) {
      if (_contested.contains(t.id) || !_isRival(t)) continue;
      if (polygonContains(t.coordinates, lat, lng)) _contested.add(t.id);
    }
  }

  /// Distância até o território selvagem escolhido no mapa, em linha reta a
  /// partir do último ponto. Sem alvo não há nada a dizer.
  String? _targetHint(List<Map<String, dynamic>> track) {
    final target = widget.target;
    if (target == null) {
      // O alvo declarado do desafio tem de aparecer na corrida: é ele que o
      // servidor cobra, e fechar o laço em outro lugar não toma território.
      final challenged = widget.challengeTarget;
      // O aviso fala do desafio que a corrida realmente carrega, não do toque
      // que a pessoa fez: com trajeto em andamento o alvo não foi aplicado.
      if (challenged == null || _draft?.targetTerritoryId != challenged.id) {
        return null;
      }
      return 'Desafio declarado: ${challenged.name}. Feche o laço passando por '
          'dentro dele — fora do território escolhido a conquista não vale.';
    }
    if (track.isEmpty) {
      return 'Rumo ao território selvagem: comece a correr até a área marcada.';
    }
    final last = track.last;
    final distance = Geolocator.distanceBetween(
      (last['lat'] as num).toDouble(),
      (last['lng'] as num).toDouble(),
      target.center.lat,
      target.center.lng,
    );
    if (distance <= target.radiusM) {
      return 'Você está na área do território selvagem — feche o laço.';
    }
    final left = target.expiresAt.difference(DateTime.now());
    final remaining = distance >= 1000
        ? '${(distance / 1000).toStringAsFixed(1)} km'
        : '~${distance.toStringAsFixed(0)} m';
    final expiry = left.isNegative
        ? 'sumindo'
        : 'some em ${left.inMinutes > 0 ? '${left.inMinutes}min' : '<1min'}';
    return 'Faltam $remaining até o território selvagem ($expiry).';
  }

  Future<void> _loadNearbyMarks() async {
    if (_loadingMarks) return;
    final api = context.read<AppState>().api;
    setState(() {
      _loadingMarks = true;
      _nearbyMarks = null;
    });
    try {
      final raw = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 15),
        ),
      );
      final pos = await _refiner.refine(raw);
      final nearby = await api.nearbyTerritories(pos.latitude, pos.longitude);
      final rivals = nearby.where(_isRival).toList()
        ..sort(
          (a, b) =>
              Geolocator.distanceBetween(
                pos.latitude,
                pos.longitude,
                a.center.lat,
                a.center.lng,
              ).compareTo(
                Geolocator.distanceBetween(
                  pos.latitude,
                  pos.longitude,
                  b.center.lat,
                  b.center.lng,
                ),
              ),
        );
      final details = <TerritoryDetail>[];
      for (final t in rivals.take(3)) {
        details.add(await api.getTerritory(t.id));
      }
      if (mounted) {
        setState(() {
          _nearbyMarks = details;
          _loadingMarks = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingMarks = false);
    }
  }

  String? get _disputeLabel {
    final rivals = _territories.where((t) => _contested.contains(t.id));
    if (rivals.isEmpty) return null;
    final owners = {
      for (final t in rivals)
        t.isOwnedByTeam ? 'equipe ${t.ownerDisplay}' : '@${t.ownerDisplay}',
    };
    return owners.length == 1
        ? 'Em disputa com ${owners.first}'
        : 'Em disputa com ${owners.length} rivais';
  }

  Future<void> _persist() async {
    if (_draft == null || _store == null || _draft!.queued) return;
    try {
      final sanitized = TrackingScreenRouteProcessor.filterTrack(_draft!.track);
      if (sanitized.length != _draft!.track.length) {
        _draft!.track.clear();
        _draft!.track.addAll(sanitized);
      }
      await _store!.save(_draft!);
    } catch (_) {
      _recording = false;
      await _subscription?.cancel();
      if (mounted) {
        setState(
          () => _message =
              'Falha ao salvar no aparelho. Libere espaço antes de continuar.',
        );
      }
    }
  }

  Future<void> _pause([String reason = 'manual']) async {    _recording = false;
    _draft?.logPause(reason);
    await _subscription?.cancel();
    _subscription = null;
    await _persist();
    if (mounted) setState(() {});
  }

  /// Pausa pedida no botão com conquista ligada: a pausa em si não custa o
  /// território, mas sair do lugar enquanto está pausado sim.
  Future<void> _pauseWithWarning() async {
    final draft = _draft;
    if (draft == null || !draft.conquer || draft.track.isEmpty) {
      await _pause();
      return;
    }
    final pause = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pausar corrida?'),
        content: const Text(
          'Pausar não quebra o território, desde que você retome onde parou. '
          'Se se deslocar durante a pausa, o traçado deixa de ser contínuo e '
          'a conquista não vale.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Continuar correndo'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Pausar mesmo assim'),
          ),
        ],
      ),
    );
    if (pause == true) await _pause();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_recording || !mounted) return;
    if (state == AppLifecycleState.detached) {
      _pause('app');
      if (mounted) {
        setState(
          () => _message =
              'Corrida pausada ao sair do aplicativo. Toque em Continuar ao voltar.',
        );
      }
    }
  }

  Future<void> _finish() async {
    if (_draft == null || _busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await _pause();
      final draft = _draft!;
      if (!draft.queued) {
        draft.name = _name.text.trim();
      }
      if (!mounted) return;
      final state = context.read<AppState>();
      final result = await RunSync(state.api, _store!).submit(draft);
      state.markRunSaved();
      try {
        await state.refreshProfile();
      } catch (_) {
        /* Upload already succeeded. */
      }
      if (!mounted) return;
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => RunDetailScreen(run: result)));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(
          () => _message =
              '${e is ApiException ? e.message : 'Não foi possível concluir o envio.'}\nA corrida permanece neste aparelho, na aba Corridas.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _persistOnDispose() async {
    final draft = _draft;
    if (draft == null || _store == null || draft.queued) return;
    try {
      draft.name = _name.text.trim();
      final sanitized = TrackingScreenRouteProcessor.filterTrack(draft.track);
      if (sanitized.length != draft.track.length) {
        draft.track.clear();
        draft.track.addAll(sanitized);
      }
      await _store!.save(draft);
    } catch (_) {
      // Disposal must not fail or interrupt teardown.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refiner.dispose();
    _recording = false;
    _subscription?.cancel();
    unawaited(_persistOnDispose());
    _mapController.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = _draft;
    final track = d?.track ?? [];
    double meters = 0;
    int seconds = 0;
    final lastAccuracy = track.isNotEmpty
        ? (track.last['accuracy'] as num?)?.toDouble()
        : null;
    final loop = TerritoryLoop.fromTrack(track);
    for (var i = 1; i < track.length; i++) {
      final a = track[i - 1], b = track[i];
      if (a['segment'] != b['segment']) continue;
      meters += Geolocator.distanceBetween(
        a['lat'],
        a['lng'],
        b['lat'],
        b['lng'],
      );
      seconds += DateTime.parse(
        b['timestamp'],
      ).difference(DateTime.parse(a['timestamp'])).inSeconds;
    }
    final groups = <int, List<ll.LatLng>>{};
    for (final p in track) {
      groups
          .putIfAbsent(p['segment'] as int, () => [])
          .add(ll.LatLng(p['lat'], p['lng']));
    }
    final last = track.isEmpty
        ? const ll.LatLng(-23.6489, -46.8523)
        : ll.LatLng(track.last['lat'], track.last['lng']);
    final target = widget.target;
    final targetCenter = target == null
        ? null
        : ll.LatLng(target.center.lat, target.center.lng);
    final canEdit = d != null && !d.queued && !_busy;
    final profile = context.watch<AppState>().profile;
    final dispute = _disputeLabel;
    return Scaffold(
      appBar: AppBar(
        title: Text(_recording ? 'Corrida em andamento' : 'Sua corrida'),
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: targetCenter ?? last,
                    initialZoom: 16,
                    onMapReady: () => _mapReady = true,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.runover.runover_app',
                    ),
                    if (target != null && targetCenter != null)
                      CircleLayer(
                        circles: [
                          CircleMarker(
                            point: targetCenter,
                            radius: target.radiusM,
                            useRadiusInMeter: true,
                            color: const Color(
                              0xFFF59E0B,
                            ).withValues(alpha: 0.14),
                            borderColor: const Color(0xFFF59E0B),
                            borderStrokeWidth: 2,
                          ),
                        ],
                      ),
                    if (target != null && targetCenter != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: targetCenter,
                            width: 32,
                            height: 32,
                            child: const Icon(
                              Icons.flag_outlined,
                              color: Color(0xFFF59E0B),
                            ),
                          ),
                        ],
                      ),
                    PolygonLayer(
                      polygons: [
                        for (final t in _territories)
                          Polygon(
                            points: t.coordinates
                                .map((p) => ll.LatLng(p.lat, p.lng))
                                .toList(),
                            color:
                                territoryColor(
                                  t,
                                  myUsername: profile?.username,
                                  myTeamName: profile?.teamName,
                                ).withValues(
                                  alpha: _contested.contains(t.id)
                                      ? 0.22
                                      : 0.08,
                                ),
                            borderColor: territoryColor(
                              t,
                              myUsername: profile?.username,
                              myTeamName: profile?.teamName,
                            ),
                            borderStrokeWidth: _contested.contains(t.id)
                                ? 5
                                : 2,
                          ),
                      ],
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
                    if (track.isNotEmpty)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: last,
                            width: 24,
                            height: 24,
                            child: const Icon(
                              Icons.my_location,
                              color: Colors.blue,
                            ),
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
                if (dispute != null)
                  Positioned(
                    top: 12,
                    left: 12,
                    right: 12,
                    child: Card(
                      child: ListTile(
                        leading: const Icon(Icons.flag_outlined),
                        title: Text(dispute),
                      ),
                    ),
                  ),
                if (_targetHint(track) case final hint?)
                  Positioned(
                    top: dispute == null ? 12 : 96,
                    left: 12,
                    right: 12,
                    child: Card(
                      child: ListTile(
                        leading: const Icon(Icons.directions_run),
                        title: Text(hint),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${(meters / 1000).toStringAsFixed(2)} km  •  ${seconds ~/ 60}min ${seconds % 60}s',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      if (meters >= 10)
                        Text(
                          'Ritmo médio: ${((seconds / (meters / 1000)) / 60).toStringAsFixed(1)} min/km',
                        ),
                      if (lastAccuracy != null)
                        Text(
                          PositionRefiner.accuracyLabel(lastAccuracy),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      if (_message != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(_message!, textAlign: TextAlign.center),
                        ),
                      if ((_draft?.pauses.isNotEmpty ?? false))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            _pauseSummary(_draft!.pauses),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      if (d?.conquer ?? false)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                loop.closed
                                    ? Icons.check_circle_outline
                                    : Icons.radio_button_unchecked,
                                size: 18,
                                // Laço fechado: tinta verde do brilho, não o
                                // #22C55E do mock (sobre o fundo claro do
                                // painel ele fica abaixo de 3:1).
                                color: loop.closed
                                    ? Pal.successInk(context)
                                    : Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  loop.label,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (_permissionBlocked && !_recording)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Column(
                            children: [
                              if (!kIsWeb)
                                OutlinedButton.icon(
                                  onPressed: _openSettings,
                                  icon: const Icon(
                                    Icons.settings_outlined,
                                    size: 18,
                                  ),
                                  label: const Text('Abrir configurações'),
                                )
                              else
                                Text(
                                  'Negada no navegador? Chrome: cadeado › Localização › Permitir. Safari no iPhone: Ajustes › Apps › Safari › Localização. Firefox: cadeado › Permissões. Depois toque em começar de novo.',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                            ],
                          ),
                        ),
                      if (track.isEmpty && !_recording && _message == null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'Sem sinal de GPS. Ative a localização no emulador ou no aparelho para registrar a corrida.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      TextField(
                        controller: _name,
                        enabled: canEdit,
                        maxLength: 80,
                        decoration: const InputDecoration(
                          labelText: 'Nome da corrida',
                        ),
                        onChanged: (value) {
                          d!.name = value;
                          _persist();
                        },
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Tentar conquistar território'),
                        subtitle: const Text(
                          'O percurso fica privado. Ao conquistar, a área formada aparece no mapa para os jogadores.',
                        ),
                        value: d?.conquer ?? false,
                        onChanged: canEdit
                            ? (v) {
                                setState(() {
                                  d.conquer = v;
                                  if (!v) _nearbyMarks = null;
                                });
                                _persist();
                                if (v) _loadNearbyMarks();
                              }
                            : null,
                      ),
                      if (d?.conquer ?? false)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(
                              'Desafio de conquista',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                ChoiceChip(
                                  label: const Text('Ritmo'),
                                  selected: (d?.challenge ?? 'pace') == 'pace',
                                  onSelected: canEdit
                                      ? (_) {
                                          setState(() => d.challenge = 'pace');
                                          _persist();
                                        }
                                      : null,
                                ),
                                const SizedBox(width: 8),
                                ChoiceChip(
                                  label: const Text('Distância'),
                                  selected: d?.challenge == 'distance',
                                  onSelected: canEdit
                                      ? (_) {
                                          setState(
                                            () => d.challenge = 'distance',
                                          );
                                          _persist();
                                        }
                                      : null,
                                ),
                              ],
                            ),
                            Text(
                              d?.challenge == 'distance'
                                  ? 'Para tomar: corra mais km que o dono, em tempo igual ou menor.'
                                  : 'Para tomar: feche o laço com ritmo médio mais rápido que o do dono.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            if (_loadingMarks)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Text('Buscando marcas por perto…'),
                                  ],
                                ),
                              ),
                            if (!_loadingMarks &&
                                _nearbyMarks != null &&
                                _nearbyMarks!.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Rivais por perto — vença uma das marcas',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 4),
                              for (final m in _nearbyMarks!)
                                _NearbyMarkTile(detail: m),
                            ],
                            if (!_loadingMarks &&
                                _nearbyMarks != null &&
                                _nearbyMarks!.isEmpty)
                              const Padding(
                                padding: EdgeInsets.only(top: 4),
                                child: Text(
                                  'Nenhum território rival por perto.',
                                ),
                              ),
                          ],
                        ),
                      if (_team != null)
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('Conquistar para ${_team!.name}'),
                          value: d?.teamId != null,
                          onChanged: canEdit
                              ? (v) {
                                  setState(
                                    () => d.teamId = v ? _team!.id : null,
                                  );
                                  _persist();
                                }
                              : null,
                        ),
                      if (canEdit)
                        OutlinedButton.icon(
                           onPressed: _starting
                               ? null
                               : (_recording ? _pauseWithWarning : _start),
                          icon: Icon(
                            _recording ? Icons.pause : Icons.play_arrow,
                          ),
                          label: Text(
                            _recording
                                ? 'Pausar'
                                : track.isEmpty
                                ? 'Iniciar'
                                : 'Continuar',
                          ),
                        ),
                      FilledButton.icon(
                        onPressed: _busy || track.length < 2 ? null : _finish,
                        icon: const Icon(Icons.save_outlined),
                        label: Text(
                          _busy
                              ? 'Salvando…'
                              : d?.queued == true
                              ? 'Tentar enviar novamente'
                              : 'Salvar corrida',
                        ),
                      ),
                      const Text(
                        'Mantenha o app aberto durante a gravação. Envie em até 7 dias.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NearbyMarkTile extends StatelessWidget {
  final TerritoryDetail detail;

  const _NearbyMarkTile({required this.detail});

  String _paceLabel(int secondsPerKm) =>
      '${secondsPerKm ~/ 60}:${(secondsPerKm % 60).toString().padLeft(2, '0')} min';

  String _durationLabel(int seconds) => '${seconds ~/ 60}min ${seconds % 60}s';

  @override
  Widget build(BuildContext context) {
    final pace = detail.ownerPaceSecondsPerKm;
    final distanceM = detail.ownerDistanceM;
    final duration = detail.ownerDurationSeconds;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.emoji_events_outlined, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  detail.isOwnedByTeam
                      ? '${detail.name} • equipe ${detail.ownerDisplay}'
                      : '${detail.name} • @${detail.ownerDisplay}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  pace != null && distanceM != null && duration != null
                      ? 'Ritmo ${_paceLabel(pace)}/km ou ${(distanceM / 1000).toStringAsFixed(2)} km em até ${_durationLabel(duration)}'
                      : 'Sem marca — vale a sobreposição do laço',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
