/// A placa de fundo do perfil é desenhada pelo estilo da faixa.
///
/// A faixa sempre foi o gradiente do catálogo atrás do nome. O payload também
/// diz `plate` — de que jeito a placa é construída: vidro fosco com borda
/// milimétrica, gradiente dinâmico na direção pedida, fibra de carbono, mapa do
/// território, metal escovado por patamar, LED neon na borda, feixe varrendo o
/// holográfico, camadas que deslocam contra o ponteiro e borda que respira
/// (`PLATE_STYLES` em `backend/app/services/shop.py`).
///
/// Sem `plate` reconhecido a placa continua o gradiente de sempre: o app não
/// desenha estrutura que a loja não vendeu — e uma faixa anterior ao vocabulário
/// não ganha mapa do nada.
///
/// A camada é decorativa (`Positioned.fill` sob o conteúdo, nunca um botão) e o
/// que se mexe vive em `progress`: nenhum estilo muda a altura que o perfil
/// reserva para a faixa. As tintas claras por cima do gradiente são a língua do
/// próprio catálogo — a faixa é escura e fixa nos dois temas, como em
/// [ProfileEffectOverlay.onDarkSurface].
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import 'cosmetics.dart';
import 'effect_painters.dart';
import 'runover_ui.dart';

const double _tau = 6.283185307179586;

/// Os nove estilos de placa (`PLATE_STYLES`).
enum PlateStyle {
  /// Vidro fosco: desfoque por dentro e filete brilhante na borda.
  glass,

  /// Gradiente dinâmico suave, na direção e no giro que o item pede.
  gradient,

  /// Fibra de carbono fosca, com a trama do `weave`.
  carbon,

  /// Silhueta de mapa vetorial da região dominada.
  territory,

  /// Metal escovado, do titânio à platina pelo `grade`.
  brushed,

  /// Placa escura com LED neon pulsante numa borda.
  splitNeon('split_neon'),

  /// Feixe de luz varrendo a placa: cartão holográfico.
  shimmer,

  /// O fundo desloca contra o ponteiro: profundidade real.
  parallax,

  /// Borda respirando devagar, sinal de perfil vivo.
  pulse;

  const PlateStyle([this.word = '']);

  /// A palavra do payload. Só difere do identificador onde o catálogo usa
  /// sublinhado (`split_neon`).
  final String word;

  static PlateStyle? parse(Object? value) {
    if (value is! String) return null;
    for (final option in PlateStyle.values) {
      if ((option.word.isEmpty ? option.name : option.word) == value) {
        return option;
      }
    }
    return null;
  }
}

/// Os patamares do metal escovado (`PLATE_GRADES`): a placa muda de material
/// conforme o item sobe de preço, então cada nome tem a sua liga.
enum PlateGrade {
  titanio(Color(0xFF39424E)),
  aco(Color(0xFF6B7280)),
  cobre(Color(0xFFB45309)),
  ouro(Color(0xFFFFC93C)),
  platina(Color(0xFFCBD5E1));

  const PlateGrade(this.metal);

  /// A cor do metal, que entra como luz da escovação.
  final Color metal;

  static PlateGrade? parse(Object? value) {
    if (value is! String) return null;
    for (final option in PlateGrade.values) {
      if (option.name == value) return option;
    }
    return null;
  }
}

/// A placa lida do payload de uma faixa: o estilo e os números que ele pede.
///
/// Os campos que não pertencem ao estilo ficam no padrão do estilo — um `blur`
/// ausente em `glass` ainda é vidro, só que no desfoque médio. É o mesmo critério
/// dos pintores de moldura: a palavra manda, o número refina.
class PlateSpec {
  const PlateSpec({
    required this.style,
    required this.item,
    required this.colors,
    required this.seed,
    required this.blur,
    required this.edge,
    required this.angle,
    required this.weave,
    required this.region,
    required this.grade,
    required this.edgeHue,
    required this.depth,
    this.period,
  });

  final PlateStyle style;
  final ShopItem item;

  /// As cores da faixa, na ordem do catálogo.
  final List<Color> colors;

