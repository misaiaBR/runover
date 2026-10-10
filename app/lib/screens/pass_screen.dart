import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'season_pass_screen.dart';

/// Atalho da home: um resumo do passe que abre a trilha ao toque.
class PassCard extends StatefulWidget {
  const PassCard({super.key});

  @override
  State<PassCard> createState() => _PassCardState();
}

class _PassCardState extends State<PassCard> with AccountWatcher<PassCard> {
  late Future<Map<String, dynamic>> _future = _startLoad();

  @override
  bool get busy => false;

  @override
  void onAccountChanged() => _reload();

  Future<Map<String, dynamic>> _load() async {
    final status = await context.read<AppState>().api.getPassRunover();
    return status;
  }

  /// A home monta o cartão numa lista preguiçosa: ele pode ser descartado
  /// antes da resposta chegar, e um `Future` sem listener denuncia o próprio
  /// erro como exceção não tratada.
  Future<Map<String, dynamic>> _startLoad() {
    final future = _load();
    future.then<void>((_) {}, onError: (Object _) {});
    return future;
  }

  void _reload() {
    markRevisionSeen();
    setState(() {
      _future = _startLoad();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _PassCardSkeleton();
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return _PassCardBroken(onRetry: _reload);
        }
        final status = snapshot.data!;
        // A home não tem Scaffold: sem este Material o InkWell do cartão não
        // tem onde desenhar o toque.
        return Material(
          type: MaterialType.transparency,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SeasonPassScreen()),
            ),
            child: PassSummary(
              status: status,
              trailing: _openTrailHint(context),
            ),
          ),
        );
      },
    );
  }

  Widget _openTrailHint(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        'Ver a trilha',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.white.withValues(alpha: 0.85),
        ),
      ),
      Icon(
        Icons.chevron_right,
        size: 18,
        color: Colors.white.withValues(alpha: 0.85),
      ),
    ],
  );
}

class _PassCardSkeleton extends StatelessWidget {
  const _PassCardSkeleton();

  @override
  Widget build(BuildContext context) => Container(
    height: 132,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(20),
    ),
    child: const Center(child: CircularProgressIndicator()),
  );
}

class _PassCardBroken extends StatelessWidget {
  const _PassCardBroken({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          const Expanded(child: Text('Não foi possível carregar o passe.')),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }
}

/// O resumo do passe: temporada, XP, progresso até o próximo tier e premium.
/// Sem `Scaffold` nem rolagem própria, serve ao cartão da home e ao topo da
/// tela da trilha.
class PassSummary extends StatelessWidget {
  const PassSummary({super.key, required this.status, this.trailing});

  final Map<String, dynamic> status;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final points = (status['seasonal_points'] as num).toInt();
    final unlocked = (status['unlocked_tier'] as num).toInt();
    final premium = status['premium_unlocked'] == true;
    final season = seasonLabel('${status['season_id']}');
    final endsAt = countdown(status['ends_at'] as String?);
    final tiers = (status['tiers'] as List? ?? const []).whereType<Map>();
    final next = tiers.where((t) => (t['unlocked'] as bool?) != true).toList();
    final nextAt = next.isEmpty
        ? null
        : (next.first['threshold'] as num).toInt();
    final progress = nextAt == null ? 1.0 : (points / nextAt).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6D28D9), Color(0xFF4C1D95)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.workspace_premium,
                color: Color(0xFFFFC93C),
                size: 28,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'PASS RUNOVER',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'Temporada $season',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${fmt(points)} XP · tier $unlocked de ${tiers.length} · $endsAt',
            style: const TextStyle(fontSize: 13, color: Colors.white70),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              valueColor: const AlwaysStoppedAnimation(Color(0xFFFFC93C)),
            ),
          ),
          if (nextAt != null) ...[
            const SizedBox(height: 6),
            Text(
              'Faltam ${fmt(nextAt - points)} XP para o tier ${unlocked + 1}',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
          const SizedBox(height: 10),
          if (premium)
            const Row(
              children: [
                Icon(Icons.check_circle, size: 18, color: Color(0xFF22C55E)),
                SizedBox(width: 8),
                Text(
                  'Trilha premium ativa',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Observa a conta mudando longe da tela e recarrega, deixando a revisão
/// pendurada enquanto uma operação própria está em voo.
mixin AccountWatcher<T extends StatefulWidget> on State<T> {
  AppState? _watched;
  int _seenRevision = 0;

  /// `true` enquanto uma operação da própria tela está em andamento.
  bool get busy;

  /// Trás o estado novo da conta para a tela.
  void onAccountChanged();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = context.read<AppState>();
    if (identical(state, _watched)) return;
    _watched?.removeListener(_onStateChanged);
    _watched = state;
    _seenRevision = state.profileRevision;
    state.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    _watched?.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    final state = _watched;
    if (state == null || state.profileRevision == _seenRevision) return;
    // Com a tela ocupada a revisão fica não consumida: se a própria operação
    // recarregar, ela alcança a revisão e o flush do fim não busca de novo; se
    // ela falhar, o mesmo flush assume a recarga em vez de mostrar o estado
    // anterior.
    if (busy) return;
    if (mounted) onAccountChanged();
  }

  /// Processa a mudança externa que chegou enquanto a tela estava ocupada.
  void flushAccountRefresh() {
    final state = _watched;
    if (state == null || state.profileRevision == _seenRevision) return;
    onAccountChanged();
  }

  /// Marca a revisão atual como consumida antes de recarregar.
  void markRevisionSeen() {
    final state = _watched;
    if (state != null) _seenRevision = state.profileRevision;
  }
}

String fmt(int n) =>
    n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');

const _months = [
  '',
  'janeiro',
  'fevereiro',
  'março',
  'abril',
  'maio',
  'junho',
  'julho',
  'agosto',
  'setembro',
  'outubro',
  'novembro',
  'dezembro',
];

String seasonLabel(String seasonId) {
  final parts = seasonId.split('-');
  if (parts.length != 2) return seasonId;
  final month = int.tryParse(parts[1]) ?? 0;
  if (month < 1 || month > 12) return seasonId;
  return '${_months[month]} de ${parts[0]}';
}

String countdown(String? endsAt) {
  final end = DateTime.tryParse(endsAt ?? '');
  if (end == null) return '';
  final left = end.difference(DateTime.now().toUtc());
  if (left.isNegative) return 'Temporada encerrada';
  final days = left.inDays;
  final hours = left.inHours % 24;
  if (days > 0) return 'Termina em $days d $hours h';
  final minutes = left.inMinutes % 60;
  if (hours > 0) return 'Termina em $hours h $minutes min';
  return 'Termina em $minutes min';
}
