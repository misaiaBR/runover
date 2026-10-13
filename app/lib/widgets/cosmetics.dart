/// Renderização dos cosméticos do mercado (molduras, faixas, estilos de
/// nome, efeitos e avatares). Tudo é desenhado em Flutter a partir do
/// `payload` do catálogo (via API) — sem binários.
///
/// [cosmeticHint] é a frase que diz o que cada categoria faz no perfil: a
/// loja e o painel do passe descrevem o mesmo item com as mesmas palavras.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/profile_image_provider.dart';
import 'effect_painters.dart';
import 'frame_painters.dart';
import 'runover_ui.dart';

// Quem veste o avatar com uma moldura de família precisa falar a língua dela.
export 'frame_painters.dart' show FrameFamily, FrameGauge, GaugeMeasure;
/// O que a categoria do cosmético entrega no perfil.
String cosmeticHint(String category) => switch (category) {
  'avatar' => 'Rosto exclusivo do avatar, com acabamento próprio.',
  'frame' => 'Moldura ao redor do seu avatar no perfil.',
  'effect' => 'Efeito animado sobre o cartão de perfil.',
  'banner' => 'Faixa de fundo do seu perfil.',
  'name_style' => 'Estilo do seu nome exibido no perfil.',
  'emoticon' => 'Pacote de emoticons exibido no mural do perfil.',
  'bundle' => 'Pacote com desconto: libera todos os itens listados.',
  _ => 'Cosmético do seu perfil.',
};

Color _hex(String hex) {
  final clean = hex.replaceAll('#', '');
  final value = int.parse(
    clean.length == 6 ? 'FF$clean' : clean,
    radix: 16,
  );
  return Color(value);
}

/// As cores declaradas no payload, na ordem em que o catálogo as pôs.
///
/// É o único lugar onde um hex do catálogo vira `Color`: anel da moldura,
/// gradiente da faixa e tinta do nome saem todos daqui.
List<Color> cosmeticColors(ShopItem item) {
  final raw = item.payload['colors'] as List? ?? const [];
  if (raw.isEmpty) return const [Color(0xFFFFC93C)];
  return [for (final c in raw) _hex('$c')];
}

ShopItem? findItem(List<ShopItem> catalog, String? id) {
  if (id == null) return null;
  for (final item in catalog) {
    if (item.id == id) return item;
  }
  return null;
}

/// Moldura ao redor do avatar. Itens `animated` ganham brilho pulsante
/// em loop (todo o catálogo é animado).
///
/// Quando o item declara uma das nove famílias de `style`, o aro é desenhado
/// pelo pintor daquela família ([FrameFamilyPainter]); sem isso ele continua o
/// anel simples na cor do payload.
class FramedAvatar extends StatefulWidget {
  const FramedAvatar({
    super.key,
    required this.radius,
    this.image,
    this.fallbackLetter = '?',
    this.frame,
    this.avatarItem,
    this.gauges = const [],
  });

  final double radius;
  final ImageProvider? image;
  final String fallbackLetter;
  final ShopItem? frame;
  final ShopItem? avatarItem;

  /// Os números que o dono do avatar tem, para a moldura de medidor
  /// (`style: ring`, `gauge: xp|sequencia|territorio`).
  ///
  /// Cada um carrega o que mede ([GaugeMeasure]); a moldura usa só o que bate
  /// com a palavra do payload. Sem número compatível o anel se mostra aberto.
  final List<FrameGauge> gauges;

  @override
  State<FramedAvatar> createState() => _FramedAvatarState();
}

