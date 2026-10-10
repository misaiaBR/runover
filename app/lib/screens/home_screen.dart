import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../format.dart';
import '../models.dart';
import '../services/api_client.dart';
import '../state/app_state.dart';
import '../widgets/centered_content.dart';
import '../widgets/play_mode_sheet.dart';
import '../widgets/slanted_menu_icon.dart';
import 'app_footer.dart';
import 'map_screen.dart';
import 'tracking_screen.dart';
import 'notifications_screen.dart';
import 'pass_screen.dart';
import 'profile_screen.dart';
import 'shop_screen.dart';
import 'team_hub_screen.dart';

/// Formata quilômetros no padrão pt-BR (8,4 km em vez de 8.40 km).
String formatKm(num value) {
  final trimmed = value
      .toStringAsFixed(2)
      .replaceAll(RegExp(r'0+$'), '')
      .replaceAll(RegExp(r'[.,]$'), '');
  return '${trimmed.replaceAll('.', ',')} km';
}

/// Formata ritmo em s/km no padrão 5'32".
String formatPace(int totalSeconds) {
  final minutes = totalSeconds ~/ 60;
  final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
  return "$minutes'$seconds\"";
}

/// Paleta da home: acentos fixos + superfícies que seguem o brilho do tema.
/// Use `Pal.of(context)` dentro de `build`; nunca os valores `dark`/`light`
/// direto, para o card acompanhar a troca claro/escuro em tempo real.
class Pal {
  // Acentos: iguais no claro e no escuro.
  static const orange = Color(0xFFFF7F4D);
  static const gold = Color(0xFFFFC93C);
  static const teal = Color(0xFF3DDBB0);
  static const purple = Color(0xFF8B7CFF);
  static const purpleDark = Color(0xFF2A2240);
  static const onAccent = Color(0xFF1A0E08);

  /// Acento do modo de equipe. O `colorScheme.tertiary` não é definido no tema
  /// e o Material 3 o derivava num oliva de contraste ruim com qualquer tinta.
  static const team = Color(0xFF2F6FD0);

  final Color hud;
  final Color card;
  final Color chip;
  final Color border;
  final Color muted;
  final Color heading;
  final Color chipText;
  final Color hardShadow;

  const Pal._({
    required this.hud,
    required this.card,
    required this.chip,
    required this.border,
    required this.muted,
    required this.heading,
    required this.chipText,
    required this.hardShadow,
  });

  static const dark = Pal._(
    hud: Color(0xFF1A1C27),
    card: Color(0xFF1C1E2B),
    chip: Color(0xFF252838),
    border: Color(0xFF2A2D3D),
    muted: Color(0xFFB8BCCB),
    heading: Colors.white,
    chipText: Colors.white,
    hardShadow: Color(0xFF0A0B10),
  );

  static const light = Pal._(
    hud: Colors.white,
    card: Colors.white,
    chip: Color(0xFFEDF1F6),
    border: Color(0xFFDDE3EA),
    muted: Color(0xFF5B6472),
    heading: Color(0xFF161B22),
    chipText: Color(0xFF161B22),
    hardShadow: Color(0x14000000),
  );

  static Pal of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

/// Tinta legível sobre um fundo de acento: devolve o candidato de maior
/// contraste WCAG. Fixar `Pal.onAccent` deixava o texto abaixo de 4:1 sobre o
/// teal da rota e sobre o azul da equipe; branco passa de 4,5:1 nesses fundos.
Color inkOnAccent(Color background) {
  final bg = background.computeLuminance();
  final ink = Pal.onAccent.computeLuminance();
  double ratio(double fg) {
    final hi = bg > fg ? bg : fg;
    final lo = bg > fg ? fg : bg;
    return (hi + 0.05) / (lo + 0.05);
  }

  // Luminância do branco é 1,0 por definição.
  return ratio(ink) >= ratio(1.0) ? Pal.onAccent : Colors.white;
}

/// Tela inicial leve: o mapa só é carregado quando o usuário pede.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.onOpenMenu, this.menuKey, this.startKey});

