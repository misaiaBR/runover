/// Kit de UI das telas de jogo (home, Corridas e Passe de Temporada).
///
/// É a fonte única das peças que se repetem nos três mockups: o painel
/// arredondado sobre o fundo preto, os cartões com gradiente e sombra dura, a
/// barra de progresso grossa, o botão que afunda, as pílulas de informação, o
/// cabeçalho em gradiente e os seis personagens em SVG embutido (sem arquivos
/// em `assets`, sem binário novo no pacote).
///
/// Nada aqui decide regra de jogo: o kit só desenha. Os números vêm da API
/// (`SeasonPassScreen`, `RunsScreen`) ou do [Pal] do tema.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

// ============================================================ Paleta

/// Paleta das telas de jogo: acentos fixos + superfícies que seguem o brilho.
///
/// Use `Pal.of(context)` dentro de `build`; nunca os valores `dark`/`light`
/// direto, para o card acompanhar a troca claro/escuro em tempo real.
class Pal {
  // Acentos: iguais no claro e no escuro.
  static const orange = Color(0xFFFF7F4D);
  static const gold = Color(0xFFFFC93C);
  static const teal = Color(0xFF3DDBB0);
  static const purple = Color(0xFF8B7CFF);
  static const purpleDark = Color(0xFF2A2240);
  static const onAccent = Color(0xFF1A0E08);

  /// Acento do modo de equipe. O `colorScheme.tertiary` não é definido no tema
  /// e o Material 3 o derivava num oliva de contraste ruim com qualquer tinta.
  static const team = Color(0xFF2F6FD0);

  /// Fundo do painel que segura a tela inteira sobre o preto da página.
  final Color panel;

  /// Barra do HUD e cartões elevados (mais claros que [card]).
  final Color hud;
  final Color card;
  final Color chip;
  final Color border;
  final Color muted;
  final Color heading;
  final Color chipText;
  final Color hardShadow;

  /// O trilho vazio de uma barra de progresso. Não dá para usar o preto
  /// translúcido do tema claro nos dois: a 30% ele some sobre o roxo escuro do
  /// cartão, e o preto preciso ficaria pesado no cartão branco.
  final Color track;

  const Pal._({
    required this.panel,
    required this.hud,
    required this.card,
    required this.chip,
    required this.border,
    required this.muted,
    required this.heading,
    required this.chipText,
    required this.hardShadow,
    required this.track,
  });

  static const dark = Pal._(
    panel: Color(0xFF14102E),
    hud: Color(0xFF2F2578),
    card: Color(0xFF241C5C),
    chip: Color(0xFF2F2578),
    border: Color(0xFF5B4BD6),
    muted: Color(0xFFB9B2F0),
    heading: Colors.white,
    chipText: Colors.white,
    hardShadow: Color(0xFF0A0820),
    track: Color(0x99000000),
  );

  static const light = Pal._(
    panel: Color(0xFFF4F1FF),
    hud: Colors.white,
    card: Colors.white,
    chip: Color(0xFFEDE8FF),
    border: Color(0xFFCFC6FF),
    muted: Color(0xFF5E5780),
    heading: Color(0xFF1B1530),
    chipText: Color(0xFF1B1530),
    hardShadow: Color(0x14000000),
    track: Color(0x4D000000),
  );

  static Pal of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;

  static bool _isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  /// Tinta verde de "você possui / concluído".
  ///
  /// O `#16A34A` do mock foi escolhido sobre branco: no cartão roxo escuro ele
  /// desce a ~3:1 e some. Cada brilho recebe o seu — vivo no escuro, queimado
  /// no claro. Para preenchimento (fundo de pílula) use [successFill].
  ///
  /// O verde do tema claro é o `#166534`: o `#15803D` passava de 4,5:1 sobre o
  /// cartão branco, mas caía a 4,2:1 sobre o `chip` lavanda, e as pílulas vivem
  /// nos dois fundos.
  static Color successInk(BuildContext context) =>
      _isDark(context) ? const Color(0xFF5BE38A) : const Color(0xFF166534);