class _FramedAvatarState extends State<FramedAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  bool get _animated =>
      (widget.frame?.payload['animated'] == true) ||
      (widget.avatarItem?.payload['animated'] == true);

  /// O anel veste o patamar mais alto entre moldura e avatar: quem paga mais por
  /// um item vê o item se mexendo mais, e isso é conta do servidor (`tier`).
  int get _tier {
    final frame = animationTier(widget.frame);
    final avatar = animationTier(widget.avatarItem);
    return frame > avatar ? frame : avatar;
  }

  /// 1 respira devagar, 4 corre. Sem isto todo item animado teria o mesmo pulso.
  Duration get _pulse => Duration(milliseconds: 1500 - 250 * _tier);

  /// O `style` do item, quando ele declara uma das nove famílias. É o que
  /// decide se o aro é desenhado pelo pintor da família ou pela cor simples.
  FrameFamily? get _family => frameFamily(widget.frame);

  Map<String, dynamic> get _payload => widget.frame?.payload ?? const {};

  /// Se o relógio precisa rodar: o catálogo diz que o item é animado, ou a
  /// família dele tem movimento próprio (o neon gira mesmo em item estático).
  bool get _moves => _animated || (_family?.loops(_payload) ?? false);

  /// A velocidade vem do servidor quando a família declara a sua (`speed_ms`
  /// do neon, `interval_ms` da falha); nas demais vale a escada de patamar.
  Duration get _period => _family?.period(_payload) ?? _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _period);
    _applyClock();
  }

  /// Acende ou apaga o relógio do anel. Famílias que giram (metal, neon,
  /// partículas, falha) rodam em avanço contínuo; o anel simples de cor
  /// continua o pulso de ida e volta que sempre teve.
  void _applyClock() {
    if (!_moves) {
      _controller.stop();
      return;
    }
    // Item trocado na mesma tela: `repeat()` grava o período no instante em
    // que é chamado, então mexer só na duração deixaria o anel respirando no
    // ritmo do item anterior. Reiniciar mantém o valor atual e adota o pulso
    // do patamar novo.
    _controller
      ..duration = _period
      ..repeat(reverse: _family == null);
  }

  @override
  void didUpdateWidget(FramedAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _applyClock();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.frame == null
        ? const <Color>[]
        : cosmeticColors(widget.frame!);
    final borderColor = colors.isEmpty
        ? Colors.transparent
        : colors.length == 1
            ? colors.first
            : null;
    final avatar = CircleAvatar(
      radius: widget.radius,
      backgroundColor: Theme.of(
        context,
      ).colorScheme.primary.withValues(alpha: .12),
      foregroundImage: widget.image,
      onForegroundImageError: widget.image != null ? (_, _) {} : null,
      child: Text(
        widget.fallbackLetter.toUpperCase(),
        style: TextStyle(
          fontSize: widget.radius * 0.75,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
    if (colors.isEmpty) return avatar;
    final family = _family;
    // Sem família o anel É a cor do item: borda fina ou varredura pelo próprio
    // Container. Com família o aro nasce do pintor, então do Container sobra
    // apenas o respiro de 3 px que já existia — o espaço que o perfil reserva
    // para o avatar não muda de uma família para outra.
    final ring = family == null
        ? Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: borderColor != null
                  ? Border.all(color: borderColor, width: 3)
                  : null,
              gradient: borderColor == null
                  ? SweepGradient(colors: [...colors, colors.first])
                  : null,
            ),
            child: avatar,
          )
        : Padding(padding: const EdgeInsets.all(3), child: avatar);

    CustomPaint life(Widget? child, double progress, int tier) => CustomPaint(
      foregroundPainter: family == null
          ? RingLifePainter(
              progress: progress,
              colors: colors,
              tier: tier,
              sparkInk: inkOnAccent(colors.first),
            )
          : FrameFamilyPainter(
              family: family,
              item: widget.frame!,
              progress: progress,
              gauges: widget.gauges,
            ),
      child: child,
    );

    if (!_moves) {
      // Item parado: o anel simples não projeta brilho e a família mostra o
      // desenho dela congelado no instante zero.
      return family == null ? ring : life(ring, _controller.value, _tier);
    }
    final tier = _tier;
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, child) {
        final progress = _controller.value;
        // O brilho é a vida visível do patamar. O anel simples vai de 0 a 1 e
        // volta, então a própria perna serve. Uma família gira em avanço
        // contínuo (o aro varre, a partícula orbita) e o dente de serra teria
        // um tranco a cada volta: aí o pulso vem do cosseno, mesmo 0,6..1,0.
        final glow =
            0.6 +
            0.4 *
                (family == null
                    ? progress
                    : 0.5 - 0.5 * math.cos(2 * math.pi * progress));
        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: colors.first.withValues(alpha: .5 * glow),
                blurRadius: (12 + 4 * tier) * glow,
                spreadRadius: 2 * glow,
              ),
            ],
          ),
          child: life(child, progress, tier),
        );
      },
      child: ring,
    );
  }
}