  final VoidCallback? onOpenMenu;

  /// Chaves para o tour guiado destacar estes controles.
  final Key? menuKey;
  final Key? startKey;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  TeamDetail? _team;
  Map<String, dynamic>? _progress;
  bool _teamFailed = false;
  bool _progressFailed = false;

  @override
  void initState() {
    super.initState();
    final api = context.read<AppState>().api;
    unawaited(
      context.read<AppState>().retryPendingRuns().catchError(
        (Object _) => false,
      ),
    );
    unawaited(_loadCardData(api));
  }

  /// Dados reais dos cards (equipe e corridas). Erro de rede não vira
  /// estado vazio: marca falha e oferece nova tentativa no próprio card.
  Future<void> _loadCardData(ApiClient api) async {
    TeamDetail? team;
    Map<String, dynamic>? progress;
    var teamFailed = false;
    var progressFailed = false;
    try {
      team = await api.getMyTeam();
    } catch (_) {
      teamFailed = true;
    }
    try {
      progress = await api.getProgress();
    } catch (_) {
      progressFailed = true;
    }
    if (!mounted) return;
    setState(() {
      _team = team;
      _progress = progress;
      _teamFailed = teamFailed;
      _progressFailed = progressFailed;
    });
  }

  void _retryCards() {
    unawaited(_loadCardData(context.read<AppState>().api));
  }

  List<String> _speedStats() {
    if (_progressFailed) return const ['Falha ao carregar', 'Tente de novo'];
    final runs = (_progress?['runs_count'] as num?)?.toInt() ?? 0;
    if (runs <= 0) return const ['Nenhuma corrida'];
    final longest = (_progress?['longest_run_km'] as num?)?.toDouble() ?? 0;
    return [
      '$runs ${runs == 1 ? 'corrida' : 'corridas'}',
      'recorde ${formatKm(longest)}',
    ];
  }

  String? _speedBadge() {
    if (_progressFailed) return null;
    final best = (_progress?['fastest_pace_seconds_per_km'] as num?)?.toInt();
    if (best == null) return null;
    return 'PB ${formatPace(best)}';
  }

  List<String> _teamStats() {
    if (_teamFailed) return const ['Falha ao carregar', 'Tente de novo'];
    final team = _team;
    if (team == null) return const ['Sem equipe', 'Crie ou entre'];
    final members = team.memberCount;
    return [
      '$members ${members == 1 ? 'membro' : 'membros'}',
      '${team.onlineCount} online',
      'Nv ${team.level}',
    ];
  }

  String? _teamBadge() {
    final team = _team;
    if (team == null) return null;
    final pending = team.pendingRequests.length;
    if (pending > 0) {
      return '$pending ${pending == 1 ? 'pedido' : 'pedidos'}';
    }
    if (team.onlineCount > 0) return '${team.onlineCount} online';
    return null;
  }

