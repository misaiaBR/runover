import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/daily_challenges.dart';
import '../services/run_store.dart';
import '../state/app_state.dart';
import '../widgets/centered_content.dart';
import 'app_footer.dart';
import 'run_detail_screen.dart';
import 'tracking_screen.dart';

class RunsScreen extends StatefulWidget {
  const RunsScreen({super.key});
  @override
  State<RunsScreen> createState() => _RunsScreenState();
}

class _RunsScreenState extends State<RunsScreen> {
  List<Map<String, dynamic>> _runs = [];
  List<RunDraft> _pending = [];
  Map<String, dynamic>? _progress;
  bool _loading = true;
  bool _more = true;
  String? _error;
  AppState? _observedState;
  int _observedRunsRevision = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = context.read<AppState>();
    if (identical(state, _observedState)) return;
    _observedState?.removeListener(_onAppStateChanged);
    _observedState = state;
    _observedRunsRevision = state.runsRevision;
    state.addListener(_onAppStateChanged);
  }

  void _onAppStateChanged() {
    final state = _observedState;
    if (state == null || state.runsRevision == _observedRunsRevision) return;
    _observedRunsRevision = state.runsRevision;
    if (mounted) _load();
  }

  @override
  void dispose() {
    _observedState?.removeListener(_onAppStateChanged);
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final state = context.read<AppState>();
    try {
      final pending = await RunStore(state.profile!.id).list();
      if (mounted) setState(() => _pending = pending);
      final runs = await state.api.listRuns(offset: more ? _runs.length : 0);
      final progress = await state.api.getProgress();
      if (!mounted) return;
      setState(() {
        _runs = more ? [..._runs, ...runs] : runs;
        _progress = progress;
        _more = runs.length == 20;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(Map<String, dynamic> run) async {
    try {
      final data = await context.read<AppState>().api.getRun(run['id']);
      if (!mounted) return;
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => RunDetailScreen(run: data)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _resume(RunDraft draft) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TrackingScreen(draftId: draft.id)),
    );
    if (mounted) _load();
  }

  Future<void> _remove(RunDraft draft) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover cópia local?'),
        content: const Text(
          'Um percurso ainda não enviado será perdido. Se o servidor já recebeu a corrida, ela continuará no histórico.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    try {
      await RunStore(context.read<AppState>().profile!.id).remove(draft.id);
      if (mounted) _load();
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Não foi possível remover a cópia local.');
      }
    }
  }

  Widget _status() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_loading) const LinearProgressIndicator(),
      if (_error != null)
        Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
    ],
  );

  Widget _tab(List<Widget> children) => RefreshIndicator(
    onRefresh: () => _load(),
    child: CenteredContent(
      maxWidth: 1280,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(28, 16, 28, 28),
        children: [
          _status(),
          ...children,
          const SizedBox(height: 24),
          const AppFooter(),
        ],
      ),
    ),
  );

  List<Widget> _history(BuildContext context) {
    final progress = _progress;
    final theme = Theme.of(context);
    return [
      if (_pending.isNotEmpty) ...[
        Text('Neste aparelho', style: theme.textTheme.titleMedium),
        for (final d in _pending)
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(
                      d.queued
                          ? Icons.cloud_upload_outlined
                          : Icons.pause_circle_outline,
                    ),
                    title: Text(d.name.isEmpty ? 'Corrida sem título' : d.name),
                    subtitle: Text(
                      d.queued
                          ? 'Envio pendente — toque para tentar novamente'
                          : 'Percurso salvo — toque para continuar',
                    ),
                    onTap: () => _resume(d),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: () => _remove(d),
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Eliminar'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonalIcon(
                        onPressed: () => _resume(d),
                        icon: const Icon(Icons.play_arrow, size: 18),
                        label: const Text('Continuar'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
      ],
      if (progress != null) ...[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Stat(
              label: 'Total de Corridas',
              value: '${progress['runs_count']}',
              icon: Icons.directions_run,
            ),
            const SizedBox(width: 12),
            _Stat(
              label: 'Distância Total',
              value: '${progress['distance_km']} km',
              icon: Icons.route,
            ),
            const SizedBox(width: 12),
            _Stat(
              label: 'Maior Corrida',
              value: '${progress['longest_run_km']} km',
              icon: Icons.emoji_events,
            ),
          ],
        ),
        const SizedBox(height: 24),
      ],
      Text('Histórico de corridas', style: theme.textTheme.titleMedium),
      if (_runs.isEmpty && !_loading)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text(
            'Suas corridas aparecerão aqui, mesmo sem conquistar um território.',
          ),
        ),
      for (final r in _runs) _RunCard(run: r, onOpen: () => _open(r)),
      if (_more && _runs.isNotEmpty)
        TextButton(
          onPressed: _loading ? null : () => _load(more: true),
          child: const Text('Carregar mais'),
        ),
    ];
  }

  List<Widget> _dailyChallenges(BuildContext context) {
    final theme = Theme.of(context);
    final muted = TextStyle(color: theme.colorScheme.onSurfaceVariant);
    final username = context.read<AppState>().profile?.username ?? 'você';
    final now = DateTime.now();
    final challenges = drawDailyChallenges(
      username: username,
      date: now,
      weeklyKm: (_progress?['distance_km'] as num?)?.toDouble() ?? 0,
      longestKm: (_progress?['longest_run_km'] as num?)?.toDouble() ?? 0,
    );
    final summary = summarizeDay(_runs, now);
    return [
      Row(
        children: [
          Expanded(
            child: Text('Desafios do dia', style: theme.textTheme.titleMedium),
          ),
          Text('troca em ${timeUntilMidnight(now)}', style: muted),
        ],
      ),
      const SizedBox(height: 4),
      Text('Sorteio pessoal de @$username • muda à meia-noite', style: muted),
      const SizedBox(height: 12),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final challenge in challenges) ...[
            _ChallengeCard(
              challenge: challenge,
              progress: measure(challenge, summary),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
      const SizedBox(height: 12),
    ];
  }

  List<Widget> _challenges(BuildContext context) {
    final progress = _progress;
    if (progress == null) return const [];
    final theme = Theme.of(context);
    final goals = [
      for (final g in progress['goals'] as List) WeeklyGoal.fromJson(g),
    ];
    final team = progress['team'];
    final remaining = weekTimeLeft(progress['week_start'], DateTime.now());
    final featured = WeeklyGoal.featured(goals);
    return [
      ..._dailyChallenges(context),
      if (featured != null) _FeaturedGoal(goal: featured, remaining: remaining),
      const SizedBox(height: 24),
      Text('Metas da semana', style: theme.textTheme.titleMedium),
      Text(
        remaining == null
            ? 'De segunda a domingo, pelo horário local.'
            : 'De segunda a domingo, pelo horário local • $remaining',
        style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
      ),
      const SizedBox(height: 8),
      for (final g in goals) _GoalTile(goal: g),
      if (team != null) ...[
        const SizedBox(height: 24),
        Text('Meta da equipe', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        _GoalTile(
          goal: WeeklyGoal(
            name: 'Equipe ${team['name']}',
            value: team['distance_km'],
            target: team['target_km'],
            unit: 'km',
          ),
        ),
        for (final c in team['contributors'])
          ListTile(
            dense: true,
            title: Text('@${c['username']}'),
            trailing: Text('${c['distance_km']} km'),
          ),
      ],
      const SizedBox(height: 24),
      Text('Medalhas', style: theme.textTheme.titleMedium),
      const SizedBox(height: 12),
      Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          for (final b in progress['badges'])
            _Medal(name: b['name'], earned: b['earned'] == true),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    // Sem wrapper de Theme aqui: a tela herda o tema claro/escuro do app.
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Corridas'),
          actions: [
            IconButton(
              tooltip: 'Atualizar',
              onPressed: _loading ? null : () => _load(),
              icon: const Icon(Icons.refresh),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Histórico'),
              Tab(text: 'Desafios'),
            ],
          ),
        ),
        body: Builder(
          builder: (context) => TabBarView(
            children: [_tab(_history(context)), _tab(_challenges(context))],
          ),
        ),
      ),
    );
  }
}