/// A vida do anel, desenhada por cima da borda: varredura de luz a partir do
/// patamar 2 e partículas orbitando o aro a partir do 3. O traço fica dentro da
/// caixa do próprio anel — nada aqui muda o tamanho que o perfil reserva.
class RingLifePainter extends CustomPainter {
  RingLifePainter({
    required this.progress,
    required this.colors,
    required this.tier,
    required this.sparkInk,
  });
  final double progress;
  final List<Color> colors;
  final int tier;
  final Color sparkInk;

  @override
  void paint(Canvas canvas, Size size) {
    if (tier < 2 || colors.isEmpty || size.isEmpty) return;
    final side = math.min(size.width, size.height);
    final box = Rect.fromLTWH(
      (size.width - side) / 2,
      (size.height - side) / 2,
      side,
      side,
    );
    final arc = box.deflate(1.5);
    final rotation = progress * math.pi * 2;
    final first = colors.first;
    canvas.drawArc(
      arc,
      rotation,
      1.1,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 2
        ..shader = LinearGradient(
          colors: [
            first.withValues(alpha: 0),
            sparkInk.withValues(alpha: .9),
            first.withValues(alpha: 0),
          ],
          stops: const [0, .5, 1],
        ).createShader(arc),
    );
    if (tier < 3) return;
    final radius = arc.width / 2;
    for (var spark = 0; spark < 3; spark++) {
      final angle = -rotation * 1.4 + spark * math.pi * 2 / 3;
      canvas.drawCircle(
        Offset(
          arc.center.dx + math.cos(angle) * radius,
          arc.center.dy + math.sin(angle) * radius,
        ),
        2,
        Paint()..color = sparkInk.withValues(alpha: .95),
      );
    }
  }

  @override
  bool shouldRepaint(RingLifePainter old) =>
      old.progress != progress ||
      old.tier != tier ||
      old.sparkInk != sparkInk ||
      old.colors.length != colors.length;
}

/// Respiração sutil em loop para prévias sem animação própria
/// (faixas, nomes, emoticons, pacotes): escala 1 ↔ 1.03 com fase por item.
class Breathe extends StatefulWidget {
  const Breathe({super.key, required this.seed, required this.child});

  final String seed;
  final Widget child;

  @override
  State<Breathe> createState() => _BreatheState();
}

class _BreatheState extends State<Breathe>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final double _phase;

  @override
  void initState() {
    super.initState();
    var hash = 0;
    for (final unit in widget.seed.codeUnits) {
      hash = ((hash * 31) + unit) & 0x7fffffff;
    }
    _phase = (hash % 1000) / 1000 * 6.283185307;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, child) {
        final s =
            1.0 +
            0.03 *
                math.sin(_controller.value * 6.283185307 + _phase);
        return Transform.scale(scale: s, child: child);
      },
      child: widget.child,
    );
  }
}

