import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../services/api_client.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/centered_content.dart';
import '../widgets/cosmetics.dart';
import '../widgets/league_emblem.dart';
import '../widgets/level_badge.dart';
import '../widgets/profile_activity.dart';

/// RF17 — visualização do perfil público de outro jogador. Só mostra dados
/// públicos (apelido, nível, pontuação, territórios, posição, equipe); se o
/// jogador tornou o perfil privado (RF05/RN13), o back-end devolve 403 e a
/// tela explica isso.
class PublicProfileScreen extends StatefulWidget {
  final String username;
  const PublicProfileScreen({super.key, required this.username});

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  late Future<PublicProfile> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<AppState>().api.getPublicProfile(widget.username);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('@${widget.username}')),
      body: FutureBuilder<PublicProfile>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(color: RunoverColors.route),
            );
          }
          if (snapshot.hasError) {
            final msg = snapshot.error is ApiException
                ? (snapshot.error as ApiException).message
                : 'Não foi possível carregar este perfil.';
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 40,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      msg,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final p = snapshot.data!;
          return FutureBuilder<List<ShopItem>>(
            future: context.read<AppState>().api.getShopCatalog(),
            builder: (context, catalogSnap) {
              final catalog = catalogSnap.data ?? const <ShopItem>[];
              final frame = findItem(catalog, p.equippedFrame);
              final avatarItem = findItem(catalog, p.equippedAvatar);
              final nameStyle = findItem(catalog, p.equippedNameStyle);
              final banner = findItem(catalog, p.equippedBanner);
              final effect = findItem(catalog, p.equippedEffect);
              final gradient = bannerGradient(banner);
              final scheme = Theme.of(context).colorScheme;
              return CenteredContent(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1080),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Cartão de identidade: mesma lógica do próprio
                        // perfil (faixa, avatar sobreposto, nome, emoticons
                        // e métricas) — sem menus, pronomes ou dados
                        // privados (só o dono vê).
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
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        Container(
                                          height: 110,
                                          decoration: BoxDecoration(
                                            gradient: gradient,
                                            color: gradient == null
                                                ? scheme
                                                      .surfaceContainerHighest
                                                : null,
                                          ),
                                        ),
                                        Positioned(
                                          left: 16,
                                          top: 65,
                                          child: Container(
                                            padding: const EdgeInsets.all(
                                              5,
                                            ),
                                            decoration: BoxDecoration(
                                              color: scheme.surface,
                                              shape: BoxShape.circle,
                                            ),
                                            child: FramedAvatar(
                                              radius: 40,
                                              image: profileAvatarImage(
                                                p.photoUrl,
                                                avatarItem,
                                                seed: p.username,
                                              ),
                                              fallbackLetter:
                                                  p.username.isNotEmpty
                                                  ? p.username[0]
                                                  : '?',
                                              frame: frame,
                                              avatarItem: avatarItem,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        57,
                                        16,
                                        20,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  p.username,
                                                  style: styledName(
                                                    p.username,
                                                    nameStyle,
                                                    const TextStyle(
                                                      fontSize: 20,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              LevelBadge(
                                                level: p.level,
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '@${p.username}',
                                            style: TextStyle(
                                              color: scheme
                                                  .onSurfaceVariant,
                                              fontSize: 13,
                                            ),
                                          ),
                                          if (p
                                              .equippedEmoticons
                                              .isNotEmpty) ...[
                                            const SizedBox(height: 8),
                                            Wrap(
                                              spacing: 6,
                                              runSpacing: 6,
                                              children: [
                                                for (final e
                                                    in p.equippedEmoticons)
                                                  Text(
                                                    e,
                                                    style:
                                                        const TextStyle(
                                                          fontSize: 20,
                                                        ),
                                                  ),
                                              ],
                                            ),
                                          ],
                                          if (p.teamName != null ||
                                              p.league != null) ...[
                                            const SizedBox(height: 8),
                                            Wrap(
                                              spacing: 8,
                                              runSpacing: 6,
                                              crossAxisAlignment:
                                                  WrapCrossAlignment.center,
                                              children: [
                                                if (p.teamName != null)
                                                  Chip(
                                                    avatar: const Icon(
                                                      Icons.groups_outlined,
                                                      size: 17,
                                                    ),
                                                    label: Text(p.teamName!),
                                                    visualDensity:
                                                        VisualDensity.compact,
                                                  ),
                                                // A liga de quem é visto:
                                                // emblema e rótulo. O RR e o
                                                // próximo degrau não saem do
                                                // GET /leagues dele.
                                                if (p.league != null)
                                                  LeagueBadgeChip(
                                                    badge: p.league!,
                                                  ),
                                              ],
                                            ),
                                          ],
                                          const SizedBox(height: 12),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: ProfileMetric(
                                                  value:
                                                      '${p.totalScore}',
                                                  label: 'Pontos',
                                                ),
                                              ),
                                              Expanded(
                                                child: ProfileMetric(
                                                  value:
                                                      '${p.territoriesCount}',
                                                  label: 'Territórios',
                                                ),
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
                                  child: ProfileEffectOverlay(
                                    effect: effect,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Evolução: mesma lógica do próprio perfil, sem o
                        // tempo de jogo (dado privado).
                        ProfileCard(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'Evolução',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 20),
                              LevelProgress(
                                level: p.level,
                                progress: p.levelProgress,
                                pointsToNext: p.pointsToNextLevel,
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
                                      p.rankPosition == null
                                          ? 'Sem posição no ranking'
                                          : '${p.rankPosition}º lugar no ranking',
                                    ),
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
              );
            },
          );
        },
      ),
    );
  }
}
