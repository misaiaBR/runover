import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';

/// Peça comum do mural, da vitrine de nível e da tela de insígnias: o
/// servidor manda uma chave de ícone, só o app sabe desenhá-la.
IconData badgeIcon(String key) {
  return switch (key) {
    'run' => Icons.directions_run,
    'flag' => Icons.flag_outlined,
    'route' => Icons.route_outlined,
    'sum' => Icons.trending_up,
    'team' => Icons.groups_outlined,
    'level' => Icons.workspace_premium_outlined,
    'season' => Icons.auto_awesome,
    _ => Icons.verified_outlined,
  };
}

/// Como cada categoria da resposta aparece: rótulo, ícone e cor.
///
/// O servidor manda só a chave (`category`), como manda o `icon` — a escada de
/// categorias é do app. Uma chave desconhecida cai em `outros` em vez de
/// mostrar o texto cru.
({Color color, IconData icon, String label}) badgeCategoryStyle(String key) {
  return switch (key) {
    'corridas' => (
      color: const Color(0xFF8A94A6),
      icon: Icons.directions_run,
      label: 'Corridas',
    ),
    'territorios' => (
      color: const Color(0xFFE5484D),
      icon: Icons.flag_outlined,
      label: 'Territórios',
    ),
    'distancia' => (
      color: const Color(0xFF34D399),
      icon: Icons.route_outlined,
      label: 'Distância',
    ),
    'acumulados' => (
      color: const Color(0xFF22D3EE),
      icon: Icons.trending_up,
      label: 'Acumulados',
    ),
    'equipe' => (
      color: const Color(0xFFA78BFA),
      icon: Icons.groups_outlined,
      label: 'Equipe',
    ),
    'temporada' => (
      color: const Color(0xFFFFB020),
      icon: Icons.auto_awesome,
      label: 'Temporada',
    ),
    _ => (
      color: const Color(0xFF8A94A6),
      icon: Icons.verified_outlined,
      label: 'Outras',
    ),
  };
}

/// 0..1 do caminho até o limiar, para as barras e para ordenar "mais próximas".
double badgeRatio(Insignia badge) {
  if (badge.earned) return 1;
  if (badge.threshold <= 0) return 0;
  return (badge.progress / badge.threshold).clamp(0.0, 1.0);
}

/// Emblema de insígnia: hexágono na cor da categoria com o ícone da regra no
/// miolo. Ganha é cheia; bloqueada aparece apenas contornada e apagada.
class BadgeEmblem extends StatelessWidget {
  const BadgeEmblem({
    super.key,
    required this.icon,
    required this.color,
    this.size = 56,
    this.earned = false,
  });

  final IconData icon;
  final Color color;
  final double size;
  final bool earned;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.square(size),
            painter: _HexagonPainter(color: color, filled: earned),
          ),
          Icon(
            icon,
            size: size * .38,
            color: earned ? RunoverColors.ink : color.withValues(alpha: .75),
          ),
        ],
      ),
    );
  }
}

class _HexagonPainter extends CustomPainter {
  _HexagonPainter({required this.color, required this.filled});

  final Color color;
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    final hexagon = _hexagon(size.center(Offset.zero), size.width / 2 * .92);
    canvas.drawPath(
      hexagon,
      Paint()..color = color.withValues(alpha: filled ? .92 : .10),
    );
    canvas.drawPath(
      hexagon,
      Paint()
        ..color = color.withValues(alpha: filled ? 1 : .38)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * .05
        ..strokeJoin = StrokeJoin.round,
    );
  }

  Path _hexagon(Offset center, double radius) {
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final angle = math.pi / 180 * (60 * i - 90);
      final point = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(_HexagonPainter old) =>
      old.color != color || old.filled != filled;
}

