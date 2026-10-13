/// O acabamento do rosto: luz, profundidade, textura e matiz.
///
/// Cada avatar da galeria declara quatro palavras no payload
/// (`_avatar_finish` em `backend/app/services/shop.py`): `light`, `depth`,
/// `texture` e `tint`. É elas que separam "mais um boneco da API de avatares"
/// de um cosmético desenhado — a luz de recorte, o relevo afundado ou chanfrado,
/// a trama fosca por cima da figura e o matiz que aquece ou esfria o conjunto.
///
/// O desenho fica sobre o rosto, recortado no formato em que o rosto aparece:
/// círculo no avatar do perfil, canto arredondado na folha de escolha. A semente
/// é o id do item (`effectSeedOf`), então a vitrine, a folha, o perfil de quem
/// equipou e o cartão de ranking mostram exatamente a mesma textura — dois
/// desenhos do mesmo item seria a mesma reclamação de "rosto trocado" que o
/// `seed` do avatar resolveu.
///
/// Nada aqui anima: quem dá vida ao item é a moldura (`frame_painters.dart`) e a
/// camada de efeito (`effect_painters.dart`).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import 'cosmetics.dart';
import 'effect_painters.dart';

/// As luzes do catálogo (`AVATAR_LIGHTS`).
enum AvatarLight {
  /// Filete claro na beira do rosto, com um ponto mais forte — luz de recorte.
  rim,

  /// Halo largo que sobe por trás da figura: a borda acende, o centro fica.
  back,

  /// Luz vinda de cima, que se apaga antes de chegar ao queixo.
  top,

  /// Luz vinda de um lado; o lado é da semente do item, não uma aposta da tela.
  side,

  /// Sem luz: o rosto cru.
  none;

  static AvatarLight? parse(Object? value) => _avatarWord(values, value);
}

/// Os relevos do catálogo (`AVATAR_DEPTHS`).
enum AvatarDepth {
  /// Bordas internas escurecidas — a figura afunda na moldura.
  inner,

  /// Claro em cima, escuro embaixo: a face chanfrada.
  bevel,

  /// Sem relevo.
  flat;

  static AvatarDepth? parse(Object? value) => _avatarWord(values, value);
}

/// As tramas do catálogo (`AVATAR_TEXTURES`).
enum AvatarTexture {
  /// Ruído fino, alternando claro e escuro — o grão do filme.
  grain,

  /// Duas passadas cruzadas a 45°, o tecido de carbono.
  carbon,

  /// Riscos horizontais paralelos — o metal escovado.
  brushed,

  /// Colmeia de hexágono, o mesmo sólido da base de equipe em escala de pele.
  hex,

  /// Trama ortogonal de lona.
  canvas,

  /// Rede regular de pontos.
  dots,

  /// Sem trama.
  none;

  static AvatarTexture? parse(Object? value) => _avatarWord(values, value);
}

T? _avatarWord<T extends Enum>(List<T> options, Object? value) {
  if (value is! String) return null;
  for (final option in options) {
    if (option.name == value) return option;
  }
  return null;
}

/// Os quatro eixos lidos do payload de um avatar.
class AvatarFinish {
  const AvatarFinish({
    required this.light,
    required this.depth,
    required this.texture,
    this.tint,
  });

  final AvatarLight light;
  final AvatarDepth depth;
  final AvatarTexture texture;

  /// O `tint` do item como cor; null quando ele não declara matiz (ou declara
  /// um hex que o app não consegue ler).
  final Color? tint;

  /// O acabamento declarado pelo item.
  ///
  /// Null quando nenhuma das quatro palavras está lá — é o caso dos avatares
  /// anteriores à galeria, dos emblemas de equipe e do avatar do passe. Esses
  /// continuam com o rosto cru: acabamento inventado seria o app desenhando uma
  /// coisa que o servidor não vendeu.
  static AvatarFinish? of(ShopItem? item) {
    if (item == null) return null;
    final payload = item.payload;
    final light = AvatarLight.parse(payload['light']);
    final depth = AvatarDepth.parse(payload['depth']);
    final texture = AvatarTexture.parse(payload['texture']);
    final tint = cosmeticHexColor(payload['tint']);
    if (light == null && depth == null && texture == null && tint == null) {
      return null;
    }
    return AvatarFinish(
      light: light ?? AvatarLight.none,
      depth: depth ?? AvatarDepth.flat,
      texture: texture ?? AvatarTexture.none,
      tint: tint,
    );
  }

  /// Um item pode declarar só palavras neutras (`light: none`, `depth: flat`,
  /// `texture: none`, sem matiz). Aí não há nada a pintar e a camada nem deve
  /// ser montada sobre o rosto.
  bool get paints =>
      light != AvatarLight.none ||
      depth != AvatarDepth.flat ||
      texture != AvatarTexture.none ||
      tint != null;

