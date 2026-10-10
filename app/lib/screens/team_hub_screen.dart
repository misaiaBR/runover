import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../format.dart';
import '../models.dart';
import '../services/api_client.dart';
import '../services/profile_image_provider.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/centered_content.dart';
import '../widgets/cosmetics.dart';
import '../widgets/level_badge.dart';
import 'app_footer.dart';
import 'lightning_screen.dart';
import 'team_shop_screen.dart';
import 'teams_screen.dart';

/// Pit stop de equipe: meta semanal, membros online e pedidos pendentes.
class TeamHubScreen extends StatefulWidget {
  const TeamHubScreen({super.key});

  @override
  State<TeamHubScreen> createState() => _TeamHubScreenState();
}

class _TeamHubScreenState extends State<TeamHubScreen> {
  TeamDetail? _team;
  Map<String, dynamic>? _goal;
  List<ShopItem> _catalog = const [];
  List<LightningBoard> _lightning = const [];
  bool _loading = true;
  final Set<String> _deciding = {};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final api = context.read<AppState>().api;
    TeamDetail? team;
    Map<String, dynamic>? goal;
    List<ShopItem> catalog = const [];
    try {
      team = await api.getMyTeam();
    } catch (_) {
      team = null;
    }
    try {
      final progress = await api.getProgress();
      final rawGoal = progress['team'];
      goal = rawGoal is Map ? Map<String, dynamic>.from(rawGoal) : null;
    } catch (_) {
      goal = null;
    }
    try {
      catalog = await api.getShopCatalog();
    } catch (_) {
      catalog = const [];
    }
    List<LightningBoard> lightning = const [];
    if (team != null) {
      try {
        lightning = await api.listLightning(team.id);
      } catch (_) {
        lightning = const [];
      }
    }
    if (!mounted) return;
    setState(() {
      _team = team;
      _goal = goal;
      _catalog = catalog;
      _lightning = lightning;
      _loading = false;
    });
  }

  Future<void> _decide(TeamJoinRequestInfo request, bool approve) async {
    final team = _team;
    if (team == null || _deciding.contains(request.id)) return;
    setState(() => _deciding.add(request.id));
    try {
      final updated = await context.read<AppState>().api.decideJoinRequest(
        team.id,
        request.id,
        approve,
      );
      if (!mounted) return;
      setState(() => _team = updated);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _deciding.remove(request.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final team = _team;
    final username = context.watch<AppState>().profile?.username;

    return Scaffold(
      appBar: AppBar(title: const Text('Pit stop de equipe')),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: RunoverColors.route),
            )
          : RefreshIndicator(
              onRefresh: _load,
              color: RunoverColors.route,
              child: CenteredContent(
                child: team == null
                    ? ListView(
                        padding: const EdgeInsets.all(24),
                        children: [
                          const SizedBox(height: 48),
                          const Icon(
                            Icons.groups_outlined,
                            size: 64,
                            color: Colors.grey,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Você ainda não tem equipe',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Crie uma ou entre em uma existente para cumprir a meta semanal em grupo.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const TeamsScreen(),
                              ),
                            ),
                            icon: const Icon(Icons.groups_outlined),
                            label: const Text('Ver equipes'),
                          ),
                        ],
                      )
                    : ListView(
                        padding: const EdgeInsets.all(20),
                        children: [
                          _TeamHeader(team: team, catalog: _catalog),
                          const SizedBox(height: 16),
                          if (_goal != null) ...[
                            _GoalCard(goal: _goal!),
                            const SizedBox(height: 16),
                          ],
                          _LightningSection(
                            team: team,
                            sessions: _lightning,
                            username: username,
                            onChanged: _load,
                          ),
                          const SizedBox(height: 16),
                          Card(
                            child: ListTile(
                              leading: const Icon(
                                Icons.storefront_outlined,
                                color: Color(0xFFFFC93C),
                              ),
                              title: const Text(
                                'Loja da equipe',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              subtitle: Text(
                                '${formatPoints(team.teamBalance)} pontos no cofre',
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => Navigator.of(context)
                                  .push(
                                    MaterialPageRoute(
                                      builder: (_) => TeamShopScreen(
                                        teamId: team.id,
                                      ),
                                    ),
                                  )
                                  .then((_) => _load()),
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (team.isAdmin &&
                              team.pendingRequests.isNotEmpty) ...[
                            Text(
                              'Convites pendentes (${team.pendingRequests.length})',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            for (final request in team.pendingRequests)
                              Card(
                                child: ListTile(
                                  leading: CircleAvatar(
                                    child: Text(
                                      request.username.isNotEmpty
                                          ? request.username[0].toUpperCase()
                                          : '?',
                                    ),
                                  ),
                                  title: Text('@${request.username}'),
                                  trailing: _deciding.contains(request.id)
                                      ? const SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              tooltip: 'Aprovar',
                                              icon: const Icon(
                                                Icons.check,
                                                color: Colors.green,
                                              ),
                                              onPressed: () =>
                                                  _decide(request, true),
                                            ),
                                            IconButton(
                                              tooltip: 'Recusar',
                                              icon: const Icon(
                                                Icons.close,
                                                color: Colors.red,
                                              ),
                                              onPressed: () =>
                                                  _decide(request, false),
                                            ),
                                          ],
                                        ),
                                ),
                              ),
                            const SizedBox(height: 16),
                          ],
                          Text(
                            'Membros',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          for (final member in team.members)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Stack(
                                children: [
                                  CircleAvatar(
                                    child: Text(
                                      member.username.isNotEmpty
                                          ? member.username[0].toUpperCase()
                                          : '?',
                                    ),
                                  ),
                                  Positioned(
                                    right: 0,
                                    bottom: 0,
                                    child: Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: member.isOnline
                                            ? Colors.green
                                            : Colors.grey,
                                        border: Border.all(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.surface,
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              title: Text('@${member.username}'),
                              trailing: member.isAdmin
                                  ? const Icon(
                                      Icons.shield_outlined,
                                      size: 18,
                                      color: Colors.grey,
                                    )
                                  : null,
                            ),
                          const SizedBox(height: 24),
                          const AppFooter(),
                        ],
                      ),
              ),
            ),
    );
  }
}

/// Cabeçalho da equipe com os cosméticos da loja equipados (faixa de
/// fundo, moldura, estilo do nome e efeito). Sem itens, visual padrão.
class _TeamHeader extends StatelessWidget {
  const _TeamHeader({required this.team, required this.catalog});

  final TeamDetail team;
  final List<ShopItem> catalog;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final frame = findItem(catalog, team.equippedFrame);
    final banner = findItem(catalog, team.equippedBanner);
    final nameStyle = findItem(catalog, team.equippedNameStyle);
    final effect = findItem(catalog, team.equippedEffect);
    final avatarAsset = galleryAvatarAsset(
      findItem(catalog, team.equippedAvatar),
    );
    final gradient = bannerGradient(banner);
    ImageProvider? image;
    if (team.photoUrl?.isNotEmpty == true) {
      image = profileImageProvider(team.photoUrl);
    } else if (avatarAsset != null) {
      image = AssetImage(avatarAsset);
    }
    return Stack(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: gradient,
            color: gradient == null ? colors.surfaceContainer : null,
          ),
          child: Row(
            children: [
              FramedAvatar(
                radius: 28,
                image: image,
                fallbackLetter: team.name.isNotEmpty
                    ? team.name[0].toUpperCase()
                    : '?',
                frame: frame,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      team.name,
                      style: styledName(
                        team.name,
                        nameStyle,
                        Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ) ??
                            const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                    Text(
                      '${team.memberCount} ${team.memberCount == 1 ? 'membro' : 'membros'} • ${team.onlineCount} online',
                      style: TextStyle(
                        color: gradient == null
                            ? colors.onSurfaceVariant
                            : Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
              LevelBadge(level: team.level),
            ],
          ),
        ),
        if (effect != null)
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: ProfileEffectOverlay(effect: effect),
            ),
          ),
      ],
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.goal});

  final Map<String, dynamic> goal;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final distance = (goal['distance_km'] as num?)?.toDouble() ?? 0;
    final target = (goal['target_km'] as num?)?.toDouble() ?? 0;
    final fraction = target <= 0 ? 0.0 : (distance / target).clamp(0.0, 1.0);
    final contributors = (goal['contributors'] as List?) ?? const [];

    return Card(
      color: colors.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Meta da semana',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '${distance.toStringAsFixed(1).replaceAll('.', ',')} de '
              '${target.toStringAsFixed(0)} km em equipe',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: fraction,
              color: RunoverColors.route,
              backgroundColor: colors.surfaceContainerHighest,
              minHeight: 10,
              borderRadius: BorderRadius.circular(5),
            ),
            if (contributors.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final c in contributors)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(child: Text('@${c['username']}')),
                      Text(
                        '${c['distance_km']} km',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Dominação Relâmpago no hub: abrir (só adm), participar e histórico.
///
/// Sem sessão aberta, quem não é adm vê que precisa aguardar — só conta o
/// laço de quem tocou em Participar.
class _LightningSection extends StatefulWidget {
  const _LightningSection({
    required this.team,
    required this.sessions,
    required this.username,
    required this.onChanged,
  });

  final TeamDetail team;
  final List<LightningBoard> sessions;
  final String? username;
  final Future<void> Function() onChanged;

  @override
  State<_LightningSection> createState() => _LightningSectionState();
}

class _LightningSectionState extends State<_LightningSection> {
  bool _busy = false;

  LightningBoard? get _open {
    for (final s in widget.sessions) {
      if (s.open) return s;
    }
    return null;
  }

  List<LightningBoard> get _past =>
      widget.sessions.where((s) => !s.open).take(3).toList();

  Future<void> _openSession(int minutes) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await context.read<AppState>().api.openLightning(
        widget.team.id,
        minutes,
      );
      await widget.onChanged();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join(String sessionId) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await context.read<AppState>().api.joinLightning(sessionId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Você entrou no relâmpago!')),
      );
      await widget.onChanged();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _board(String sessionId) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => LightningScreen(sessionId: sessionId)));
  }

  @override
  Widget build(BuildContext context) {
    final open = _open;
    final joined =
        open != null &&
        widget.username != null &&
        open.participants.contains(widget.username);
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.bolt_outlined),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Dominação Relâmpago',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (open == null) ...[
              Text(
                widget.team.isAdmin
                    ? 'Partida curta de 15 ou 30 min. Só conta o laço de quem participar.'
                    : 'Nenhum relâmpago aberto. Aguarde o adm abrir a partida.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (widget.team.isAdmin) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : () => _openSession(15),
                        icon: const Icon(Icons.flash_on_outlined),
                        label: const Text('Abrir 15 min'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : () => _openSession(30),
                        icon: const Icon(Icons.flash_on_outlined),
                        label: const Text('Abrir 30 min'),
                      ),
                    ),
                  ],
                ),
              ],
            ] else ...[
              Text(
                '${open.takes} tomadas · ${formatPoints(open.points)} pts · '
                '${open.participants.length} participando',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (!joined)
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _busy ? null : () => _join(open.id),
                        icon: const Icon(Icons.directions_run),
                        label: const Text('Participar'),
                      ),
                    ),
                  if (!joined) const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _board(open.id),
                      icon: const Icon(Icons.leaderboard_outlined),
                      label: const Text('Ver placar'),
                    ),
                  ),
                ],
              ),
            ],
            for (final past in _past) ...[
              const Divider(height: 24),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.history),
                title: Text(
                  'Relâmpago ${past.durationMin} min · ${past.takes} tomadas',
                ),
                subtitle: Text(
                  past.mvp == null
                      ? '${formatPoints(past.points)} pts'
                      : '${formatPoints(past.points)} pts · MVP @${past.mvp}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _board(past.id),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