class WeeklyGoal {
  const WeeklyGoal({
    required this.name,
    required this.value,
    required this.target,
    required this.unit,
  });

  factory WeeklyGoal.fromJson(Map<String, dynamic> j) => WeeklyGoal(
    name: j['name'],
    value: j['value'],
    target: j['target'],
    unit: j['unit'],
  );

  final String name;
  final num value;
  final num target;
  final String unit;

  bool get completed => value >= target;
  double get fraction =>
      target <= 0 ? 1.0 : (value / target).clamp(0, 1).toDouble();

  /// Meta em aberto mais perto de ser concluída; a primeira, se todas já foram.
  static WeeklyGoal? featured(List<WeeklyGoal> goals) {
    if (goals.isEmpty) return null;
    final open = goals.where((g) => !g.completed).toList();
    if (open.isEmpty) return goals.first;
    return open.reduce((a, b) => b.fraction > a.fraction ? b : a);
  }

  String get missing {
    final left = target - value;
    final text = left == left.roundToDouble()
        ? left.round().toString()
        : left.toStringAsFixed(1).replaceAll('.', ',');
    if (left == 1) {
      final singular = switch (unit) {
        'dias' => 'dia',
        'conquistas' => 'conquista',
        _ => unit,
      };
      return 'Falta 1 $singular';
    }
    return 'Faltam $text $unit';
  }
}