  @override
  bool operator ==(Object other) =>
      other is AvatarFinish &&
      other.light == light &&
      other.depth == depth &&
      other.texture == texture &&
      other.tint == tint;

  @override
  int get hashCode => Object.hash(light, depth, texture, tint);

  @override
  String toString() => 'AvatarFinish($light, $depth, $texture, tint: $tint)';
}

/// A camada que põe o acabamento do item sobre o rosto dele.
///
/// Toda superfície que mostra a figura de um avatar passa por aqui — é um só
/// lugar de propósito: o mesmo item tem de ter o mesmo acabamento na vitrine, na
/// folha de escolha, no perfil e no ranking.
class AvatarFinishLayer extends StatelessWidget {
  const AvatarFinishLayer({
    super.key,
    required this.item,
    required this.child,
    this.cornerRadius,
  });

  final ShopItem? item;

  /// O rosto, desenhado por quem chama (o `CircleAvatar` do perfil, o
  /// `ClipRRect` da folha).
  final Widget child;

  /// Recorte em canto arredondado em vez de círculo. O perfil não passa nada
  /// (é círculo); a folha de escolha passa o raio do próprio card.
  final double? cornerRadius;

  @override
  Widget build(BuildContext context) {
    final painter = AvatarFinishPainter.forItem(
      item,
      cornerRadius: cornerRadius,
    );
    if (painter == null) return child;
    return CustomPaint(foregroundPainter: painter, child: child);
  }
}

/// Pinta luz, profundidade, textura e matiz sobre o rosto.
class AvatarFinishPainter extends CustomPainter {
  const AvatarFinishPainter({
    required this.finish,
    required this.seed,
    this.cornerRadius,
  });

  /// A partir do item: o acabamento do payload e a semente do id. Devolve null
  /// quando o item não tem acabamento, para quem desenha não montar camada à
  /// toa.
  static AvatarFinishPainter? forItem(ShopItem? item, {double? cornerRadius}) {
    final finish = AvatarFinish.of(item);
    if (item == null || finish == null || !finish.paints) return null;
    return AvatarFinishPainter(
      finish: finish,
      seed: effectSeedOf(item.id),
      cornerRadius: cornerRadius,
    );
  }

  final AvatarFinish finish;
  final int seed;
  final double? cornerRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final box = Offset.zero & size;
    final side = math.min(size.width, size.height);
    if (side <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = side / 2;
    // 44 px é o avatar grande do perfil. Em cédula menor o traço e a opacidade
    // caem junto — uma textura em escala cheia viria lama em 24 px e cobriria o
    // rosto que a pessoa comprou.
    final strength = (radius / 44).clamp(0.35, 1.0).toDouble();
    final outline = _outline(box, center, radius - 0.5);
    canvas.clipPath(outline);
    _paintTint(canvas, box, strength);
    _paintTexture(canvas, box, center, radius, strength);
    _paintDepth(canvas, box, outline, strength);
    _paintLight(canvas, box, outline, strength);
  }

  /// O recorte do rosto: círculo no avatar do perfil, canto arredondado na
  /// folha de escolha. Tudo que vem depois é clipado por ele, então nenhum
  /// filete sai da caixa que a tela reservou para a figura.
  Path _outline(Rect box, Offset center, double radius) {
    final corner = cornerRadius;
    if (corner == null) {
      return Path()..addOval(Rect.fromCircle(center: center, radius: radius));
    }
    return Path()..addRRect(
      RRect.fromRectAndRadius(box, Radius.circular(corner)),
    );
  }

  /// O matiz do item: um véu fino por cima da figura. Baixo de propósito — é o
  /// que faz dois avatares do mesmo estilo parecerem itens diferentes, não o que
  /// tapa o rosto.
  void _paintTint(Canvas canvas, Rect box, double strength) {
    final tint = finish.tint;
    if (tint == null) return;
    canvas.drawRect(
      box,
      Paint()..color = tint.withValues(alpha: 0.05 + 0.13 * strength),
    );
  }

