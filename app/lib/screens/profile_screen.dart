import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/level_badge.dart';
import 'terms_screen.dart';
import 'edit_profile_screen.dart';
import 'runs_screen.dart';
import '../widgets/profile_activity.dart';

/// RF05/RF13/RF19 — perfil, estatísticas, progressão e histórico do usuário.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  static String formatPlaytime(int seconds) {
    if (seconds <= 0) return '0min';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return m > 0 ? '${h}h ${m}min' : '${h}h';
    return '${m}min';
  }

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Future<Map<String, dynamic>>? _progress;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = context.watch<AppState>();
    if (state.profile != null) {
      _progress ??= state.api.getProgress();
    }
  }

  Future<void> _refresh() async {
    final state = context.read<AppState>();
    final progressRequest = state.api.getProgress();
    setState(() {
      _progress = progressRequest;
    });
    try {
      await Future.wait([state.refreshProfile(), progressRequest]);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível atualizar todos os dados. Tente novamente.',
            ),
          ),
        );
      }
    }
  }

  void _retryProgress() {
    setState(() {
      _progress = context.read<AppState>().api.getProgress();
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AppState>().profile;
    if (profile == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final hasPhoto = profile.photoUrl?.isNotEmpty == true;
    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProfileCard(
          child: Column(
            children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: RunoverColors.route.withValues(alpha: .12),
                foregroundImage: hasPhoto
                    ? NetworkImage(profile.photoUrl!)
                    : null,
                onForegroundImageError: hasPhoto ? (_, _) {} : null,
                child: Text(
                  profile.username.isEmpty
                      ? '?'
                      : profile.username[0].toUpperCase(),
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    color: RunoverColors.route,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                profile.fullName.trim().isEmpty
                    ? profile.username
                    : profile.fullName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '@${profile.username}',
                style: const TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  LevelBadge(level: profile.level),
                  if (profile.teamName != null)
                    Chip(
                      avatar: const Icon(Icons.groups_outlined, size: 17),
                      label: Text(profile.teamName!),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    profile.isPublic ? Icons.public : Icons.lock_outline,
                    size: 15,
                    color: Colors.black54,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    profile.isPublic ? 'Perfil público' : 'Perfil privado',
                    style: const TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Divider(height: 1),
              ),
              Row(
                children: [
                  Expanded(
                    child: ProfileMetric(
                      value: '${profile.totalScore}',
                      label: 'Pontos',
                    ),
                  ),
                  Expanded(
                    child: ProfileMetric(
                      value: '${profile.territoriesCount}',
                      label: 'Territórios',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => EditProfileScreen(profile: profile),
                    ),
                  ),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Editar perfil'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ProfileCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Sua evolução',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 20),
              LevelProgress(
                level: profile.level,
                progress: profile.levelProgress,
                pointsToNext: profile.pointsToNextLevel,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Icon(
                    Icons.leaderboard_outlined,
                    color: RunoverColors.territory,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      profile.rankPosition == null
                          ? 'Sem posição no ranking'
                          : '${profile.rankPosition}º lugar no ranking',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(
                    Icons.timer_outlined,
                    color: RunoverColors.territory,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${ProfileScreen.formatPlaytime(profile.playSeconds)} de tempo de jogo',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
    final activity = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FutureBuilder<Map<String, dynamic>>(
          future: _progress,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const ProfileCard(
                child: SizedBox(
                  height: 180,
                  child: Center(child: CircularProgressIndicator()),
                ),
              );
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return ProfileCard(
                child: Column(
                  children: [
                    const Icon(
                      Icons.cloud_off_outlined,
                      size: 32,
                      color: Colors.black54,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Não foi possível carregar suas atividades.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _retryProgress,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              );
            }
            return ProfileActivity(progress: snapshot.data!);
          },
        ),
        const SizedBox(height: 16),
        ProfileCard(
          child: Column(
            children: [
              _profileLink(
                Icons.directions_run,
                'Minhas corridas',
                'Veja seus percursos e atividades',
                () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const RunsScreen())),
              ),
              const Divider(height: 24),
              _profileLink(
                Icons.emoji_events_outlined,
                'Histórico de conquistas',
                'Acompanhe seus territórios e pontos',
                () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const HistoryScreen()),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const TermsScreen())),
          child: const Text(
            'Termos de Uso e Política de Privacidade',
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Meu perfil'),
        actions: [
          IconButton(
            tooltip: 'Atualizar perfil',
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
          IconButton(
            tooltip: 'Sair da conta',
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<AppState>().logout(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < 760) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        identity,
                        const SizedBox(height: 20),
                        activity,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 320, child: identity),
                      const SizedBox(width: 24),
                      Expanded(child: activity),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _profileLink(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: RunoverColors.route),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late Future<List<HistoryEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<AppState>().api.getMyHistory();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Histórico')),
      body: FutureBuilder<List<HistoryEntry>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: RunoverColors.route),
            );
          }
          final items = snapshot.data!;
          if (items.isEmpty) {
            return const Center(
              child: Text(
                'Nenhuma atividade ainda — vá conquistar um território!',
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final e = items[i];
              final positive = e.delta >= 0;
              return ListTile(
                leading: Icon(
                  positive ? Icons.emoji_events : Icons.trending_down,
                  color: positive ? RunoverColors.territory : Colors.redAccent,
                ),
                title: Text(e.territoryName ?? 'Território removido'),
                subtitle: Text(
                  '${e.reason} · ${e.createdAt.day}/${e.createdAt.month}/${e.createdAt.year}',
                ),
                trailing: Text(
                  '${positive ? '+' : ''}${e.delta} pts',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: positive
                        ? RunoverColors.territory
                        : Colors.redAccent,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
