import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/centered_content.dart';
import '../widgets/insignia.dart';
import '../widgets/profile_activity.dart';
import 'app_footer.dart';

/// Insígnias: as conquistas que o mural publica, ganhas e por ganhar.
class BadgesScreen extends StatefulWidget {
  const BadgesScreen({super.key});

  @override
  State<BadgesScreen> createState() => _BadgesScreenState();
}

class _BadgesScreenState extends State<BadgesScreen> {
  Future<List<Insignia>>? _badges;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _badges ??= context.read<AppState>().api.getBadges();
  }

  void _retry() {
    final next = context.read<AppState>().api.getBadges();
    setState(() {
      _badges = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Insígnias')),
      body: FutureBuilder<List<Insignia>>(
        future: _badges,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || snapshot.data == null) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Não foi possível carregar suas insígnias.'),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _retry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Tentar novamente'),
                  ),
                ],
              ),
            );
          }
          final badges = snapshot.data!;
          final earned = badges.where((b) => b.earned).length;
          return CenteredContent(
            maxWidth: 720,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              children: [
                ProfileCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Ganhas · $earned de ${badges.length}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'O mural do perfil publica o que você já ganhou.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                for (final badge in badges) ...[
                  _BadgeTile(badge: badge),
                  const SizedBox(height: 12),
                ],
                const AppFooter(),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _BadgeTile extends StatelessWidget {
  const _BadgeTile({required this.badge});

  final Insignia badge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = badge.earned
        ? RunoverColors.territory
        : scheme.onSurfaceVariant;
    return ProfileCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: color.withValues(alpha: badge.earned ? .12 : .06),
              shape: BoxShape.circle,
            ),
            padding: const EdgeInsets.all(10),
            child: Icon(badgeIcon(badge.icon), color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  badge.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  badge.description,
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  badge.earned
                      ? 'Ganha em ${badgeDateLabel(badge.earnedAt!)}'
                      : 'Bloqueada · ${badgeProgressLabel(badge)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
