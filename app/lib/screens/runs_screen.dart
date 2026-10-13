/// Tela de Corridas: histórico do que foi corrido e os desafios do dia.
///
/// A tela é desenhada sobre [Pal.panel] com as peças do kit (`GradientBar`,
/// `GameCard`, `ChunkyProgress`, `GameButton`), igual à home e ao passe. Nenhum
/// número é local: o resumo vem de `GET /runs/progress`, as corridas de
/// `GET /runs`, e os desafios de `GET /runs/challenges` — o sorteio e a medição
/// são do servidor, o resgate credita XP e dracmas.
library;

import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../format.dart';
import '../services/run_store.dart';
import '../state/app_state.dart';
import '../widgets/centered_content.dart';
import '../widgets/game_mode_card.dart';
import '../widgets/runover_ui.dart';
import '../widgets/slanted_menu_icon.dart';
import 'app_footer.dart';
import 'run_detail_screen.dart';
import 'tracking_screen.dart';

/// Largura do cartão único do estado vazio: o convite se lê como o da home,
/// esticado até aqui e não até a borda da tela.
const double _emptyModeMaxWidth = 420;

class RunsScreen extends StatefulWidget {
  const RunsScreen({super.key});

  @override
  State<RunsScreen> createState() => _RunsScreenState();
}

/// Como uma corrida entrou no jogo: só a cor da linha no histórico.
///
/// Derivado do que o servidor já registra — conquista com desafio (marca de
/// ritmo ou distância do dono do território) é `desafio`; conquista simples é
/// `dominacao`; corrida sem tentativa de território é `livre`. A tela não
/// nomeia o modo na linha: o que o dono vê é a data, a distância e o que a
/// corrida rendeu.
enum RunMode {
  dominacao(RCharacter.zona, RGrad.orange),
  desafio(RCharacter.turbo, RGrad.gold),
  livre(RCharacter.coach, null);

  const RunMode(this.character, this.gradient);

  /// O personagem que representa a linha — desenho, não nome de modo.
  final RCharacter character;

  /// `null` é o cartão neutro do tema: a corrida livre não tem cor de modo.
  final LinearGradient? gradient;

  static RunMode of(Map<String, dynamic> run) {
    final claim = run['claim'];
    if (claim is! Map) return RunMode.livre;
    return claim['challenge'] != null ? RunMode.desafio : RunMode.dominacao;
  }
}

/// Desafio do dia como o servidor devolve, já medido e com o resgate.
class _DailyChallenge {
  const _DailyChallenge(this.json);

  final Map<String, dynamic> json;

  String get id => '${json['id']}';
  String get title => '${json['title']}';
  String get detail => '${json['detail']}';
  String get unit => '${json['unit']}';
  num get target => (json['target'] as num?) ?? 0;
  num get value => (json['value'] as num?) ?? 0;
  bool get done => json['done'] == true;
  bool get claimed => json['claimed'] == true;
  int get points => (json['points'] as num?)?.toInt() ?? 0;
  int get coins => (json['coins'] as num?)?.toInt() ?? 0;

  Rarity get rarity => switch ('${json['rarity']}') {
    'raro' => Rarity.rare,
    'épico' => Rarity.epic,
    _ => Rarity.common,
  };

  /// O personagem que apresenta o desafio sobe de nível com a raridade.
  RCharacter get character => switch (rarity) {
    Rarity.common => RCharacter.coach,
    Rarity.rare => RCharacter.zona,
    Rarity.epic => RCharacter.lenda,
  };

  double get fraction => target <= 0 ? 1 : (value / target).clamp(0.0, 1.0);
}