  /// Jogar na Dominação começa pela escolha da mecânica — o mapa sozinho não
  /// diz o que fazer. Laço livre pula o mapa e abre o tracking direto; as
  /// outras duas passam pelo mapa já focado na mecânica (dica + camadas).
  void _playDomination() {
    showPlayModeSheet(
      context,
      onSelect: (mode) {
        switch (mode) {
          case PlayMode.freeLoop:
            Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const TrackingScreen()));
          case PlayMode.huntWild:
          case PlayMode.challenge:
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => MapScreen(focus: mode)),
            );
        }
      },
    );
  }

  Future<void> _openTeam() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const TeamHubScreen()));
    if (!mounted) return;
    unawaited(_loadCardData(context.read<AppState>().api));
  }

  void _openProfile() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ProfileScreen()));
  }

  Future<void> _openShop() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ShopScreen()));
    if (!mounted) return;
    try {
      await context.read<AppState>().refreshProfile();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final pal = Pal.of(context);
    final profile = context.watch<AppState>().profile;
    final zones = profile?.territoriesCount ?? 0;
    final rank = profile?.rankPosition;
    final level = profile?.level ?? 1;
    final levelProgress = profile?.levelProgress ?? 0;
    final streakDays =
        (_progress?['streak_days'] as num?)?.toInt() ??
        (_progress?['streakDays'] as num?)?.toInt() ??
        0;
    final coins = profile?.coinsBalance ?? 0;
    final name = profile?.username ?? 'Corredor';

    final modes = [
      _GameMode(
        title: 'Dominação de territórios',
        description: 'Corra, reclame zonas no mapa e defenda o que é seu.',
        icon: Icons.map_outlined,
        color: colors.primary,
        action: 'Jogar',
        pills: [
          '$zones ${zones == 1 ? 'zona sua' : 'zonas suas'}',
          if (rank != null) 'Ranking #$rank',
        ],
        tag: 'Em andamento',
        highlighted: true,
        onPlay: _playDomination,
      ),
      _GameMode(
        title: 'Desafio de velocidade',
        description:
            'Voltas cronometradas. Bata seu recorde e suba no ranking.',
        icon: Icons.timer_outlined,
        color: colors.secondary,
        // O modo ainda não tem regra definida: o card fica na tela como
        // antecipação, mas sem botão jogável. A falha de carregamento continua
        // acionável porque o mesmo dado alimenta a sequência do HUD.
        action: _progressFailed ? 'Tentar de novo' : 'Em breve',
        pills: _speedStats(),
        tag: _speedBadge(),
        highlighted: false,
        onPlay: _progressFailed ? _retryCards : null,
      ),
      _GameMode(
        title: 'Pit stop de equipe',
        description: 'Una forças com o time e cumpra objetivos relâmpago.',
        icon: Icons.groups_outlined,
        color: Pal.team,
        action: _teamFailed ? 'Tentar de novo' : 'Entrar',
        pills: _teamStats(),
        tag: _teamBadge(),
        highlighted: !_teamFailed,
        onPlay: _teamFailed ? _retryCards : _openTeam,
      ),
    ];

    final topSections = <Widget>[
      Row(
        children: [
          Semantics(
            button: true,
            label: 'Abrir menu',
            child: IconButton(
              key: widget.menuKey,
              tooltip: 'Menu',
              icon: const SlantedMenuIcon(),
              onPressed: widget.onOpenMenu,
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Notificações',
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      _Hud(
        name: name,
        level: level,
        levelProgress: levelProgress,
        streakDays: streakDays,
        coins: coins,
        onProfileTap: _openProfile,
        onShopTap: _openShop,
      ),
      const SizedBox(height: 16),
      _StoreCta(coins: coins, onTap: _openShop),
      const SizedBox(height: 16),
      _MissionBanner(
        text: 'Conquiste 1 território novo hoje e mantenha sua sequência.',
        rewardXp: 150,
      ),
    ];

    final sectionTitle = Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 4),
      child: Text(
        'ESCOLHA SEU MODO',
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.8,
          color: pal.heading,
        ),
      ),
    );

    return SafeArea(
      child: CenteredContent(
        maxWidth: 1280,
        child: LayoutBuilder(
          builder: (_, c) {
            // O passe vira o segundo painel da versão larga, então a
            // distribuição de altura só acontece quando há espaço para os
            // dois; abaixo disso tudo rola junto na ListView.
            if (c.maxWidth >= 700 && c.maxHeight >= 1000) {
              return _WideHome(
                top: topSections,
                sectionTitle: sectionTitle,
                modes: modes,
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(28, 12, 28, 32),
              children: [
                ...topSections,
                const SizedBox(height: 20),
                sectionTitle,
                const SizedBox(height: 8),
                _ModeGrid(modes: modes),
                const SizedBox(height: 20),
                const PassCard(),
                const AppFooter(),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Home em janela larga e alta: o grid de modos absorve a sobra vertical, o
/// passe fica no cartão compacto que abre a trilha, e o rodapé desce com tudo.
/// A [ListView] padrão deixava o conteúdo ancorado no topo e uma faixa vazia
/// embaixo do rodapé.
class _WideHome extends StatelessWidget {
  const _WideHome({
    required this.top,
    required this.sectionTitle,
    required this.modes,
  });

  final List<Widget> top;
  final Widget sectionTitle;
  final List<_GameMode> modes;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 12, 28, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: top,
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: sectionTitle,
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 0),
              child: _ModeGrid(modes: modes, stretch: true),
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: const PassCard(),
          ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 28),
            child: AppFooter(),
          ),
        ],
      ),
    );
  }
}

/// Dados de um modo de jogo para o grid.
class _GameMode {
  const _GameMode({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.action,
    required this.pills,
    required this.onPlay,
    this.tag,
    this.highlighted = false,
  });

  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final String action;
  final List<String> pills;
  final String? tag;
  final bool highlighted;

  /// `null` mantém o card na tela sem oferecer o modo.
  final VoidCallback? onPlay;
}

// ---------------------------------------------------------------- HUD

class _Hud extends StatelessWidget {
  const _Hud({
    required this.name,
    required this.level,
    required this.levelProgress,
    required this.streakDays,
    required this.coins,
    required this.onProfileTap,
    required this.onShopTap,
  });

  final String name;
  final int level, streakDays, coins;

  /// 0..1 do XP já ganho no nível atual: é o arco dourado da moldura.
  final double levelProgress;
  final VoidCallback onProfileTap;
  final VoidCallback onShopTap;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    // A moldura inteira é o alvo que abre o perfil — antes só o selo pequeno
    // respondia ao toque. Ela também é o anel de XP do nível, que voltou ao HUD
    // como arco em vez de barra.
    final avatar = Semantics(
      button: true,
      label: 'Abrir perfil',
      child: GestureDetector(
        onTap: onProfileTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 54,
          height: 54,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              _LevelRing(
                progress: levelProgress,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Pal.orange,
                    ),
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : 'V',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF2A1308),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: -6,
                bottom: -2,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: Pal.purple,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: pal.hud, width: 2),
                  ),
                  child: Text(
                    'NV $level',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // O número do nível fica no selo do avatar e o XP que falta para o próximo
    // fica no arco da moldura: a barra de XP não volta ao HUD.
    final identity = Expanded(
      child: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 13, color: pal.muted),
      ),
    );

    final streak = _StreakTier.of(streakDays, pal);
    final chips = [
      _StatChip(
        icon: streak.icon,
        color: streak.color,
        iconSize: streak.size,
        iconShadows: streak.shadows,
        label: '$streakDays dias',
      ),
      const SizedBox(width: 8),
      GestureDetector(
        onTap: onShopTap,
        child: _StatChip(
          icon: Icons.monetization_on,
          color: Pal.gold,
          label: formatPoints(coins),
        ),
      ),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: pal.hud,
        border: Border(bottom: BorderSide(color: pal.border, width: 2)),
      ),
      child: LayoutBuilder(
        builder: (_, c) => c.maxWidth >= 560
            ? Row(
                children: [
                  avatar,
                  const SizedBox(width: 14),
                  identity,
                  const SizedBox(width: 12),
                  ...chips,
                ],
              )
            : Column(
                children: [
                  Row(children: [avatar, const SizedBox(width: 14), identity]),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Row(children: chips),
                  ),
                ],
              ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.color,
    required this.label,
    this.iconSize = 18,
    this.iconShadows = const [],
  });

  final IconData icon;
  final Color color;
  final String label;
  final double iconSize;
  final List<Shadow> iconShadows;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: pal.chip,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: color,
            size: iconSize,
            shadows: iconShadows.isEmpty ? null : iconShadows,
          ),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 14, color: pal.chipText)),
        ],
      ),
    );
  }
}

