import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../services/api_client.dart';
import '../services/profile_image_provider.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/cosmetics.dart';
import '../widgets/insignia.dart';
import '../widgets/level_badge.dart';
import 'badges_screen.dart';
import 'season_pass_screen.dart';
import 'app_footer.dart';
import 'terms_screen.dart';
import 'edit_profile_screen.dart';
import 'shop_screen.dart';
import 'runs_screen.dart';
import '../widgets/profile_activity.dart';

/// RF05/RF13/RF19 — perfil, estatísticas, progressão e histórico do usuário.
///
/// Cosméticos da loja são opcionais: o perfil e o mural funcionam mesmo
/// quando o catálogo ou as corridas recentes falham (lista vazia).
Future<List<ShopItem>> _catalogOrEmpty(ApiClient api) async {
  try {
    return await api.getShopCatalog();
  } catch (_) {
    return const <ShopItem>[];
  }
}

/// "6 de jun. de 2020" a partir da data de criação da conta.
String _memberSinceLabel(DateTime date) {
  const months = [
    'jan.',
    'fev.',
    'mar.',
    'abr.',
    'mai.',
    'jun.',
    'jul.',
    'ago.',
    'set.',
    'out.',
    'nov.',
    'dez.',
  ];
  return '${date.day} de ${months[date.month - 1]} de ${date.year}';
}

