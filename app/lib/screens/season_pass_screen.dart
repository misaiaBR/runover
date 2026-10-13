import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../format.dart';
import '../season_pass/backend.dart';
import '../season_pass/models.dart';
import '../season_pass/palette.dart';
import '../season_pass/trail_metrics.dart';
import '../season_pass/widgets/season_pass_header_bar.dart';
import '../season_pass/widgets/season_pass_hex_node.dart';
import '../season_pass/widgets/season_pass_highlight.dart';
import '../season_pass/widgets/season_pass_lane_labels.dart';
import '../season_pass/widgets/season_pass_level_column.dart';
import '../season_pass/widgets/season_pass_progress_bar.dart';
import '../season_pass/widgets/season_pass_reward_card.dart';
import '../services/api_client.dart';
import '../state/app_state.dart';
import '../widgets/runover_ui.dart';
import 'pass_screen.dart';

/// A recompensa aberta no painel de destaque.
typedef RewardSelection = ({int level, RewardLane lane});

/// Passe de Temporada: trilha horizontal de 30 níveis com faixa grátis (laranja,
/// em cima) e faixa do passe (violeta, embaixo).
///
/// A tela é colorida de propósito: as duas faixas carregam o próprio fundo
/// saturado, o nó da trilha mostra os pontos que abrem aquele nível e o painel
/// de destaque mostra a recompensa escolhida em tamanho grande, com o botão que
/// age sobre ela.
///
/// A trilha não resgata no toque. Tocar um cartão seleciona a recompensa; o
/// resgate e a ativação do passe são o botão do painel — um toque que escolhesse
/// e gastasse ao mesmo tempo não teria volta.
///
/// Dois modos:
/// - Controlado: com [season] pronta (testes, demonstração). [onClaim] e
///   [onOpenPass] são callbacks; se [onClaim] lançar erro, o resgate é
///   desfeito na tela com mensagem de erro.
/// - Backend (padrão): sem [season], a tela baixa a temporada (`GET /pass`),
///   resgata (`POST /pass/claim`) e desbloqueia o premium (`POST /pass/premium`)
///   sozinha, recarregando após cada operação.
///
/// As recompensas do passe são só visuais: nada que dê vantagem no mapa ou no
/// ranking.
///
/// Layout responsivo, sem "caixa" estreita na web:
/// - Largo (>= 900 px): cabeçalho e barra de nível em cima, trilha e painel de
///   destaque lado a lado abaixo — os cartões crescem com a janela em vez de
///   deixar um vazio embaixo.
/// - Estreito: tudo empilhado, e o painel vem depois da trilha.
/// A trilha é sempre a única rolagem horizontal (arrastável com o mouse na web)
/// e a coluna "Grátis / Passe" fica fixa à esquerda dela. Ela abre no nível
/// atual do jogador e termina num nó de bandeira.
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

  /// Recompensa aberta no painel de destaque; `null` = ainda não tocada, e a
  /// tela escolhe uma (ver [SeasonPassScreen]).
  RewardSelection? _selection;

  bool get _controlled => widget.season != null;

  /// Acima disso o painel de destaque divide a linha com a trilha.
  static const double _wideLayout = 900;

  /// Respiro do tabuleiro: o fundo roxo que margeia as faixas em cima e em
  /// baixo. A trilha e a decisão de "cabe ou rola" usam o mesmo número.
  static const double _boardPadding = 24;

  /// Altura aproximada do conteúdo do painel de destaque. Acima dela a janela
  /// estica o painel; abaixo, ele rola — o número é a régua da escolha, não uma
  /// medida exata do texto do item.
  static const double _panelNaturalHeight = 430;

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
      // painel oferecer o desbloqueio de novo para um 409.
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
        backgroundColor: Pal.of(context).panel,
        appBar: _appBar(context),
        body: _layout(context, widget.season!, _claimed),
      );
    }
    return Scaffold(
      backgroundColor: Pal.of(context).panel,
      appBar: _appBar(context),
      body: FutureBuilder<Season>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          // Uma resposta válida de `GET /pass` sempre traz os 30 níveis. Sem
          // nenhum deles o payload chegou quebrado e não há trilha a montar: a
          // tela trata isso como falha — com a nova tentativa na tela — em vez
          // de estourar na busca do nível em destaque.
          final season = snapshot.data;
          if (snapshot.hasError || season == null || season.levels.isEmpty) {
            final pal = Pal.of(context);
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Não foi possível carregar o passe.',
                    style: TextStyle(color: pal.heading),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _reload,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: pal.heading,
                      side: BorderSide(color: pal.border),
                    ),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Tentar novamente'),
                  ),
                ],
              ),
            );
          }
          return _layout(
            context,
            season,
            {...season.claimed, ..._pending},
          );
        },
      ),
    );
  }

  /// A barra veste o painel do tema — o mesmo fundo do corpo da tela — para não
  /// abrir faixa entre o cabeçalho e a trilha. No escuro é o roxo de sempre; no
  /// claro ela acompanha o resto do aplicativo.
  AppBar _appBar(BuildContext context) {
    final pal = Pal.of(context);
    return AppBar(
      title: const Text('Passe de Temporada'),
      backgroundColor: pal.panel,
      foregroundColor: pal.heading,
      elevation: 0,
      scrolledUnderElevation: 0,
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
    final selection = _selected(season, claimed);
    final header = SeasonPassHeaderBar(
      seasonName: season.name,
      remaining: _remaining(season.endsAt),
      hasPass: season.hasPass,
      dracmas: _controlled
          ? null
          : context.read<AppState>().profile?.coinsBalance,
    );
    final progress = SeasonPassProgressBar(season: season);
    final highlight = _highlight(season, claimed, selection);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _wideLayout) {
          // `SingleChildScrollView` + `Column`, e não `ListView`: o painel é a
          // peça onde ficam o resgate e o preço do passe, e uma lista preguiçosa
          // deixaria o botão fora da tela de quem acabou de tocar um cartão.
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                const SizedBox(height: 12),
                progress,
                const SizedBox(height: 16),
                _trail(context, season, claimed, selection, TrailMetrics.base),
                const SizedBox(height: 16),
                highlight,
              ],
            ),
          );
        }
        return Column(
          children: [
            // Faixa do topo do mock: a barra da temporada e, logo abaixo, a
            // barra do nível ocupando a largura toda — as duas em coluna, e não
            // lado a lado, para o nome da temporada caber inteiro.
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 20, 32, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [header, const SizedBox(height: 12), progress],
              ),
            ),
            // A trilha e o painel dividem a altura que sobra: os cartões
            // crescem até [TrailMetrics.maxScale] e o painel veste a altura da
            // janela, para não sobrar faixa vazia embaixo de nenhum dos dois.
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
                child: LayoutBuilder(
                  builder: (context, box) {
                    // O tabuleiro paga o próprio respiro: a escala aproveita a
                    // altura que sobra depois dela.
                    final metrics = TrailMetrics.fitting(
                      box.maxHeight - _boardPadding,
                    );
                    final trail = _trail(
                      context,
                      season,
                      claimed,
                      selection,
                      metrics,
                    );
                    // A escala já saiu da altura disponível, então o caso
                    // normal é caber justo: daí o `<=`.
                    final body =
                        metrics.trailHeight + _boardPadding <= box.maxHeight
                        ? Align(alignment: Alignment.topLeft, child: trail)
                        : SingleChildScrollView(child: trail);
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: body),
                        const SizedBox(width: 20),
                        SizedBox(
                          width: 330,
                          child: LayoutBuilder(
                            builder: (context, panel) {
                              // O painel veste a altura da janela — mas só
                              // quando a janela tem a altura que o conteúdo
                              // pede, e com o texto ampliado essa altura cresce
                              // junto. Abaixo dela o painel rola, porque o
                              // botão de resgate é a peça que não pode sair da
                              // tela.
                              final scale =
                                  MediaQuery.textScalerOf(context).scale(14) /
                                  14;
                              final needed = _panelNaturalHeight * scale;
                              if (panel.maxHeight < needed) {
                                return SingleChildScrollView(child: highlight);
                              }
                              return SizedBox(
                                height: panel.maxHeight,
                                child: _highlight(
                                  season,
                                  claimed,
                                  selection,
                                  fill: true,
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Recompensa em destaque: a tocada, ou a que a tela escolhe ao abrir.
  RewardSelection _selected(Season season, Set<String> claimed) {
    final current = _selection;
    if (current != null &&
        season.levels.any((level) => level.level == current.level)) {
      return current;
    }
    return _defaultSelection(season, claimed);
  }

  /// Escolta de abertura do painel, para a tela não nascer com um vazio ao
  /// lado da trilha:
  /// 1. o resgate pendente mais alto (faixa grátis primeiro — é a que todo
  ///    jogador tem);
  /// 2. sem resgate, o passe no nível atual: é o cartão que explica o preço;
  /// 3. com o passe aberto, o próximo nível por abrir;
  /// 4. trilha toda resgatada, o último nível.
  RewardSelection _defaultSelection(Season season, Set<String> claimed) {
    RewardState stateOf(SeasonLevel level, RewardLane lane) => rewardStateOf(
      season: season,
      claimed: claimed,
      level: level,
      lane: lane,
    );
    for (final level in season.levels.reversed) {
      if (level.level > season.currentLevel) continue;
      for (final lane in RewardLane.values) {
        if (stateOf(level, lane) == RewardState.claimable) {
          return (level: level.level, lane: lane);
        }
      }
    }
    for (final level in season.levels.reversed) {
      if (stateOf(level, RewardLane.pass) == RewardState.needsPass) {
        return (level: level.level, lane: RewardLane.pass);
      }
    }
    for (final level in season.levels) {
      if (stateOf(level, RewardLane.free) == RewardState.locked) {
        return (level: level.level, lane: RewardLane.free);
      }
    }
    final last = season.levels.last;
    return (level: last.level, lane: RewardLane.free);
  }

  Widget _highlight(
    Season season,
    Set<String> claimed,
    RewardSelection selection, {
    bool fill = false,
  }) {
    final level = season.levels.firstWhere(
      (item) => item.level == selection.level,
    );
    final lane = selection.lane;
    return SeasonPassHighlightPanel(
      level: level.level,
      threshold: level.threshold,
      lane: lane,
      reward: lane == RewardLane.free ? level.free : level.pass,
      state: rewardStateOf(
        season: season,
        claimed: claimed,
        level: level,
        lane: lane,
      ),
      premiumPriceCoins: season.premiumPriceCoins,
      fill: fill,
      onClaim: () => _pin(selection, () => _claim(level.level, lane)),
      onActivatePass: () =>
          _pin(selection, () => _unlockPremium(season.premiumPriceCoins)),
    );
  }

  /// Fixa o painel na recompensa em que o jogador agiu, antes de agir.
  ///
  /// Sem isso a escolha ainda automática (nenhum cartão tocado) faria o painel
  /// saltar para a próxima ação no meio do próprio resgate — o cartão acabado
  /// de resgatar sumiria da tela bem na hora de confirmar o visto.
  void _pin(RewardSelection selection, VoidCallback act) {
    if (_selection != selection) setState(() => _selection = selection);
    act();
  }

  /// A trilha: rótulos fixos à esquerda + níveis em rolagem horizontal.
  ///
  /// Não desenha caixa própria — a tela inteira já é o painel do passe, no tema
  /// que o jogador usa, então sobra só o respiro vertical que alinha as duas
  /// faixas.
  Widget _trail(
    BuildContext context,
    Season season,
    Set<String> claimed,
    RewardSelection selection,
    TrailMetrics metrics,
  ) {
    final dragBoth = ScrollConfiguration.of(context).copyWith(
      // Permite arrastar a trilha com o mouse na versão web.
      dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
    );
    _centerOnCurrentLevel(season, metrics);
    return Container(
      height: metrics.trailHeight + _boardPadding,
      padding: const EdgeInsets.symmetric(vertical: _boardPadding / 2),
      child: Row(
        children: [
          const SizedBox(width: 6),
          SeasonPassLaneLabels(metrics: metrics),
          const SizedBox(width: 6),
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
                      threshold: level.threshold,
                      currentLevel: season.currentLevel,
                      metrics: metrics,
                      freeCard: _card(
                        season,
                        claimed,
                        level,
                        RewardLane.free,
                        selection,
                        metrics,
                      ),
                      passCard: _card(
                        season,
                        claimed,
                        level,
                        RewardLane.pass,
                        selection,
                        metrics,
                      ),
                    ),
                  _trailEnd(context, metrics),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _card(
    Season season,
    Set<String> claimed,
    SeasonLevel level,
    RewardLane lane,
    RewardSelection selection,
    TrailMetrics metrics,
  ) {
    return SeasonPassRewardCard(
      reward: lane == RewardLane.free ? level.free : level.pass,
      state: rewardStateOf(
        season: season,
        claimed: claimed,
        level: level,
        lane: lane,
      ),
      level: level.level,
      premium: lane == RewardLane.pass,
      metrics: metrics,
      selected: selection.level == level.level && selection.lane == lane,
      onSelect: () =>
          setState(() => _selection = (level: level.level, lane: lane)),
    );
  }

  /// Nó de bandeira depois do último nível: diz que a trilha acabou, sem
  /// precisar rolar às cegas até o fim dela.
  ///
  /// O nó fica exatamente sobre a linha da trilha (por isso o [Stack] em vez
  /// de uma coluna centralizada: o rótulo embaixo empurraria o nó para cima)
  /// e um pedaço de trilho liga ele ao último nível.
  Widget _trailEnd(BuildContext context, TrailMetrics metrics) {
    final pal = Pal.of(context);
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
              child: Container(height: 4, color: pal.track),
            ),
          ),
          SeasonPassHexNode(
            label: Icon(
              Icons.flag_outlined,
              size: 17 * metrics.scale,
              color: trailAccentInk,
            ),
            color: trailAccent,
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
                color: pal.muted,
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
