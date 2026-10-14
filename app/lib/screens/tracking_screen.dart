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
    'velocidade' => 'veículo',
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

  /// Onde o aparelho está, lido assim que a tela abre. Antes o mapa abria num
  /// ponto fixo e só se mexia quando a gravação começava — a tela não dava
  /// nenhuma prova de que estava vendo o lugar de quem corre.
  ll.LatLng? _here;
  bool _lookingHere = false;

  /// Pares consecutivos acima do teto de corrida. Um só pode ser o GPS errando
  /// uma leitura; dois são movimento de veículo.
  int _fastPairs = 0;

  /// O GPS erra assim: um ponto longe demais, rápido demais, e o próximo volta
  /// para o lugar. Não é deslocamento — é leitura torta.
  bool _looksLikeBadFix(
    Map<String, dynamic> previous,
    Map<String, dynamic> next,
  ) {
    final previousTime = DateTime.tryParse('${previous['timestamp']}');
    final currentTime = DateTime.tryParse('${next['timestamp']}');
    if (previousTime == null || currentTime == null) return false;
    final elapsed = currentTime.difference(previousTime).inSeconds;
    if (elapsed <= 0 || elapsed > 5) return false;
    return Geolocator.distanceBetween(
      (previous['lat'] as num).toDouble(),
      (previous['lng'] as num).toDouble(),
      (next['lat'] as num).toDouble(),
      (next['lng'] as num).toDouble(),
    ) >
        250;
  }
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
      unawaited(_locateHere());
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

  Future<Position?> _firstFixOrNull() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 8),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  /// Joga o percurso fora deste aparelho e deixa a tela pronta para outra corrida.
  /// Num envio congelado o aviso é explícito: a corrida pode já ter chegado ao
  /// servidor, e descartar não desfaz o que foi salvo lá.
  Future<void> _discard() async {
    final draft = _draft;
    final store = _store;
    if (draft == null || store == null || _busy) return;
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Descartar esta corrida?'),
        content: Text(
          draft.queued
              ? 'O último envio pode ter chegado ao servidor — confira na aba '
                    'Corridas antes de apagar. Os ${draft.track.length} pontos '
                    'deste aparelho serão apagados.'
              : draft.track.isEmpty
              ? 'Este percurso ainda não tem pontos gravados.'
              : '${draft.track.length} pontos de GPS serão apagados deste '
                    'aparelho. Corridas já enviadas não são afetadas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Manter'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    _recording = false;
    await _subscription?.cancel();
    _subscription = null;
    try {
      await store.remove(draft.id);
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'Não foi possível apagar o percurso neste aparelho.',
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _draft = RunDraft.create();
      _contested.clear();
      _nearbyMarks = null;
      _challengeDeclined = false;
      _name.clear();
      _message = 'Percurso descartado. Toque em Iniciar para começar outra.';
    });
  }

  /// Lê onde o aparelho está e centraliza o mapa ali. Melhor esforço: sem
  /// permissão ou sem sinal a tela continua funcionando como antes, só não mostra
  /// o ponto — e o Iniciar continua pedindo a permissão com a mensagem própria.
  Future<void> _locateHere() async {
    if (_lookingHere) return;
    setState(() => _lookingHere = true);
    try {
      final raw = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 15),
        ),
      );
      final pos = await _refiner.refine(raw);
      if (!mounted) return;
      setState(() {
        _here = ll.LatLng(pos.latitude, pos.longitude);
        _lookingHere = false;
      });
      if (_mapReady && (_draft?.track.isEmpty ?? true)) {
        _mapController.move(_here!, 16);
      }
    } catch (_) {
      if (mounted) setState(() => _lookingHere = false);
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
      // Começar dentro de um trem não é começar uma corrida. Melhor esforço:
      // sem leitura de velocidade (plataforma não informa, ou o sinal demora), a
      // porta não bloqueia ninguém — o par de pontos durante a gravação continua
      // sendo a regra que vale.
      final first = await _firstFixOrNull();
      if (first != null && first.speed > maxPlausibleSpeedMps) {
        throw ApiException(
          'Você está se movendo rápido demais para começar uma corrida. '
          'Pare, espere alguns segundos e comece de novo.',
        );
      }
      if (!mounted) return;
      _fastPairs = 0;
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
                _stopRecording('gps');
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
      _stopRecording('limite');
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
    // Veículo não é corrida: o servidor recusaria o envio inteiro por causa
    // deste par. Mas o GPS também erra — uma leitura torta isolada não pode
    // parar a corrida de quem está correndo, e era justamente isso que o filtro
    // de salto antigo descartava em silêncio. O que separa os dois é a
    // insistência: um salto fora do lugar é jogado fora, e o segundo par
    // consecutivo acima do teto encerra a gravação. Um deslocamento rápido que
    // não tem cara de leitura torta — trem, ônibus — encerra na primeira vez.
    if (d.track.isNotEmpty &&
        TerritoryLoop.speedMps(d.track.last, candidate) > maxPlausibleSpeedMps) {
      final jumped = _looksLikeBadFix(d.track.last, candidate);
      _fastPairs = jumped ? _fastPairs + 1 : 2;
      if (_fastPairs >= 2) {
        _fastPairs = 0;
        _stopRecording('velocidade');
        setState(
          () => _message =
              'Você está se movendo mais rápido que uma corrida — o registro foi '
              'pausado e este ponto não foi gravado. Estava em veículo? Salve ou '
              'descarte a corrida na aba Corridas antes de continuar a pé.',
        );
      }
      return;
    }
    _fastPairs = 0;
    setState(() {
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

  /// A gravação para por um motivo que a pessoa não escolheu: caiu o GPS, o app
  /// foi para segundo plano, o limite de pontos chegou, o movimento virou de
  /// veículo. O percurso fica no aparelho e o botão passa a ser Continuar.
  ///
  /// Não existe pausar por escolha: uma corrida é contínua do Iniciar ao Salvar,
  /// e a única quebra de traçado que aparece é a que o aparelho detectou.
  Future<void> _stopRecording(String reason) async {
    _recording = false;
    _draft?.logPause(reason);
    await _subscription?.cancel();
    _subscription = null;
    await _persist();
    if (mounted) setState(() {});
  }

  /// Termina a gravação para enviar. Não é pausa, então não entra no resumo:
  /// antes entrava, e uma corrida com dois envios recusados mostrava pausas que
  /// ninguém tinha feito.
  Future<void> _endRecording() async {
    _recording = false;
    await _subscription?.cancel();
    _subscription = null;
    await _persist();
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_recording || !mounted) return;
    if (state == AppLifecycleState.detached) {
      _stopRecording('app');
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
      await _endRecording();
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
    // O pino que aparece no mapa: o último ponto gravado, e enquanto não há
    // nenhum — o lugar onde o aparelho diz que a pessoa está.
    final mePoint = track.isEmpty ? _here : last;
    final target = widget.target;
    final targetCenter = target == null
        ? null
        : ll.LatLng(target.center.lat, target.center.lng);
    final canEdit = d != null && !d.queued && !_busy;
    // Sempre que haja o que jogar fora: um trajeto gravado, ou um envio já
    // congelado. Sem isto a pessoa fica presa nesta tela com uma corrida que o
    // servidor nunca vai aceitar, sem saída a não ser voltar e caçar o percurso
    // na aba Corridas.
    final canDiscard = d != null && !_busy && (track.isNotEmpty || d.queued);
    final profile = context.watch<AppState>().profile;
    final dispute = _disputeLabel;
    return Scaffold(
      appBar: AppBar(
        title: Text(_recording ? 'Corrida em andamento' : 'Sua corrida'),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: targetCenter ?? _here ?? last,
                    initialZoom: 16,
                    onMapReady: () {
                      _mapReady = true;
                      // O mapa nasce pronto antes de a pessoa tocar em qualquer
                      // coisa: se a leitura do local chegou depois do primeiro
                      // quadro, é aqui que ele vai para cima dela.
                      final here = _here;
                      if (here != null && track.isEmpty) {
                        _mapController.move(here, 16);
                      }
                    },
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
                    if (mePoint != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: mePoint,
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
                // Os avisos vivos ficam no topo do mapa, não dentro do painel:
                // é para cima que quem corre olha, e o painel pode estar
                // retraído justo na hora em que a mensagem muda.
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: Column(
                    children: [
                      if (dispute != null)
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.flag_outlined),
                            title: Text(dispute),
                          ),
                        ),
                      if (_targetHint(track) case final hint?)
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.directions_run),
                            title: Text(hint),
                          ),
                        ),
                      if (d?.conquer ?? false)
                        Card(
                          child: ListTile(
                            leading: Icon(
                              loop.closed
                                  ? Icons.check_circle_outline
                                  : Icons.radio_button_unchecked,
                              size: 18,
                              // Laço fechado: tinta verde do brilho, não o
                              // #22C55E do mock (sobre o fundo claro do cartão
                              // ele fica abaixo de 3:1).
                              color: loop.closed
                                  ? Pal.successInk(context)
                                  : Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                            ),
                            title: Text(
                              loop.label,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // Volta ao próprio lugar sem ter de começar a corrida: é o gesto
                // que responde "este mapa está me vendo?" antes do Iniciar.
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: IconButton(
                      onPressed: _lookingHere ? null : _locateHere,
                      tooltip: 'Meu local',
                      icon: const Icon(Icons.my_location),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // O mapa é o fundo da tela inteira e o painel sobe sobre ele: a
          // divisão fixa ao meio deixava os números e as ações espremidos, e o
          // resto das escolhas só existia rolando uma lista curta.
          DraggableScrollableSheet(
            initialChildSize: 0.55,
            minChildSize: 0.42,
            maxChildSize: 0.92,
            builder: (context, sheetController) => Material(
              elevation: 8,
              color: Theme.of(context).colorScheme.surface,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  children: [
                    // Alça de arrastar, na tinta do tema: é o convite para subir
                    // o painel e ver o resto das escolhas.
                    Container(
                      width: 32,
                      height: 4,
                      margin: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    // Fixo no topo do painel: os números e as ações, sempre à
                    // mão. O que é escolha desce na lista.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
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
                      // As ações ficam com os números, não no fim do painel: é
                      // aqui que a pessoa decide correr, e o resto (nome,
                      // conquista, desafio, equipe) é escolha que vem depois.
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (canEdit && !_recording)
                            OutlinedButton.icon(
                              onPressed: _starting ? null : _start,
                              icon: const Icon(Icons.play_arrow),
                              label: Text(
                                track.isEmpty ? 'Iniciar' : 'Continuar',
                              ),
                            ),
                          if (canEdit && !_recording) const SizedBox(width: 8),
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
                        ],
                      ),
                      if (canDiscard)
                        TextButton.icon(
                          onPressed: _discard,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Descartar corrida'),
                        ),
                      const Text(
                        'Mantenha o app aberto durante a gravação. Envie em até 7 dias.',
                        style: TextStyle(fontSize: 12),
                      ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        controller: sheetController,
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        children: [
                      if (_draft?.pauses.isNotEmpty ?? false)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            _pauseSummary(_draft!.pauses),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall,
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
                        ],
                      ),
                    ),
                  ],
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