  /// A semente do desenho: região e trama saem daqui, então a mesma placa
  /// pintada duas vezes (perfil e vitrine) é a mesma placa.
  final int seed;

  final int blur;
  final Color edge;
  final double angle;
  final int weave;
  final String region;
  final PlateGrade grade;
  final double edgeHue;
  final int depth;

  /// O ciclo do que se mexe, ou null quando a placa é parada.
  final Duration? period;

  Color get base => colors.first;

  /// A placa do item, ou null quando a faixa não declara um estilo conhecido.
  static PlateSpec? of(ShopItem? banner) {
    final style = PlateStyle.parse(banner?.payload['plate']);
    if (banner == null || style == null) return null;
    final payload = banner.payload;
    final colors = cosmeticColors(banner);
    final region = payload['region'] is String ? payload['region'] as String : '';
    return PlateSpec(
      style: style,
      item: banner,
      colors: colors,
      seed: effectSeedOf('${banner.id}$region'),
      blur: _whole(payload['blur'], 3, 1, 5),
      edge: cosmeticHexColor(payload['edge']) ??
          Color.lerp(colors.first, Colors.white, .62)!,
      angle: _part(payload['angle'], 45, 0, 180),
      weave: _whole(payload['weave'], 2, 1, 3),
      region: region,
      grade: PlateGrade.parse(payload['grade']) ?? PlateGrade.aco,
      edgeHue: _part(payload['edge_hue'], 165, 0, 360),
      depth: _whole(payload['depth'], 2, 1, 3),
      period: _periodOf(style, payload),
    );
  }

  /// O ritmo vem do catálogo (`sweep_ms`, `pulse_ms`, `period_ms`). Os dois
  /// estilos que não recebem milissegundos do servidor — o gradiente que gira e
  /// o paralaxe que espera o ponteiro — têm ciclo próprio e lento.
  static Duration? _periodOf(PlateStyle style, Map<String, dynamic> payload) {
    return switch (style) {
      PlateStyle.shimmer => _ms(payload['sweep_ms'], 2600),
      PlateStyle.splitNeon => _ms(payload['pulse_ms'], 1800),
      PlateStyle.pulse => _ms(payload['period_ms'], 2200),
      PlateStyle.gradient => const Duration(milliseconds: 7000),
      PlateStyle.parallax => const Duration(milliseconds: 14000),
      _ => null,
    };
  }

  static Duration? _ms(Object? value, int fallback) {
    if (value is! num) return Duration(milliseconds: fallback);
    return Duration(milliseconds: value.toInt().clamp(400, 20000));
  }
}

int _whole(Object? value, int fallback, int low, int high) {
  if (value is! num) return fallback;
  return value.toInt().clamp(low, high);
}

double _part(Object? value, double fallback, double low, double high) {
  if (value is! num) return fallback;
  return value.toDouble().clamp(low, high);
}

/// A placa de fundo de um perfil: o gradiente da faixa equipado com o desenho do
/// `plate` por baixo do conteúdo.
///
/// Quem usa passa o que a faixa segura (nome, avatar, métricas) em [child] e a
/// cor do cartão em [fallbackColor] para quando não há faixa nenhuma. Sem
/// [child] a placa ocupa o espaço que o pai der — é o caso da faixa do cartão de
/// identidade, que só existe como fundo.
class BannerPlate extends StatefulWidget {
  const BannerPlate({
    super.key,
    required this.banner,
    this.child,
    this.borderRadius = BorderRadius.zero,
    this.fallbackColor,
  });

  final ShopItem? banner;
  final Widget? child;
  final BorderRadius borderRadius;
  final Color? fallbackColor;

  @override
  State<BannerPlate> createState() => _BannerPlateState();
}

