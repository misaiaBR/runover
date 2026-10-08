import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../services/api_client.dart';
import '../state/app_state.dart';
import '../widgets/centered_content.dart';
import '../widgets/slanted_menu_icon.dart';
import 'app_footer.dart';
import 'map_screen.dart';
import 'notifications_screen.dart';
import 'speed_screen.dart';
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
    if (runs <= 0) return const ['Nenhuma corrida', 'Em breve'];
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

  void _openMap() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const MapScreen()));
  }

  Future<void> _openSpeed() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SpeedScreen()));
    if (!mounted) return;
    unawaited(_loadCardData(context.read<AppState>().api));
  }

  Future<void> _openTeam() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const TeamHubScreen()));
    if (!mounted) return;
    unawaited(_loadCardData(context.read<AppState>().api));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final pal = Pal.of(context);
    final profile = context.watch<AppState>().profile;
    final zones = profile?.territoriesCount ?? 0;
    final rank = profile?.rankPosition;
    final xp = profile?.totalScore ?? 0;
    final xpMax =
        (profile?.totalScore ?? 0) + (profile?.pointsToNextLevel ?? 1000);
    final level = profile?.level ?? 1;
    final streakDays = 0; // TODO: add streak to backend
    final coins = 0; // TODO: add coins to backend
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
        onPlay: _openMap,
      ),
      _GameMode(
        title: 'Desafio de velocidade F1',
        description:
            'Voltas cronometradas. Bata seu recorde e suba no ranking.',
        icon: Icons.timer_outlined,
        color: colors.secondary,
        action: _progressFailed ? 'Tentar de novo' : 'Correr',
        pills: _speedStats(),
        tag: _speedBadge(),
        highlighted: !_progressFailed,
        onPlay: _progressFailed ? _retryCards : _openSpeed,
      ),
      _GameMode(
        title: 'Pit stop de equipe',
        description: 'Una forças com o time e cumpra objetivos relâmpago.',
        icon: Icons.groups_outlined,
        color: colors.tertiary,
        action: _teamFailed ? 'Tentar de novo' : 'Entrar',
        pills: _teamStats(),
        tag: _teamBadge(),
        highlighted: !_teamFailed,
        onPlay: _teamFailed ? _retryCards : _openTeam,
      ),
    ];

    return SafeArea(
      child: CenteredContent(
        maxWidth: 1280,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(28, 12, 28, 32),
          children: [
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
                    MaterialPageRoute(
                      builder: (_) => const NotificationsScreen(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _Hud(
              name: name,
              level: level,
              xp: xp,
              xpMax: xpMax,
              streakDays: streakDays,
              coins: coins,
            ),
            const SizedBox(height: 16),
            _MissionBanner(
              text:
                  'Conquiste 1 território novo hoje e mantenha sua sequência.',
              rewardXp: 150,
            ),
            const SizedBox(height: 20),
            Padding(
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
            ),
            const SizedBox(height: 8),
            _ModeGrid(modes: modes),
            const SizedBox(height: 32),
            const AppFooter(),
          ],
        ),
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
  final VoidCallback onPlay;
}

// ---------------------------------------------------------------- HUD

class _Hud extends StatelessWidget {
  const _Hud({
    required this.name,
    required this.level,
    required this.xp,
    required this.xpMax,
    required this.streakDays,
    required this.coins,
  });

  final String name;
  final int level, xp, xpMax, streakDays, coins;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final avatar = SizedBox(
      width: 54,
      height: 54,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Pal.orange,
              border: Border.all(color: Pal.gold, width: 3),
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
          Positioned(
            right: -6,
            bottom: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
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
    );

    final xpBar = Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: pal.muted),
                ),
              ),
              Flexible(
                child: Text(
                  '$xp / $xpMax XP',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: TextStyle(fontSize: 13, color: pal.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: xpMax > 0 ? xp / xpMax : 0),
              duration: const Duration(milliseconds: 1100),
              curve: Curves.easeOutCubic,
              builder: (_, value, _) => LinearProgressIndicator(
                value: value.clamp(0.0, 1.0),
                minHeight: 12,
                backgroundColor: pal.border,
                valueColor: const AlwaysStoppedAnimation(Pal.teal),
              ),
            ),
          ),
        ],
      ),
    );

    final chips = [
      _StatChip(
        icon: Icons.local_fire_department,
        color: Pal.orange,
        label: '$streakDays dias',
      ),
      const SizedBox(width: 8),
      _StatChip(
        icon: Icons.monetization_on,
        color: Pal.gold,
        label: _fmt(coins),
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
                  xpBar,
                  const SizedBox(width: 12),
                  ...chips,
                ],
              )
            : Column(
                children: [
                  Row(children: [avatar, const SizedBox(width: 14), xpBar]),
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
  });

  final IconData icon;
  final Color color;
  final String label;

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
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 14, color: pal.chipText)),
        ],
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
  const _ModeGrid({required this.modes});

  final List<_GameMode> modes;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, c) {
        if (c.maxWidth >= 700) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < modes.length; i++) ...[
                  if (i > 0) const SizedBox(width: 16),
                  Expanded(child: _ModeCard(mode: modes[i], fillHeight: true)),
                ],
              ],
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
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: Pal.onAccent,
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
  final VoidCallback onPressed;

  @override
  State<_GameButton> createState() => _GameButtonState();
}

class _GameButtonState extends State<_GameButton> {
  bool _down = false;

  void _set(bool v) => setState(() => _down = v);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: GestureDetector(
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 13),
          alignment: Alignment.center,
          transform: Matrix4.translationValues(0, _down ? 4 : 0, 0),
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(color: widget.shadow, offset: Offset(0, _down ? 0 : 4)),
            ],
          ),
          child: Text(
            widget.label.toUpperCase(),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
              color: Pal.onAccent,
            ),
          ),
        ),
      ),
    );
  }
}

String _fmt(int n) =>
    n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
