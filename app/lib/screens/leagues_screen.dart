import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../format.dart';
import '../state/app_state.dart';
import '../widgets/centered_content.dart';
import '../widgets/league_emblem.dart';
import '../widgets/profile_activity.dart';
import 'app_footer.dart';

/// Ligas do RUNOVER: a escada completa (7 ligas × 3 divisões + Lenda) e a
/// posição atual do jogador. Os números da temporada vêm do servidor.
class LeaguesScreen extends StatefulWidget {
  const LeaguesScreen({super.key});

  @override
  State<LeaguesScreen> createState() => _LeaguesScreenState();
}

class _LeaguesScreenState extends State<LeaguesScreen> {
  Future<LeaguesResponse>? _leagues;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _leagues ??= context.read<AppState>().api.getLeagues();
  }

  void _retry() {
    final next = context.read<AppState>().api.getLeagues();
    setState(() {
      _leagues = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ligas')),
      body: FutureBuilder<LeaguesResponse>(
        future: _leagues,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || snapshot.data == null) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Não foi possível carregar as ligas.'),
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
          final data = snapshot.data!;
          return CenteredContent(
            maxWidth: 900,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              children: [
                Text(
                  'Ligas do RUNOVER',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '7 ligas com 3 divisões cada, mais a liga Lenda no topo.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                _MeCard(
                  me: data.me,
                  entry: data.ladder.firstWhere(
                    (l) => l.key == data.me.league,
                    orElse: () => LeagueEntry(
                      key: data.me.league,
                      name: data.me.name,
                      color: data.me.color,
                      shape: 'circle',
                      tiers: const [],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final scale = (constraints.maxWidth / _boardWidth)
                        .clamp(0.55, 1.0);
                    return Center(
                      child: _LadderBoard(data: data, scale: scale),
                    );
                  },
                ),
                const SizedBox(height: 20),
                Text(
                  'Dentro de cada liga, a divisão 3 é a mais alta. '
                  'Lenda é uma posição de elite, sem divisões.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                const AppFooter(),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Card de posição atual: emblema, liga, barra de RR e próximo degrau.
class _MeCard extends StatelessWidget {
  const _MeCard({required this.me, required this.entry});

  final LeagueStatus me;
  final LeagueEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final leagueColor = _parseColor(entry.color);
    final divisionLabel = me.division == null ? '' : ' ${me.division}';
    final next = me.next;
    return ProfileCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              LeagueEmblem(
                color: leagueColor,
                shape: entry.shape,
                size: 56,
                highlight: true,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${me.name}$divisionLabel'.toUpperCase(),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: leagueColor,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${formatPoints(me.trophies)} troféus (RR)',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (next != null)
                Text(
                  'Faltam ${me.rrToNext} RR\npara ${next.name} ${next.division ?? ''}'
                      .trim(),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          if (me.rrToNext != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: me.rr / (me.rr + me.rrToNext!),
                minHeight: 8,
                backgroundColor: scheme.onSurfaceVariant.withValues(alpha: .15),
                valueColor: AlwaysStoppedAnimation(leagueColor),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${me.rr} / ${me.rr + me.rrToNext!} RR nesta divisão',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Você está no topo da escada.',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: leagueColor,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

const double _boardWidth = 8 * _cellWidth;
const double _cellWidth = 104;
const double _hexSize = 68;
const double _rowLabelWidth = 26;

/// A escada em si: colunas por liga, linhas da divisão 3 (topo) à 1,
/// Lenda sozinha na última coluna. Degraus acima do saldo ficam apagados.
class _LadderBoard extends StatelessWidget {
  const _LadderBoard({required this.data, required this.scale});

  final LeaguesResponse data;
  final double scale;

  double get _s => scale;

  @override
  Widget build(BuildContext context) {
    final regular = data.ladder.where((l) => l.key != 'lenda').toList();
    final lenda = data.ladder.firstWhere(
      (l) => l.key == 'lenda',
      orElse: () => const LeagueEntry(
        key: 'lenda',
        name: 'Lenda',
        color: '#F472B6',
        shape: 'star',
        tiers: [LeagueTier(division: null, at: 2100)],
      ),
    );
    final rowHeight = (_hexSize + 26) * _s;

    Widget cell(LeagueEntry league, LeagueTier tier) {
      final isCurrent =
          data.me.league == league.key && data.me.division == tier.division;
      final reached = data.me.trophies >= tier.at;
      final color = _parseColor(league.color);
      return SizedBox(
        width: _cellWidth * _s,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LeagueEmblem(
              color: color,
              shape: league.shape,
              size: _hexSize * _s,
              dimmed: !reached && !isCurrent,
              highlight: isCurrent,
            ),
            SizedBox(height: 6 * _s),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < (tier.division ?? 1); i++)
                  Container(
                    margin: EdgeInsets.symmetric(horizontal: 2.4 * _s),
                    width: 5 * _s,
                    height: 5 * _s,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withValues(
                        alpha: reached || isCurrent ? 0.95 : 0.3,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
    }

    return SizedBox(
      width: _boardWidth * _s,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Cabeçalho: nomes das ligas alinhados às colunas.
          Padding(
            padding: EdgeInsets.only(left: _rowLabelWidth * _s),
            child: Row(
              children: [
                for (final league in [...regular, lenda])
                  SizedBox(
                    width: _cellWidth * _s,
                    child: Text(
                      league.name.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12 * _s,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: _parseColor(league.color).withValues(
                          alpha:
                                  data.me.league == league.key ? 1.0 : 0.55,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(height: 8 * _s),
          // Divisão 3 no topo, 1 embaixo — a 3 é a mais alta da liga.
          for (var row = 0; row < 3; row++) ...[
            if (row > 0) SizedBox(height: 8 * _s),
            SizedBox(
              height: rowHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: _rowLabelWidth * _s,
                    child: Text(
                      '${3 - row}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13 * _s,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  for (final league in regular)
                    cell(league, league.tiers[2 - row]),
                  // Lenda: uma única posição de elite, centralizada.
                  if (row == 1) cell(lenda, lenda.tiers.first),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

Color _parseColor(String hex) {
  final value = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
  if (value == null) return const Color(0xFF8A94A6);
  return Color(0xFF000000 | value);
}