  /// Fundo translúcido que combina com [successInk] na mesma pílula.
  static Color successFill(BuildContext context) => const Color(
    0xFF22C55E,
  ).withValues(alpha: _isDark(context) ? 0.20 : 0.14);

  /// Tinta dourada de troféu/liga.
  ///
  /// `Pal.gold` (`#FFC93C`) é um acento de superfície — sobre o branco do tema
  /// claro ele não tem contraste nenhum como texto ou ícone, então a versão de
  /// tinta queima no claro e fica viva no escuro. O tom claro é `#8A5600` para
  /// passar de 4,5:1 também sobre o `chip` lavanda, não só sobre o branco.
  static Color goldInk(BuildContext context) =>
      _isDark(context) ? const Color(0xFFFFB020) : const Color(0xFF8A5600);
}

/// Razão de contraste WCAG entre duas cores opacas (1:1 iguais, 21:1 no máximo).
double contrastRatio(Color foreground, Color background) {
  final a = foreground.computeLuminance();
  final b = background.computeLuminance();
  final hi = a > b ? a : b;
  final lo = a > b ? b : a;
  return (hi + 0.05) / (lo + 0.05);
}

/// Os fundos onde uma tinta de texto pode acabar pousada neste brilho.
///
/// Medir só contra `colorScheme.surface` era o buraco: o `chip` lavanda do tema
/// claro e o `hud` roxo do tema escuro são mais claros que a superfície, e uma
/// tinta aprovada no branco caía abaixo de 4,5:1 neles.
List<Color> inkSurfaces(BuildContext context) {
  final theme = Theme.of(context);
  final pal = Pal.of(context);
  return [
    theme.colorScheme.surface,
    theme.scaffoldBackgroundColor,
    pal.panel,
    pal.card,
    pal.hud,
    pal.chip,
  ];
}

/// Menor contraste de [ink] contra qualquer fundo de [inkSurfaces].
double contrastOnSurfaces(Color ink, BuildContext context) {
  var worst = double.infinity;
  for (final surface in inkSurfaces(context)) {
    final ratio = contrastRatio(ink, surface);
    if (ratio < worst) worst = ratio;
  }
  return worst;
}

/// Tinta legível sobre um fundo de acento: devolve o candidato de maior
/// contraste WCAG. Fixar `Pal.onAccent` deixava o texto abaixo de 4:1 sobre o
/// teal da rota e sobre o azul da equipe; branco passa de 4,5:1 nesses fundos.
Color inkOnAccent(Color background) =>
    contrastRatio(Pal.onAccent, background) >=
            contrastRatio(Colors.white, background)
    ? Pal.onAccent
    : Colors.white;

/// Tinta de um acento que precisa se ler sobre a superfície do tema.
///
/// A cor não nasce do tema: vem da categoria de uma insígnia, da liga do
/// jogador, de uma faixa do servidor — todas desenhadas sobre o cartão escuro
/// do mock. Solta no tema claro, o amarelo e o ciano dessas paletas ficam abaixo
/// de 2:1 sobre o branco. Isto queima a cor em direção ao preto (ou ao branco,
/// no escuro) até passar de 4,5:1, mantendo o matiz.
///
/// O alvo é o pior fundo do brilho ([contrastOnSurfaces]), não só a superfície:
/// assim a mesma tinta se lê no cartão, no `chip` e na barra do HUD.
///
/// Use para texto e ícone. Preenchimento de fundo continua com a cor crua.
Color legibleInk(Color accent, BuildContext context) {
  final toward = Theme.of(context).brightness == Brightness.dark
      ? Colors.white
      : const Color(0xFF000000);
  var ink = accent;
  // Doze passos de 15% levam a cor de 100% do matiz a ~15%: chega no pior caso
  // da paleta (ciano `#22D3EE`) sem virar cinza.
  for (var step = 0;
      step < 12 && contrastOnSurfaces(ink, context) < 4.5;
      step++) {
    ink = Color.lerp(ink, toward, 0.15)!;
  }
  return ink;
}

// ============================================================ Formas

