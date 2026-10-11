import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/profile_image_provider.dart';

// ============================================================ Cores por tema
//
// Registre as duas versões no ThemeData:
//   theme:     ThemeData(extensions: [RunoverColors.light])
//   darkTheme: ThemeData(brightness: Brightness.dark, extensions: [RunoverColors.dark])
// Dentro dos widgets, use `context.rc`.
//
// Este tema centraliza as cores usadas em cards, borders, texto e-muted;
// substitui a paletaHardcoded espalhada pelos screens.

@immutable
class RunoverColors extends ThemeExtension<RunoverColors> {
  const RunoverColors({
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.text,
    required this.muted,
  });

  final Color bg, surface, surfaceAlt, border, text, muted;

  static const dark = RunoverColors(
    bg: Color(0xFF14102E),
    surface: Color(0xFF241C5C),
    surfaceAlt: Color(0xFF2F2578),
    border: Color(0xFF5B4BD6),
    text: Colors.white,
    muted: Color(0xFFB9B2F0),
  );

  static const light = RunoverColors(
    bg: Color(0xFFF4F1FF),
    surface: Colors.white,
    surfaceAlt: Color(0xFFEDE8FF),
    border: Color(0xFFCFC6FF),
    text: Color(0xFF1B1530),
    muted: Color(0xFF5E5780),
  );

  @override
  RunoverColors copyWith({
    Color? bg,
    Color? surface,
    Color? surfaceAlt,
    Color? border,
    Color? text,
    Color? muted,
  }) =>
      RunoverColors(
        bg: bg ?? this.bg,
        surface: surface ?? this.surface,
        surfaceAlt: surfaceAlt ?? this.surfaceAlt,
        border: border ?? this.border,
        text: text ?? this.text,
        muted: muted ?? this.muted,
      );

  @override
  RunoverColors lerp(ThemeExtension<RunoverColors>? other, double t) {
    if (other is! RunoverColors) return this;
    return RunoverColors(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      border: Color.lerp(border, other.border, t)!,
      text: Color.lerp(text, other.text, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
    );
  }
}

extension RunoverContext on BuildContext {
  RunoverColors get rc => Theme.of(this).extension<RunoverColors>()!;
}

// ============================================================ Gradientes

class RGrad {
  static const orange = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFF9A4D), Color(0xFFE8452C)],
  );
  static const teal = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF34D6B2), Color(0xFF14907A)],
  );
  static const gold = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFF7C93C), Color(0xFFD9921A)],
  );
  static const header = LinearGradient(colors: [Color(0xFFFF7F4D), Color(0xFFE5367A)]);
  static const progress = LinearGradient(colors: [Color(0xFF8CF2D6), Color(0xFF3DDBB0)]);
}

/// Raridade dos desafios: define as cores do cartão.
enum Rarity {
  common('comum', Color(0xFF3F8CFF), Color(0xFF1E4FB8)),
  rare('raro', Color(0xFF9B6BFF), Color(0xFF5B2FC0)),
  epic('épico', Color(0xFFFFB21A), Color(0xFFE8452C));

  const Rarity(this.label, this.from, this.to);
  final String label;
  final Color from, to;

  LinearGradient get gradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [from, to],
      );
}

// ============================================================ Sombra de texto

const kTextShadow = [Shadow(color: Color(0x4D000000), offset: Offset(0, 2))];

// ============================================================ Formatação pt-BR

/// Formatação pt-BR de milhares (`10.000`) para pontos, moedas e saldos.
///
/// Implementação canônica única — não duplique este regex nas telas;
/// importe da `format.dart`.
String fmtNum(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1).replaceAll('.', ',');

// ============================================================ Cartão

/// Cartão com gradiente, borda clara e sombra "dura" embaixo.
class GameCard extends StatelessWidget {
  const GameCard({
    super.key,
    required this.child,
    this.gradient,
    this.color,
    this.padding = const EdgeInsets.all(12),
    this.radius = 18,
    this.borderColor = const Color(0x2EFFFFFF),
  });

  final Widget child;
  final Gradient? gradient;
  final Color? color;
  final EdgeInsets padding;
  final double radius;
  final Color borderColor;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          gradient: gradient,
          color: color,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: borderColor, width: 2),
          boxShadow: const [BoxShadow(color: Color(0x59000000), offset: Offset(0, 4))],
        ),
        child: child,
      );
}