/// Tempo até o fim da semana (segunda 00:00 local + 7 dias).
String? weekTimeLeft(String? weekStartUtc, DateTime now) {
  if (weekStartUtc == null) return null;
  final start = DateTime.tryParse(weekStartUtc);
  if (start == null) return null;
  final left = start.add(const Duration(days: 7)).difference(now.toUtc());
  if (left.isNegative) return null;
  if (left.inDays >= 1) {
    return '${left.inDays}d ${left.inHours % 24}h restantes';
  }
  if (left.inHours >= 1) {
    return '${left.inHours}h ${left.inMinutes % 60}min restantes';
  }
  return '${left.inMinutes}min restantes';
}

IconData _goalIcon(String unit) => switch (unit) {
  'dias' => Icons.calendar_month,
  'conquistas' => Icons.flag,
  _ => Icons.directions_run,
};

class _GoalBadge extends StatelessWidget {
  const _GoalBadge({required this.goal});

  final WeeklyGoal goal;
  static const double size = 56;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final done = goal.completed;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? colors.primary : colors.primary.withValues(alpha: .12),
        border: Border.all(color: colors.primary, width: 2),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            done ? Icons.check : _goalIcon(goal.unit),
            size: size * .34,
            color: done ? colors.onPrimary : colors.primary,
          ),
          Text(
            '${goal.target}',
            style: TextStyle(
              fontSize: size * .24,
              fontWeight: FontWeight.w800,
              height: 1.1,
              color: done ? colors.onPrimary : colors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeaturedGoal extends StatelessWidget {
  const _FeaturedGoal({required this.goal, required this.remaining});

  final WeeklyGoal goal;
  final String? remaining;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final onPrimary = colors.onPrimary;
    return Card(
      color: colors.primary,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              goal.completed ? 'Meta concluída' : 'Próxima meta',
              style: TextStyle(color: onPrimary.withValues(alpha: .8)),
            ),
            const SizedBox(height: 6),
            Text(
              goal.name,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: onPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: goal.fraction,
                minHeight: 10,
                color: onPrimary,
                backgroundColor: onPrimary.withValues(alpha: .25),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${goal.value} / ${goal.target} ${goal.unit}',
                    style: TextStyle(
                      color: onPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  goal.completed ? 'Concluída' : goal.missing,
                  style: TextStyle(color: onPrimary),
                ),
              ],
            ),
            if (remaining != null) ...[
              const SizedBox(height: 4),
              Text(
                remaining!,
                style: TextStyle(color: onPrimary.withValues(alpha: .8)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GoalTile extends StatelessWidget {
  const _GoalTile({required this.goal});

  final WeeklyGoal goal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = TextStyle(color: theme.colorScheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          _GoalBadge(goal: goal),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  goal.name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(value: goal.fraction),
                const SizedBox(height: 6),
                Text(
                  '${goal.value} / ${goal.target} ${goal.unit}'
                  '${goal.completed ? ' • Concluída' : ''}',
                  style: muted,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChallengeCard extends StatelessWidget {
  const _ChallengeCard({required this.challenge, required this.progress});

  final DailyChallenge challenge;
  final ChallengeProgress progress;

  static const _rarityColors = {
    'comum': Colors.blue,
    'raro': Colors.deepPurple,
    'épico': Colors.amber,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = TextStyle(color: theme.colorScheme.onSurfaceVariant);
    final rarity = _rarityColors[challenge.rarity] ?? Colors.blue;
    final fraction = challenge.target <= 0
        ? 1.0
        : (progress.value / challenge.target).clamp(0.0, 1.0).toDouble();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    challenge.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: rarity.withValues(alpha: .15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    challenge.rarity,
                    style: TextStyle(
                      color: rarity,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(challenge.detail, style: muted),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(value: fraction, minHeight: 8),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_formatValue(progress.value)} / '
                    '${_formatValue(challenge.target)} ${challenge.unit}',
                    style: muted,
                  ),
                ),
                if (progress.done) ...[
                  Icon(
                    Icons.check_circle,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Concluído',
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _formatValue(num value) {
  final whole = value == value.roundToDouble();
  return whole
      ? value.round().toString()
      : value.toStringAsFixed(1).replaceAll('.', ',');
}

class _Medal extends StatelessWidget {
  const _Medal({required this.name, required this.earned});

  final String name;
  final bool earned;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: 84,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: earned
                  ? Colors.amber.shade700
                  : colors.surfaceContainerHighest,
            ),
            child: Icon(
              earned ? Icons.emoji_events : Icons.lock_outline,
              color: earned ? Colors.white : colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            name,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: earned ? colors.onSurface : colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(
            children: [
              Icon(icon, color: theme.colorScheme.primary, size: 24),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cartão de histórico em layout horizontal: miniatura do percurso à
/// esquerda e dados em coluna à direita (título/data + métricas).
class _RunCard extends StatelessWidget {
  const _RunCard({required this.run, required this.onOpen});

  final Map<String, dynamic> run;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final startedAt = DateTime.tryParse('${run['started_at']}');
    final distanceKm = (run['distance_m'] as num?) != null
        ? (run['distance_m'] as num) / 1000
        : null;
    // A lista pode não trazer tempo/ritmo (vêm do detalhe); nesses casos
    // a métrica exibe '—' em vez de quebrar.
    final durationSeconds = (run['duration_seconds'] as num?)?.toInt();
    final paceSeconds = (run['pace_seconds_per_km'] as num?)?.toInt();
    return Card(
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _RouteThumbnail(seed: '${run['id']}'),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${run['name']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      startedAt == null
                          ? 'Data indisponível'
                          : _formatRunDate(startedAt.toLocal()),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _RunMetric(
                          icon: Icons.straighten,
                          label: 'Distância',
                          value: distanceKm == null
                              ? '—'
                              : '${distanceKm.toStringAsFixed(2).replaceAll('.', ',')} km',
                        ),
                        _RunMetric(
                          icon: Icons.timer_outlined,
                          label: 'Tempo Total',
                          value: durationSeconds == null
                              ? '—'
                              : _formatDuration(durationSeconds),
                        ),
                        _RunMetric(
                          icon: Icons.speed,
                          label: 'Ritmo Médio',
                          value: paceSeconds == null
                              ? '—'
                              : _formatPace(paceSeconds),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RunMetric extends StatelessWidget {
  const _RunMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: muted),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
          Text(label, style: TextStyle(color: muted, fontSize: 11)),
        ],
      ),
    );
  }
}

/// Miniatura estilizada do percurso: fundo tipo mapa com grelha e trajeto.
/// Determinística por corrida (seed do id), sem rede — funciona offline e
/// nos testes de widget.
class _RouteThumbnail extends StatelessWidget {
  const _RouteThumbnail({required this.seed});

  final String seed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: 104,
      height: 104,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: CustomPaint(
          painter: _RouteThumbnailPainter(
            seed: seed,
            background: colors.surfaceContainerHighest,
            grid: colors.onSurface.withValues(alpha: 0.08),
            route: colors.primary,
          ),
        ),
      ),
    );
  }
}

class _RouteThumbnailPainter extends CustomPainter {
  _RouteThumbnailPainter({
    required this.seed,
    required this.background,
    required this.grid,
    required this.route,
  });

  final String seed;
  final Color background;
  final Color grid;
  final Color route;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var x = 0.0; x <= size.width; x += 13) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var y = 0.0; y <= size.height; y += 13) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    // Caminhada pseudoaleatória estável a partir do seed.
    var state = seed.isEmpty ? 1 : seed.hashCode & 0x7fffffff;
    if (state == 0) state = 1;
    double next() {
      state = (state * 1103515245 + 12345) & 0x7fffffff;
      return state / 0x7fffffff;
    }

    var x = size.width * (0.2 + 0.25 * next());
    var y = size.height * (0.2 + 0.25 * next());
    final points = <Offset>[Offset(x, y)];
    for (var i = 1; i <= 24; i++) {
      x += (next() - 0.45) * size.width * 0.16;
      y += (next() - 0.45) * size.height * 0.16;
      x = x.clamp(6.0, size.width - 6);
      y = y.clamp(6.0, size.height - 6);
      points.add(Offset(x, y));
    }
    canvas.drawPoints(
      PointMode.polygon,
      points,
      Paint()
        ..color = route
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(points.first, 4, Paint()..color = Colors.green);
    canvas.drawCircle(points.last, 4, Paint()..color = route);
    canvas.drawCircle(points.last, 4, Paint()..color = Colors.white);
    canvas.drawCircle(points.last, 2.2, Paint()..color = route);
  }

  @override
  bool shouldRepaint(covariant _RouteThumbnailPainter oldDelegate) =>
      oldDelegate.seed != seed ||
      oldDelegate.background != background ||
      oldDelegate.grid != grid ||
      oldDelegate.route != route;
}

const _ptMonths = [
  'Jan',
  'Fev',
  'Mar',
  'Abr',
  'Mai',
  'Jun',
  'Jul',
  'Ago',
  'Set',
  'Out',
  'Nov',
  'Dez',
];

/// 'Corrida Matinal - 12 Out, 07:05'.
String _formatRunDate(DateTime date) =>
    '${date.day} ${_ptMonths[date.month - 1]}, '
    '${date.hour.toString().padLeft(2, '0')}:'
    '${date.minute.toString().padLeft(2, '0')}';

String _formatDuration(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

/// Segundos por km em m'ss"/km (ex.: 330 -> 5'30"/km).
String _formatPace(int paceSeconds) =>
    "${paceSeconds ~/ 60}'${(paceSeconds % 60).toString().padLeft(2, '0')}\"/km";