/// As insígnias também são opcionais no perfil: sem elas o mural e a vitrine
/// de nível ficam vazios, mas a conta continua legível.
Future<List<Insignia>> _badgesOrEmpty(ApiClient api) async {
  try {
    return await api.getBadges();
  } catch (_) {
    return const <Insignia>[];
  }
}

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
  Future<List<ShopItem>>? _catalog;
  Future<List<Insignia>>? _badges;
  bool _photoBusy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = context.watch<AppState>();
    if (state.profile != null) {
      _progress ??= state.api.getProgress();
      _catalog ??= _catalogOrEmpty(state.api);
      _badges ??= _badgesOrEmpty(state.api);
    }
  }

  Future<void> _refresh() async {
    final state = context.read<AppState>();
    final progressRequest = state.api.getProgress();
    final catalogRequest = _catalogOrEmpty(state.api);
    final badgesRequest = _badgesOrEmpty(state.api);
    setState(() {
      _progress = progressRequest;
      _catalog = catalogRequest;
      _badges = badgesRequest;
    });
    try {
      await Future.wait([
        state.refreshProfile(),
        progressRequest,
        catalogRequest,
        badgesRequest,
      ]);
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
    final api = context.read<AppState>().api;
    setState(() {
      _progress = api.getProgress();
      _catalog = _catalogOrEmpty(api);
      _badges = _badgesOrEmpty(api);
    });
  }

  Future<void> _openBadges() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const BadgesScreen()));
    if (!mounted) return;
    final next = _badgesOrEmpty(context.read<AppState>().api);
    setState(() {
      _badges = next;
    });
  }

  Future<void> _openShop() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ShopScreen()));
    if (!mounted) return;
    _refresh();
  }

  Future<void> _savePhoto(String? photoUrl) async {
    if (_photoBusy) return;
    final app = context.read<AppState>();
    final current = app.profile;
    if (current == null) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _photoBusy = true);
    try {
      await app.api.updateProfile(
        photoUrl: photoUrl ?? '',
        distanceUnits: current.distanceUnits,
        weeklyFrequency: current.weeklyFrequency,
        trainingDays: current.trainingDays,
        activityLevel: current.activityLevel,
      );
      await app.refreshProfile();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            photoUrl == null ? 'Foto removida.' : 'Foto atualizada.',
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  Future<void> _uploadPhoto() async {
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (image == null || !mounted) return;
      final avatar = fitAvatarPhoto(await image.readAsBytes());
      if (avatar == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Escolha uma imagem JPG, PNG ou WebP.'),
            ),
          );
        }
        return;
      }
      await _savePhoto(
        'data:${avatar.mimeType};base64,${base64Encode(avatar.bytes)}',
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível abrir a foto. Tente outra imagem.'),
          ),
        );
      }
    }
  }

  void _showPhotoOptions() {
    final hasPhoto =
        (context.read<AppState>().profile?.photoUrl?.isNotEmpty ?? false);
    final colors = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Alterar foto do perfil',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              title: Center(
                child: Text(
                  'Carregar foto',
                  style: TextStyle(
                    color: colors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _uploadPhoto();
              },
            ),
            const Divider(height: 1),
            if (hasPhoto)
              ListTile(
                title: Center(
                  child: Text(
                    'Remover foto atual',
                    style: TextStyle(
                      color: colors.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _savePhoto(null);
                },
              ),
            if (hasPhoto) const Divider(height: 1),
            ListTile(
              title: Center(
                child: Text(
                  'Cancelar',
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              ),
              onTap: () => Navigator.of(sheetContext).pop(),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final profile = appState.profile;
    if (profile == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final identity = FutureBuilder<List<ShopItem>>(
      future: _catalog,
      builder: (context, snapshot) {
        final catalog = snapshot.data;
        final frame = findItem(catalog ?? const [], profile.equippedFrame);
        final avatarItem = findItem(
          catalog ?? const [],
          profile.equippedAvatar,
        );
        final banner = findItem(catalog ?? const [], profile.equippedBanner);
        final nameStyle = findItem(
          catalog ?? const [],
          profile.equippedNameStyle,
        );
        final effect = findItem(catalog ?? const [], profile.equippedEffect);
        final gradient = bannerGradient(banner);
        final displayName = profile.fullName.trim().isEmpty
            ? profile.username
            : profile.fullName;
        // Cartão de identidade: faixa da loja (placa de
        // identificação, editável) no topo, avatar sobreposto, nome,
        // @usuário • pronomes, fileira de emoticons, ações e métricas.
        final scheme = Theme.of(context).colorScheme;
        final pronouns = (profile.pronouns ?? '').trim();
        void openEditor() => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => EditProfileScreen(profile: profile),
          ),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          // Altura cobre o avatar sobreposto (110 do banner
                          // + 45 visíveis abaixo): sem isso, o centro do
                          // avatar cai na borda do Stack e o toque não chega
                          // ao GestureDetector.
                          height: 155,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                height: 110,
                                decoration: BoxDecoration(
                                  gradient: gradient,
                                  color: gradient == null
                                      ? scheme.surfaceContainerHighest
                                      : null,
                                ),
                              ),
                              Positioned(
                                left: 0,
                                right: 0,
                                top: 65,
                                child: Center(
                                  child: Container(
                                    padding: const EdgeInsets.all(5),
                                    decoration: BoxDecoration(
                                      color: scheme.surface,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Semantics(
                                      button: true,
                                      label: 'Alterar foto do perfil',
                                      child: GestureDetector(
                                        onTap: _photoBusy
                                            ? null
                                            : _showPhotoOptions,
                                        child: FramedAvatar(
                                          radius: 40,
                                          image: profileAvatarImage(
                                            profile.photoUrl,
                                            avatarItem,
                                            seed: profile.username,
                                          ),
                                          fallbackLetter:
                                              profile.username.isEmpty
                                              ? '?'
                                              : profile.username[0],
                                          frame: frame,
                                          avatarItem: avatarItem,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 57, 16, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Wrap(
                                alignment: WrapAlignment.center,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 8,
                                children: [
                                  Text(
                                    displayName,
                                    style: styledName(
                                      displayName,
                                      nameStyle,
                                      const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  LevelBadge(level: profile.level),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Wrap(
                                alignment: WrapAlignment.center,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 6,
                                children: [
                                  Text(
                                    '@${profile.username}',
                                    style: TextStyle(
                                      color: scheme.onSurfaceVariant,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    '•',
                                    style: TextStyle(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                  if (pronouns.isNotEmpty)
                                    Text(
                                      pronouns,
                                      style: TextStyle(
                                        color: scheme.onSurfaceVariant,
                                        fontSize: 12,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    )
                                  else
                                    GestureDetector(
                                      onTap: openEditor,
                                      child: Text(
                                        'Adicionar pronomes',
                                        style: TextStyle(
                                          color: scheme.onSurfaceVariant,
                                          fontSize: 12,
                                          fontStyle: FontStyle.italic,
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              if (profile.equippedEmoticons.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Wrap(
                                  alignment: WrapAlignment.center,
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    for (final e in profile.equippedEmoticons)
                                      Text(
                                        e,
                                        style: const TextStyle(fontSize: 20),
                                      ),
                                  ],
                                ),
                              ],
                              if (profile.teamName != null) ...[
                                const SizedBox(height: 8),
                                Chip(
                                  avatar: const Icon(
                                    Icons.groups_outlined,
                                    size: 17,
                                  ),
                                  label: Text(profile.teamName!),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                              const SizedBox(height: 12),
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
                              if (profile.memberSince != null) ...[
                                const SizedBox(height: 10),
                                Text(
                                  'Membro desde ${_memberSinceLabel(profile.memberSince!)}',
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 14),
                              _ProfileMenuBlock(
                                children: [
                                  _ProfileMenuItem(
                                    icon: Icons.edit_outlined,
                                    title: 'Editar perfil',
                                    hasArrow: true,
                                    onTap: openEditor,
                                  ),
                                  _ProfileMenuItem(
                                    icon: Icons.storefront_outlined,
                                    title: 'Loja de cosméticos',
                                    trailing: Text(
                                      '${profile.coinsBalance} dracmas',
                                      style: TextStyle(
                                        color: scheme.onSurfaceVariant,
                                        fontSize: 12,
                                      ),
                                    ),
                                    onTap: _openShop,
                                  ),
                                  _ProfileMenuItem(
                                    icon: Icons.emoji_events_outlined,
                                    title: 'Insígnias',
                                    hasArrow: true,
                                    onTap: _openBadges,
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
                if (effect != null)
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: ProfileEffectOverlay(effect: effect),
                    ),
                  ),
              ],
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
                  const SizedBox(height: 20),
                  _LevelRewards(badges: _badges),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _MuralCard(badges: _badges, onOpenAll: _openBadges),
          ],
        );
      },
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
                    Icon(
                      Icons.cloud_off_outlined,
                      size: 32,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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
              const Divider(height: 24),
              _profileLink(
                Icons.workspace_premium_outlined,
                'Pass Runover',
                'Temporada e a trilha de XP',
                () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const SeasonPassScreen())),
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
          ThemeModeButton(
            mode: appState.themeMode,
            onSelected: appState.setThemeMode,
          ),
          IconButton(
            tooltip: 'Loja de cosméticos',
            icon: const Icon(Icons.storefront_outlined),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const ShopScreen())),
          ),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LayoutBuilder(
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
                  const SizedBox(height: 32),
                  const AppFooter(),
                ],
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

/// Mural do perfil: as conquistas publicadas como insígnias já ganhas.
class _MuralCard extends StatelessWidget {
  const _MuralCard({required this.badges, required this.onOpenAll});

  final Future<List<Insignia>>? badges;
  final VoidCallback onOpenAll;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Insignia>>(
      future: badges,
      builder: (context, snapshot) {
        final earned = (snapshot.data ?? const <Insignia>[]).where((b) => b.earned).toList();
        return ProfileCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      earned.isEmpty ? 'Mural' : 'Mural · ${earned.length}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: onOpenAll,
                    child: const Text('Ver todas'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (snapshot.connectionState != ConnectionState.done)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (earned.isEmpty)
                Text(
                  'Nenhuma insígnia ainda — vá correr!',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final badge in earned)
                      BadgeChip(badge: badge, showDate: true),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Vitrine estática das recompensas de nível: selos que a conta libera ao
/// subir de nível. Não é resgate — o servidor concede pela regra do nível.
class _LevelRewards extends StatelessWidget {
  const _LevelRewards({required this.badges});

  final Future<List<Insignia>>? badges;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Insignia>>(
      future: badges,
      builder: (context, snapshot) {
        final rewards = (snapshot.data ?? const <Insignia>[])
            .where((b) => b.isLevelReward)
            .toList();
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        if (rewards.isEmpty) {
          // Sem catálogo não há vitrine: o resto da evolução segue legível.
          return const SizedBox.shrink();
        }
        final scheme = Theme.of(context).colorScheme;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Recompensas de nível',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Selos concedidos pelo nível da conta, sem resgate.',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final reward in rewards)
                  Tooltip(
                    message: reward.description,
                    child: BadgeChip(badge: reward),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Bloco de menu do cartão de identidade (editar, loja, insígnias…).
class _ProfileMenuBlock extends StatelessWidget {
  const _ProfileMenuBlock({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(children: children),
    );
  }
}

class _ProfileMenuItem extends StatelessWidget {
  const _ProfileMenuItem({
    required this.icon,
    required this.title,
    this.trailing,
    this.hasArrow = false,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final Widget? trailing;
  final bool hasArrow;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 18, color: scheme.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(color: scheme.onSurface, fontSize: 13),
                ),
              ),
              trailing ?? const SizedBox.shrink(),
              if (hasArrow)
                Icon(
                  Icons.chevron_right,
                  color: scheme.onSurfaceVariant,
                  size: 18,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class ThemeModeButton extends StatelessWidget {
  const ThemeModeButton({
    super.key,
    required this.mode,
    required this.onSelected,
  });

  final ThemeMode mode;
  final ValueChanged<ThemeMode> onSelected;

  static const _options = [
    (ThemeMode.system, Icons.brightness_auto_outlined, 'Sistema'),
    (ThemeMode.light, Icons.light_mode_outlined, 'Claro'),
    (ThemeMode.dark, Icons.dark_mode_outlined, 'Escuro'),
  ];

  @override
  Widget build(BuildContext context) {
    final current = _options.firstWhere((o) => o.$1 == mode);
    return PopupMenuButton<ThemeMode>(
      tooltip: 'Tema do app',
      icon: Icon(current.$2),
      initialValue: mode,
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final (value, icon, label) in _options)
          PopupMenuItem(
            value: value,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 12),
                Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
                if (value == mode) ...[
                  const SizedBox(width: 12),
                  Icon(
                    Icons.check,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    this.title = 'Histórico',
    this.loader,
  });

  final String title;
  /// De onde vem o extrato: sem isto, é o histórico da própria conta. A tela
  /// da equipe passa os eventos de pontuação da equipe.
  final Future<List<HistoryEntry>> Function()? loader;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late Future<List<HistoryEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future =
        widget.loader?.call() ?? context.read<AppState>().api.getMyHistory();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
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