// ============================================================ Progresso

class ChunkyProgress extends StatelessWidget {
  const ChunkyProgress({super.key, required this.value, this.height = 14});

  final double value; // 0 a 1
  final double height;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(height / 2),
        child: SizedBox(
          height: height,
          child: LayoutBuilder(
            builder: (_, c) => Stack(children: [
              Positioned.fill(child: Container(color: const Color(0x4D000000))),
              TweenAnimationBuilder<double>(
                tween: Tween(end: value.clamp(0.0, 1.0)),
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOut,
                builder: (_, v, __) => Container(
                  // largura mínima de 6px para o progresso zero ainda aparecer
                  width: (c.maxWidth * v).clamp(6.0, c.maxWidth),
                  decoration: BoxDecoration(
                    gradient: RGrad.progress,
                    borderRadius: BorderRadius.circular(height / 2),
                  ),
                ),
              ),
            ]),
          ),
        ),
      );
}

// ============================================================ Botão 3D

/// Botão que "afunda" ao ser pressionado. `onPressed` nulo deixa o botão apagado.
class GameButton extends StatefulWidget {
  const GameButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.background = Colors.white,
    this.foreground = const Color(0xFF2A1308),
    this.compact = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color background, foreground;
  final bool compact;

  @override
  State<GameButton> createState() => _GameButtonState();
}

class _GameButtonState extends State<GameButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      child: Opacity(
        opacity: enabled ? 1 : 0.55,
        child: GestureDetector(
          onTapDown: enabled ? (_) => setState(() => _down = true) : null,
          onTapUp: enabled ? (_) => setState(() => _down = false) : null,
          onTapCancel: enabled ? () => setState(() => _down = false) : null,
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            transform: Matrix4.translationValues(0, _down ? 3 : 0, 0),
            padding: EdgeInsets.symmetric(
              horizontal: widget.compact ? 12 : 16,
              vertical: widget.compact ? 6 : 11,
            ),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: widget.background,
              borderRadius: BorderRadius.circular(widget.compact ? 9 : 12),
              boxShadow: [BoxShadow(color: const Color(0x4D000000), offset: Offset(0, _down ? 0 : 3))],
            ),
            child: Text(
              widget.label.toUpperCase(),
              style: TextStyle(
                color: widget.foreground,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
                fontSize: widget.compact ? 12 : 14,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================ Animações leves

/// Faz o filho subir e descer devagar. Respeita "reduzir movimento" do aparelho.
class Bob extends StatefulWidget {
  const Bob({super.key, required this.child});

  final Widget child;

  @override
  State<Bob> createState() => _BobState();
}

class _BobState extends State<Bob> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) =>
          Transform.translate(offset: Offset(0, -4 * Curves.easeInOut.transform(_c.value)), child: child),
      child: widget.child,
    );
  }
}

/// Anel de brilho que pulsa em volta do filho (usado em "Resgatar").
class PulseGlow extends StatefulWidget {
  const PulseGlow({super.key, required this.child, this.radius = 9});

  final Widget child;
  final double radius;

  @override
  State<PulseGlow> createState() => _PulseGlowState();
}

class _PulseGlowState extends State<PulseGlow> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          boxShadow: [
            BoxShadow(
              color: Colors.white.withAlpha((130 * (1 - _c.value)).round()),
              spreadRadius: 6 * _c.value,
            ),
          ],
        ),
        child: child,
      ),
      child: widget.child,
    );
  }
}

// ============================================================ Peças pequenas

class InfoPill extends StatelessWidget {
  const InfoPill(this.text, {super.key, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(color: const Color(0x4D000000), borderRadius: BorderRadius.circular(14)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 14, color: const Color(0xFFFFD866)), const SizedBox(width: 6)],
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
      );
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.pill});

  final String title;
  final String? pill;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              color: context.rc.text,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
        ),
        if (pill != null) InfoPill(pill!, icon: Icons.timer_outlined),
      ]);
}

// ============================================================ Barra superior

/// Barra superior com gradiente, usada no topo das telas.
class GradientBar extends StatelessWidget {
  const GradientBar({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          gradient: RGrad.header,
          boxShadow: [BoxShadow(color: Color(0x40000000), offset: Offset(0, 3))],
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
            child: Row(children: [
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    shadows: kTextShadow,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ]),
          ),
        ),
      );
}