/// O contorno de um hexágono — a forma do território em todo o jogo (base da
/// equipe, mapa da placa, emblema da liga, insígnia).
///
/// [startAngle] é o ângulo do primeiro vértice: `-π/2` dá a ponta para cima
/// (o hexágono dos mapas), `0` dá a ponta para a direita (a trama de carbono do
/// avatar). Passar isso em vez de manter cinco cópias do laço é o que permite
/// comparar um hexágono com o outro sem reescrever trigonometria.
Path hexagonPath(
  Offset center,
  double radius, {
  double startAngle = -math.pi / 2,
}) {
  final path = Path();
  for (var i = 0; i < 6; i++) {
    final angle = startAngle + i * math.pi / 3;
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
  return path..close();
}

// ============================================================ Gradientes

/// Gradientes verticais dos cartões de modo e dos botões de moeda.
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

  /// Barra do título (CORRIDAS, TEMPORADA DE OUTUBRO).
  static const header = LinearGradient(
    colors: [Color(0xFFFF7F4D), Color(0xFFE5367A)],
  );

  /// Faixa do HUD da home, atrás do avatar, da sequência e das dracmas.
  static const hud = LinearGradient(
    colors: [Color(0xFF6D28D9), Color(0xFF9C2A8F)],
  );

  /// Preenchimento das barras de progresso.
  static const progress = LinearGradient(
    colors: [Color(0xFF8CF2D6), Color(0xFF3DDBB0)],
  );

  /// Painel do "próxima meta" da semana.
  static const goal = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFF9A4D), Color(0xFFE8452C)],
  );
}

/// Raridade dos desafios do dia: define as cores do cartão.
enum Rarity {
  common('COMUM', Color(0xFF3F8CFF), Color(0xFF1E4FB8)),
  rare('RARO', Color(0xFF9B6BFF), Color(0xFF5B2FC0)),
  epic('ÉPICO', Color(0xFFFFB21A), Color(0xFFE8452C));

  const Rarity(this.label, this.from, this.to);
  final String label;
  final Color from, to;

  LinearGradient get gradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [from, to],
  );
}

/// Sombra dura dos títulos brancos sobre gradiente.
const kTextShadow = [Shadow(color: Color(0x4D000000), offset: Offset(0, 2))];

// ============================================================ Moeda

/// A moeda dracma: círculo dourado com o "D" da moeda, desenhado em vez de
/// ícone Material para bater com o cartão do mercado e o pill do HUD.
///
/// [onGold] inverte as tintas para usar dentro de um cartão já dourado.
class DracmaCoin extends StatelessWidget {
  const DracmaCoin({super.key, this.size = 22, this.onGold = false});

  final double size;
  final bool onGold;

  @override
  Widget build(BuildContext context) {
    final fill = onGold ? const Color(0xFFF7DE8A) : null;
    final gradient = onGold
        ? null
        : const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFE08A), Color(0xFFE9A81C)],
          );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill,
        gradient: gradient,
        border: Border.all(
          color: onGold ? const Color(0xFF7A5A08) : const Color(0xFF9A6A06),
          width: (size * 0.09).clamp(1.5, 4.0),
        ),
      ),
      child: Center(
        child: Text(
          'D',
          style: TextStyle(
            fontSize: size * 0.56,
            height: 1,
            fontWeight: FontWeight.w900,
            color: const Color(0xFF3A2A00),
          ),
        ),
      ),
    );
  }
}

// ============================================================ Cartão

/// Cartão com gradiente (ou cor sólida), borda e sombra dura embaixo.
class GameCard extends StatelessWidget {
  const GameCard({
    super.key,
    required this.child,
    this.gradient,
    this.color,
    this.padding = const EdgeInsets.all(12),
    this.radius = 18,
    this.borderColor,
    this.onTap,
  });

  final Widget child;
  final Gradient? gradient;
  final Color? color;
  final EdgeInsets padding;
  final double radius;

