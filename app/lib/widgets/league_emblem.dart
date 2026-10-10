import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';

/// Cor oficial da liga a partir do hex que o servidor devolve (`#RRGGBB`).
/// Um único parser para toda a escada: tela de Ligas, card do perfil e o
/// emblema dos outros jogadores.
Color leagueColor(String hex) {
  final value = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
  if (value == null) return const Color(0xFF8A94A6);
  return Color(0xFF000000 | value);
}

/// A liga de outra pessoa, em linha: emblema pequeno + rótulo ("TURBO 2").
/// É o que o ranking e o perfil público mostram — o RR continua privado.
class LeagueBadgeChip extends StatelessWidget {
  const LeagueBadgeChip({
    super.key,
    required this.badge,
    this.emblemSize = 26,
    this.fontSize = 12,
  });

  final LeagueBadge badge;
  final double emblemSize;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final color = leagueColor(badge.color);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        LeagueEmblem(color: color, shape: badge.shape, size: emblemSize),
        const SizedBox(width: 6),
        // Flexible: dentro de um Wrap apertado o rótulo encurta em vez de
        // estourar a linha.
        Flexible(
          child: Text(
            badge.label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

/// Emblema de liga: hexágono na cor oficial com a forma interna da liga
/// (`circle`, `triangle`, `diamond`, `pentagon`, `hexagon`, `octagon`,
/// `gem`, `star`). Usado no card do perfil e na escada da tela de Ligas.
class LeagueEmblem extends StatelessWidget {
  const LeagueEmblem({
    super.key,
    required this.color,
    required this.shape,
    this.size = 56,
    this.dimmed = false,
    this.highlight = false,
  });

  final Color color;
  final String shape;
  final double size;
  final bool dimmed;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _LeagueEmblemPainter(
        color: color,
        shape: shape,
        dimmed: dimmed,
        highlight: highlight,
      ),
    );
  }
}

class _LeagueEmblemPainter extends CustomPainter {
  _LeagueEmblemPainter({
    required this.color,
    required this.shape,
    required this.dimmed,
    required this.highlight,
  });

  final Color color;
  final String shape;
  final bool dimmed;
  final bool highlight;

  Color get _paintColor =>
      color.withValues(alpha: dimmed ? 0.35 : (highlight ? 1.0 : 0.8));

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.width / 2;
    final base = _paintColor;

    if (highlight) {
      // Halo suave + anel branco: marca a divisão atual na escada.
      canvas.drawPath(
        _hexagon(center, r * 0.98),
        Paint()
          ..color = color.withValues(alpha: 0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.28,
      );
      canvas.drawPath(
        _hexagon(center, r * 0.98),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.92)
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.09,
      );
    }

    canvas.drawPath(
      _hexagon(center, r * 0.82),
      Paint()
        ..color = base
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.13
        ..strokeJoin = StrokeJoin.round,
    );
    _drawShape(canvas, center, r * 0.45, base);
  }

  Path _hexagon(Offset c, double radius) {
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final angle = math.pi / 180 * (60 * i - 90);
      final point = Offset(
        c.dx + radius * math.cos(angle),
        c.dy + radius * math.sin(angle),
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

  Path _ngon(Offset c, double radius, int sides, {double startDeg = -90}) {
    final path = Path();
    for (var i = 0; i < sides; i++) {
      final angle = math.pi / 180 * (360 / sides * i + startDeg);
      final point = Offset(
        c.dx + radius * math.cos(angle),
        c.dy + radius * math.sin(angle),
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

  Path _star(Offset c, double radius) {
    final path = Path();
    final inner = radius * 0.32;
    for (var i = 0; i < 8; i++) {
      final angle = math.pi / 180 * (45 * i - 90);
      final r = i.isEven ? radius : inner;
      final point = Offset(
        c.dx + r * math.cos(angle),
        c.dy + r * math.sin(angle),
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

  void _drawShape(Canvas canvas, Offset c, double r, Color paintColor) {
    final fill = Paint()..color = paintColor;
    final stroke = Paint()
      ..color = paintColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.34
      ..strokeJoin = StrokeJoin.round;
    switch (shape) {
      case 'triangle':
        // Triângulo para baixo, como no mockup das ligas.
        final path = Path()
          ..moveTo(c.dx, c.dy + r)
          ..lineTo(c.dx - r * 0.95, c.dy - r * 0.6)
          ..lineTo(c.dx + r * 0.95, c.dy - r * 0.6)
          ..close();
        canvas.drawPath(path, fill);
      case 'diamond':
        canvas.drawPath(_ngon(c, r, 4), fill);
      case 'pentagon':
        canvas.drawPath(_ngon(c, r, 5), fill);
      case 'hexagon':
        canvas.drawPath(_hexagon(c, r), stroke);
      case 'octagon':
        canvas.drawPath(_ngon(c, r, 8, startDeg: -67.5), fill);
      case 'gem':
        canvas.drawPath(_ngon(c, r, 4), stroke);
      case 'star':
        canvas.drawPath(_star(c, r), fill);
      default: // circle
        canvas.drawCircle(c, r * 0.85, fill);
    }
  }

  @override
  bool shouldRepaint(_LeagueEmblemPainter old) =>
      old.color != color ||
      old.shape != shape ||
      old.dimmed != dimmed ||
      old.highlight != highlight;
}