/// Faixa do perfil (banner). Devolve `null` quando não há item.
LinearGradient? bannerGradient(ShopItem? banner) {
  if (banner == null) return null;
  final colors = cosmeticColors(banner);
  return LinearGradient(
    colors: colors.length == 1 ? [colors.first, colors.first] : colors,
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

/// Nome exibido com o estilo equipado (cor + brilho; arco-íris usa a
/// primeira cor como base e sombra colorida).
///
/// A cor do estilo vem do catálogo, nunca do tema: o amarelo e o ciano da
/// paleta foram desenhados sobre o cartão escuro do mockup e somem no cartão
/// branco do tema claro. Passe [context] para receber a tinta queimada do
/// brilho (a cor crua continua em [onBanner], porque ali atrás do nome há a
/// faixa de gradiente fixa do próprio jogador).
TextStyle styledName(
  String name,
  ShopItem? style,
  TextStyle base, {
  BuildContext? context,
  bool onBanner = false,
}) {
  if (style == null) return base;
  final colors = cosmeticColors(style);
  final glow = style.payload['glow'] == true;
  final ink = (context == null || onBanner)
      ? colors.first
      : legibleInk(colors.first, context);
  return base.copyWith(
    color: ink,
    shadows: glow
        ? [
            Shadow(
              color: colors.first.withValues(alpha: .7),
              blurRadius: 12,
            ),
          ]
        : null,
  );
}

/// Efeito do perfil: a camada animada do tipo equipado sobre o cartão.
///
/// O desenho vem de `payload['kind']` — um renderizador por tipo, em
/// `effect_painters.dart` —, a velocidade de `cycle_ms` e a cor de `hue`. O
/// campo inteiro é decorativo (`IgnorePointer`), nunca um botão.
///
/// [onDarkSurface] diz o que a camada está cobrindo: o cartão do tema (perfil,
/// ficha do produto) ou o gradiente fixo e escuro da raridade (a caixa de arte
/// da vitrine e do passe). No segundo caso a tinta legível do tema claro é
/// preta sobre azul-marinho e some — ali a partícula continua branca.
class ProfileEffectOverlay extends StatefulWidget {
  const ProfileEffectOverlay({
    super.key,
    required this.effect,
    this.onDarkSurface = false,
  });
  final ShopItem effect;
  final bool onDarkSurface;

  @override
  State<ProfileEffectOverlay> createState() => _ProfileEffectOverlayState();
}

class _ProfileEffectOverlayState extends State<ProfileEffectOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: EffectSpec.from(widget.effect).cycle,
    )..repeat();
  }

  @override
  void didUpdateWidget(ProfileEffectOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.effect.id == widget.effect.id) return;
    // Outro item é outro ciclo: névoa respira em segundos, estroboscópio pisca
    // em menos de um. Ajustar a duração é o que faz a prévia tocar no ritmo que
    // o servidor deu.
    _controller.duration = EffectSpec.from(widget.effect).cycle;
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spec = EffectSpec.from(widget.effect);
    final raw = spec.tint();
    final accent = widget.onDarkSurface
        ? raw
        : legibleInk(raw, context);
    final neutral = widget.onDarkSurface
        ? Colors.white
        : Pal.of(context).heading;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, _) => CustomPaint(
          painter: StageEffectPainter(
            spec: spec,
            progress: _controller.value,
            accent: accent,
            neutral: neutral,
          ),
        ),
      ),
    );
  }
}

/// Estilo DiceBear do item gerado (`payload['generated']`), ou null.
String? generatedAvatarStyle(ShopItem? item) {
  final style = item?.payload['generated'];
  if (style is! String || !diceBearAvatarStyles.contains(style)) {
    return null;
  }
  return style;
}

/// O rosto do item, não o de quem o equipou.
///
/// O servidor põe `seed` no payload de cada avatar da API (é o id do item) para
/// que a vitrine, a folha de escolha, o perfil de quem equipou e o cartão de
/// ranking mostrem a mesma figura. Seed por apelido fazia o "Corredor" da loja
/// ser um rosto e o "Corredor" equipado ser outro.
String avatarSeed(ShopItem item) {
  final seed = item.payload['seed'];
  if (seed is String && seed.isNotEmpty) return seed;
  return item.id;
}

/// Provedor de imagem do perfil: o avatar da loja (a figura é do item) e, por
/// último, a foto enviada.
ImageProvider? profileAvatarImage(String? photoUrl, ShopItem? avatarItem) {
  final style = generatedAvatarStyle(avatarItem);
  if (style != null && avatarItem != null) {
    return NetworkImage(diceBearAvatarUrl(avatarSeed(avatarItem), style: style));
  }
  return profileImageProvider(photoUrl);
}

/// A escada de animação do item: 1 pulsa, 2 varre, 3 acende partículas, 4 corre
/// mais rápido. É o `tier` que o catálogo calcula pelo preço, não uma aposta do
/// app — sem ele, um anel de bronze e uma moldura de diamante respirariam igual.
int animationTier(ShopItem? item) {
  final tier = item?.payload['tier'];
  if (tier is! num) return 1;
  return tier.toInt().clamp(1, 4);
}
