/// Renderização dos cosméticos do mercado (molduras, faixas, estilos de
/// nome, efeitos e avatares animados da galeria pronta). Tudo é desenhado
/// em Flutter a partir do `payload` do catálogo (via API) — sem binários.
///
/// [cosmeticHint] é a frase que diz o que cada categoria faz no perfil: a
/// loja e o painel do passe descrevem o mesmo item com as mesmas palavras.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/profile_image_provider.dart';
import 'effect_painters.dart';
import 'runover_ui.dart';

/// O que a categoria do cosmético entrega no perfil.
String cosmeticHint(String category) => switch (category) {
  'avatar' => 'Decoração de avatar da galeria pronta.',
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

List<Color> _colors(ShopItem item) {
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
class FramedAvatar extends StatefulWidget {
  const FramedAvatar({
    super.key,
    required this.radius,
    this.image,
    this.fallbackLetter = '?',
    this.frame,
    this.avatarItem,
  });

  final double radius;
  final ImageProvider? image;
  final String fallbackLetter;
  final ShopItem? frame;
  final ShopItem? avatarItem;

  @override
  State<FramedAvatar> createState() => _FramedAvatarState();
}

class _FramedAvatarState extends State<FramedAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  bool get _animated =>
      (widget.frame?.payload['animated'] == true) ||
      (widget.avatarItem?.payload['animated'] == true);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    if (_animated) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(FramedAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final was = (oldWidget.frame?.payload['animated'] == true) ||
        (oldWidget.avatarItem?.payload['animated'] == true);
    if (_animated && !was) {
      _controller.repeat(reverse: true);
    } else if (!_animated && was) {
      _controller.stop();
    }
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
        : _colors(widget.frame!);
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
    final ring = Container(
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
    );
    if (!_animated) return ring;
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, child) {
        final glow = 0.6 + 0.4 * _controller.value;
        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: colors.first.withValues(alpha: .5 * glow),
                blurRadius: 18 * glow,
                spreadRadius: 2 * glow,
              ),
            ],
          ),
          child: child,
        );
      },
      child: ring,
    );
  }
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
  final colors = _colors(banner);
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
  final colors = _colors(style);
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

/// Avatar da galeria pronta: resolve o asset pelo `payload['asset']`.
/// A galeria vive em `assets/avatars/`; itens animados usam o mesmo
/// asset com anel animado (FramedAvatar).
String? galleryAvatarAsset(ShopItem? item) {
  final asset = item?.payload['asset'];
  if (asset is! String || asset.isEmpty) return null;
  return 'assets/avatars/avatar_$asset.png';
}

/// Estilo DiceBear do item gerado (`payload['generated']`), ou null.
String? generatedAvatarStyle(ShopItem? item) {
  final style = item?.payload['generated'];
  if (style is! String || !diceBearAvatarStyles.contains(style)) {
    return null;
  }
  return style;
}

/// Provedor de imagem do perfil: avatar da loja (galeria pronta ou gerado
/// com seed = apelido do dono) e, por último, a foto enviada.
ImageProvider? profileAvatarImage(
  String? photoUrl,
  ShopItem? avatarItem, {
  String? seed,
}) {
  final asset = galleryAvatarAsset(avatarItem);
  if (asset != null) return AssetImage(asset);
  final style = generatedAvatarStyle(avatarItem);
  if (style != null) {
    return NetworkImage(diceBearAvatarUrl(seed ?? '', style: style));
  }
  return profileImageProvider(photoUrl);
}