class _BannerPlateState extends State<BannerPlate>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// O ponteiro em fração da placa (-1..1 em cada eixo), para o paralaxe.
  Offset _pointer = Offset.zero;

  PlateSpec? get _spec => PlateSpec.of(widget.banner);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _spec?.period);
    _applyClock();
  }

  /// Só as placas que se mexem mantêm um relógio rodando: o perfil de uma
  /// pessoa com faixa de carbono não paga quadro por quadro por um desenho
  /// parado.
  void _applyClock() {
    final period = _spec?.period;
    if (period == null) {
      if (_controller.isAnimating) _controller.stop();
      return;
    }
    // Reacender o relógio é trocar de faixa, não reconstruir a tela: `repeat()`
    // grava o período e volta o valor a zero, então chamá-lo a cada `setState`
    // do perfil faria a respiração soluçar no meio do ciclo. A faixa nova com
    // período novo precisa do `repeat()` justamente por isso — o período só é
    // lido no instante em que ele é chamado.
    if (_controller.duration == period && _controller.isAnimating) return;
    _controller
      ..duration = period
      ..repeat();
  }

  @override
  void didUpdateWidget(BannerPlate oldWidget) {
    super.didUpdateWidget(oldWidget);
    _applyClock();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _trackPointer(PointerEvent event) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || box.size.isEmpty) return;
    final size = box.size;
    final next = Offset(
      (event.localPosition.dx / size.width) * 2 - 1,
      (event.localPosition.dy / size.height) * 2 - 1,
    );
    final clamped = Offset(next.dx.clamp(-1.0, 1.0), next.dy.clamp(-1.0, 1.0));
    if ((clamped - _pointer).distance < 0.02) return;
    setState(() => _pointer = clamped);
  }

  @override
  Widget build(BuildContext context) {
    final spec = _spec;
    final gradient = bannerGradient(widget.banner);
    final content = widget.child ?? const SizedBox.expand();
    final Widget plate;
    if (spec == null) {
      plate = DecoratedBox(
        decoration: BoxDecoration(gradient: gradient, color: widget.fallbackColor),
        child: content,
      );
    } else {
      // O relógio precisa ser escutado: um `repeat()` sem `AnimatedBuilder`
      // queima quadro e deixa a faixa congelada no primeiro desenho — a placa
      // comprada existiria no payload e não apareceria na tela.
      final layer = Positioned.fill(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (_, _) => CustomPaint(
            painter: PlatePainter(
              spec: spec,
              progress: _progress(spec),
              pointer: _pointer,
            ),
          ),
        ),
      );
      plate = DecoratedBox(
        decoration: BoxDecoration(gradient: gradient, color: widget.fallbackColor),
        child: Stack(
          children: [
            layer,
            content,
          ],
        ),
      );
    }
    final clipped = ClipRRect(borderRadius: widget.borderRadius, child: plate);
    if (spec?.style != PlateStyle.parallax) return clipped;
    // O paralaxe é o único estilo que escuta o ponteiro: sem ele a placa
    // respira sozinha, com ele o fundo vai contra a mão de quem olha.
    return MouseRegion(
      onExit: (_) => setState(() => _pointer = Offset.zero),
      child: Listener(onPointerMove: _trackPointer, child: clipped),
    );
  }

  double _progress(PlateSpec spec) =>
      spec.period == null ? 0 : _controller.value;
}

/// O desenho da placa, estilo por estilo.
class PlatePainter extends CustomPainter {
  PlatePainter({required this.spec, required this.progress, this.pointer = Offset.zero});

  final PlateSpec spec;

  /// 0..1 do ciclo do estilo.
  final double progress;

  /// O ponteiro, em fração da placa; só o paralaxe usa.
  final Offset pointer;

  /// A onda do ciclo, de -1 a 1, começando em zero para a volta não ter tranco.
  double get _wave => math.sin(progress * _tau);

  Color get _base => spec.base;

  /// O claro do material: puxado ao branco, nunca branco puro, para a placa
  /// continuar lendo sobre o cartão claro do tema.
  Color _light([double amount = .62]) => Color.lerp(_base, Colors.white, amount)!;

