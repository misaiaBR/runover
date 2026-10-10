import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../format.dart';
import '../models.dart';
import '../state/app_state.dart';
import '../widgets/centered_content.dart';
import '../widgets/cosmetics.dart';
import '../widgets/league_emblem.dart';
import 'public_profile_screen.dart';

class RankingScreen extends StatefulWidget {
  const RankingScreen({super.key});

  @override
  State<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends State<RankingScreen> {
  // Acentos da marca: iguais no claro e no escuro.
  static const _orange = Color(0xFFFF7F4D);
  static const _gold = Color(0xFFFFC93C);
  static const _teal = Color(0xFF3DDBB0);
  static const _purple = Color(0xFF8B7CFF);

  // Superfícies e textos acompanham o brilho do app — nunca fixos.
  ColorScheme get _scheme => Theme.of(context).colorScheme;
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _panel => _scheme.surface;
  Color get _border => _scheme.outlineVariant;
  Color get _muted => _scheme.onSurfaceVariant;

  String _period = 'week';
  bool _teams = false;
  late Future<List<RankingEntry>> _future;
  List<ShopItem> _catalog = const [];

  @override
  void initState() {
    super.initState();
    _future = context.read<AppState>().api.getRanking(period: _period);
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    try {
      final catalog = await context.read<AppState>().api.getShopCatalog();
      if (!mounted) return;
      setState(() => _catalog = catalog);
    } catch (_) {
      // Sem catálogo, o ranking mostra foto e nome padrão.
    }
  }

  void _selectPeriod(String period) {
    if (_period == period) return;
    setState(() {
      _period = period;
      _future = context.read<AppState>().api.getRanking(period: period);
    });
  }

  Future<void> _reload() async {
    setState(
      () => _future = context.read<AppState>().api.getRanking(period: _period),
    );
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AppState>().profile;
    return Scaffold(
      body: SafeArea(
        child: CenteredContent(
          maxWidth: 1500,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 18, 32, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(),
                const SizedBox(height: 20),
                _categoryTabs(),
                const SizedBox(height: 10),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _reload,
                    color: _orange,
                    child: FutureBuilder<List<RankingEntry>>(
                      future: _future,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(color: _orange),
                          );
                        }
                        if (snapshot.hasError) {
                          return ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              const SizedBox(height: 80),
                              Icon(
                                Icons.cloud_off_outlined,
                                size: 48,
                                color: _muted,
                              ),
                              const SizedBox(height: 12),
                              Center(
                                child: Text(
                                  'Não foi possível carregar o ranking. Arraste para tentar de novo.',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          );
                        }
                        final entries =
                            (snapshot.data ?? const <RankingEntry>[])
                                .where(
                                  (e) =>
                                      e.ownerType == (_teams ? 'team' : 'user'),
                                )
                                .toList();
                        return _rankingList(
                          entries,
                          profile?.username ?? '',
                          profile?.teamName,
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() => LayoutBuilder(
    builder: (context, constraints) {
      final periodTabs = _periodTabs();
      final title = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ranking',
            style: TextStyle(
              fontSize: 36,
              height: 1.1,
              color: _scheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _periodSubtitle,
            style: TextStyle(color: _muted, fontSize: 18),
          ),
        ],
      );
      if (constraints.maxWidth < 700) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            title,
            const SizedBox(height: 14),
            Align(alignment: Alignment.centerLeft, child: periodTabs),
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: title),
          periodTabs,
        ],
      );
    },
  );

  String get _periodSubtitle => switch (_period) {
    'week' => 'Quem dominou mais territórios nesta semana',
    'month' => 'Quem dominou mais territórios neste mês',
    _ => 'Quem dominou mais territórios no geral',
  };

  Widget _periodTabs() => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.centerLeft,
    child: Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _periodButton('week', 'Semana'),
          _periodButton('month', 'Mês'),
          _periodButton('all', 'Geral'),
        ],
      ),
    ),
  );

  Widget _periodButton(String period, String label) {
    final selected = _period == period;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: () => _selectPeriod(period),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? _orange : Colors.transparent,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? const Color(0xFF28140B) : _muted,
              fontSize: 16,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _categoryTabs() => Row(
    children: [
      _categoryButton(
        'Jogadores',
        selected: !_teams,
        onTap: () => setState(() => _teams = false),
      ),
      const SizedBox(width: 12),
      _categoryButton(
        'Equipes',
        selected: _teams,
        onTap: () => setState(() => _teams = true),
      ),
    ],
  );

  Widget _categoryButton(
    String label, {
    required bool selected,
    required VoidCallback onTap,
  }) => Semantics(
    button: true,
    selected: selected,
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF302018) : _panel,
          border: Border.all(
            color: selected ? _orange : Colors.transparent,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? const Color(0xFFFFAE8D) : _muted,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
  );

  Widget _rankingList(
    List<RankingEntry> entries,
    String username,
    String? teamName,
  ) {
    if (entries.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          Icon(
            _teams ? Icons.groups_outlined : Icons.emoji_events_outlined,
            size: 48,
            color: _muted,
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              _teams
                  ? 'Nenhuma equipe pontuou neste período.'
                  : 'Ninguém pontuou neste período. Seja o primeiro!',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted),
            ),
          ),
        ],
      );
    }
    final top = entries.take(3).toList();
    final rest = entries.skip(3).toList();
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 6, bottom: 12),
      children: [
        _podium(top, username, teamName),
        const SizedBox(height: 12),
        for (var i = 0; i < rest.length; i++)
          _entryCard(rest[i], i + 4, username, teamName),
        _progressPanel(entries, username, teamName),
      ],
    );
  }

  Widget _podium(List<RankingEntry> top, String username, String? teamName) =>
      SizedBox(
        height: 390,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final places = top.length == 3
                ? [(top[1], 2), (top[0], 1), (top[2], 3)]
                : [for (var i = 0; i < top.length; i++) (top[i], i + 1)];
            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final (entry, rank) in places)
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: _podiumPlace(
                        entry,
                        rank,
                        _isMine(entry, username, teamName),
                        constraints.maxWidth / places.length,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      );

  Widget _podiumPlace(RankingEntry entry, int rank, bool isMe, double width) {
    final accent = switch (rank) {
      1 => _gold,
      2 => const Color(0xFFB8BCCB),
      _ => _orange,
    };
    final barHeight = switch (rank) {
      1 => 145.0,
      2 => 95.0,
      _ => 70.0,
    };
    final radius = rank == 1 ? 49.0 : 40.0;
    return GestureDetector(
      onTap: entry.ownerType == 'user' ? () => _openProfile(entry) : null,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width, maxHeight: 390),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (rank == 1)
              const Icon(Icons.emoji_events_outlined, color: _gold, size: 26)
            else
              const SizedBox(height: 26),
            const SizedBox(height: 8),
            _avatar(entry, radius: radius, accent: accent, isMe: isMe),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                _entryName(entry),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _rankedName(
                  entry,
                  TextStyle(
                    color: _scheme.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${formatPoints(entry.totalScore)} pts',
              style: TextStyle(
                color: accent,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            // Liga de quem está no pódio — emblema e rótulo, sem o RR.
            if (entry.league != null) ...[
              const SizedBox(height: 6),
              LeagueBadgeChip(
                badge: entry.league!,
                emblemSize: 22,
                fontSize: 11,
              ),
            ],
            const SizedBox(height: 12),
            Container(
              height: barHeight,
              width: double.infinity,
              decoration: BoxDecoration(
                color: _panel,
                border: Border.all(color: accent, width: 1.5),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(18),
                ),
              ),
              alignment: Alignment.topCenter,
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                '$rank',
                style: TextStyle(
                  color: accent,
                  fontSize: 30,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _entryCard(
    RankingEntry entry,
    int rank,
    String username,
    String? teamName,
  ) {
    final isMe = _isMine(entry, username, teamName);
    final accent = isMe ? _orange : _border;
    final banner = findItem(_catalog, entry.equippedBanner);
    final gradient = bannerGradient(banner);
    final onBanner = gradient != null;
    final rankColor = onBanner
        ? Colors.white
        : (isMe ? _scheme.onPrimaryContainer : _muted);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: gradient == null
            ? (isMe ? _scheme.primaryContainer : _panel)
            : null,
        gradient: gradient,
        border: Border.all(color: accent, width: isMe ? 1.5 : 1),
        borderRadius: BorderRadius.circular(18),
      ),
      child: InkWell(
        onTap: entry.ownerType == 'user' ? () => _openProfile(entry) : null,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              SizedBox(
                width: 32,
                child: Text(
                  '$rank',
                  style: TextStyle(
                    color: rankColor,
                    fontSize: 20,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _avatar(
                entry,
                radius: 26,
                accent: isMe ? _orange : null,
                isMe: isMe,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      children: [
                        Text(
                          _entryName(entry),
                          style: _rankedName(
                            entry,
                            TextStyle(
                              color: _scheme.onSurface,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                            onBanner: onBanner,
                          ),
                        ),
                        if (isMe)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: _orange,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'Você',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                            ),
                          ),
                      ],
                    ),
                    // Liga de quem está na lista — emblema e rótulo, sem o RR
                    // do rival. Linha própria: ao lado do nome do adversário o
                    // card é estreito demais. Equipe não tem liga.
                    if (entry.league != null) ...[
                      const SizedBox(height: 4),
                      LeagueBadgeChip(badge: entry.league!),
                    ],
                    Text(
                      '${entry.territoriesCount} territórios',
                      style: TextStyle(
                        color: onBanner ? Colors.white70 : _muted,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${formatPoints(entry.totalScore)} pts',
                style: TextStyle(
                  color: onBanner ? Colors.white : _scheme.onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _progressPanel(
    List<RankingEntry> entries,
    String username,
    String? teamName,
  ) {
    final index = entries.indexWhere((e) => _isMine(e, username, teamName));
    if (index < 0) return const SizedBox(height: 4);
    final mine = entries[index];
    final next = index > 0 ? entries[index - 1] : null;
    final gap = next == null
        ? 0
        : (next.totalScore - mine.totalScore).clamp(0, 1 << 30);
    final progress = next == null || next.totalScore <= 0
        ? 1.0
        : (mine.totalScore / next.totalScore).clamp(0.0, 1.0);
    final place = index + 1;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _isDark ? const Color(0xFF2A2240) : const Color(0xFFE9E6FF),
        border: Border.all(color: _purple, width: 1.5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Você está em $placeº',
                style: TextStyle(
                  color: _scheme.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (next != null)
                Text(
                  'Faltam $gap pts para o ${place - 1}º',
                  style: TextStyle(
                    color: _isDark ? const Color(0xFFC9C2FF) : _muted,
                    fontSize: 15,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 12,
              backgroundColor: _isDark
                  ? const Color(0xFF40385B)
                  : _scheme.surfaceContainerHighest,
              valueColor: const AlwaysStoppedAnimation(_teal),
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth < 520
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _pointsText(),
                      const SizedBox(height: 10),
                      _pointsButton(),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: _pointsText()),
                      const SizedBox(width: 12),
                      _pointsButton(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _pointsText() => Text(
    'Cada território novo vale +50 pts',
    style: TextStyle(color: _muted, fontSize: 16),
  );

  Widget _pointsButton() => FilledButton(
    style: FilledButton.styleFrom(
      backgroundColor: _gold,
      foregroundColor: const Color(0xFF3A2A00),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    ),
    onPressed: _showPointsHelp,
    child: const Text('Ver como ganhar pontos'),
  );

  Widget _avatar(
    RankingEntry entry, {
    required double radius,
    Color? accent,
    required bool isMe,
  }) {
    final frame = findItem(_catalog, entry.equippedFrame);
    final avatarItem = findItem(_catalog, entry.equippedAvatar);
    final initial = entry.name.isEmpty
        ? '?'
        : entry.name.characters.first.toUpperCase();
    final avatar = FramedAvatar(
      radius: radius,
      image: profileAvatarImage(
        entry.photoUrl,
        avatarItem,
        seed: entry.name,
      ),
      fallbackLetter: initial,
      frame: frame,
      avatarItem: avatarItem,
    );
    if (frame != null) return avatar;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: accent ?? (isMe ? _orange : _border),
          width: 2,
        ),
      ),
      child: avatar,
    );
  }

  /// Nome com o estilo da loja do dono.
  TextStyle _rankedName(RankingEntry entry, TextStyle base, {bool onBanner = false}) {
    final style = findItem(_catalog, entry.equippedNameStyle);
    return styledName(
      _entryName(entry),
      style,
      onBanner ? base.copyWith(color: Colors.white) : base,
    );
  }

  String _entryName(RankingEntry entry) =>
      entry.ownerType == 'user' ? '@${entry.name}' : entry.name;

  bool _isMine(RankingEntry entry, String username, String? teamName) =>
      entry.ownerType == 'user'
      ? entry.name == username
      : entry.name == teamName;

  void _openProfile(RankingEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PublicProfileScreen(username: entry.name),
      ),
    );
  }

  void _showPointsHelp() {
    final scheme = _scheme;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _panel,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Como ganhar pontos',
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Conquiste territórios correndo para somar pontos. Defender e recuperar áreas também altera sua pontuação.',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}