/// A chama da sequência escala por faixa de dias: sem sequência ela se apaga, e
/// 150 dias não pode ter a mesma cara de 3.
class _StreakTier {
  const _StreakTier(this.icon, this.size, this.color, this.shadows);

  final IconData icon;
  final double size;
  final Color color;
  final List<Shadow> shadows;

  static const _glow = [Shadow(color: Color(0x99FFC93C), blurRadius: 10)];

  static _StreakTier of(int days, Pal pal) {
    if (days <= 0) {
      return _StreakTier(
        Icons.local_fire_department_outlined,
        16,
        pal.muted,
        const [],
      );
    }
    if (days < 7) {
      return const _StreakTier(
        Icons.local_fire_department,
        16,
        Pal.orange,
        [],
      );
    }
    if (days < 30) {
      return const _StreakTier(
        Icons.local_fire_department,
        20,
        Pal.orange,
        [],
      );
    }
    if (days < 100) {
      return const _StreakTier(
        Icons.local_fire_department,
        24,
        Pal.gold,
        [],
      );
    }
    return const _StreakTier(
      Icons.local_fire_department,
      26,
      Pal.gold,
      _glow,
    );
  }
}

/// A moldura do avatar como anel de XP do nível: trilho discreto com o arco
/// dourado crescendo no sentido do relógio a partir do topo.
class _LevelRing extends StatelessWidget {
  const _LevelRing({required this.progress, required this.child});

