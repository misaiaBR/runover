import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../format.dart';
import '../season_pass/backend.dart';
import '../season_pass/models.dart';
import '../season_pass/trail_metrics.dart';
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
/// - Estreito (< 760 px, celular): cabeçalho em cima, card de progresso e
///   banner do passe lado a lado, e a trilha logo abaixo.
/// - Largo (web): cabeçalho, progresso e banner formam uma linha no topo e a
///   trilha ocupa toda a altura que sobra — os cartões crescem com a janela
///   em vez de deixar um vazio embaixo.
/// A trilha é sempre a única rolagem horizontal (arrastável com o mouse na
/// web) e a coluna "Grátis / Passe" fica fixa à esquerda dela. Ela abre no
/// nível atual do jogador e termina num nó de bandeira.
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

  /// Rolagem da trilha horizontal: serve para abrir a tela no nível atual.
  final ScrollController _trailScroll = ScrollController();

  /// Último nível para o qual a trilha já foi posicionada — uma vez por nível,
  /// para não brigar com o arrasto de quem já está olhando a trilha.
  int _centeredLevel = -1;

  bool get _controlled => widget.season != null;

  @override
  bool get busy => _busy;

  @override
  void dispose() {
    _trailScroll.dispose();
    super.dispose();
  }

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
    var claimCommitted = false;
    try {
      await app.api.claimPassReward(level, passTrack(lane));
      claimCommitted = true;
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
      // O POST persistiu mas algo depois falhou: recarrega em vez de
      // oferecer o resgate de novo (o servidor responderia 409).
      if (claimCommitted) _reload();
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
    var premiumCommitted = false;
    try {
      await app.api.unlockPassPremium();
      premiumCommitted = true;
      await app.refreshProfile();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Trilha premium desbloqueada!')),
      );
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      // Mesmo caso do resgate: o POST da compra persistiu, então a trilha
      // recarrega (o servidor já devolve o passe aberto) em vez de deixar o
      // banner oferecer o desbloqueio de novo para um 409.
      if (premiumCommitted) _reload();
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
              _cardsRow(context, season, withHeader: false),
              const SizedBox(height: 16),
              _trail(context, season, claimed, TrailMetrics.base),
            ],
          );
        }
        // Cabeçalho, progresso e banner formam uma linha só a partir de
        // 1.100 px; abaixo disso o cabeçalho sobe numa linha própria para os
        // dois cartões não ficarem espremidos.
        final withHeader = constraints.maxWidth >= 1100;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 24, 32, 16),
              child: Column(
                children: [
                  if (!withHeader) ...[
                    _header(context, season),
                    const SizedBox(height: 12),
                  ],
                  _cardsRow(context, season, withHeader: withHeader),
                ],
              ),
            ),
            // A trilha come a altura que sobra na janela: os cartões crescem
            // até [TrailMetrics.maxScale] em vez de deixar o vazio embaixo.
            // Em janela muito baixa, ela própria rola.
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
                child: LayoutBuilder(
                  builder: (context, box) {
                    final metrics = TrailMetrics.fitting(box.maxHeight);
                    final trail = _trail(
                      context,
                      season,
                      claimed,
                      metrics,
                    );
                    return metrics.trailHeight < box.maxHeight
                        ? Center(child: trail)
                        : SingleChildScrollView(child: trail);
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Linha do topo: progresso e banner lado a lado — e o cabeçalho junto,
  /// quando há largura para os três ([withHeader]).
  Widget _cardsRow(
    BuildContext context,
    Season season, {
    required bool withHeader,
  }) {
    final progress = SeasonPassProgressCard(season: season);
    final banner = season.hasPass
        ? null
        : SeasonPassBanner(
            name: season.name,
            priceCoins: season.premiumPriceCoins,
            onTap: () => _unlockPremium(season.premiumPriceCoins),
          );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (withHeader) ...[
          SizedBox(width: 300, child: _header(context, season)),
          const SizedBox(width: 20),
        ],
        Expanded(flex: withHeader ? 5 : 1, child: progress),
        const SizedBox(width: 20),
        // Sem o banner o espaço continua reservado: o card de progresso não
        // se espicha meia tela de web sozinho.
        Expanded(
          flex: withHeader ? 6 : 1,
          child: banner ?? const SizedBox.shrink(),
        ),
      ],
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
  Widget _trail(
    BuildContext context,
    Season season,
    Set<String> claimed,
    TrailMetrics metrics,
  ) {
    final dragBoth = ScrollConfiguration.of(context).copyWith(
      // Permite arrastar a trilha com o mouse na versão web.
      dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
    );
    _centerOnCurrentLevel(season, metrics);
    return SizedBox(
      height: metrics.trailHeight,
      child: Row(
        children: [
          SeasonPassLaneLabels(metrics: metrics),
          Expanded(
            child: ScrollConfiguration(
              behavior: dragBoth,
              child: ListView(
                controller: _trailScroll,
                scrollDirection: Axis.horizontal,
                children: [
                  for (final level in season.levels)
                    SeasonPassLevelColumn(
                      level: level.level,
                      currentLevel: season.currentLevel,
                      metrics: metrics,
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
                        metrics: metrics,
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
                        metrics: metrics,
                        onClaim: () => _claim(level.level, RewardLane.pass),
                        // "Requer passe" é um caminho de verdade: abre a
                        // mesma confirmação do banner em vez de só avisar.
                        onNeedsPass: () =>
                            _unlockPremium(season.premiumPriceCoins),
                      ),
                    ),
                  _trailEnd(context, metrics),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Nó de bandeira depois do último nível: diz que a trilha acabou, sem
  /// precisar rolar às cegas até o fim dela.
  ///
  /// O nó fica exatamente sobre a linha da trilha (por isso o [Stack] em vez
  /// de uma coluna centralizada: o rótulo embaixo empurraria o nó para cima)
  /// e um pedaço de trilho liga ele ao último nível.
  Widget _trailEnd(BuildContext context, TrailMetrics metrics) {
    final scheme = Theme.of(context).colorScheme;
    final nodeSize = 34 * metrics.scale;
    return SizedBox(
      width: metrics.cardWidth * 1.4,
      height: metrics.trailHeight,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: metrics.cardWidth * 0.55,
              child: Container(
                height: 4,
                color: scheme.surfaceContainerHighest,
              ),
            ),
          ),
          SeasonPassHexNode(
            label: Icon(
              Icons.flag_outlined,
              size: 17 * metrics.scale,
              color: scheme.onPrimary,
            ),
            color: scheme.secondary,
            size: nodeSize,
          ),
          Positioned(
            top: metrics.trailHeight / 2 + nodeSize / 2 + 6 * metrics.scale,
            left: 0,
            right: 0,
            child: Text(
              'Fim da trilha',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11 * metrics.scale,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Abre a trilha no nível atual do jogador — com 30 níveis, começar no 1 é
  /// chegar numa tela de cartões lacrados e ter que procurar a si mesmo.
  void _centerOnCurrentLevel(Season season, TrailMetrics metrics) {
    if (_centeredLevel == season.currentLevel) return;
    _centeredLevel = season.currentLevel;
    final index = season.levels.indexWhere(
      (level) => level.level == season.currentLevel,
    );
    // Nível 1 (ou temporada zerada) já é o começo da trilha.
    if (index <= 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_trailScroll.hasClients) return;
      final position = _trailScroll.position;
      // O nível atual no meio da janela, com a trilha dos dois lados — é ele
      // que o jogador veio olhar.
      final target =
          index * metrics.cardWidth -
          position.viewportDimension / 2 +
          metrics.cardWidth / 2;
      position.jumpTo(target.clamp(0.0, position.maxScrollExtent).toDouble());
    });
  }
}
