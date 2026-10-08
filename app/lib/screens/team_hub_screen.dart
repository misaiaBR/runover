import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../services/api_client.dart';
import '../services/profile_image_provider.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/centered_content.dart';
import '../widgets/level_badge.dart';
import 'app_footer.dart';
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
    if (!mounted) return;
    setState(() {
      _team = team;
      _goal = goal;
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
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 28,
                                backgroundColor: colors.tertiary.withValues(
                                  alpha: 0.15,
                                ),
                                foregroundImage:
                                    team.photoUrl?.isNotEmpty == true
                                    ? profileImageProvider(team.photoUrl)
                                    : null,
                                onForegroundImageError:
                                    team.photoUrl?.isNotEmpty == true
                                    ? (_, _) {}
                                    : null,
                                child: Text(
                                  team.name.isNotEmpty
                                      ? team.name[0].toUpperCase()
                                      : '?',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: colors.tertiary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      team.name,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                    Text(
                                      '${team.memberCount} ${team.memberCount == 1 ? 'membro' : 'membros'} • ${team.onlineCount} online',
                                      style: TextStyle(
                                        color: colors.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              LevelBadge(level: team.level),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (_goal != null) ...[
                            _GoalCard(goal: _goal!),
                            const SizedBox(height: 16),
                          ],
                          if (team.isAdmin &&
                              team.pendingRequests.isNotEmpty) ...[
                            Text(
                              'Pedidos pendentes (${team.pendingRequests.length})',
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