  final double progress;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _LevelRingPainter(
        value: progress.clamp(0.0, 1.0),
        // O trilho é ouro apagado, não cinza: a moldura continua sendo a
        // moldura dourada do avatar mesmo com o nível zerado.
        track: Pal.gold.withValues(alpha: 0.28),
        fill: Pal.gold,
      ),
      child: child,
    );
  }
}

class _LevelRingPainter extends CustomPainter {
  const _LevelRingPainter({
    required this.value,
    required this.track,
    required this.fill,
  });

  final double value;
  final Color track;
  final Color fill;

  static const _stroke = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - _stroke / 2;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke,
    );
    if (value <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * value,
      false,
      Paint()
        ..color = fill
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_LevelRingPainter old) =>
      old.value != value || old.track != track || old.fill != fill;
}

/// Chamada para o mercado interno: abre a [ShopScreen] (nova tela).
class _StoreCta extends StatelessWidget {
  const _StoreCta({required this.coins, required this.onTap});

  final int coins;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Semantics(
      button: true,
      label: 'Explorar a loja',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: pal.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Pal.gold, width: 2),
          ),
          child: Row(
            children: [
              const Icon(Icons.storefront_outlined, color: Pal.gold, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'MERCADO',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                    Text(
                      'Você tem ${formatPoints(coins)} dracmas',
                      style: TextStyle(fontSize: 14, color: pal.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Pal.gold,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'EXPLORAR A LOJA',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF3A2A00),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Missão

class _MissionBanner extends StatelessWidget {
  const _MissionBanner({required this.text, required this.rewardXp});

  final String text;
  final int rewardXp;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? Pal.purpleDark : const Color(0xFFE9E6FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Pal.purple, width: 2),
      ),
      child: Row(
        children: [
          Icon(
            Icons.gps_fixed,
            color: isDark ? const Color(0xFFC9C2FF) : Pal.purple,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MISSÃO DO DIA',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: isDark ? Colors.white : scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark
                        ? const Color(0xFFD9D4FF)
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Pal.gold,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '+$rewardXp XP',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Color(0xFF3A2A00),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Modos

class _ModeGrid extends StatelessWidget {
  const _ModeGrid({required this.modes, this.stretch = false});

  final List<_GameMode> modes;

  /// Quando o pai já dá a altura (janela larga e alta), os cards esticam direto
  /// no `Row`; sem isso é preciso medir o card mais alto com [IntrinsicHeight].
  final bool stretch;

  List<Widget> _children({required bool fillHeight}) => [
    for (var i = 0; i < modes.length; i++) ...[
      Expanded(
        child: _ModeCard(mode: modes[i], fillHeight: fillHeight),
      ),
      if (i < modes.length - 1) const SizedBox(width: 16),
    ],
  ];

  @override
  Widget build(BuildContext context) {
    if (stretch) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _children(fillHeight: true),
      );
    }
    return LayoutBuilder(
      builder: (_, c) {
        if (c.maxWidth >= 700) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _children(fillHeight: true),
            ),
          );
        }
        return Column(
          children: [
            for (var i = 0; i < modes.length; i++) ...[
              if (i > 0) const SizedBox(height: 22),
              _ModeCard(mode: modes[i], fillHeight: false),
            ],
          ],
        );
      },
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({required this.mode, required this.fillHeight});

  final _GameMode mode;
  final bool fillHeight;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Pastilha do ícone e sombra do botão acompanham o brilho: no claro,
    // um bloco quase preto pesaria demais sobre o fundo claro.
    final tile = isDark
        ? Color.lerp(mode.color, Colors.black, 0.6)!
        : Color.lerp(mode.color, Colors.white, 0.8)!;
    final btnShadow = isDark
        ? Color.lerp(mode.color, Colors.black, 0.8)!
        : Color.lerp(mode.color, Colors.black, 0.3)!;
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.passthrough,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: pal.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: mode.highlighted ? mode.color : pal.border,
              width: 2,
            ),
            boxShadow: [
              BoxShadow(color: pal.hardShadow, offset: const Offset(0, 4)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: tile,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: mode.color, width: 2),
                ),
                child: Icon(mode.icon, color: mode.color, size: 30),
              ),
              const SizedBox(height: 12),
              Text(
                mode.title.toUpperCase(),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                  height: 1.2,
                  color: pal.heading,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                mode.description,
                style: TextStyle(fontSize: 14, height: 1.45, color: pal.muted),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [for (final p in mode.pills) _Pill(p)],
              ),
              if (fillHeight) const Spacer() else const SizedBox(height: 14),
              if (fillHeight) const SizedBox(height: 14),
              _GameButton(
                label: mode.action,
                color: mode.color,
                shadow: btnShadow,
                onPressed: mode.onPlay,
              ),
            ],
          ),
        ),
        if (mode.tag != null)
          Positioned(
            top: -11,
            left: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
              decoration: BoxDecoration(
                color: mode.color,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                mode.tag!.toUpperCase(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: inkOnAccent(mode.color),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: pal.chip,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text, style: TextStyle(fontSize: 13, color: pal.chipText)),
    );
  }
}