// ============================================================ Personagens

// Os desenhos são SVGs embutidos no código (não precisa de arquivos em assets).
// Requer o pacote flutter_svg:  flutter pub add flutter_svg

enum RCharacter { hexi, zona, turbo, pit, coach, lenda }

class CharacterAvatar extends StatelessWidget {
  const CharacterAvatar(this.character, {super.key, this.size = 60, this.bob = false});

  final RCharacter character;
  final double size;
  final bool bob;

  @override
  Widget build(BuildContext context) {
    final art = SvgPicture.string(_svgs[character]!, width: size, height: size);
    return Semantics(
      label: _names[character],
      image: true,
      child: bob ? Bob(child: art) : art,
    );
  }
}

const _names = {
  RCharacter.hexi: 'Hexi, o mascote',
  RCharacter.zona: 'Capitã Zona',
  RCharacter.turbo: 'Turbo',
  RCharacter.pit: 'Pit',
  RCharacter.coach: 'Treinador Passo',
  RCharacter.lenda: 'Lenda',
};

const _open = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">'
    '<g stroke="#1c1220" stroke-width="3" stroke-linejoin="round" stroke-linecap="round">';
const _close = '</g></svg>';

const _svgs = <RCharacter, String>{
  RCharacter.hexi: _open +
      '<polygon points="50,8 90,30 90,72 50,94 10,72 10,30" fill="#B0246A"/>'
          '<polygon points="50,8 90,30 50,52 10,30" fill="#D14A90" stroke="none"/>'
          '<polygon transform="translate(50 29) scale(0.6)" fill="#fff" points="0,-14 3.4,-4.7 13.3,-4.3 5.5,1.8 8.2,11.3 0,5.8 -8.2,11.3 -5.5,1.8 -13.3,-4.3 -3.4,-4.7"/>'
          '<ellipse cx="36" cy="62" rx="8" ry="9.5" fill="#fff"/><ellipse cx="64" cy="62" rx="8" ry="9.5" fill="#fff"/>'
          '<circle cx="38" cy="64" r="4.2" fill="#1c1220" stroke="none"/><circle cx="66" cy="64" r="4.2" fill="#1c1220" stroke="none"/>'
          '<path d="M38,79 Q50,92 62,79Z" fill="#fff"/>' +
      _close,
  RCharacter.zona: _open +
      '<circle cx="22" cy="40" r="9" fill="#5a2f1c"/>'
      '<path d="M12,100 Q12,76 50,76 Q88,76 88,100Z" fill="#FF7F4D"/>'
      '<circle cx="50" cy="48" r="25" fill="#f2b48a"/>'
      '<path d="M25,46 Q23,20 50,20 Q77,20 75,46 Q64,33 50,35 Q36,33 25,46Z" fill="#5a2f1c"/>'
      '<ellipse cx="40" cy="52" rx="4.5" ry="6" fill="#fff" stroke-width="2.5"/><ellipse cx="60" cy="52" rx="4.5" ry="6" fill="#fff" stroke-width="2.5"/>'
      '<circle cx="41" cy="53" r="2.4" fill="#1c1220" stroke="none"/><circle cx="61" cy="53" r="2.4" fill="#1c1220" stroke="none"/>'
      '<path d="M42,64 Q50,74 58,64Z" fill="#fff"/>' +
      _close,
  RCharacter.turbo: _open +
      '<path d="M12,100 Q12,76 50,76 Q88,76 88,100Z" fill="#FFC93C"/>'
      '<rect x="26" y="88" width="48" height="8" fill="#e53935" stroke="none"/>'
      '<circle cx="50" cy="50" r="26" fill="#8d5a3b"/>'
      '<path d="M23,52 Q22,16 50,16 Q78,16 77,52 L77,56 Q50,48 23,56Z" fill="#FFC93C"/>'
      '<path d="M45,16 L55,16 L55,38 L45,38Z" fill="#e53935" stroke="none"/>'
      '<rect x="26" y="38" width="48" height="21" rx="10" fill="#1d2a4a"/>'
      '<ellipse cx="39" cy="48" rx="5" ry="6" fill="#fff" stroke="none"/><ellipse cx="61" cy="48" rx="5" ry="6" fill="#fff" stroke="none"/>'
      '<circle cx="40" cy="49" r="2.5" fill="#1c1220" stroke="none"/><circle cx="62" cy="49" r="2.5" fill="#1c1220" stroke="none"/>'
      '<path d="M40,69 Q50,79 60,69Z" fill="#fff"/>' +
      _close,
  RCharacter.pit: _open +
      '<path d="M12,100 Q12,76 50,76 Q88,76 88,100Z" fill="#22b58e"/>'
      '<circle cx="50" cy="50" r="26" fill="#e0a97a"/>'
      '<path d="M24,48 Q24,18 50,18 Q76,18 76,48Z" fill="#169a77"/>'
      '<path d="M28,46 L86,46 Q91,50 84,54 L28,54Z" fill="#169a77"/>'
      '<path d="M24,56 Q22,16 50,16 Q78,16 76,56" fill="none" stroke="#2b2f3a" stroke-width="4"/>'
      '<circle cx="24" cy="58" r="6" fill="#2b2f3a"/><circle cx="76" cy="58" r="6" fill="#2b2f3a"/>'
      '<ellipse cx="40" cy="60" rx="4.5" ry="6" fill="#fff" stroke-width="2.5"/><ellipse cx="60" cy="60" rx="4.5" ry="6" fill="#fff" stroke-width="2.5"/>'
      '<circle cx="41" cy="61" r="2.4" fill="#1c1220" stroke="none"/><circle cx="61" cy="61" r="2.4" fill="#1c1220" stroke="none"/>'
      '<path d="M40,72 Q50,82 60,72Z" fill="#fff"/>' +
      _close,
  RCharacter.coach: _open +
      '<path d="M12,100 Q12,76 50,76 Q88,76 88,100Z" fill="#4A6FA5"/>'
      '<rect x="42" y="82" width="16" height="10" rx="5" fill="#FFC93C" stroke-width="2.5"/>'
      '<circle cx="50" cy="48" r="25" fill="#c68a5e"/>'
      '<path d="M24,44 Q24,18 50,18 Q76,18 76,44Z" fill="#1f3558"/>'
      '<path d="M26,42 L82,42 Q87,46 80,51 L26,51Z" fill="#1f3558"/>'
      '<ellipse cx="40" cy="55" rx="4" ry="5" fill="#fff" stroke-width="2.5"/><ellipse cx="60" cy="55" rx="4" ry="5" fill="#fff" stroke-width="2.5"/>'
      '<circle cx="41" cy="56" r="2.2" fill="#1c1220" stroke="none"/><circle cx="61" cy="56" r="2.2" fill="#1c1220" stroke="none"/>'
      '<path d="M38,67 Q44,62 50,67 Q56,62 62,67 Q56,72 50,69 Q44,72 38,67Z" fill="#3a2a22" stroke-width="2.5"/>' +
      _close,
  RCharacter.lenda: _open +
      '<circle cx="50" cy="14" r="11" fill="#e6e8ee"/>'
      '<path d="M12,100 Q12,76 50,76 Q88,76 88,100Z" fill="#FFB21A"/>'
      '<circle cx="42" cy="90" r="6" fill="#FFE066" stroke-width="2.5"/><circle cx="58" cy="90" r="6" fill="#cfd5e3" stroke-width="2.5"/>'
      '<circle cx="50" cy="48" r="25" fill="#b9825d"/>'
      '<path d="M25,46 Q23,20 50,20 Q77,20 75,46 Q64,33 50,35 Q36,33 25,46Z" fill="#e6e8ee"/>'
      '<path d="M27,40 Q50,28 73,40 L72,45 Q50,34 28,45Z" fill="#FF4D8D" stroke-width="2.5"/>'
      '<ellipse cx="40" cy="53" rx="4.5" ry="5.5" fill="#fff" stroke-width="2.5"/><ellipse cx="60" cy="53" rx="4.5" ry="5.5" fill="#fff" stroke-width="2.5"/>'
      '<circle cx="41" cy="54" r="2.4" fill="#1c1220" stroke="none"/><circle cx="61" cy="54" r="2.4" fill="#1c1220" stroke="none"/>'
      '<path d="M41,64 Q50,72 59,64" fill="none"/>' +
      _close,
};