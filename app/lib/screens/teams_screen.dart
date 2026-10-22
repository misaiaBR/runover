import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../services/api_client.dart';
import '../services/profile_image_provider.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/centered_content.dart';
import '../widgets/runover_ui.dart';
import '../widgets/cosmetics.dart';
import '../widgets/level_badge.dart';
import '../widgets/team_exit.dart';
import 'app_footer.dart';
import 'profile_screen.dart';
import 'public_profile_screen.dart';
import 'team_settings_screen.dart';

/// Uma equipe conta como "nova" nos primeiros 7 dias. Comparação em UTC dos
/// dois lados para não depender do fuso do aparelho nem do formato (com ou
/// sem `Z`) enviado pelo backend.
bool isNewTeam(TeamSummary team) {
  final created = team.createdAt;
  if (created == null) return false;
  return DateTime.now().toUtc().difference(created.toUtc()).inDays < 7;
}

/// RF16/RN14/RN15 — UC10 (Criar/participar de equipe).
class TeamsScreen extends StatefulWidget {
  const TeamsScreen({super.key});

  @override
  State<TeamsScreen> createState() => _TeamsScreenState();
}

class _TeamsScreenState extends State<TeamsScreen> {
  TeamDetail? _myTeam;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final team = await context.read<AppState>().api.getMyTeam();
      setState(() => _myTeam = team);
    } on ApiException {
      setState(() => _myTeam = null);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Recarga pedida por quem vive dentro desta tela: o painel, a aba de
  /// ingresso/criação e a rota empilhada das Configurações.
  ///
  /// A guarda fica aqui, no dono, e não nos filhos: uma escrita que deu certo
  /// na tela de configurações precisa recarregar a lista mesmo se aquela rota
  /// fechou enquanto a requisição esperava. Filho que chama o callback depois de
  /// um `await` não tem como saber se este ainda está montado.
  void _refresh() {
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final team = _myTeam;
    // Sem wrapper de Theme aqui: a tela herda o tema claro/escuro do app
    // (MaterialApp) para acompanhar a troca em tempo real.
    return Scaffold(
      appBar: AppBar(
          title: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.groups_outlined),
              SizedBox(width: 8),
              Text('Equipe'),
            ],
          ),
          // A engrenagem é para todo mundo da equipe: a tela de configurações
          // mostra as seções que o papel daquela pessoa pode mexer.
          actions: [
            if (team != null)
              IconButton(
                tooltip: 'Configurações da equipe',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => TeamSettingsScreen(
                      team: team,
                      onChanged: _refresh,
                    ),
                  ),
                ),
              ),
          ],
        ),
        body: _loading
            ? Center(
                child: CircularProgressIndicator(
                  color: Theme.of(context).colorScheme.primary,
                ),
              )
            : RefreshIndicator(
                onRefresh: _load,
                child: _myTeam != null
                    ? _MyTeamView(team: _myTeam!, onChanged: _refresh)
                    : _JoinOrCreateView(onChanged: _refresh, error: _error),
              ),
    );
  }
}