  Color _dark([double amount = .55]) => Color.lerp(_base, Colors.black, amount)!;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    switch (spec.style) {
      case PlateStyle.glass:
        _glass(canvas, size);
      case PlateStyle.gradient:
        _gradient(canvas, size);
      case PlateStyle.carbon:
        _carbon(canvas, size);
      case PlateStyle.territory:
        _territory(canvas, size);
      case PlateStyle.brushed:
        _brushed(canvas, size);
      case PlateStyle.splitNeon:
        _splitNeon(canvas, size);
      case PlateStyle.shimmer:
        _shimmer(canvas, size);
      case PlateStyle.parallax:
        _parallax(canvas, size);
      case PlateStyle.pulse:
        _pulse(canvas, size);
    }
  }

  /// Vidro fosco: o `blur` do catálogo é o quanto a placa leitosa esconde o que
  /// tem atrás, e a `edge` é o filete milimétrico que reflete na borda.
  void _glass(Canvas canvas, Size size) {
    final box = Offset.zero & size;
    final rng = math.Random(spec.seed);
    final frost = spec.blur * 2.2;
    for (var blob = 0; blob < 3; blob++) {
      canvas.drawOval(
        Rect.fromCircle(
          center: Offset(
            box.width * (0.22 + 0.3 * blob),
            box.height * (0.25 + 0.5 * rng.nextDouble()),
          ),
          radius: box.shortestSide * (0.42 + 0.16 * blob),
        ),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.05 + 0.025 * blob)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, frost),
      );
    }
    // A espessura do vidro: luz em cima, sombra embaixo, e o fio da `edge`
    // fechando a placa — é o "milimétrica" que a loja vende.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, box.width, 1.6),
      Paint()..color = spec.edge.withValues(alpha: .85),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, box.height - 2.4, box.width, 2.4),
      Paint()..color = Colors.black.withValues(alpha: .28),
    );
    canvas.drawRect(
      box.deflate(.6),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = spec.edge.withValues(alpha: .45),
    );
  }

  /// Gradiente dinâmico: a direção vem do `angle` e o recheio desliza devagar,
  /// sem linha dura — por isso os topos se tocam em `stops` contínuos.
  void _gradient(Canvas canvas, Size size) {
    final box = Offset.zero & size;
    final radians = spec.angle * math.pi / 180;
    final direction = Offset(math.cos(radians), math.sin(radians));
    final slide = (progress + 1) % 2 - 1; // -1..1 e volta, sem salto
    final colors = spec.colors;
    final stops = <double>[];
    final painted = <Color>[];
    for (var i = 0; i < colors.length; i++) {
      final span = colors.length == 1 ? 1.0 : i / (colors.length - 1);
      stops.add((0.15 + span * 0.7 + slide * 0.15).clamp(0.0, 1.0));
      painted.add(colors[i]);
    }
    stops.sort();
    canvas.drawRect(
      box,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment(-direction.dx, -direction.dy),
          end: Alignment(direction.dx, direction.dy),
          colors: painted,
          stops: stops,
        ).createShader(box),
    );
  }

  /// Fibra de carbono: trefas cruzadas em blocos de `weave` pixels. O desenho é
  /// uma malha, não um ruído — por isso o passo é fixo e a placa continua
  /// parecendo o mesmo material em qualquer tamanho.
  void _carbon(Canvas canvas, Size size) {
    final cell = 4.0 + spec.weave * 3;
    final box = Offset.zero & size;
    canvas.drawRect(box, Paint()..color = _dark(.72));
    for (var row = 0; row * cell < box.height + cell; row++) {
      for (var col = 0; col * cell < box.width + cell; col++) {
        final horizontal = (row + col) % 2 == 0;
        final tile = Rect.fromLTWH(col * cell, row * cell, cell, cell);
        canvas.drawRect(
          tile,
          Paint()
            ..shader = LinearGradient(
              begin: horizontal ? Alignment.centerLeft : Alignment.topCenter,
              end: horizontal ? Alignment.centerRight : Alignment.bottomCenter,
              colors: [
                _dark(.55),
                horizontal ? _dark(.86) : _dark(.8),
                _dark(.5),
              ],
            ).createShader(tile),
        );
      }
    }
    // O fosco do material: uma leve vinheta escurecendo as bordas.
    canvas.drawRect(
      box,
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.transparent, Colors.black.withValues(alpha: .45)],
          radius: .9,
        ).createShader(box),
    );
  }

  /// Mapa do território: a grade hexagonal do jogo, com as células da região
  /// acesa em volta de um centro que só depende do nome da região. É o mesmo
  /// hexágono da base da equipe e do emblema da liga, agora como fundo.
  void _territory(Canvas canvas, Size size) {
    final box = Offset.zero & size;
    canvas.drawRect(box, Paint()..color = _dark(.45));
    final radius = math.max(7.0, box.height / 5);
    final stepX = radius * math.sqrt(3);
    final stepY = radius * 1.5;
    final rng = math.Random(spec.seed);
    final focusX = rng.nextDouble() * (box.width / stepX).floor();
    final focusY = rng.nextDouble() * (box.height / stepY).floor();
    final cols = (box.width / stepX).floor() + 2;
    final rows = (box.height / stepY).floor() + 2;
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        final center = Offset(
          col * stepX + (row.isOdd ? stepX / 2 : 0) + stepX / 2,
          row * stepY + radius,
        );
        if (center.dx > box.width + radius || center.dy > box.height + radius) {
          continue;
        }
        final distance = (Offset(col - focusX, row - focusY)).distance;
        final lit = distance <= 1.6;
        final hex = hexagonPath(center, radius * .92);
        canvas.drawPath(
          hex,
          Paint()..color = lit
              ? _base.withValues(alpha: .38 + .22 * (1 - distance / 1.6))
              : Colors.black.withValues(alpha: .16),
        );
        canvas.drawPath(
          hex,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = (lit ? _light(.5) : _dark(.3)).withValues(alpha: .5),
        );
      }
    }
  }

  /// Metal escovado: o `grade` escolhe a liga e a escovação é um feixe de
  /// riscos horizontais com peso variado — o que dá o brilho de chapa.
  void _brushed(Canvas canvas, Size size) {
    final box = Offset.zero & size;
    final metal = spec.grade.metal;
    canvas.drawRect(
      box,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(metal, Colors.white, .25)!, metal, Color.lerp(metal, Colors.black, .45)!],
        ).createShader(box),
    );
    final rng = math.Random(spec.seed);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var y = 1.0; y < box.height; y += 2.0) {
      stroke.color = (y % 6 < 3
              ? Colors.white
              : Colors.black)
          .withValues(alpha: 0.03 + 0.07 * rng.nextDouble());
      canvas.drawLine(Offset(0, y), Offset(box.width, y), stroke);
    }
    // A luz que corre pela chapa. O `grade` não vem com milissegundo nenhum do
    // catálogo, então o brilho é fixo: metal escovado é placa parada, não
    // sinal — quem pulsa é quem declara ritmo (`period_ms`, `sweep_ms`).
    final glow = Rect.fromLTWH(0, box.height * .14, box.width, box.height * .32);
    canvas.drawRect(
      glow,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: .12),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(glow),
    );
  }

  /// LED na borda: a placa escurece e o fio de neon do `edge_hue` pulsa na
  /// beira de baixo com o `pulse_ms` do item.
  void _splitNeon(Canvas canvas, Size size) {
    final box = Offset.zero & size;
    canvas.drawRect(box, Paint()..color = Colors.black.withValues(alpha: .42));
    // Metade de cima mais clara: é a "split" da placa, o LED ilumina o vidro.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, box.width, box.height * .5),
      Paint()..color = Colors.white.withValues(alpha: .05),
    );
    final hue = HSLColor.fromAHSL(1, spec.edgeHue, .92, .6);
    final beat = 0.55 + 0.45 * ((_wave + 1) / 2);
    final neon = hue.toColor();
    final line = Rect.fromLTWH(0, box.height - 3.4, box.width, 3.4);
    canvas.drawRect(
      line,
      Paint()
        ..color = neon.withValues(alpha: .35 + .45 * beat)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 * beat),
    );
    canvas.drawRect(line, Paint()..color = neon.withValues(alpha: .6 + .4 * beat));
    canvas.drawRect(
      box.deflate(.8),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = neon.withValues(alpha: .25 * beat),
    );
  }

  /// Holográfico: um feixe branco varre a placa e uma segunda faixa na cor do
  /// item corre atrás dele em meio ritmo — é o que faz o cartão parecer
  /// iridescente em vez de um reflexo só.
  void _shimmer(Canvas canvas, Size size) {
    final box = Offset.zero & size;
    final sweep = (box.width + 240) * progress - 120;
    void band(double center, Color color, double halfWidth) {
      final rect = Rect.fromLTWH(
        math.max(0, center - halfWidth),
        0,
        math.min(box.width, halfWidth * 2),
        box.height,
      );
      if (rect.width <= 0) return;
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            colors: [color.withValues(alpha: 0), color, color.withValues(alpha: 0)],
          ).createShader(rect),
      );
    }

    band(sweep, Colors.white.withValues(alpha: .26), 90);
    band(box.width - sweep * .6, _light(.45).withValues(alpha: .22), 120);
  }

  /// Paralaxe: `depth + 1` camadas que andam contra o ponteiro, cada uma no seu
  /// passo. Sem ponteiro (toque) as camadas derivam sozinhas, devagar, para a
  /// placa continuar viva no celular.
  void _parallax(Canvas canvas, Size size) {
    final box = Offset.zero & size;
    final layers = spec.depth + 1;
    final rng = math.Random(spec.seed);
    for (var layer = 0; layer < layers; layer++) {
      // Contra o ponteiro, e a camada mais funda anda menos: é o oposto do
      // movimento da mão que o olho lê como profundidade.
      final shift = (layer + 1) * -7.0 * spec.depth;
      final drift = Offset(
        pointer.dx * shift + math.sin(progress * _tau + layer) * 10,
        pointer.dy * shift * .6 + math.cos(progress * _tau + layer) * 6,
      );
      for (var blob = 0; blob < 2; blob++) {
        final center = Offset(
          box.width * (0.25 + 0.5 * blob) + drift.dx,
          box.height * (0.3 + 0.4 * rng.nextDouble()) + drift.dy,
        );
        final tint = spec.colors[(layer + blob) % spec.colors.length];
        final halo = Rect.fromCircle(
          center: center,
          radius: box.shortestSide * (0.5 + 0.12 * layer),
        );
        // Nuvem iluminada no centro e sumindo na borda: um disco de cor chapada
        // não empilha, e a placa precisaria de `depth` camadas invisíveis.
        canvas.drawOval(
          halo,
          Paint()
            ..shader = RadialGradient(
              colors: [
                Color.lerp(tint, Colors.white, .45)!.withValues(
                  alpha: 0.3 - 0.06 * layer,
                ),
                tint.withValues(alpha: .12),
                tint.withValues(alpha: 0),
              ],
              stops: const [0, .55, 1],
            ).createShader(halo),
        );
      }
    }
  }

  /// Perfil vivo: a borda respira no `period_ms` do item — luz e espessura,
  /// nunca tamanho, para a faixa não empurrar o avatar.
  void _pulse(Canvas canvas, Size size) {
    final box = Offset.zero & size;
    final beat = (_wave + 1) / 2;
    final rim = Color.lerp(_base, Colors.white, .45 + .35 * beat)!;
    // O halo largo é o que se vê de longe — sem ele, a "borda que respira" só
    // existe quando alguém aproxima o olho do cartão.
    canvas.drawRect(
      box.deflate(1.2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 + 3 * beat
        ..color = rim.withValues(alpha: .3 + .4 * beat)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 5 + 9 * beat),
    );
    canvas.drawRect(
      box.deflate(.6),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = rim.withValues(alpha: .55 + .4 * beat),
    );
  }

  @override
  bool shouldRepaint(PlatePainter old) =>
      old.spec.item.id != spec.item.id ||
      old.spec.style != spec.style ||
      old.progress != progress ||
      old.pointer != pointer;
}
