import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Account-scoped drafts. A queued request is immutable, including its ID.
class RunDraft {
  final String id;
  final List<Map<String, dynamic>> track;
  String name;
  int segment;
  bool queued;
  bool conquer;
  String? challenge; // "pace" | "distance" — desafio de conquista
  String? teamId;
  /// Território escolhido no mapa para o desafio ("Desafiar dono"). Enviado como
  /// `target_territory_id`: sem ele, quem fecha o laço na divisa de dois
  /// territórios desafia o que a sobreposição escolher.
  String? targetTerritoryId;
  /// Pausas detectadas pelo aparelho: gps, app, limite, velocidade. A pessoa não
  /// pausa por escolha — o motivo `manual` só existe em rascunhos gravados antes
  /// disso.
  final List<Map<String, String>> pauses;
  RunDraft({
    required this.id,
    required this.track,
    this.name = '',
    this.segment = 0,
    this.queued = false,
    this.conquer = false,
    this.challenge,
    this.teamId,
    this.targetTerritoryId,
    List<Map<String, String>>? pauses,
  }) : pauses = pauses ?? [];

  void logPause(String reason) {
    pauses.add({
      'reason': reason,
      'at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  void beginSegment() {
    // Multiple resume attempts without a GPS fix must not skip segment IDs.
    segment = track.isEmpty ? 0 : (track.last['segment'] as int? ?? 0) + 1;
  }

  factory RunDraft.create() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return RunDraft(
      id: '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}',
      track: [],
    );
  }
  factory RunDraft.fromJson(Map<String, dynamic> j) => RunDraft(
    id: j['id'],
    track: (j['track'] as List)
        .map((p) => Map<String, dynamic>.from(p))
        .toList(),
    name: j['name'] ?? '',
    segment: j['segment'] ?? 0,
    queued: j['queued'] ?? false,
    conquer: j['conquer'] ?? false,
    challenge: j['challenge'],
    teamId: j['team_id'],
    targetTerritoryId: j['target_territory_id'],
    pauses:
        (j['pauses'] as List?)
            ?.map((p) => Map<String, String>.from(p as Map))
            .toList() ??
        [],
  );
  Map<String, dynamic> get payload => {
    'id': id,
    'track': track,
    'name': name.isEmpty ? null : name,
    'conquer': conquer,
    'challenge': conquer ? (challenge ?? 'pace') : challenge,
    'team_id': teamId,
    'target_territory_id': targetTerritoryId,
  };
  Map<String, dynamic> toJson() => {
    ...payload,
    'segment': segment,
    'queued': queued,
    'pauses': pauses,
  };
}

class RunStore {
  final String userId;
  RunStore(this.userId);
  String get _key => 'runover_drafts_$userId';
  static Future<void> _writes = Future.value();
  static Zone? _writesZone;

  /// Serializa escritas concorrentes no mesmo aparelho.
  ///
  /// A cadeia pertence à zona assíncrona que a criou: um Future concluído
  /// numa zona anterior (ex.: o teste anterior do arquivo, cada
  /// `testWidgets` roda na sua própria zona FakeAsync) nunca resolve quando
  /// aguardado de outra zona. Ao trocar de zona, recomeça a cadeia em vez
  /// de travar. Em produção há uma única zona, então nada muda.
  Future<void> _settleWrites() {
    if (!identical(_writesZone, Zone.current)) {
      _writesZone = Zone.current;
      _writes = Future.value();
    }
    return _writes;
  }

  Future<List<RunDraft>> list() async {
    await _settleWrites();
    final text = (await SharedPreferences.getInstance()).getString(_key);
    if (text == null) return [];
    return (jsonDecode(text) as List).map((j) => RunDraft.fromJson(j)).toList();
  }

  Future<void> _mutate(String id, Map<String, dynamic>? snapshot) {
    final next = _settleWrites().then((_) async {
      final prefs = await SharedPreferences.getInstance();
      final text = prefs.getString(_key);
      final rows = text == null ? <dynamic>[] : jsonDecode(text) as List;
      rows.removeWhere((r) => r['id'] == id);
      if (snapshot != null) rows.add(snapshot);
      if (!await prefs.setString(_key, jsonEncode(rows))) {
        throw StateError('Não foi possível salvar o percurso neste aparelho.');
      }
    });
    // Keep later writes usable while returning this failure to the caller.
    _writes = next.catchError((Object _) {});
    return next;
  }

  Future<void> save(RunDraft draft) => _mutate(
    draft.id,
    jsonDecode(jsonEncode(draft.toJson())) as Map<String, dynamic>,
  );
  Future<void> remove(String id) => _mutate(id, null);
}