/// O hexágono neutro do "+N" do mural: só o contorno, sem cor de categoria.
class _DimHexagonPainter extends CustomPainter {
  const _DimHexagonPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 * .92;
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final angle = math.pi / 180 * (60 * i - 90);
      final point = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF8A94A6).withValues(alpha: .3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * .05
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Os meses em pt-BR abreviados, usados pelas duas datas da insígnia.
const _badgeMonths = [
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

/// "6 de jun. de 2026" a partir da data em que o servidor registrou o ganho.
String badgeDateLabel(DateTime date) {
  // O servidor grava em UTC: sem converter, quem corre em UTC−3 vê a insígnia
  // ganha na véspera como se fosse do dia seguinte.
  final local = date.toLocal();
  return '${local.day} de ${_badgeMonths[local.month - 1]} de ${local.year}';
}

/// "3 de 10" / "5,2 de 10 km" — o progresso da regra ainda não cumprida.
String badgeProgressLabel(Insignia badge) {
  final current = badge.progress > badge.threshold
      ? badge.threshold
      : badge.progress;
  return '${_trim(current)} de ${_trim(badge.threshold)}';
}

String _trim(double value) {
  return value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1).replaceAll('.', ',');
}

/// "10 out. 2026" — a data curta do mural, onde o card é estreito.
String badgeWallDateLabel(DateTime date) {
  final local = date.toLocal();
  return '${local.day} ${_badgeMonths[local.month - 1]} ${local.year}';
}

/// Card de insígnia: emblema, nome e o estado por baixo — a data no mural, o
/// "Ganha" na tela, e o progresso ("0 de 5") enquanto está bloqueada.
class BadgeTile extends StatelessWidget {
  const BadgeTile({
    super.key,
    required this.badge,
    this.showBar = true,
    this.emblemSize = 46,
    this.earnedLabel,
    this.onTap,
  });

  final Insignia badge;

  /// A barra fina entre o nome e o estado; o mural dispensa, a tela mostra.
  final bool showBar;
  final double emblemSize;

  /// Como nomear o estado de quem já ganhou. Sem nada dito, é só "Ganha".
  final String Function(Insignia badge)? earnedLabel;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = badgeCategoryStyle(badge.category);
    final earned = badge.earned;
    final caption = earned
        ? (earnedLabel?.call(badge) ?? 'Ganha')
        : badgeProgressLabel(badge);
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: BadgeEmblem(
              icon: badgeIcon(badge.icon),
              color: style.color,
              size: emblemSize,
              earned: earned,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            badge.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          if (showBar) ...[
            BadgeProgressBar(
              ratio: badgeRatio(badge),
              color: earned ? style.color : scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 6),
          ],
          Text(
            caption,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: earned ? FontWeight.w700 : FontWeight.w500,
              color: earned ? style.color : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
    return Card(
      margin: EdgeInsets.zero,
      child: onTap == null
          ? content
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: content,
            ),
    );
  }
}

/// Celula "+N" do mural: o hexágono apagado que avisa haver mais por trás.
class BadgeMoreTile extends StatelessWidget {
  const BadgeMoreTile({super.key, required this.count, this.onTap});

  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: SizedBox(
                  width: 46,
                  height: 46,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      const CustomPaint(
                        size: Size.square(46),
                        painter: _DimHexagonPainter(),
                      ),
                      Text(
                        '+$count',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
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

/// Grade de cards de insígnia: duas colunas no celular, até quatro no card
/// largo. É a mesma grade da tela de Insígnias e do mural do perfil.
class BadgeGrid extends StatelessWidget {
  const BadgeGrid({
    super.key,
    required this.badges,
    this.showBar = true,
    this.emblemSize = 46,
    this.earnedLabel,
    this.onTap,
    this.extraCells = const [],
  });

  final List<Insignia> badges;
  final bool showBar;
  final double emblemSize;
  final String Function(Insignia badge)? earnedLabel;
  final ValueChanged<Insignia>? onTap;

  /// Celulas extras depois das insígnias — o "+N" do mural.
  final List<Widget> extraCells;

  static const double _spacing = 12;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cells = <Widget>[
          for (final badge in badges)
            BadgeTile(
              badge: badge,
              showBar: showBar,
              emblemSize: emblemSize,
              earnedLabel: earnedLabel,
              onTap: onTap == null ? null : () => onTap!(badge),
            ),
          ...extraCells,
        ];
        final int columns = math.max(
          2,
          math.min(4, math.min((constraints.maxWidth / 150).floor(), cells.length)),
        );
        final width =
            (constraints.maxWidth - _spacing * (columns - 1)) / columns;
        final rows = <Widget>[];
        for (var start = 0; start < cells.length; start += columns) {
          final slice = cells.sublist(
            start,
            math.min(start + columns, cells.length),
          );
          final row = <Widget>[];
          for (var column = 0; column < columns; column++) {
            if (column > 0) row.add(const SizedBox(width: _spacing));
            row.add(
              column < slice.length
                  ? SizedBox(width: width, child: slice[column])
                  : SizedBox(width: width),
            );
          }
          rows.add(
            Padding(
              padding: EdgeInsets.only(top: start == 0 ? 0 : _spacing),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: row,
                ),
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rows,
        );
      },
    );
  }
}

/// Barra fina de progresso usada pelos cards e pelo resumo da tela.
class BadgeProgressBar extends StatelessWidget {
  const BadgeProgressBar({
    super.key,
    required this.ratio,
    required this.color,
    this.height = 5,
  });

  final double ratio;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: Stack(
        children: [
          Container(
            height: height,
            color: scheme.onSurfaceVariant.withValues(alpha: .22),
          ),
          FractionallySizedBox(
            widthFactor: ratio.clamp(0.0, 1.0),
            child: Container(height: height, color: color),
          ),
        ],
      ),
    );
  }
}
