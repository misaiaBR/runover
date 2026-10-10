import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../format.dart';
import '../season_pass/backend.dart';
import '../season_pass/models.dart';
import '../season_pass/widgets/season_pass_banner.dart';
import '../season_pass/widgets/season_pass_hex_node.dart';
import '../season_pass/widgets/season_pass_lane_labels.dart';
import '../season_pass/widgets/season_pass_level_column.dart';
import '../season_pass/widgets/season_pass_progress_card.dart';
import '../season_pass/widgets/season_pass_reward_card.dart';
import '../services/api_client.dart';
import '../state/app_state.dart';
import 'pass_screen.dart';

/// Passe de Temporada: trilha horizontal de níveis com faixa grátis (em cima)
/// e faixa do passe (embaixo).
///
/// Dois modos:
/// - Controlado: com [season] pronta (testes, demonstração). [onClaim] e
///   [onOpenPass] são callbacks; se [onClaim] lançar erro, o resgate é
///   desfeito na tela com mensagem de erro.
/// - Backend (padrão): sem [season], a tela baixa a temporada (`GET /pass`),
///   resgata (`POST /pass/claim`) e desbloqueia o premium (`POST
///   /pass/premium`) sozinha, recarregando após cada operação.
///
/// As recompensas do passe são só visuais: nada que dê vantagem no mapa ou
/// no ranking.
///
/// Layout responsivo, sem "caixa" estreita na web:
/// - Estreito (< 760 px, celular): coluna única com uma só rolagem vertical.
/// - Largo (web): cabeçalho, progresso e banner numa coluna lateral de 340 px
///   e a trilha ocupando todo o restante da largura — a página só mostra
///   barra de rolagem se o conteúdo exceder a altura.
/// A trilha é sempre a única rolagem horizontal (arrastável com o mouse na
/// web) e a coluna "Grátis / Passe" fica fixa à esquerda dela.
class SeasonPassScreen extends StatefulWidget {
  const SeasonPassScreen({super.key, this.season, this.onClaim, this.onOpenPass});

  /// Temporada pronta. Quando nulo, a tela carrega do backend sozinha.
  final Season? season;

  /// Chamado ao resgatar no modo controlado. Se lançar erro, o resgate é
  /// desfeito na tela.
  final Future<void> Function(int level, RewardLane lane)? onClaim;
  final VoidCallback? onOpenPass;

  @override
  State<SeasonPassScreen> createState() => _SeasonPassScreenState();
}