  /// A luz do item, por cima de tudo: é o que faz o rosto parecer iluminado por
  /// um estúdio e não por um fundo chapado.
  void _paintLight(Canvas canvas, Rect box, Path outline, double strength) {
    final bright = 0.10 + 0.26 * strength;
    final dim = 0.10 + 0.08 * strength;
    switch (finish.light) {
      case AvatarLight.none:
        return;
      case AvatarLight.rim:
        // Um giro completo com um pico angular: o filete existe em toda a beira,
        // mas só acende de verdade de um lado — o lado é da semente.
        final peak = math.Random(seed).nextDouble() * math.pi * 2;
        final sweep = SweepGradient(
          startAngle: peak - math.pi,
          endAngle: peak + math.pi,
          colors: [
            Colors.white.withValues(alpha: dim),
            Colors.white.withValues(alpha: dim),
            Colors.white.withValues(alpha: bright + 0.22),
            Colors.white.withValues(alpha: dim),
            Colors.white.withValues(alpha: dim),
          ],
          stops: const [0.0, 0.34, 0.5, 0.66, 1.0],
        );
        canvas.drawPath(
          outline,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0 + 1.4 * strength
            ..shader = sweep.createShader(box),
        );
      case AvatarLight.back:
        // Halo: o centro fica como está e a borda ganha a luz, na cor do matiz
        // quando o item tem um.
        final glow = finish.tint ?? Colors.white;
        canvas.drawRect(
          box,
          Paint()
            ..shader = RadialGradient(
              center: const Alignment(0, 0.12),
              radius: 0.56,
              colors: [
                glow.withValues(alpha: 0),
                glow.withValues(alpha: bright * 0.7),
              ],
            ).createShader(box),
        );
      case AvatarLight.top:
        canvas.drawRect(
          box,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: bright),
                Colors.white.withValues(alpha: 0),
              ],
              stops: const [0.0, 0.62],
            ).createShader(box),
        );
      case AvatarLight.side:
        final fromLeft = math.Random(seed).nextBool();
        final alignment = fromLeft ? -0.85 : 0.85;
        canvas.drawRect(
          box,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment(alignment, 0),
              end: Alignment(-alignment, 0),
              colors: [
                Colors.white.withValues(alpha: bright),
                Colors.white.withValues(alpha: 0),
              ],
              stops: const [0.0, 0.7],
            ).createShader(box),
        );
    }
  }

  /// O relevo do item: afundado (inner), chanfrado (bevel) ou chapado (flat).
  void _paintDepth(Canvas canvas, Rect box, Path outline, double strength) {
    switch (finish.depth) {
      case AvatarDepth.flat:
        return;
      case AvatarDepth.inner:
        // Sombra interna: o miolo intacto, a borda afundando.
        canvas.drawRect(
          box,
          Paint()
            ..shader = RadialGradient(
              radius: 0.56,
              colors: [
                Colors.black.withValues(alpha: 0),
                Colors.black.withValues(alpha: 0.06 + 0.24 * strength),
              ],
              stops: const [0.42, 1.0],
            ).createShader(box),
        );
      case AvatarDepth.bevel:
        // O chanfro: a mesma borda recebe luz em cima e sombra embaixo, o que é
        // o que faz o aro ter espessura em vez de ser um traço pintado.
        canvas.drawPath(
          outline,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2 + 1.6 * strength
            ..shader = const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0x99FFFFFF), Color(0x73000000)],
            ).createShader(box),
        );
    }
  }

  /// A trama do item. Cada palavra de `AVATAR_TEXTURES` tem um desenho próprio,
  /// sempre na opacidade de um acabamento — a figura por cima continua sendo o
  /// rosto, não a textura.
  void _paintTexture(
    Canvas canvas,
    Rect box,
    Offset center,
    double radius,
    double strength,
  ) {
    switch (finish.texture) {
      case AvatarTexture.none:
        return;
      case AvatarTexture.grain:
        _grain(canvas, box, strength);
      case AvatarTexture.dots:
        _dots(canvas, box, radius, strength);
      case AvatarTexture.brushed:
        _brushed(canvas, box, radius, strength);
      case AvatarTexture.canvas:
        _weave(canvas, box, radius, strength);
      case AvatarTexture.carbon:
        _carbon(canvas, box, radius, strength);
      case AvatarTexture.hex:
        _hive(canvas, center, radius, strength);
    }
  }

  void _grain(Canvas canvas, Rect box, double strength) {
    final rng = math.Random(seed);
    // A contagem acompanha a área: 24 px não leva o mesmo grão de 88 px.
    final count = ((box.width * box.height) / 34).clamp(24.0, 240.0).toInt();
    final paint = Paint();
    for (var i = 0; i < count; i++) {
      final x = box.left + rng.nextDouble() * box.width;
      final y = box.top + rng.nextDouble() * box.height;
      final r = 0.3 + rng.nextDouble() * 0.6;
      final alpha = (0.02 + rng.nextDouble() * 0.05) * (0.4 + strength);
      paint.color = rng.nextBool()
          ? Colors.white.withValues(alpha: alpha)
          : Colors.black.withValues(alpha: alpha);
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  void _dots(Canvas canvas, Rect box, double radius, double strength) {
    final step = (radius / 3.4).clamp(4.0, 14.0).toDouble();
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04 + 0.07 * strength);
    final ink = Paint()
      ..color = Colors.black.withValues(alpha: 0.02 + 0.05 * strength);
    for (var y = box.top + step; y < box.bottom; y += step) {
      for (var x = box.left + step; x < box.right; x += step) {
        final c = Offset(x, y);
        // Ponto com sombra um pixel abaixo: a rede vira relevo, não poeira.
        canvas.drawCircle(c.translate(0.4, 0.5), 0.5 + 0.9 * strength, ink);
        canvas.drawCircle(c, 0.5 + 0.9 * strength, paint);
      }
    }
  }

  void _brushed(Canvas canvas, Rect box, double radius, double strength) {
    final step = (radius / 7).clamp(2.5, 8.0).toDouble();
    final rng = math.Random(seed);
    final paint = Paint()..strokeWidth = 1.0;
    for (var y = box.top; y < box.bottom; y += step) {
      final tone = rng.nextDouble();
      paint.color = tone > 0.5
          ? Colors.white.withValues(alpha: 0.03 + 0.05 * strength * tone)
          : Colors.black.withValues(alpha: 0.02 + 0.05 * strength * tone);
      canvas.drawLine(Offset(box.left, y), Offset(box.right, y), paint);
    }
  }

  void _weave(Canvas canvas, Rect box, double radius, double strength) {
    // Lona: urdume e trama ortogonais, um fio mais claro que o outro.
    final step = (radius / 4.2).clamp(4.0, 12.0).toDouble();
    final warp = Paint()
      ..strokeWidth = 1.0
      ..color = Colors.white.withValues(alpha: 0.03 + 0.05 * strength);
    final weft = Paint()
      ..strokeWidth = 1.0
      ..color = Colors.black.withValues(alpha: 0.02 + 0.045 * strength);
    for (var x = box.left; x < box.right; x += step) {
      canvas.drawLine(Offset(x, box.top), Offset(x, box.bottom), warp);
    }
    for (var y = box.top; y < box.bottom; y += step) {
      canvas.drawLine(Offset(box.left, y), Offset(box.right, y), weft);
    }
  }

  void _carbon(Canvas canvas, Rect box, double radius, double strength) {
    final step = (radius / 4.5).clamp(3.5, 11.0).toDouble();
    final light = Paint()
      ..strokeWidth = 0.9 + 0.7 * strength
      ..color = Colors.white.withValues(alpha: 0.03 + 0.05 * strength);
    final dark = Paint()
      ..strokeWidth = 0.9 + 0.7 * strength
      ..color = Colors.black.withValues(alpha: 0.03 + 0.06 * strength);
    // As duas passadas de 45° do tecido. Cada passada é desenhada em coordenadas
    // giradas e dentro do próprio save/restore: girar duas vezes sobre a mesma
    // matriz deixaria a segunda passada a 0°, e o carbono viria uma listra.
    final reach = box.width;
    for (final angle in [math.pi / 4, -math.pi / 4]) {
      canvas.save();
      canvas.translate(box.center.dx, box.center.dy);
      canvas.rotate(angle);
      for (var y = -reach; y <= reach; y += step) {
        canvas.drawLine(Offset(-reach, y), Offset(reach, y), light);
        canvas.drawLine(
          Offset(-reach, y + step / 2),
          Offset(reach, y + step / 2),
          dark,
        );
      }
      canvas.restore();
    }
  }

  void _hive(Canvas canvas, Offset center, double radius, double strength) {
    final size = (radius / 3.6).clamp(4.5, 15.0).toDouble();
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7 + 0.6 * strength
      ..color = Colors.black.withValues(alpha: 0.03 + 0.07 * strength);
    final light = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7 + 0.6 * strength
      ..color = Colors.white.withValues(alpha: 0.02 + 0.05 * strength);
    final dx = size * 1.5;
    final dy = size * math.sqrt(3);
    final reach = radius + size;
    var column = 0;
    for (var x = center.dx - reach; x <= center.dx + reach; x += dx, column++) {
      final offset = column.isOdd ? dy / 2 : 0.0;
      for (var y = center.dy - reach; y <= center.dy + reach; y += dy) {
        final hex = _hexagon(Offset(x, y + offset), size);
        canvas.drawPath(hex, paint);
        // O mesmo hexágono refeito meio pixel acima é o fio iluminado da colmeia.
        canvas.drawPath(
          Path()..addPath(hex, const Offset(0, -0.5)),
          light,
        );
      }
    }
  }

  Path _hexagon(Offset center, double size) {
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final angle = i * math.pi / 3;
      final point = Offset(
        center.dx + math.cos(angle) * size,
        center.dy + math.sin(angle) * size,
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    return path..close();
  }

  @override
  bool shouldRepaint(AvatarFinishPainter old) =>
      old.finish != finish ||
      old.seed != seed ||
      old.cornerRadius != cornerRadius;
}