  /// Borda do cartão. Sem nada passado ela vem do fundo: branco translúcido
  /// sobre gradiente fixo e `pal.border` sobre cor sólida — a mesma tinta
  /// branca sobre o cartão branco do tema claro não é borda nenhuma.
  final Color? borderColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final border =
        borderColor ??
        (gradient != null
            ? const Color(0x2EFFFFFF)
            : Pal.of(context).border);
    final card = Container(
      decoration: BoxDecoration(
        gradient: gradient,
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border, width: 2),
        boxShadow: const [
          BoxShadow(color: Color(0x59000000), offset: Offset(0, 4)),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null) return card;
    return Semantics(
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap,
        child: card,
      ),
    );
  }
}

// ============================================================ Progresso

/// Barra grossa com preenchimento em gradiente e canto redondo.
class ChunkyProgress extends StatelessWidget {
  const ChunkyProgress({
    super.key,
    required this.value,
    this.height = 14,
    this.gradient,
  });

  /// 0 a 1.
  final double value;
  final double height;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (_, c) => Stack(
            children: [
              Positioned.fill(
                child: Container(
                  color: pal.track,
                ),
              ),
              TweenAnimationBuilder<double>(
                tween: Tween(end: value.clamp(0.0, 1.0)),
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOut,
                builder: (_, v, _) => Container(
                  // Largura mínima de 6 px: com progresso zero a barra ainda
                  // aparece, senão parece que o cartão está vazio.
                  width: (c.maxWidth * v).clamp(6.0, c.maxWidth),
                  decoration: BoxDecoration(
                    gradient: gradient ?? RGrad.progress,
                    borderRadius: BorderRadius.circular(height / 2),
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

// ============================================================ Botão 3D

/// Botão que afunda ao ser pressionado. `onPressed` nulo deixa o botão apagado
/// (contorno, sem sombra) — o modo aparece na tela sem fingir que dá para usar.
///
/// [ghost] é o mesmo contorno de um botão apagado, mas acionável: é o botão que
/// abre a explicação de um modo ainda sem regra, não um botão morto.
class GameButton extends StatefulWidget {
  const GameButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.background = Colors.white,
    this.foreground,
    this.compact = false,
    this.expand = false,
    this.shadow,
    this.ghost = false,
    this.big = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color background;

  /// Tinta do rótulo, nos dois estados. `null` escolhe a de maior contraste
  /// sobre [background] quando o botão tem enchimento e o brilho do tema
  /// quando não tem. Quem senta o botão sobre uma gradiente fixa passa a tinta
  /// branca: o brilho do tema é preto no claro e some no cartão escuro.
  final Color? foreground;
  final bool compact;

  /// Preenche a largura do pai (botão de cartão) em vez de abraçar o texto.
  final bool expand;
  final Color? shadow;
  final bool ghost;

  /// Corpo de botão de cartão: 16 px e mais respiro vertical.
  final bool big;

  @override
  State<GameButton> createState() => _GameButtonState();
}

class _GameButtonState extends State<GameButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final pal = Pal.of(context);
    // O botão fantasma nunca parece "apagado" no sentido de inerte: ele só não
    // tem enchimento nem sombra. A tinta vem do brilho, porque sobre o `hud`
    // branco do tema claro uma borda branca não é botão nenhum.
    final filled = enabled && !widget.ghost;
    final shadow = widget.shadow ?? widget.background.withValues(alpha: 0.6);
    // Tinta do contorno quando o botão não tem enchimento (fantasma ou apagado).
    final ink = widget.foreground ?? pal.heading;
    return Semantics(
      button: true,
      enabled: enabled,
      child: Opacity(
        opacity: enabled ? 1 : 0.72,
        child: GestureDetector(
          onTapDown: enabled ? (_) => setState(() => _down = true) : null,
          onTapUp: enabled ? (_) => setState(() => _down = false) : null,
          onTapCancel: enabled ? () => setState(() => _down = false) : null,
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            width: widget.expand ? double.infinity : null,
            transform: Matrix4.translationValues(0, _down ? 3 : 0, 0),
            padding: EdgeInsets.symmetric(
              horizontal: widget.compact ? 12 : 16,
              vertical: widget.big ? 14 : (widget.compact ? 6 : 11),
            ),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: filled ? widget.background : Colors.transparent,
              borderRadius: BorderRadius.circular(widget.compact ? 9 : 12),
              border: filled
                  ? null
                  : Border.all(
                    color: (widget.foreground ?? pal.muted).withValues(
                      alpha: 0.65,
                    ),
                    width: 2,
                  ),
              boxShadow: [
                if (filled)
                  BoxShadow(
                    color: shadow,
                    offset: Offset(0, _down ? 0 : 3),
                  ),
              ],
            ),
            child: Text(
              widget.label.toUpperCase(),
              textAlign: TextAlign.center,
              style: TextStyle(
                // [foreground] vale nos dois estados: sem ele o botão preenchido
                // escolhe a tinta de maior contraste e o apagado cai no brilho
                // do tema — que sobre um cartão de gradiente fixo é a tinta errada.
                color: filled
                    ? (widget.foreground ?? inkOnAccent(widget.background))
                    : ink,
                fontWeight: FontWeight.w800,
                letterSpacing: widget.big ? 1 : 0.5,
                fontSize: widget.compact ? 12 : (widget.big ? 16 : 14),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================ Animações leves

/// Faz o filho subir e descer devagar. Respeita "reduzir movimento".
class Bob extends StatefulWidget {
  const Bob({super.key, required this.child});

  final Widget child;

  @override
  State<Bob> createState() => _BobState();
}

class _BobState extends State<Bob> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat(reverse: true);

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
      builder: (_, child) => Transform.translate(
        offset: Offset(0, -4 * Curves.easeInOut.transform(_c.value)),
        child: child,
      ),
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

class _PulseGlowState extends State<PulseGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat(reverse: true);

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

/// Pílula de informação ("troca em 6h 24min"): texto curto, canto arredondado.
///
/// [onColored] diz onde ela está sentada. Sobre gradiente fixo (o cartão de
/// modo) ela é preta translúcida com texto branco, como no mock; sobre o painel
/// da tela ela vem do tema, porque 30% de preto sobre o lilás claro do tema
/// claro dá um cinza lamuriento e o branco de 12 px desaparece nele.
class InfoPill extends StatelessWidget {
  const InfoPill(this.text, {super.key, this.icon, this.onColored = false});

  final String text;
  final IconData? icon;
  final bool onColored;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final background = onColored ? const Color(0x4D000000) : pal.chip;
    final ink = onColored ? Colors.white : pal.heading;
    final iconColor = onColored ? const Color(0xFFFFD866) : pal.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: iconColor),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                color: ink,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Título de seção com a pílula de tempo alinhada à direita.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.pill, this.pillIcon});

  final String title;
  final String? pill;
  final IconData? pillIcon;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(
        child: Text(
          title.toUpperCase(),
          style: TextStyle(
            color: Pal.of(context).heading,
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
      ),
      if (pill != null) InfoPill(pill!, icon: pillIcon),
    ],
  );
}

/// Falha de carregamento visível e acionável, sem sumir com o resto da tela.
///
/// É o cartão que toda tela de leitura única mostra quando o `FutureBuilder`
/// vem com erro: a frase do servidor (pt-BR, com ponto) e o botão que refaz a
/// chamada. Um spinner girando para sempre não é estado de erro.
class ErrorBanner extends StatelessWidget {
  const ErrorBanner({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => GameCard(
    color: Pal.of(context).card,
    child: Row(
      children: [
        Expanded(
          child: Text(
            message,
            style: TextStyle(color: Pal.of(context).muted, fontSize: 13),
          ),
        ),
        const SizedBox(width: 12),
        GameButton(
          label: 'Tentar de novo',
          compact: true,
          background: Pal.team,
          onPressed: onRetry,
        ),
      ],
    ),
  );
}

/// Barra de título em gradiente, com os cantos de cima arredondados.
class GradientBar extends StatelessWidget {
  const GradientBar({
    super.key,
    required this.title,
    this.trailing,
    this.leading,
    this.radius = 26,
  });

  final String title;
  final Widget? trailing;
  final Widget? leading;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      gradient: RGrad.header,
      borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
      boxShadow: const [
        BoxShadow(color: Color(0x40000000), offset: Offset(0, 3)),
      ],
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 14, 16),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
                shadows: kTextShadow,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    ),
  );
}

// ============================================================ Personagens

/// Os seis personagens do jogo, desenhados em SVG embutido no código: sem
/// arquivo em `assets`, sem binário novo no pacote, e a arte escala com o
/// tamanho do cartão.
enum RCharacter { hexi, zona, turbo, pit, coach, lenda }

/// Retrato de um personagem. [bob] faz ele flutuar devagar (o mascote do
/// cartão de destaque); em tela com animação em loop, deixe `false`.
class CharacterAvatar extends StatelessWidget {
  const CharacterAvatar(this.character, {
    super.key,
    this.size = 60,
    this.bob = false,
  });

  final RCharacter character;
  final double size;
  final bool bob;

  @override
  Widget build(BuildContext context) {
    final art = SvgPicture.string(
      _svgs[character]!,
      width: size,
      height: size,
    );
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

const _open =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">'
    '<g stroke="#1c1220" stroke-width="3" stroke-linejoin="round" stroke-linecap="round">';
const _close = '</g></svg>';

const _svgs = <RCharacter, String>{
  RCharacter.hexi: '$_open'
      '<polygon points="50,8 90,30 90,72 50,94 10,72 10,30" fill="#B0246A"/>'
          '<polygon points="50,8 90,30 50,52 10,30" fill="#D14A90" stroke="none"/>'
          '<polygon transform="translate(50 29) scale(0.6)" fill="#fff" points="0,-14 3.4,-4.7 13.3,-4.3 5.5,1.8 8.2,11.3 0,5.8 -8.2,11.3 -5.5,1.8 -13.3,-4.3 -3.4,-4.7"/>'
          '<ellipse cx="36" cy="62" rx="8" ry="9.5" fill="#fff"/><ellipse cx="64" cy="62" rx="8" ry="9.5" fill="#fff"/>'
          '<circle cx="38" cy="64" r="4.2" fill="#1c1220" stroke="none"/><circle cx="66" cy="64" r="4.2" fill="#1c1220" stroke="none"/>'
          '<path d="M38,79 Q50,92 62,79Z" fill="#fff"/>'
      '$_close',
  RCharacter.zona: '$_open'
      '<circle cx="22" cy="40" r="9" fill="#5a2f1c"/>'
      '<path d="M12,100 Q12,76 50,76 Q88,76 88,100Z" fill="#FF7F4D"/>'
      '<circle cx="50" cy="48" r="25" fill="#f2b48a"/>'
      '<path d="M25,46 Q23,20 50,20 Q77,20 75,46 Q64,33 50,35 Q36,33 25,46Z" fill="#5a2f1c"/>'
      '<ellipse cx="40" cy="52" rx="4.5" ry="6" fill="#fff" stroke-width="2.5"/><ellipse cx="60" cy="52" rx="4.5" ry="6" fill="#fff" stroke-width="2.5"/>'
      '<circle cx="41" cy="53" r="2.4" fill="#1c1220" stroke="none"/><circle cx="61" cy="53" r="2.4" fill="#1c1220" stroke="none"/>'
      '<path d="M42,64 Q50,74 58,64Z" fill="#fff"/>'
      '$_close',
  RCharacter.turbo: '$_open'
      '<path d="M12,100 Q12,76 50,76 Q88,76 88,100Z" fill="#FFC93C"/>'
      '<rect x="26" y="88" width="48" height="8" fill="#e53935" stroke="none"/>'
      '<circle cx="50" cy="50" r="26" fill="#8d5a3b"/>'
      '<path d="M23,52 Q22,16 50,16 Q78,16 77,52 L77,56 Q50,48 23,56Z" fill="#FFC93C"/>'
      '<path d="M45,16 L55,16 L55,38 L45,38Z" fill="#e53935" stroke="none"/>'
      '<rect x="26" y="38" width="48" height="21" rx="10" fill="#1d2a4a"/>'
      '<ellipse cx="39" cy="48" rx="5" ry="6" fill="#fff" stroke="none"/><ellipse cx="61" cy="48" rx="5" ry="6" fill="#fff" stroke="none"/>'
      '<circle cx="40" cy="49" r="2.5" fill="#1c1220" stroke="none"/><circle cx="62" cy="49" r="2.5" fill="#1c1220" stroke="none"/>'
      '<path d="M40,69 Q50,79 60,69Z" fill="#fff"/>'
      '$_close',
  RCharacter.pit: '$_open'
      '<path d="M12,100 Q12,76 50,76 Q88,76 88,100Z" fill="#22b58e"/>'
      '<circle cx="50" cy="50" r="26" fill="#e0a97a"/>'
      '<path d="M24,48 Q24,18 50,18 Q76,18 76,48Z" fill="#169a77"/>'
      '<path d="M28,46 L86,46 Q91,50 84,54 L28,54Z" fill="#169a77"/>'
      '<path d="M24,56 Q22,16 50,16 Q78,16 76,56" fill="none" stroke="#2b2f3a" stroke-width="4"/>'
      '<circle cx="24" cy="58" r="6" fill="#2b2f3a"/><circle cx="76" cy="58" r="6" fill="#2b2f3a"/>'
      '<ellipse cx="40" cy="60" rx="4.5" ry="6" fill="#fff" stroke-width="2.5"/><ellipse cx="60" cy="60" rx="4.5" ry="6" fill="#fff" stroke-width="2.5"/>'
      '<circle cx="41" cy="61" r="2.4" fill="#1c1220" stroke="none"/><circle cx="61" cy="61" r="2.4" fill="#1c1220" stroke="none"/>'
      '<path d="M40,72 Q50,82 60,72Z" fill="#fff"/>'
      '$_close',
  RCharacter.coach: '$_open'
      '<path d="M12,100 Q12,76 50,76 Q88,76 88,100Z" fill="#4A6FA5"/>'
      '<rect x="42" y="82" width="16" height="10" rx="5" fill="#FFC93C" stroke-width="2.5"/>'
      '<circle cx="50" cy="48" r="25" fill="#c68a5e"/>'
      '<path d="M24,44 Q24,18 50,18 Q76,18 76,44Z" fill="#1f3558"/>'
      '<path d="M26,42 L82,42 Q87,46 80,51 L26,51Z" fill="#1f3558"/>'
      '<ellipse cx="40" cy="55" rx="4" ry="5" fill="#fff" stroke-width="2.5"/><ellipse cx="60" cy="55" rx="4" ry="5" fill="#fff" stroke-width="2.5"/>'
      '<circle cx="41" cy="56" r="2.2" fill="#1c1220" stroke="none"/><circle cx="61" cy="56" r="2.2" fill="#1c1220" stroke="none"/>'
      '<path d="M38,67 Q44,62 50,67 Q56,62 62,67 Q56,72 50,69 Q44,72 38,67Z" fill="#3a2a22" stroke-width="2.5"/>'
      '$_close',
  RCharacter.lenda: '$_open'
      '<circle cx="50" cy="14" r="11" fill="#e6e8ee"/>'
      '<path d="M12,100 Q12,76 50,76 Q88,76 88,100Z" fill="#FFB21A"/>'
      '<circle cx="42" cy="90" r="6" fill="#FFE066" stroke-width="2.5"/><circle cx="58" cy="90" r="6" fill="#cfd5e3" stroke-width="2.5"/>'
      '<circle cx="50" cy="48" r="25" fill="#b9825d"/>'
      '<path d="M25,46 Q23,20 50,20 Q77,20 75,46 Q64,33 50,35 Q36,33 25,46Z" fill="#e6e8ee"/>'
      '<path d="M27,40 Q50,28 73,40 L72,45 Q50,34 28,45Z" fill="#FF4D8D" stroke-width="2.5"/>'
      '<ellipse cx="40" cy="53" rx="4.5" ry="5.5" fill="#fff" stroke-width="2.5"/><ellipse cx="60" cy="53" rx="4.5" ry="5.5" fill="#fff" stroke-width="2.5"/>'
      '<circle cx="41" cy="54" r="2.4" fill="#1c1220" stroke="none"/><circle cx="61" cy="54" r="2.4" fill="#1c1220" stroke="none"/>'
      '<path d="M41,64 Q50,72 59,64" fill="none"/>'
      '$_close',
};