class _SeasonPassScreenState extends State<SeasonPassScreen>
    with AccountWatcher<SeasonPassScreen> {
  /// Resgates otimistas ainda sem confirmação da recarga (modo backend).
  final Set<String> _pending = {};

  /// Resgates otimistas do modo controlado.
  late final Set<String> _claimed = {...?widget.season?.claimed};

  late Future<Season> _future = _startLoad();
  bool _busy = false;

  bool get _controlled => widget.season != null;

  @override
  bool get busy => _busy;

  @override
  void didChangeDependencies() {
    // Modo controlado (testes/demonstração): sem AppState na árvore.
    if (_controlled) return;
    super.didChangeDependencies();
  }

  @override
  void onAccountChanged() {
    if (!_controlled) _reload();
  }

  /// A tela pode ser descartada antes da resposta chegar; um `Future` sem
  /// listener denuncia o próprio erro como exceção não tratada.
  Future<Season> _startLoad() {
    final future = loadSeasonPass(context.read<AppState>().api);
    future.then<void>((_) {}, onError: (Object _) {});
    return future;
  }

  void _reload() {
    markRevisionSeen();
    setState(() {
      _future = _startLoad();
    });
  }

  Future<void> _claim(int level, RewardLane lane) async {
    if (_controlled) return _claimControlled(level, lane);
    if (_busy) return;
    final key = seasonRewardKey(level, lane);
    final app = context.read<AppState>();
    setState(() {
      _busy = true;
      _pending.add(key); // atualiza na hora; desfaz se falhar
    });
    try {
      await app.api.claimPassReward(level, passTrack(lane));
      await app.refreshProfile();
      if (!mounted) return;
      // A revisão que o próprio resgate provocou fica consumida: o flush do
      // fim não busca de novo.
      markRevisionSeen();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Recompensa resgatada!')));
      final reload = _startLoad();
      setState(() {
        _future = reload;
      });
      await reload;
      if (!mounted) return;
      setState(() => _pending.clear());
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _pending.remove(key));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        flushAccountRefresh();
      }
    }
  }

  Future<void> _claimControlled(int level, RewardLane lane) async {
    final key = seasonRewardKey(level, lane);
    setState(() => _claimed.add(key)); // atualiza na hora; desfaz se falhar
    try {
      await widget.onClaim?.call(level, lane);
    } catch (_) {
      if (!mounted) return;
      setState(() => _claimed.remove(key));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível resgatar. Tente de novo.'),
        ),
      );
    }
  }

  Future<void> _unlockPremium(int price) async {
    if (_controlled) {
      widget.onOpenPass?.call();
      return;
    }
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Trilha premium?'),
        content: Text(
          'Desbloqueia as recompensas premium desta temporada por '
          '${formatPoints(price)} dracmas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Agora não'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Desbloquear'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final app = context.read<AppState>();
    setState(() => _busy = true);
    try {
      await app.api.unlockPassPremium();
      await app.refreshProfile();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Trilha premium desbloqueada!')),
      );
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        flushAccountRefresh();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_controlled) {
      return Scaffold(
        appBar: AppBar(title: const Text('Passe de Temporada')),
        body: _layout(context, widget.season!, _claimed),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Passe de Temporada')),
      body: FutureBuilder<Season>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Não foi possível carregar o passe.'),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Tentar novamente'),
                  ),
                ],
              ),
            );
          }
          final season = snapshot.data!;
          return _layout(
            context,
            season,
            {...season.claimed, ..._pending},
          );
        },
      ),
    );
  }

  String _remaining(DateTime endsAt) {
    final left = endsAt.difference(DateTime.now());
    if (left.isNegative) return 'Temporada encerrada';
    final days = left.inDays;
    final hours = left.inHours % 24;
    if (days > 0) return 'Termina em $days d $hours h';
    final minutes = left.inMinutes % 60;
    if (hours > 0) return 'Termina em $hours h $minutes min';
    return 'Termina em $minutes min';
  }

  Widget _layout(BuildContext context, Season season, Set<String> claimed) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _header(context, season),
              const SizedBox(height: 12),
              SeasonPassProgressCard(season: season),
              const SizedBox(height: 16),
              _trail(context, season, claimed),
              const SizedBox(height: 12),
              if (!season.hasPass)
                SeasonPassBanner(
                  name: season.name,
                  onTap: () => _unlockPremium(season.premiumPriceCoins),
                ),
            ],
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 340,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(context, season),
                    const SizedBox(height: 12),
                    SeasonPassProgressCard(season: season),
                    const SizedBox(height: 12),
                    if (!season.hasPass)
                      SeasonPassBanner(
                        name: season.name,
                        onTap: () => _unlockPremium(season.premiumPriceCoins),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 32),
              Expanded(child: _trail(context, season, claimed)),
            ],
          ),
        );
      },
    );
  }

  /// Cabeçalho: hexágono da temporada, nome e contagem regressiva.
  Widget _header(BuildContext context, Season season) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        SeasonPassHexNode(
          label: Icon(Icons.flag, color: scheme.onPrimary),
          color: scheme.primary,
          size: 48,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Temporada ${season.name}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                _remaining(season.endsAt),
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// A trilha: rótulos fixos à esquerda + níveis em rolagem horizontal.
  Widget _trail(BuildContext context, Season season, Set<String> claimed) {
    final dragBoth = ScrollConfiguration.of(context).copyWith(
      // Permite arrastar a trilha com o mouse na versão web.
      dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
    );
    return SizedBox(
      height:
          SeasonPassLevelColumn.cardSlotHeight * 2 +
          SeasonPassLevelColumn.railHeight,
      child: Row(
        children: [
          const SeasonPassLaneLabels(),
          Expanded(
            child: ScrollConfiguration(
              behavior: dragBoth,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final level in season.levels)
                    SeasonPassLevelColumn(
                      level: level.level,
                      currentLevel: season.currentLevel,
                      freeCard: SeasonPassRewardCard(
                        reward: level.free,
                        state: rewardStateOf(
                          season: season,
                          claimed: claimed,
                          level: level,
                          lane: RewardLane.free,
                        ),
                        level: level.level,
                        premium: false,
                        onClaim: () => _claim(level.level, RewardLane.free),
                      ),
                      passCard: SeasonPassRewardCard(
                        reward: level.pass,
                        state: rewardStateOf(
                          season: season,
                          claimed: claimed,
                          level: level,
                          lane: RewardLane.pass,
                        ),
                        level: level.level,
                        premium: true,
                        onClaim: () => _claim(level.level, RewardLane.pass),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