/// Arte estável por equipe a partir da galeria de avatares (sem campo
/// de imagem na API): o id define qual asset ilustra o card.
/// Usa FNV-1a porque `String.hashCode` varia entre execuções/plataformas.
String teamCardAsset(String teamId) {
  var hash = 0x811c9dc5;
  for (final unit in teamId.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  return presetAvatars[hash % presetAvatars.length].asset;
}

class _MyTeamView extends StatelessWidget {
  final TeamDetail team;
  final VoidCallback onChanged;
  const _MyTeamView({required this.team, required this.onChanged});

  Future<void> _act(BuildContext context, Future<void> Function() call) async {
    try {
      await call();
      // Sem checar `mounted` aqui: o que saiu de cena pode ser só este painel,
      // e a escrita deu certo — quem precisa recarregar é o dono do callback.
      onChanged();
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final slots = team.zoneCapacity;
    return CenteredContent(
      maxWidth: 1500,
      child: ListView(
        padding: const EdgeInsets.all(28),
        children: [
          _TeamIdentity(team: team),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final stats = _statsRow(context, slots);
              final base = _TeamBaseCard(team: team);
              final progress = _TeamProgressCard(team: team);
              final members = _TeamMembersCard(team: team, onAct: _act);
              if (constraints.maxWidth < 900) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    stats,
                    const SizedBox(height: 12),
                    base,
                    const SizedBox(height: 12),
                    progress,
                    const SizedBox(height: 12),
                    members,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [stats, const SizedBox(height: 12), base],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [progress, const SizedBox(height: 12), members],
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () async {
              if (await confirmTeamExit(context, team)) onChanged();
            },
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('Sair da equipe'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const _BrowseTeamsScreen(),
              ),
            ),
            icon: const Icon(Icons.explore_outlined, size: 18),
            label: const Text('Ver outras equipes'),
          ),
          const SizedBox(height: 24),
          const AppFooter(),
        ],
      ),
    );
  }

  Widget _statsRow(BuildContext context, int slots) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: 'Pontos',
            value: '${team.totalScore}',
            icon: Icons.bolt,
            iconColor: scheme.primary,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => HistoryScreen(
                  title: 'Pontos de ${team.name}',
                  loader: () =>
                      context.read<AppState>().api.getTeamHistory(team.id),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            label: 'Zonas conquistadas',
            value: '${math.min(team.territoriesCount, slots)} / $slots',
            icon: Icons.map_outlined,
            iconColor: scheme.secondary,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => _TeamZonesScreen(team: team),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Cabeçalho do painel: arte da equipe, nome, autor e o selo de nível.
class _TeamIdentity extends StatelessWidget {
  const _TeamIdentity({required this.team});

  final TeamDetail team;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final photoImage = profileImageProvider(team.photoUrl);
    return Column(
      children: [
        CircleAvatar(
          radius: 40,
          backgroundColor: scheme.secondary.withValues(alpha: 0.15),
          foregroundImage: photoImage,
          onForegroundImageError: photoImage == null ? null : (_, _) {},
          child: Text(
            team.name.isNotEmpty ? team.name[0].toUpperCase() : '?',
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.bold,
              color: scheme.secondary,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          team.name,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        Text(
          'Criada por @${team.creatorUsername}',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        LevelBadge(level: team.level),
      ],
    );
  }
}

/// Voltas de hexágono necessárias para desenhar `capacity` células. O
/// servidor publica a capacidade; daqui só sai geometria.
int _baseRingsForCapacity(int capacity) {
  var rings = 1;
  while (1 + 3 * rings * (rings + 1) < capacity && rings < 6) {
    rings++;
  }
  return rings;
}

/// Pontos axiais (q, r) de um hexágono de `rings` voltas, do centro para fora
/// e depois no sentido horário.
List<Offset> _hexCells(int rings) {
  final cells = <Offset>[];
  for (var q = -rings; q <= rings; q++) {
    for (var r = math.max(-rings, -q - rings);
        r <= math.min(rings, -q + rings);
        r++) {
      cells.add(Offset(q.toDouble(), r.toDouble()));
    }
  }
  cells.sort((a, b) {
    final distance = _hexDistance(a).compareTo(_hexDistance(b));
    if (distance != 0) return distance;
    return math
        .atan2(a.dy, a.dx)
        .compareTo(math.atan2(b.dy, b.dx));
  });
  return cells;
}

double _hexDistance(Offset cell) {
  final q = cell.dx, r = cell.dy;
  return (q.abs() + r.abs() + (q + r).abs()) / 2;
}

/// A base vista de cima: uma célula por território em posse da equipe, do
/// centro para fora, na ordem em que foram conquistados.
class _TeamBaseCard extends StatelessWidget {
  const _TeamBaseCard({required this.team});

  final TeamDetail team;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rings = _baseRingsForCapacity(team.zoneCapacity);
    // O servidor define quantas células existem; o anel só empresta a forma.
    final cells = _hexCells(rings).take(team.zoneCapacity).toList();
    // A posse atual vem do servidor; perder um território apaga a célula.
    final zones = team.territories.take(cells.length).toList();
    // Célula de 56px enquanto couber; uma base de 4 voltas transbordaria.
    final hexWidth = math.min(56.0, 340.0 / (1 + 1.5 * rings));
    final hexHeight = hexWidth * math.sqrt(3) / 2;
    final originX = hexWidth / 2 + 0.75 * hexWidth * rings;
    final originY = hexHeight / 2 + hexHeight * rings;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Base da equipe',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: SizedBox(
                width: originX * 2,
                height: originY * 2,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (var i = 0; i < cells.length; i++)
                      Positioned(
                        left: originX +
                            0.75 * hexWidth * cells[i].dx -
                            hexWidth / 2,
                        top: originY +
                            hexHeight *
                                (cells[i].dy + cells[i].dx / 2) -
                            hexHeight / 2,
                        child: _HexSlot(
                          width: hexWidth,
                          height: hexHeight,
                          zone: i < zones.length ? zones[i] : null,
                          onTap: () => _showZone(context, i),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                zones.isEmpty
                    ? 'Zona 1: conquiste um território no mapa para acendê-la'
                    : 'Toque em uma zona para ver o território que a acende',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A célula ocupada mostra o território real por trás dela; a vazia explica
  /// o que falta acendê-la. Nenhuma das duas inventa uma conquista própria.
  Future<void> _showZone(BuildContext context, int index) async {
    final zone = index < team.territories.length
        ? team.territories[index]
        : null;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Zona ${index + 1}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            if (zone != null) ...[
              Text(
                zone.name,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${zone.points} pts · conquistado em ${_zoneDate(zone.conqueredAt)}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'A célula pertence enquanto a posse for da equipe: se outro '
                'corredor fechar o laço por cima, o território muda de dono e '
                'a zona se apaga.',
              ),
            ] else ...[
              const Text('Livre — nada ocupa esta célula ainda.'),
              const SizedBox(height: 10),
              const Text(
                'Território se conquista correndo: abra o mapa, saia daqui e '
                'feche um laço com o trajeto gravado. A tolerância para fechar '
                'vem da precisão do GPS em cada ponto, e uma pausa só custa a '
                'zona se você retomar a mais de 100 m do ponto parado.',
              ),
            ],
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Entendi'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _zoneDate(DateTime d) {
  final local = d.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year}';
}

/// Uma célula hexagonal da base: ocupada por um território ou livre.
class _HexSlot extends StatelessWidget {
  const _HexSlot({
    required this.width,
    required this.height,
    required this.zone,
    required this.onTap,
  });

  final double width;
  final double height;
  final TeamTerritoryInfo? zone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final conquered = zone != null;
    final accent = conquered ? scheme.primary : scheme.onSurfaceVariant;
    return Tooltip(
      message: conquered
          ? 'Zona: ${zone!.name}'
          : 'Zona livre: conquiste um território no mapa',
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: width,
          height: height,
          child: CustomPaint(
            painter: _HexagonPainter(
              fill: conquered
                  ? scheme.primary.withValues(alpha: 0.18)
                  : scheme.onSurface.withValues(alpha: 0.04),
              stroke: conquered
                  ? scheme.primary
                  : scheme.outlineVariant.withValues(alpha: 0.7),
            ),
            child: Center(
              child: Icon(
                conquered ? Icons.push_pin : Icons.add,
                size: 18,
                color: accent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HexagonPainter extends CustomPainter {
  const _HexagonPainter({required this.fill, required this.stroke});

  final Color fill;
  final Color stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final angle = math.pi / 3 * i;
      final point = Offset(
        size.width / 2 + size.width / 2 * math.cos(angle),
        size.height / 2 + size.height / 2 * math.sin(angle),
      );
      i == 0
          ? path.moveTo(point.dx, point.dy)
          : path.lineTo(point.dx, point.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = stroke,
    );
  }

  @override
  bool shouldRepaint(_HexagonPainter old) =>
      old.fill != fill || old.stroke != stroke;
}

/// Progresso da equipe até o próximo nível e o que ele libera.
class _TeamProgressCard extends StatelessWidget {
  const _TeamProgressCard({required this.team});

  final TeamDetail team;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final nextThreshold = team.totalScore + team.pointsToNextLevel;
    void openTrail() => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _TeamTrailScreen(team: team)),
    );
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: openTrail,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Progresso da equipe',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '${team.totalScore} / $nextThreshold pts',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _TeamProgressBar(progress: team.levelProgress),
              const SizedBox(height: 8),
              Text(
                'Faltam ${team.pointsToNextLevel} pts para o nível '
                '${team.level + 1}',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
              const SizedBox(height: 14),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: openTrail,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          _IconTile(icon: Icons.add, color: scheme.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Próximo nível',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'O nível ${team.level + 1} libera mais zonas '
                                  'na base',
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            color: scheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
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

/// A trilha de níveis da equipe em serpentina: cada parada diz quanto custa e
/// quantas células da base ela acende. Os números vêm do servidor
/// (`TeamDetail.levelTrail`); daqui sai só o desenho.
class _TeamTrailScreen extends StatelessWidget {
  const _TeamTrailScreen({required this.team});

  final TeamDetail team;

  static const _nodeWidth = 210.0;
  static const _nodeExtent = 176.0;
  static const _badgeSize = 38.0;
  static const _laneShifts = [-0.7, 0.0, 0.7, 0.0];

  double _lane(int index) => _laneShifts[index % _laneShifts.length];

  double _dx(int index, double width) =>
      width / 2 + _lane(index) * math.max(0.0, (width - _nodeWidth) / 2);

  /// Nível 1 embaixo, subindo — igual à trilha do passe.
  double _dy(int index, int count) =>
      (count - 1 - index) * _nodeExtent + _badgeSize / 2;

  Offset _center(int index, double width) =>
      Offset(_dx(index, width), _dy(index, team.levelTrail.length));

  /// Posição fracionária da equipe: o nível alcançado mais a fatia do caminho
  /// que a barra de progresso já cobriu.
  double get _runnerIndex {
    final count = team.levelTrail.length;
    if (count == 0) return 0;
    final current = math.max(0.0, team.level - 1).toDouble();
    return (current + team.levelProgress).clamp(0.0, (count - 1).toDouble());
  }

  Offset _runnerPosition(double width) {
    final count = team.levelTrail.length;
    final index = _runnerIndex;
    final lower = index.floor();
    if (count == 0 || lower + 1 >= count) return _center(lower, width);
    final start = _center(lower, width);
    final end = _center(lower + 1, width);
    final fraction = index - lower;
    return Offset(
      start.dx + (end.dx - start.dx) * fraction,
      start.dy + (end.dy - start.dy) * fraction,
    );
  }

  /// Marca da equipe na trilha — acima do ponto do caminho, senão cobriria o
  /// número do nível.
  Widget _runner(BuildContext context, double width) {
    final scheme = Theme.of(context).colorScheme;
    final badge = scheme.secondary;
    final position = _runnerPosition(width);
    return Positioned(
      left: position.dx - 17,
      top: position.dy - _badgeSize - 10,
      child: Semantics(
        label: 'Equipe aqui',
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: badge,
            shape: BoxShape.circle,
            // O anel separa a marca da linha da trilha; na superfície do tema
            // ele aparece nos dois, enquanto o branco fixo sumia no tema claro.
            border: Border.all(color: scheme.surface, width: 2),
          ),
          child: Icon(Icons.flag, size: 18, color: inkOnAccent(badge)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stops = team.levelTrail;
    return Scaffold(
      appBar: AppBar(title: Text('Trilha de ${team.name}')),
      body: CenteredContent(
        maxWidth: 720,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Cada nível acende mais células na base. A equipe está no '
                'nível ${team.level}, com ${team.totalScore} pts.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth.isFinite
                      ? constraints.maxWidth
                      : _nodeWidth;
                  return CustomPaint(
                    painter: _TeamTrailPainter(
                      screen: this,
                      width: width,
                      route: scheme.primary,
                    ),
                    child: SizedBox(
                      width: width,
                      height: math.max(
                        _nodeExtent,
                        stops.length * _nodeExtent,
                      ),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          for (var i = 0; i < stops.length; i++)
                            Positioned(
                              left: _dx(i, width) - _nodeWidth / 2,
                              top: _dy(i, stops.length) - _badgeSize / 2,
                              width: _nodeWidth,
                              child: Column(
                                children: [
                                  _TeamLevelBadge(
                                    stop: stops[i],
                                    current: stops[i].level == team.level,
                                  ),
                                  const SizedBox(height: 6),
                                  _TeamLevelStopCard(
                                    stop: stops[i],
                                    previous: i == 0 ? null : stops[i - 1],
                                    score: team.totalScore,
                                  ),
                                ],
                              ),
                            ),
                          if (stops.isNotEmpty) _runner(context, width),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TeamTrailPainter extends CustomPainter {
  const _TeamTrailPainter({
    required this.screen,
    required this.width,
    required this.route,
  });

  final _TeamTrailScreen screen;
  final double width;

  /// Cor do caminho percorrido, vinda do tema: o pintor não tem `BuildContext`,
  /// então quem desenha entrega a tinta. Fixar `RunoverColors.route` deixava a
  /// trilha escura sobre o painel escuro.
  final Color route;

  @override
  void paint(Canvas canvas, Size size) {
    final stops = screen.team.levelTrail;
    if (stops.length < 2) return;
    for (var i = 0; i < stops.length - 1; i++) {
      final from = screen._center(i, width);
      final to = screen._center(i + 1, width);
      final reached = stops[i + 1].reached;
      final path = Path()
        ..moveTo(from.dx, from.dy)
        ..quadraticBezierTo(width / 2, (from.dy + to.dy) / 2, to.dx, to.dy);
      canvas.drawPath(
        path,
        Paint()
          ..color = route.withValues(alpha: reached ? 0.85 : 0.2)
          ..strokeWidth = reached ? 7 : 4
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(_TeamTrailPainter old) =>
      old.width != width ||
      old.route != route ||
      old.screen.team != screen.team;
}

class _TeamLevelBadge extends StatelessWidget {
  const _TeamLevelBadge({required this.stop, required this.current});

  final TeamLevelStop stop;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fill = stop.reached
        ? scheme.primary
        : scheme.surfaceContainerHighest;
    // O anel branco do mock separava o número do trilho escuro; no cartão claro
    // ele não existia. A superfície do tema faz o mesmo serviço nos dois.
    final ring = current
        ? scheme.secondary
        : (stop.reached ? scheme.surface : scheme.outlineVariant);
    return Container(
      width: _TeamTrailScreen._badgeSize,
      height: _TeamTrailScreen._badgeSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill,
        border: Border.all(color: ring, width: current ? 3 : 2),
      ),
      child: Center(
        child: Text(
          '${stop.level}',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 15,
            color: stop.reached
                ? inkOnAccent(fill)
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _TeamLevelStopCard extends StatelessWidget {
  const _TeamLevelStopCard({
    required this.stop,
    required this.previous,
    required this.score,
  });

  final TeamLevelStop stop;
  final TeamLevelStop? previous;
  final int score;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final gained = stop.zoneCapacity - (previous?.zoneCapacity ?? 0);
    final zones = previous == null
        ? 'A base abre com ${stop.zoneCapacity} células'
        : (gained > 0
              ? 'Libera +$gained células na base'
              : 'A base já está cheia (${stop.zoneCapacity} células)');
    final muted = TextStyle(fontSize: 11, color: scheme.onSurfaceVariant);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: stop.reached ? scheme.surface : scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: stop.reached ? scheme.primary : scheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Nível ${stop.level} · ${stop.pointsRequired} pts',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
            const SizedBox(height: 2),
            Text(zones, style: muted),
            Text(
              stop.reached
                  ? (stop.level == 1
                        ? 'Ponto de partida da equipe'
                        : 'Alcançado')
                  : 'Faltam ${stop.pointsRequired - score} pts',
              style: muted,
            ),
          ],
        ),
      ),
    );
  }
}

class _TeamProgressBar extends StatelessWidget {
  const _TeamProgressBar({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        height: 10,
        color: scheme.onSurface.withValues(alpha: 0.08),
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: progress.clamp(0.0, 1.0),
          child: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [RunoverColors.route, RunoverColors.routeDark],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Membros visíveis, papel de cada um e como entrar na equipe.
class _TeamMembersCard extends StatelessWidget {
  const _TeamMembersCard({required this.team, required this.onAct});

  final TeamDetail team;
  final Future<void> Function(BuildContext, Future<void> Function()) onAct;

  static const _visible = 3;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = team.members.take(_visible).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Membros (${team.memberCount})',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (team.members.length > _visible)
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            _AllMembersScreen(team: team, onAct: onAct),
                      ),
                    ),
                    child: const Text('Ver todos'),
                  ),
              ],
            ),
            for (final member in shown)
              _MemberRow(team: team, member: member, onAct: onAct),
            const SizedBox(height: 10),
            if (team.isAdmin)
              FilledButton.tonalIcon(
                onPressed: () => _inviteFriend(context),
                icon: const Icon(Icons.person_add_alt, size: 18),
                label: const Text('Convidar amigos'),
              )
            else
              Text(
                'Só o dono e os admins convidam por aqui.',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
            if (team.isOwner)
              Text(
                'Pedidos de entrada aparecem em Configurações da equipe.',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Dono/admin chama pelo @usuário: o servidor abre o pedido em nome do
  /// convidado, que aceita ou recusa na aba Equipe.
  Future<void> _inviteFriend(BuildContext context) async {
    final username = await showDialog<String>(
      context: context,
      builder: (_) => _InviteDialog(teamName: team.name),
    );
    if (username == null || !context.mounted) return;
    await onAct(context, () async {
      await context.read<AppState>().api.inviteTeammate(team.id, username);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('@$username foi convidado para ${team.name}.')),
      );
    });
  }
}

class _InviteDialog extends StatefulWidget {
  const _InviteDialog({required this.teamName});

  final String teamName;

  @override
  State<_InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends State<_InviteDialog> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _username => _controller.text.trim().replaceFirst('@', '');

  void _submit() {
    if (_username.length < _minUsernameLength) return;
    Navigator.of(context).pop(_username);
  }

  static const _minUsernameLength = 3;

  @override
  Widget build(BuildContext context) {
    final valid = _username.length >= _minUsernameLength;
    return AlertDialog(
      title: Text('Chamar para ${widget.teamName}'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        maxLength: 24,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: '@usuário',
          helperText: valid
              ? 'O convite chega como aviso; a pessoa aceita quando quiser.'
              : 'Digite o @usuário a partir de 3 letras.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Agora não'),
        ),
        FilledButton(
          onPressed: valid ? _submit : null,
          child: const Text('Convidar'),
        ),
      ],
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.team, required this.member, required this.onAct});

  final TeamDetail team;
  final TeamMemberInfo member;
  final Future<void> Function(BuildContext, Future<void> Function()) onAct;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isCreator = member.username == team.creatorUsername;
    final photo = profileImageProvider(member.photoUrl);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        // O mesmo perfil público que o ranking abre.
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PublicProfileScreen(username: member.username),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            children: [
              CircleAvatar(
                radius: 19,
                backgroundColor: scheme.primary.withValues(alpha: 0.18),
                foregroundImage: photo,
                onForegroundImageError: photo == null ? null : (_, _) {},
                child: Text(
                  member.username.isNotEmpty
                      ? member.username[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '@${member.username}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (isCreator)
                const _RoleChip(label: 'Criador', color: Color(0xFFE3A008))
              else if (member.isAdmin)
                const _RoleChip(label: 'Admin', color: RunoverColors.territory),
              if (team.isOwner && !isCreator)
                PopupMenuButton<String>(
                  tooltip: 'Ações de admin',
                  icon: const Icon(Icons.more_vert),
                  onSelected: (action) => onAct(
                    context,
                    action == 'promote'
                        ? () => context
                              .read<AppState>()
                              .api
                              .promoteAdmin(team.id, member.username)
                        : () => context
                              .read<AppState>()
                              .api
                              .demoteAdmin(team.id, member.username),
                  ),
                  itemBuilder: (_) => [
                    if (!member.isAdmin)
                      const PopupMenuItem(
                        value: 'promote',
                        child: Text('Tornar admin'),
                      )
                    else
                      const PopupMenuItem(
                        value: 'demote',
                        child: Text('Remover admin'),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.label, required this.color});

  final String label;

  /// Matiz do papel. Vira tinta legível da superfície atual dentro do widget:
  /// o chamador só diz "é o azul de admin", nunca de que tema é a cor.
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ink = legibleInk(color, context);
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: ink.withValues(alpha: 0.16),
      ),
      child: Text(
        label,
        style: TextStyle(color: ink, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _IconTile extends StatelessWidget {
  const _IconTile({required this.icon, required this.color});

  final IconData icon;

  /// Ver [_RoleChip]: o matiz é do chamador, a leitura é do tema.
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ink = legibleInk(color, context);
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: ink.withValues(alpha: 0.16),
      ),
      child: Icon(icon, color: ink, size: 20),
    );
  }
}

/// Lista completa de membros para quando o card não dá conta.
class _AllMembersScreen extends StatelessWidget {
  const _AllMembersScreen({required this.team, required this.onAct});

  final TeamDetail team;
  final Future<void> Function(BuildContext, Future<void> Function()) onAct;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Membros de ${team.name}')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          for (final member in team.members)
            _MemberRow(team: team, member: member, onAct: onAct),
        ],
      ),
    );
  }
}

/// As zonas acesas na base, em lista rolável: o mesmo dado que acende os
/// hexágonos, agora com histórico e valor de cada um.
class _TeamZonesScreen extends StatelessWidget {
  const _TeamZonesScreen({required this.team});

  final TeamDetail team;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final zones = team.territories;
    return Scaffold(
      appBar: AppBar(title: Text('Zonas de ${team.name}')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          Text(
            zones.isEmpty
                ? 'Nenhuma das ${team.zoneCapacity} células da base está acesa.'
                : '${zones.length} de ${team.zoneCapacity} células acesas, da '
                      'conquista mais antiga para a mais nova.',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          if (zones.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Território se conquista correndo: abra o mapa, feche um '
                  'laço com o trajeto gravado e a primeira célula da base '
                  'acende.',
                ),
              ),
            )
          else
            for (var i = 0; i < zones.length; i++)
              Card(
                child: ListTile(
                  leading: _IconTile(
                    icon: Icons.push_pin,
                    color: RunoverColors.route,
                  ),
                  title: Text('Zona ${i + 1} · ${zones[i].name}'),
                  subtitle: Text(
                    '${zones[i].points} pts · conquistado em '
                    '${_zoneDate(zones[i].conqueredAt)}',
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;
  final VoidCallback? onTap;
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
          child: Row(
            children: [
              _IconTile(icon: icon, color: iconColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        value,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      label,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(
                  Icons.chevron_right,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Card de equipe com arte de fundo e véu escuro para legibilidade.
class _TeamCard extends StatelessWidget {
  const _TeamCard({
    required this.team,
    required this.pending,
    required this.onJoin,
    this.frame,
    this.nameStyle,
  });

  final TeamSummary team;
  final bool pending;
  final VoidCallback onJoin;
  final ShopItem? frame;
  final ShopItem? nameStyle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = [
      const Color(0xFF3DDBB0),
      const Color(0xFF8B7CFF),
      const Color(0xFFFFC93C),
      const Color(0xFFFF7F4D),
    ];
    var hash = 0x811c9dc5;
    for (final unit in team.id.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    final accent = colors[hash % colors.length];
    final isNew = isNewTeam(team);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 650;
        final details = Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    team.name,
                    style: styledName(
                      team.name,
                      nameStyle,
                      TextStyle(
                        color: scheme.onSurface,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                      // O nome está no cartão do tema, não na faixa do banner:
                      // sem contexto o estilo do catálogo ficava cru.
                      context: context,
                    ),
                  ),
                  if (isNew) _teamTag('Nova', const Color(0xFF8B7CFF)),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Criada por @${team.creatorUsername}',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _teamStat(
                    context,
                    '${team.memberCount} ${team.memberCount == 1 ? 'membro' : 'membros'}',
                  ),
                  _teamStat(
                    context,
                    team.territoriesCount == 0
                        ? 'Seja o primeiro'
                        : '${team.territoriesCount} zonas',
                  ),
                ],
              ),
            ],
          ),
        );
        final join = Semantics(
          button: !pending,
          container: true,
          excludeSemantics: true,
          label: pending
              ? 'Pedido pendente em ${team.name}'
              : 'Solicitar entrada na equipe ${team.name}',
          child: OutlinedButton(
            key: Key('team-join-${team.id}'),
            onPressed: pending ? null : onJoin,
            style: OutlinedButton.styleFrom(
              // O acento derivado do id foi desenhado sobre o cartão escuro do
              // mock: solto no tema claro o teal e o dourado somem, e o botão
              // deixa de ter contorno. Tinta e contorno vêm da mesma leitura.
              foregroundColor: legibleInk(accent, context),
              side: BorderSide(color: legibleInk(accent, context), width: 1.5),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(pending ? 'Aguardando aprovação' : 'Solicitar entrada'),
          ),
        );

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? const Color(0xFF0A0B10)
                    : Colors.black.withValues(alpha: 0.08),
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        _teamAvatar(team, accent),
                        const SizedBox(width: 16),
                        details,
                      ],
                    ),
                    const SizedBox(height: 12),
                    Align(alignment: Alignment.centerRight, child: join),
                  ],
                )
              : Row(
                  children: [
                    _teamAvatar(team, accent),
                    const SizedBox(width: 24),
                    details,
                    const SizedBox(width: 16),
                    join,
                  ],
                ),
        );
      },
    );
  }

  Widget _teamAvatar(TeamSummary team, Color accent) {
    final photo = profileImageProvider(team.photoUrl);
    return FramedAvatar(
      radius: 40,
      image: photo ?? AssetImage(teamCardAsset(team.id)),
      fallbackLetter: team.name.isNotEmpty
          ? team.name[0].toUpperCase()
          : '?',
      frame: frame,
    );
  }

  Widget _teamTag(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      label,
      style: const TextStyle(
        color: Color(0xFF17131A),
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _teamStat(BuildContext context, String label) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: scheme.onSurface,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// Vitrine de outras equipes para quem já tem equipe: ver pode, entrar
/// só depois de sair da atual (o servidor barra com 400).
class _BrowseTeamsScreen extends StatelessWidget {
  const _BrowseTeamsScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Outras equipes')),
      body: _JoinOrCreateView(browseOnly: true, error: null, onChanged: () {}),
    );
  }
}

class _JoinOrCreateView extends StatefulWidget {
  final VoidCallback onChanged;
  final String? error;
  final bool browseOnly;
  const _JoinOrCreateView({
    required this.onChanged,
    required this.error,
    this.browseOnly = false,
  });

  @override
  State<_JoinOrCreateView> createState() => _JoinOrCreateViewState();
}

class _JoinOrCreateViewState extends State<_JoinOrCreateView> {
  late Future<List<TeamSummary>> _teamsFuture;
  Future<List<TeamInvitation>>? _invitesFuture;
  List<ShopItem> _catalog = const [];
  final _requested = <String>{};
  final _searchController = TextEditingController();
  final _inviteController = TextEditingController();
  bool _joiningWithInvite = false;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    final api = context.read<AppState>().api;
    _teamsFuture = api.listTeams();
    if (!widget.browseOnly) {
      _invitesFuture = _loadInvites();
    }
    api.getShopCatalog().then((catalog) {
      if (!mounted) return;
      setState(() => _catalog = catalog);
    }).ignore();
  }

  /// O FutureBuilder é o único ouvinte da lista, então uma falha do pedido
  /// precisa de um tratador para não ficar sem dono.
  Future<List<TeamInvitation>> _loadInvites() {
    final future = context.read<AppState>().api.getMyInvites();
    future.then<void>((_) {}, onError: (Object _) {});
    return future;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _inviteController.dispose();
    super.dispose();
  }

  Future<void> _createTeam() async {
    final nameCtrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Criar equipe'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(labelText: 'Nome da equipe'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(nameCtrl.text.trim()),
            child: const Text('Criar'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    try {
      await context.read<AppState>().api.createTeam(name);
      widget.onChanged();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _joinWithInvite() async {
    final raw = _inviteController.text.trim();
    if (raw.isEmpty || _joiningWithInvite) return;
    // Aceita o link copiado (/teams/join/<token>) ou só o token.
    final token = raw.split('/').last;
    if (token.isEmpty) return;
    setState(() => _joiningWithInvite = true);
    try {
      await context.read<AppState>().api.joinTeamByToken(token);
      if (!mounted) return;
      widget.onChanged();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _joiningWithInvite = false);
    }
  }

  Future<void> _join(TeamSummary team) async {
    if (widget.browseOnly) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saia da sua equipe atual para participar de outra.'),
        ),
      );
      return;
    }
    try {
      await context.read<AppState>().api.joinTeam(team.id);
      if (mounted) setState(() => _requested.add(team.id));
    } on ApiException catch (e) {
      if (!mounted) return;
      // Pedido duplicado: já está aguardando aprovação.
      if (e.statusCode == 409) {
        setState(() => _requested.add(team.id));
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _answerInvite(TeamInvitation invite, bool accept) async {
    final api = context.read<AppState>().api;
    try {
      if (accept) {
        await api.acceptInvite(invite.id);
        if (!mounted) return;
        // Aceitou: o painel passa a mostrar a equipe.
        widget.onChanged();
        return;
      }
      await api.declineInvite(invite.id);
      if (!mounted) return;
      setState(() {
        _invitesFuture = _loadInvites();
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Convites recebidos: quem decide é o convidado, então a resposta vive aqui
  /// e não na tela de quem chamou.
  Widget _invitesSection() {
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<List<TeamInvitation>>(
      future: _invitesFuture,
      builder: (context, snapshot) {
        final invites = snapshot.data ?? const <TeamInvitation>[];
        if (snapshot.hasError || invites.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'CONVITES PARA VOCÊ',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 17,
                letterSpacing: .6,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            for (final invite in invites)
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        invite.invitedByUsername == null
                            ? 'Você foi convidado para ${invite.teamName}.'
                            : '@${invite.invitedByUsername} convidou você '
                                  'para ${invite.teamName}.',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          FilledButton(
                            onPressed: () => _answerInvite(invite, true),
                            child: const Text('Aceitar'),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton(
                            onPressed: () => _answerInvite(invite, false),
                            child: const Text('Recusar'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CenteredContent(
      maxWidth: 1500,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(32, 18, 32, 28),
        children: [
          if (widget.error != null)
            _infoCard('Não foi possível carregar sua equipe. ${widget.error}'),
          if (widget.browseOnly)
            _infoCard(
              'Você já está em uma equipe. Para participar de outra, '
              'saia da atual primeiro.',
            ),
          if (!widget.browseOnly) ...[
            _invitesSection(),
            const SizedBox(height: 20),
          ],
          if (!widget.browseOnly) _createBanner(),
          const SizedBox(height: 24),
          TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Buscar equipe pelo nome',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: scheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: scheme.outlineVariant),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: scheme.outlineVariant),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            children: [
              _filterChip('all', 'Todas'),
              _filterChip('new', 'Novas'),
            ],
          ),
          if (!widget.browseOnly) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _inviteController,
              enabled: !_joiningWithInvite,
              onSubmitted: (_) => _joinWithInvite(),
              decoration: InputDecoration(
                hintText: 'Tem um convite? Cole o link ou o código',
                prefixIcon: const Icon(Icons.link_outlined),
                suffixIcon: _joiningWithInvite
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        tooltip: 'Entrar com convite',
                        icon: const Icon(Icons.login_outlined),
                        onPressed: _joinWithInvite,
                      ),
                filled: true,
                fillColor: scheme.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: scheme.outlineVariant),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: scheme.outlineVariant),
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Text(
            'EQUIPES DISPONÍVEIS',
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 17,
              letterSpacing: .6,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          FutureBuilder<List<TeamSummary>>(
            future: _teamsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                );
              }
              if (snapshot.hasError) {
                return Column(
                  children: [
                    _infoCard(
                      'Não foi possível carregar as equipes disponíveis.',
                    ),
                    TextButton.icon(
                      onPressed: () => setState(
                        () => _teamsFuture = context
                            .read<AppState>()
                            .api
                            .listTeams(),
                      ),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Tentar de novo'),
                    ),
                  ],
                );
              }
              final query = _searchController.text.trim().toLowerCase();
              var teams = snapshot.data ?? const <TeamSummary>[];
              if (query.isNotEmpty) {
                teams = teams
                    .where((team) => team.name.toLowerCase().contains(query))
                    .toList();
              }
              if (_filter == 'new') {
                teams = teams.where(isNewTeam).toList();
              }
              if (teams.isEmpty) {
                final message = query.isNotEmpty
                    ? 'Nenhuma equipe corresponde à busca.'
                    : _filter == 'new'
                    ? 'Nenhuma equipe nova nesta semana.'
                    : 'Nenhuma equipe criada ainda.';
                return _infoCard(message);
              }
              return Column(
                children: teams
                    .map(
                      (t) => _TeamCard(
                        team: t,
                        pending: _requested.contains(t.id),
                        frame: findItem(_catalog, t.equippedFrame),
                        nameStyle: findItem(_catalog, t.equippedNameStyle),
                        onJoin: () => _join(t),
                      ),
                    )
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 24),
          const AppFooter(),
        ],
      ),
    );
  }

  Widget _createBanner() {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const purple = Color(0xFF8B7CFF);
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2240) : const Color(0xFFE9E6FF),
        border: Border.all(color: purple, width: 1.5),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? const Color(0xFF0A0B10)
                : Colors.black.withValues(alpha: 0.08),
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final icon = Container(
            width: 78,
            height: 78,
            decoration: BoxDecoration(
              color: purple.withValues(alpha: .15),
              border: Border.all(color: purple),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              Icons.groups_outlined,
              color: isDark ? const Color(0xFFC9C2FF) : purple,
              size: 38,
            ),
          );
          final copy = Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Corra em grupo, domine mais',
                  style: TextStyle(
                    color: isDark ? Colors.white : scheme.onSurface,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Você ainda não tem equipe. Crie a sua ou entre em uma para conquistar territórios juntos.',
                  style: TextStyle(
                    color: isDark
                        ? const Color(0xFFD9D4FF)
                        : scheme.onSurfaceVariant,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          );
        final button = FilledButton.icon(
          onPressed: _createTeam,
          icon: const Icon(Icons.add),
          label: const Text('Criar equipe'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFFF7F4D),
            foregroundColor: const Color(0xFF28140B),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          ),
        );
        return constraints.maxWidth < 650
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [icon, const SizedBox(width: 16), copy]),
                  const SizedBox(height: 16),
                  button,
                ],
              )
            : Row(
                children: [
                  icon,
                  const SizedBox(width: 24),
                  copy,
                  const SizedBox(width: 20),
                  button,
                ],
              );
      },
    ),
    );
  }

  Widget _filterChip(String value, String label) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _filter == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _filter = value),
      selectedColor: scheme.primary.withValues(alpha: 0.16),
      backgroundColor: scheme.surface,
      labelStyle: TextStyle(
        color: selected ? scheme.primary : scheme.onSurfaceVariant,
      ),
      side: BorderSide(
        color: selected ? scheme.primary : Colors.transparent,
      ),
      shape: const StadiumBorder(),
    );
  }

  Widget _infoCard(String message) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(message, style: TextStyle(color: scheme.onSurfaceVariant)),
    );
  }
}