class _RunsScreenState extends State<RunsScreen> {
  List<Map<String, dynamic>> _runs = [];
  List<RunDraft> _pending = [];
  Map<String, dynamic>? _progress;
  List<_DailyChallenge> _challenges = const [];
  bool _loading = true;
  bool _more = true;
  bool _claiming = false;
  String? _error;
  int _tab = 0;
  /// Filtro de período do histórico: `true` é "Este mês", cortado no servidor.
  bool _monthOnly = false;
  /// Nº da leitura em andamento. As chamadas não chegam na ordem em que saem,
  /// e uma resposta velha nunca pode escrever por cima da escolha recente.
  int _loadGeneration = 0;
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
    final generation = ++_loadGeneration;
    // O período é capturado antes do primeiro `await`. Trocar de filtro abre
    // outra chamada, e esta tem de responder pela pergunta que fez — senão a
    // lista do mês chega por último e veste a etiqueta de "Tudo".
    final monthOnly = _monthOnly;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final state = context.read<AppState>();
    try {
      final pending = await RunStore(state.profile!.id).list();
      if (!_current(generation)) return;
      setState(() => _pending = pending);
      final runs = await state.api.listRuns(
        offset: more ? _runs.length : 0,
        since: monthOnly ? _monthStart() : null,
      );
      final progress = await state.api.getProgress();
      final challenges = await state.api.getDailyChallenges();
      if (!_current(generation)) return;
      setState(() {
        _runs = more ? [..._runs, ...runs] : runs;
        _progress = progress;
        _challenges = [
          for (final item in (challenges['challenges'] as List? ?? const []))
            _DailyChallenge(Map<String, dynamic>.from(item as Map)),
        ];
        _more = runs.length == 20;
      });
    } catch (e) {
      if (_current(generation)) setState(() => _error = e.toString());
    } finally {
      if (_current(generation)) setState(() => _loading = false);
    }
  }

  /// A resposta desta chamada ainda vale? Não vale quando a tela foi fechada,
  /// nem quando outra leitura — outra página, outro período, outro filtro — já
  /// saiu na frente.
  bool _current(int generation) =>
      mounted && generation == _loadGeneration;

  /// Primeiro instante do mês no fuso do aparelho. O cliente manda o instante
  /// em UTC; quem mora em -03:00 vê o mês dele, não o mês de Greenwich.
  DateTime _monthStart() {
    final now = DateTime.now();
    return DateTime(now.year, now.month);
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

  /// Resgata um desafio concluído. O servidor devolve o dia inteiro já
  /// atualizado; o HUD (dracmas e nível) é revalidado em seguida.
  Future<void> _claim(_DailyChallenge challenge) async {
    if (_claiming) return;
    setState(() => _claiming = true);
    try {
      final body = await context.read<AppState>().api.claimDailyChallenge(
        challenge.id,
      );
      if (!mounted) return;
      setState(() {
        _challenges = [
          for (final item in (body['challenges'] as List? ?? const []))
            _DailyChallenge(Map<String, dynamic>.from(item as Map)),
        ];
      });
      final reward = [
        if (challenge.points > 0) '+${formatPoints(challenge.points)} XP',
        if (challenge.coins > 0) '+${formatPoints(challenge.coins)} dracmas',
      ].join(' · ');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${challenge.title} resgatado${reward.isEmpty ? '' : ': $reward'}.',
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
  }

  Widget _list({required List<Widget> children}) {
    // O rato não arrasta lista nenhuma por padrão na web. Sem isto, tirar o
    // botão de atualizar deixava o desktop sem porta nenhuma para recarregar.
    final dragWithMouse = ScrollConfiguration.of(context).copyWith(
      dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
    );
    return RefreshIndicator(
      onRefresh: () => _load(),
      child: CenteredContent(
        maxWidth: 1280,
        child: ScrollConfiguration(
          behavior: dragWithMouse,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            children: [
              if (_error != null) ...[
                ErrorBanner(message: _error!, onRetry: _load),
                const SizedBox(height: 16),
              ],
              ...children,
              const SizedBox(height: 24),
              const AppFooter(),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ Histórico

  List<Widget> _history(BuildContext context) {
    final pal = Pal.of(context);
    final progress = _progress;
    // O corte de período é do servidor, então a lista que chega já é só do
    // mês. `runs_count` é o total de sempre: ele diz se o vazio é "nunca
    // corri" ou "não corri neste mês".
    final totalRuns = (progress?['runs_count'] as num?)?.toInt() ?? 0;
    final emptyMonth =
        _monthOnly && !_loading && _runs.isEmpty && totalRuns > 0;
    return [
      if (_pending.isNotEmpty) ...[
        SectionHeader('Neste aparelho'),
        const SizedBox(height: 12),
        for (final draft in _pending) ...[
          _DraftCard(
            draft: draft,
            onResume: () => _resume(draft),
            onRemove: () => _remove(draft),
          ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 20),
      ],
      if (progress != null) ...[
        _StatStrip(progress: progress),
        const SizedBox(height: 20),
      ],
      _PeriodFilterChips(
        monthOnly: _monthOnly,
        onChanged: (monthOnly) {
          if (monthOnly == _monthOnly) return;
          setState(() => _monthOnly = monthOnly);
          // Trocar de período recomeça a paginação do zero.
          _load();
        },
      ),
      const SizedBox(height: 16),
      if (emptyMonth)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Nenhuma corrida neste mês.',
            style: TextStyle(color: pal.muted),
          ),
        )
      else if (_runs.isEmpty && !_loading)
        ..._emptyHistory(context)
      else ...[
        for (final run in _runs) ...[
          _RunRow(run: run, onOpen: () => _open(run)),
          const SizedBox(height: 12),
        ],
        // "Carregar mais" vale nos dois períodos: o servidor corta por página
        // de 20, então um mês com 40 corridas tem duas páginas exatamente como
        // o histórico completo. O que a página seguinte respeita é o `since`
        // que a chamada captura lá em cima.
        if (_more) ...[
          const SizedBox(height: 4),
          GameButton(
            label: 'Carregar mais',
            expand: true,
            background: pal.chip,
            onPressed: _loading ? null : () => _load(more: true),
          ),
        ],
      ],
    ];
  }

  /// Estado vazio pelo mock: painel tracejado com o Hexi convidando a primeira
  /// corrida, o cartão do modo ainda em desenvolvimento e o bônus real do dia
  /// (vindo do `/progress`).
  List<Widget> _emptyHistory(BuildContext context) {
    final pal = Pal.of(context);
    final bonus = (_progress?['daily_bonus'] as num?)?.toInt() ?? 0;
    final pending = _progress?['daily_bonus_pending'] != false;
    return [
      _DashedPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    // O branco a 16% era a placa do mock sobre o cartão escuro;
                    // no cartão branco do tema claro ele não existe. O chip do
                    // `Pal` é a placa dos dois lados.
                    color: pal.chip,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const CharacterAvatar(RCharacter.hexi, size: 52),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Nenhuma corrida ainda',
                        style: TextStyle(
                          color: pal.heading,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Suas corridas aparecem aqui, mesmo sem conquistar um '
                        'território.',
                        style: TextStyle(color: pal.muted, height: 1.35),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Um cartão só, e ele não estica pela tela: o convite é para um
            // modo, não para uma prateleira de modos.
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _emptyModeMaxWidth),
                child: GameModeCard(mode: _challengeMode()),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                const DracmaCoin(size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    pending && bonus > 0
                        ? 'Bônus do dia: +${formatPoints(bonus)} dracmas na '
                              'primeira corrida.'
                        : 'Bônus do dia de hoje já creditado.',
                    style: TextStyle(color: pal.muted, fontSize: 13),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ];
  }

  /// O único cartão do estado vazio: o modo que ainda não tem regra. O texto é
  /// o mesmo da home — a tela não reinventa o modo, só adianta que ele chega.
  /// Sem `onPlay` o botão fica apagado de verdade: tocar não faz nada, porque
  /// não há o que abrir enquanto a mecânica não existe.
  GameMode _challengeMode() => GameMode(
    title: 'Desafio de velocidade',
    description: 'Voltas cronometradas. Bata seu recorde e suba no ranking.',
    character: RCharacter.turbo,
    gradient: dimmedModeGradient(RGrad.gold),
    action: 'Jogar',
    tag: 'Em breve',
    pills: const [],
    onPlay: null,
  );

  // ------------------------------------------------------------ Desafios

  List<Widget> _challengesTab(BuildContext context) {
    final pal = Pal.of(context);
    final progress = _progress;
    final username = context.read<AppState>().profile?.username ?? 'você';
    final goals = [
      for (final g in (progress?['goals'] as List? ?? const []))
        WeeklyGoal.fromJson(Map<String, dynamic>.from(g as Map)),
    ];
    final remaining = weekTimeLeft(progress?['week_start'], DateTime.now());
    final featured = WeeklyGoal.featured(goals);
    final team = progress?['team'];
    final others = goals.where((g) => g != featured).toList();

    return [
      SectionHeader(
        'Desafios do dia',
        pill: 'troca em ${timeUntilMidnight(DateTime.now())}',
        pillIcon: Icons.schedule,
      ),
      const SizedBox(height: 6),
      Text(
        'Sorteio pessoal de @$username · muda à meia-noite',
        style: TextStyle(color: pal.muted, fontSize: 13),
      ),
      const SizedBox(height: 14),
      if (_challenges.isEmpty && !_loading)
        _DashedPanel(
          child: Text(
            'Não foi possível carregar os desafios de hoje.',
            style: TextStyle(color: pal.muted),
          ),
        )
      else
        for (final challenge in _challenges) ...[
          _ChallengeCard(
            challenge: challenge,
            onClaim: () => _claim(challenge),
            busy: _claiming,
          ),
          const SizedBox(height: 14),
        ],
      const SizedBox(height: 8),
      SectionHeader(
        'Metas da semana',
        pill: remaining,
        pillIcon: Icons.calendar_month,
      ),
      const SizedBox(height: 14),
      if (featured != null) ...[
        _FeaturedGoal(goal: featured, remaining: remaining),
        const SizedBox(height: 14),
      ],
      for (final goal in others) ...[
        _GoalTile(goal: goal),
        const SizedBox(height: 12),
      ],
      if (team != null) ...[
        const SizedBox(height: 8),
        SectionHeader('Meta da equipe'),
        const SizedBox(height: 14),
        _TeamGoalCard(team: Map<String, dynamic>.from(team as Map)),
      ],
      if (progress != null && (progress['badges'] as List? ?? []).isNotEmpty) ...[
        const SizedBox(height: 24),
        SectionHeader('Medalhas'),
        const SizedBox(height: 14),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final b in progress['badges'] as List)
              _Medal(
                name: '${(b as Map)['name']}',
                earned: b['earned'] == true,
              ),
          ],
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final tabs = const ['Histórico', 'Desafios'];
    final pushed = BackBarButton.implied(context);
    return Scaffold(
      body: ColoredBox(
        color: pal.panel,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GradientBar(
                title: 'Corridas',
                // O cabeçalho de Corridas não tem porta de menu: quem navega
                // daqui para fora é a barra de baixo. A seta só existe quando a
                // tela vem empurrada por cima da casca — ali não há barra nem
                // menu, e sem ela a tela seria um beco sem saída.
                leading: pushed ? const BackBarButton() : null,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                child: _TabPills(
                  labels: tabs,
                  index: _tab,
                  onSelect: (index) => setState(() => _tab = index),
                ),
              ),
              Expanded(
                child: _tab == 0
                    ? _list(children: _history(context))
                    : _list(children: _challengesTab(context)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ Cabeçalho

/// As duas abas como pílulas: a ativa veste branco com tinta escura.
class _TabPills extends StatelessWidget {
  const _TabPills({
    required this.labels,
    required this.index,
    required this.onSelect,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          // As duas abas dividem a largura: em 320px duas pílulas com o texto
          // natural não cabem lado a lado, e o que não cabe não pode sobrar.
          Expanded(
            child: _Pill(
              label: labels[i],
              active: i == index,
              onTap: () => onSelect(i),
              palette: pal,
            ),
          ),
        ],
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.active,
    required this.onTap,
    required this.palette,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final Pal palette;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: active,
    child: InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: active ? palette.card : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active ? Colors.transparent : palette.border,
            width: 2,
          ),
          boxShadow: active
              ? const [BoxShadow(color: Color(0x40000000), offset: Offset(0, 3))]
              : null,
        ),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label.toUpperCase(),
              style: TextStyle(
                color: active ? palette.heading : palette.muted,
                fontWeight: FontWeight.w900,
                fontSize: 13,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

// ------------------------------------------------------------------ Histórico

/// Os três cartões de número do topo do histórico.
class _StatStrip extends StatelessWidget {
  const _StatStrip({required this.progress});

  final Map<String, dynamic> progress;

  @override
  Widget build(BuildContext context) {
    final runs = (progress['runs_count'] as num?)?.toInt() ?? 0;
    final total = (progress['distance_km'] as num?) ?? 0;
    final longest = (progress['longest_run_km'] as num?) ?? 0;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _StatCard(
              gradient: RGrad.orange,
              icon: Icons.directions_run,
              value: '$runs',
              label: runs == 1 ? 'Corrida' : 'Corridas',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _StatCard(
              gradient: RGrad.teal,
              icon: Icons.route,
              value: '${formatNumber(total)} km',
              label: 'Distância total',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _StatCard(
              gradient: RGrad.gold,
              icon: Icons.emoji_events,
              value: '${formatNumber(longest)} km',
              label: 'Maior corrida',
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.gradient,
    required this.icon,
    required this.value,
    required this.label,
  });

  final LinearGradient gradient;
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => GameCard(
    gradient: gradient,
    padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.24),
          ),
          child: Icon(icon, size: 19, color: Colors.white),
        ),
        const SizedBox(height: 12),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              height: 1.05,
              shadows: kTextShadow,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.92),
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
          ),
        ),
      ],
    ),
  );
}

/// Chips de período do histórico. O corte acontece no servidor (`since`), não
/// na lista já carregada: com paginação de 20, filtrar no aparelho mostraria um
/// mês pela metade.
class _PeriodFilterChips extends StatelessWidget {
  const _PeriodFilterChips({required this.monthOnly, required this.onChanged});

  final bool monthOnly;
  final ValueChanged<bool> onChanged;

  static const _options = <String, bool>{'Este mês': true, 'Tudo': false};

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final entry in _options.entries)
          Semantics(
            button: true,
            selected: entry.value == monthOnly,
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => onChanged(entry.value),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: entry.value == monthOnly
                      ? pal.chip
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: entry.value == monthOnly
                        ? Pal.orange
                        : pal.border,
                    width: 2,
                  ),
                ),
                child: Text(
                  entry.key,
                  style: TextStyle(
                    color: entry.value == monthOnly
                        ? pal.heading
                        : pal.muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Uma corrida na lista: linha full-width com a cor do modo, o personagem, as
/// métricas e as pílulas do que ela rendeu.
class _RunRow extends StatelessWidget {
  const _RunRow({required this.run, required this.onOpen});

  final Map<String, dynamic> run;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final mode = RunMode.of(run);
    final colored = mode.gradient != null;
    final heading = colored ? Colors.white : pal.heading;
    final muted = colored ? Colors.white.withValues(alpha: 0.85) : pal.muted;

    final distanceM = (run['distance_m'] as num?)?.toDouble();
    final distanceKm = distanceM == null ? null : distanceM / 1000;
    // A lista pode não trazer tempo/ritmo (vêm do detalhe); nesses casos a
    // métrica exibe '—' em vez de quebrar.
    final durationSeconds = (run['duration_seconds'] as num?)?.toInt();
    final paceSeconds = (run['pace_seconds_per_km'] as num?)?.toInt();
    final metrics = [
      if (durationSeconds != null) _formatDuration(durationSeconds),
      if (paceSeconds != null) 'ritmo ${_formatPace(paceSeconds)}',
    ].join(' · ');

    final claim = run['claim'];
    final points = claim is Map
        ? (claim['points_awarded'] as num?)?.toInt() ?? 0
        : 0;
    final error = run['claim_error'];

    return GameCard(
      gradient: mode.gradient,
      color: colored ? null : pal.card,
      onTap: onOpen,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Os selos de recompensa competem com as métricas pela mesma linha.
          // Abaixo de 360px eles descem para uma linha própria embaixo do
          // texto — é onde a largura sobra — em vez de espremer o título.
          final compact = constraints.maxWidth < 360;
          final pills = [
            if (claim is Map)
              _RewardPill(
                text: '+1 território',
                onColored: colored,
                palette: pal,
              ),
            if (points > 0)
              _RewardPill(
                text: '+${formatPoints(points)} XP',
                onColored: colored,
                palette: pal,
              ),
          ];
          final metricsColumn = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                // Só a data: a linha não anuncia modo de jogo, e o que a
                // corrida rendeu já está nas pílulas do mesmo cartão.
                formatDayLabelFromIso(run['started_at']).toUpperCase(),
                style: TextStyle(
                  color: muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  distanceKm == null
                      ? '—'
                      : '${formatNumber(distanceKm)} km',
                  style: TextStyle(
                    color: heading,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                    shadows: colored ? kTextShadow : null,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                metrics.isEmpty ? 'Tempo indisponível' : metrics,
                style: TextStyle(color: muted, fontSize: 13),
              ),
              if (error is String && error.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  error,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ],
              if (compact && pills.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: pills,
                ),
              ],
            ],
          );
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: (colored ? Colors.white : pal.muted).withValues(
                    alpha: 0.2,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: CharacterAvatar(mode.character, size: 38),
              ),
              const SizedBox(width: 12),
              Expanded(child: metricsColumn),
              if (!compact && pills.isNotEmpty) ...[
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < pills.length; i++) ...[
                      if (i > 0) const SizedBox(height: 6),
                      pills[i],
                    ],
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Pílula branca de recompensa sobre a linha colorida; no cartão neutro ela
/// veste o chip do tema para não sumir.
class _RewardPill extends StatelessWidget {
  const _RewardPill({
    required this.text,
    required this.onColored,
    required this.palette,
  });

  final String text;
  final bool onColored;
  final Pal palette;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: onColored ? Colors.white : palette.chip,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: onColored ? Pal.onAccent : palette.heading,
        fontSize: 12,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}

/// Cópia local de uma corrida ainda não enviada.
class _DraftCard extends StatelessWidget {
  const _DraftCard({
    required this.draft,
    required this.onResume,
    required this.onRemove,
  });

  final RunDraft draft;
  final VoidCallback onResume;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return GameCard(
      color: pal.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                draft.queued ? Icons.cloud_upload_outlined : Icons.pause_circle_outline,
                size: 20,
                color: pal.muted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      draft.name.isEmpty ? 'Corrida sem título' : draft.name,
                      style: TextStyle(
                        color: pal.heading,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      draft.queued
                          ? 'Envio pendente — toque para tentar novamente'
                          : 'Percurso salvo — toque para continuar',
                      style: TextStyle(color: pal.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: GameButton(
                  label: 'Continuar',
                  compact: true,
                  background: Pal.team,
                  onPressed: onResume,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GameButton(
                  label: 'Eliminar',
                  compact: true,
                  background: pal.chip,
                  onPressed: onRemove,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ Desafios

/// Cartão de um desafio do dia: raridade define a cor, o progresso vem do
/// servidor e o botão resgata a recompensa real.
class _ChallengeCard extends StatelessWidget {
  const _ChallengeCard({
    required this.challenge,
    required this.onClaim,
    required this.busy,
  });

  final _DailyChallenge challenge;
  final VoidCallback onClaim;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final rarity = challenge.rarity;
    return GameCard(
      gradient: rarity.gradient,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: CharacterAvatar(challenge.character, size: 36),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rarity.label,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      challenge.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        height: 1.15,
                        shadows: kTextShadow,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      challenge.detail,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (challenge.claimed)
                const _DonePill()
              else if (challenge.done)
                GameButton(
                  label: 'Resgatar',
                  compact: true,
                  background: Colors.white,
                  // Enquanto o resgate está em voo o botão fica apagado sobre a
                  // gradiente fixa da raridade: sem tinta branca explícita ele
                  // herdaria o preto do tema claro e somem no cartão.
                  foreground: busy ? Colors.white : null,
                  onPressed: busy ? null : onClaim,
                )
              else
                _RewardTag(challenge: challenge),
            ],
          ),
          const SizedBox(height: 14),
          ChunkyProgress(value: challenge.fraction),
          const SizedBox(height: 8),
          Text(
            '${formatNumber(challenge.value)} / '
            '${formatNumber(challenge.target)} ${challenge.unit}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// O que o desafio paga, em XP e dracmas.
class _RewardTag extends StatelessWidget {
  const _RewardTag({required this.challenge});

  final _DailyChallenge challenge;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0x4D000000),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '+${formatPoints(challenge.points)} XP',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
        if (challenge.coins > 0) ...[
          const SizedBox(width: 6),
          const DracmaCoin(size: 15),
          const SizedBox(width: 4),
          Text(
            formatPoints(challenge.coins),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ],
    ),
  );
}

class _DonePill extends StatelessWidget {
  const _DonePill();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0x4D000000),
      borderRadius: BorderRadius.circular(999),
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check, size: 14, color: Pal.teal),
        SizedBox(width: 5),
        Text(
          // Mesma caixa do botão que o cartão substitui no mesmo espaço.
          'RESGATADO',
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );
}

/// A meta em aberto mais perto do fim, no cartão grande do mock.
class _FeaturedGoal extends StatelessWidget {
  const _FeaturedGoal({required this.goal, required this.remaining});

  final WeeklyGoal goal;
  final String? remaining;

  @override
  Widget build(BuildContext context) => GameCard(
    gradient: RGrad.goal,
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          goal.completed ? 'Meta concluída' : 'Próxima meta',
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
            shadows: kTextShadow,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          goal.name,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w900,
            height: 1.15,
            shadows: kTextShadow,
          ),
        ),
        const SizedBox(height: 14),
        ChunkyProgress(value: goal.fraction),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                '${formatNumber(goal.value)} / ${formatNumber(goal.target)} '
                '${goal.unit}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              goal.completed ? 'Concluída' : goal.missing,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.95),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _hint(goal.unit),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.92),
            fontSize: 13,
            height: 1.35,
          ),
        ),
      ],
    ),
  );

  /// Reforço da regra da meta, sem inventar recompensa.
  static String _hint(String unit) => switch (unit) {
    'dias' => 'Correr um pouco em três dias da semana já cumpre a meta.',
    'conquistas' => 'Feche um laço no mapa para conquistar mais um território.',
    _ => 'Dá para dividir em duas ou três corridas. Cada quilômetro conta.',
  };
}

class _GoalTile extends StatelessWidget {
  const _GoalTile({required this.goal});

  final WeeklyGoal goal;

  static Color _color(String unit) => switch (unit) {
    'dias' => Pal.gold,
    'conquistas' => const Color(0xFFE5367A),
    _ => Pal.orange,
  };

  static IconData _icon(String unit) => switch (unit) {
    'dias' => Icons.schedule,
    'conquistas' => Icons.flag,
    _ => Icons.directions_run,
  };

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final color = _color(goal.unit);
    return GameCard(
      color: pal.card,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_icon(goal.unit), color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  goal.name,
                  style: TextStyle(
                    color: pal.heading,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                ChunkyProgress(
                  value: goal.fraction,
                  height: 10,
                  gradient: LinearGradient(
                    colors: [color, color.withValues(alpha: 0.7)],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${formatNumber(goal.value)} / ${formatNumber(goal.target)} '
                  '${goal.unit}'
                  '${goal.completed ? ' · Concluída' : ' · ${goal.missing}'}',
                  style: TextStyle(color: pal.muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Meta da equipe e quem correu por ela — a mecânica de grupo continua aqui.
class _TeamGoalCard extends StatelessWidget {
  const _TeamGoalCard({required this.team});

  final Map<String, dynamic> team;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final goal = WeeklyGoal(
      name: 'Equipe ${team['name']}',
      value: team['distance_km'],
      target: team['target_km'],
      unit: 'km',
    );
    final contributors = (team['contributors'] as List? ?? const []).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GoalTile(goal: goal),
        if (contributors.isNotEmpty) ...[
          const SizedBox(height: 12),
          GameCard(
            color: pal.card,
            child: Column(
              children: [
                for (final c in contributors)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '@${(c as Map)['username']}',
                            style: TextStyle(color: pal.muted, fontSize: 13),
                          ),
                        ),
                        Text(
                          '${formatNumber(c['distance_km'])} km',
                          style: TextStyle(
                            color: pal.heading,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Medal extends StatelessWidget {
  const _Medal({required this.name, required this.earned});

  final String name;
  final bool earned;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return SizedBox(
      width: 84,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: earned ? RGrad.gold : null,
              color: earned ? null : pal.chip,
              border: Border.all(color: pal.border, width: 2),
            ),
            child: Icon(
              earned ? Icons.emoji_events : Icons.lock_outline,
              color: earned ? Colors.white : pal.muted,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            name,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: pal.muted),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ Painel

/// Painel de borda tracejada do estado vazio.
class _DashedPanel extends StatelessWidget {
  const _DashedPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _DashedBorderPainter(color: Pal.of(context).border),
    child: Padding(padding: const EdgeInsets.all(20), child: child),
  );
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color});

  final Color color;

  static const _radius = 22.0;
  static const _dash = 9.0;
  static const _gap = 7.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final rect = Rect.fromLTWH(1, 1, size.width - 2, size.height - 2);
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(_radius)),
      );
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + _dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color;
}

// ------------------------------------------------------------------- Modelos

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

/// Tempo até a meia-noite local, quando o sorteio do dia troca.
String timeUntilMidnight(DateTime now) {
  final left = DateTime(now.year, now.month, now.day + 1).difference(now);
  if (left.inHours >= 1) {
    return '${left.inHours}h ${left.inMinutes % 60}min';
  }
  return '${left.inMinutes}min';
}

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