/// Botão "3D": a sombra sem desfoque some e o botão desce ao ser pressionado.
class _GameButton extends StatefulWidget {
  const _GameButton({
    required this.label,
    required this.color,
    required this.shadow,
    required this.onPressed,
  });

  final String label;
  final Color color, shadow;

  /// `null` desabilita o botão: o modo aparece na tela, mas sem fingir que dá
  /// para jogar.
  final VoidCallback? onPressed;

  @override
  State<_GameButton> createState() => _GameButtonState();
}

class _GameButtonState extends State<_GameButton> {
  bool _down = false;

  void _set(bool v) => setState(() => _down = v);

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final enabled = widget.onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      child: GestureDetector(
        onTapDown: enabled ? (_) => _set(true) : null,
        onTapUp: enabled ? (_) => _set(false) : null,
        onTapCancel: enabled ? () => _set(false) : null,
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 13),
          alignment: Alignment.center,
          transform: Matrix4.translationValues(0, _down ? 4 : 0, 0),
          decoration: BoxDecoration(
            color: enabled ? widget.color : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: enabled ? null : Border.all(color: pal.border, width: 2),
            boxShadow: [
              if (enabled)
                BoxShadow(
                  color: widget.shadow,
                  offset: Offset(0, _down ? 0 : 4),
                ),
            ],
          ),
          child: Text(
            widget.label.toUpperCase(),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
              color: enabled ? inkOnAccent(widget.color) : pal.muted,
            ),
          ),
        ),
      ),
    );
  }
}

