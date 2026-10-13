import 'package:flutter/material.dart';

import '../format.dart';
import '../models.dart';
import 'banner_plate.dart';
import 'cosmetics.dart';
import 'emoticon_pieces.dart';
import 'runover_ui.dart';

/// Fileira de oferta: arte em caixa de raridade,
/// nome + selos no meio e botão verde de preço à direita.
///
/// Usada pela loja pessoal e pela loja da equipe (que passa seu ícone
/// de preço e a trava de permissão).
class OfferRow extends StatelessWidget {
  const OfferRow({
    super.key,
    required this.item,
    this.subtitle,
    required this.owned,
    required this.equipped,
    required this.busy,
    this.locked = false,
    required this.priceIcon,
    required this.onOpen,
    required this.onBuy,
    required this.onEquip,
  });

  final ShopItem item;
  final String? subtitle;
  final bool owned;
  final bool equipped;
  final bool busy;
  final bool locked;
  final IconData priceIcon;
  final VoidCallback onOpen;
  final VoidCallback onBuy;
  final VoidCallback onEquip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tier = tierFor(item);
    final isBundle = item.category == 'bundle';
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              OfferArt(item: item),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${tier.label} · ${_categoryLabel(item)}'
                          .toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: legibleInk(tier.accent, context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 6),
                    _OfferBadges(item: item, owned: owned, equipped: equipped),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _OfferPriceButton(
                item: item,
                owned: owned,
                equipped: equipped,
                isBundle: isBundle,
                busy: busy,
                locked: locked,
                priceIcon: priceIcon,
                onBuy: onBuy,
                onEquip: onEquip,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _categoryLabel(ShopItem item) {
  return switch (item.category) {
    'avatar' => 'Avatar',
    'frame' => 'Moldura',
    'effect' => 'Efeito',
    'banner' => 'Faixa',
    'name_style' => 'Nome',
    'emoticon' => 'Emoticon',
    'bundle' => 'Pacote',
    _ => item.category,
  };
}

/// Raridade pela faixa de preço, com as cores do cartão.
///
/// [accent] é a cor-crua da raridade: o rótulo e a caixa de arte passam por
/// `legibleInk`, que escolhe a tinta legível dela sobre o cartão do tema. Ela
/// agora é o topo do gradiente [background] — a raridade é uma cor só, e um
/// rótulo de outra família ao lado do cartão da mesma faixa se contradiz.
/// [background] é o enchimento do cartão, por cima do qual mora texto branco,
/// então os dois topos têm de passar de 4,5:1 com o branco. As cores vivas do
/// mock (`#3F8CFF`, `#FFB21A`) ficam em 3,3:1 e 1,8:1: são cor de rótulo sobre
/// branco, não cor de cartão com texto em cima.
class OfferTier {
  const OfferTier(this.label, this.accent, this.background);

  final String label;
  final Color accent;
  final List<Color> background;

  LinearGradient get gradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: background,
  );
}

OfferTier tierFor(ShopItem item) {
  final price = item.price;
  if (price < 200) {
    return const OfferTier(
      'Comum',
      Color(0xFF2563EB),
      [Color(0xFF2563EB), Color(0xFF1E3A8A)],
    );
  }
  if (price < 600) {
    return const OfferTier(
      'Raro',
      Color(0xFF7C3AED),
      [Color(0xFF7C3AED), Color(0xFF4C1D95)],
    );
  }
  if (price < 1200) {
    return const OfferTier(
      'Épico',
      Color(0xFFC2410C),
      [Color(0xFFC2410C), Color(0xFF9A3412)],
    );
  }
  return const OfferTier(
    'Lendário',
    Color(0xFFFFC93C),
    [Color(0xFFB45309), Color(0xFF78350F)],
  );
}

/// Arte da oferta: caixa 84px na cor da raridade com a prévia animada.
class OfferArt extends StatelessWidget {
  const OfferArt({super.key, required this.item});

  final ShopItem item;

  @override
  Widget build(BuildContext context) {
    final tier = tierFor(item);
    return Container(
      width: 84,
      height: 84,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: tier.background,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.black.withValues(alpha: 0.25),
          width: 2,
        ),
      ),
      child: Center(
        child: ShopPreview(item: item, scale: 0.62, onDarkSurface: true),
      ),
    );
  }
}

/// Prévia do produto (tamanhos escaláveis para fileira e detalhes).
///
/// [onDarkSurface] é para as caixas de arte, cujo fundo é o gradiente fixo da
/// raridade e não o cartão do tema: o efeito desenhado ali precisa de tinta
/// clara, senão desaparece no azul-escuro.
class ShopPreview extends StatelessWidget {
  const ShopPreview({
    super.key,
    required this.item,
    this.scale = 1.0,
    this.onDarkSurface = false,
  });

  final ShopItem item;
  final double scale;
  final bool onDarkSurface;

  @override
  Widget build(BuildContext context) {
    return switch (item.category) {
      'avatar' => FramedAvatar(
        radius: 34 * scale,
        image: profileAvatarImage(null, item),
        fallbackLetter: item.name.isEmpty ? '?' : item.name[0],
        avatarItem: item,
      ),
      'frame' => FramedAvatar(
        radius: 34 * scale,
        fallbackLetter: 'V',
        frame: item,
      ),
      'banner' => Breathe(
        seed: item.id,
        child: Container(
          width: 120 * scale,
          height: 72 * scale,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          // A vitrine mostra a placa que o item é: só o gradiente deixaria
          // "faixa de vidro" e "faixa de carbono" com a mesma cara na loja.
          child: BannerPlate(
            banner: item,
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      'name_style' => Breathe(
        seed: item.id,
        child: Text(
          'Nome',
          style: styledName(
            'Nome',
            item,
            TextStyle(fontSize: 26 * scale, fontWeight: FontWeight.w800),
          ),
        ),
      ),
      // O efeito ocupa a caixa inteira: ele é o produto, não um rótulo dele.
      'effect' => LayoutBuilder(
        builder: (context, constraints) => SizedBox(
          width: constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : 132 * scale,
          height: constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : 96 * scale,
          child: ProfileEffectOverlay(
            effect: item,
            onDarkSurface: onDarkSurface,
          ),
        ),
      ),
      // A prévia é a própria peça do mural: material, gesto e rastro do pacote,
      // na escala da arte. Um `Text` de emoji não mostrava a diferença entre
      // "Pacote pulso" e "Pacote mola" antes do toque.
      'emoticon' => Wrap(
        alignment: WrapAlignment.center,
        spacing: 2,
        runSpacing: 2,
        children: [
          for (final glyph in _previewGlyphs(item))
            EmoticonPiece(
              glyph: glyph,
              pack: item,
              fontSize: 30 * scale,
              onDarkSurface: onDarkSurface,
            ),
        ],
      ),
      'bundle' => BundleCover(item: item, scale: scale),
      _ => const Icon(Icons.style_outlined, size: 40),
    };
  }
}

/// Os glifos que a prévia do pacote mostra: no máximo três, para a arte
/// continuar uma caixa e não uma tira. Item sem lista de glifos é anomalia de
/// catálogo — cai no único emoji que a vitrine sempre usou.
List<String> _previewGlyphs(ShopItem item) {
  final glyphs = emoticonGlyphs(item);
  return (glyphs.isEmpty ? const ['🎽'] : glyphs).take(3).toList();
}

/// Capa do pacote: as cartas que ele libera, em leque, na cor do `colors` do
/// item. Cem pacotes com a mesma caixa de emoji não se distinguem antes do
/// toque, e o catálogo já dá capa própria a cada um.
class BundleCover extends StatelessWidget {
  const BundleCover({
    super.key,
    required this.item,
    this.scale = 1.0,
  });

  final ShopItem item;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final gradient = bannerGradient(item);
    final grants = (item.payload['grants'] as List? ?? const []).length;
    // Uma carta de frente sempre existe; o leque tem no máximo as três que o
    // pacote libera.
    final count = grants < 1 ? 1 : (grants > 3 ? 3 : grants);
    return SizedBox(
      width: 78 * scale,
      height: 62 * scale,
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (var i = 0; i < count; i++)
            // A carta da frente fica reta; as de trás saem do leque e sobem.
            Transform.rotate(
              angle: (count - 1 - i) * -0.18,
              child: Transform.translate(
                offset: Offset(
                  (count - 1 - i) * -5 * scale,
                  (count - 1 - i) * 4 * scale,
                ),
                child: Container(
                  width: 44 * scale,
                  height: 40 * scale,
                  decoration: BoxDecoration(
                    gradient: gradient,
                    borderRadius: BorderRadius.circular(8 * scale),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Os nomes dos itens que um pacote libera, na ordem do `grants` do payload.
///
/// Única leitura de `grants` para exibição — a linha da loja e a ficha de
/// detalhes, nas duas lojas, resolvem por aqui. Um id que o catálogo informado
/// não conhece fica de fora: identificador interno não aparece na interface, e
/// uma lista de presentes escrita em código confunde mais do que informa. Pacote
/// com nada resolvido devolve lista vazia, e quem mostra perde a seção inteira.
List<String> grantNames(ShopItem item, List<ShopItem> catalog) {
  final grants = item.payload['grants'] as List? ?? const [];
  return [for (final id in grants) findItem(catalog, '$id')?.name]
      .nonNulls
      .toList();
}

/// Botão verde de preço estilo CR (vira Equipar/Equipada quando é seu).
class _OfferPriceButton extends StatelessWidget {
  const _OfferPriceButton({
    required this.item,
    required this.owned,
    required this.equipped,
    required this.isBundle,
    required this.busy,
    required this.locked,
    required this.priceIcon,
    required this.onBuy,
    required this.onEquip,
  });

  final ShopItem item;
  final bool owned;
  final bool equipped;
  final bool isBundle;
  final bool busy;
  final bool locked;
  final IconData priceIcon;
  final VoidCallback onBuy;
  final VoidCallback onEquip;

  @override
  Widget build(BuildContext context) {
    // O verde aqui é enchimento sólido do botão de compra, não o selo de
    // "você possui": a tinta precisa ser a de maior contraste sobre ele, porque
    // branco sobre #22C55E fica em ~2,3:1 nos dois temas.
    const green = Color(0xFF22C55E);
    const darkGreen = Color(0xFF15803D);
    if (!owned) {
      return FilledButton(
        onPressed: busy ? null : onBuy,
        style: FilledButton.styleFrom(
          backgroundColor: green,
          foregroundColor: inkOnAccent(green),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: darkGreen, width: 2),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (locked)
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(Icons.lock_outline, size: 14),
              )
            else
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(priceIcon, size: 16),
              ),
            Text(
              item.price == 0 ? 'Resgatar' : formatPoints(item.price),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ],
        ),
      );
    }
    if (isBundle) {
      return const _OfferOwnedChip(label: 'Na coleção');
    }
    if (equipped) {
      return FilledButton.tonal(
        onPressed: busy ? null : onEquip,
        style: FilledButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check, size: 16),
            SizedBox(width: 4),
            Text('Equipada'),
          ],
        ),
      );
    }
    return OutlinedButton(
      onPressed: busy ? null : onEquip,
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
      ),
      child: const Text('Equipar'),
    );
  }
}

/// Selos da oferta: estado de posse/coleção e marca de parceria.
/// Compartilhado pela fileira e pelo card da grade.
class _OfferBadges extends StatelessWidget {
  const _OfferBadges({
    required this.item,
    required this.owned,
    required this.equipped,
  });

  final ShopItem item;
  final bool owned;
  final bool equipped;

  @override
  Widget build(BuildContext context) {
    // Os selos de posse vêm da família verde do kit (tinta + fundo translúcido
    // por brilho); 'Parceria' mantém o roxo sólido e ganha tinta por contraste.
    final ownedFill = Pal.successFill(context);
    final ownedInk = Pal.successInk(context);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        if (equipped)
          _OfferPill(
            label: 'Equipada',
            color: ownedFill,
            ink: ownedInk,
          )
        else if (item.category == 'bundle' && owned)
          _OfferPill(
            label: 'Na coleção',
            color: ownedFill,
            ink: ownedInk,
          ),
        if (item.payload['collection'] == 'parceria')
          const _OfferPill(label: 'Parceria', color: Pal.purple),
      ],
    );
  }
}

/// Selo de raridade: pílula clara no canto do cartão.
class _TierSeal extends StatelessWidget {
  const _TierSeal({required this.label, this.color = Colors.white});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.6,
          color: inkOnAccent(color),
        ),
      ),
    );
  }
}

/// A caixa de arte sobre o cartão colorido: branco translúcido em vez da cor
/// da raridade, que já é o fundo do cartão inteiro.
class _OfferArtTile extends StatelessWidget {
  const _OfferArtTile({required this.item});

  final ShopItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 92,
      height: 92,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Center(
        child: ShopPreview(item: item, scale: 0.68, onDarkSurface: true),
      ),
    );
  }
}

/// Botão de preço sobre o cartão colorido: pílula escurecida, moeda dourada.
///
/// O verde de [_OfferPriceButton] é a tinta da fileira, que vive sobre o cartão
/// do tema. Sobre o gradiente da raridade ele viria cor sobre cor.
class _GradientBuyButton extends StatelessWidget {
  const _GradientBuyButton({
    required this.item,
    required this.busy,
    required this.locked,
    required this.priceIcon,
    required this.onBuy,
  });

  final ShopItem item;
  final bool busy;
  final bool locked;
  final IconData priceIcon;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: busy ? null : onBuy,
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0x4D000000),
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0x33000000),
        disabledForegroundColor: Colors.white70,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (locked)
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child: Icon(Icons.lock_outline, size: 16),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(priceIcon, size: 18, color: Pal.gold),
            ),
          Text(
            item.price == 0 ? 'Resgatar' : formatPoints(item.price),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

/// Botão branco de posse, no rodapé do cartão colorido. Sempre aciona algo:
/// equipar ou tirar do equipamento.
class _GradientOwnButton extends StatelessWidget {
  const _GradientOwnButton({
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: inkOnAccent(Colors.white),
        disabledBackgroundColor: Colors.white70,
        disabledForegroundColor: const Color(0xB3000000),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 6)],
          Text(
            label,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

/// Rodapé de posse sem ação: o pacote já é seu e não existe equipar pacote.
/// É pílula, não botão, porque botão que não faz nada engana o toque.
class _GradientOwnedPill extends StatelessWidget {
  const _GradientOwnedPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0x4D000000),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// Card de oferta para a grade da loja em telas largas: o cartão é a cor da
/// raridade, com o selo no canto, a arte grande no meio, o nome e o preço em
/// baixo. Mesmos dados e ações da [OfferRow], só muda a geometria.
class OfferCard extends StatelessWidget {
  const OfferCard({
    super.key,
    required this.item,
    this.subtitle,
    required this.owned,
    required this.equipped,
    required this.busy,
    this.locked = false,
    required this.balance,
    required this.priceIcon,
    required this.onOpen,
    required this.onBuy,
    required this.onEquip,
  });

  final ShopItem item;
  final String? subtitle;
  final bool owned;
  final bool equipped;
  final bool busy;
  final bool locked;

  /// Saldo atual: quando o preço passa dele o cartão diz quantos dracmas faltam
  /// em vez de deixar a pessoa descobrir no toque.
  final int balance;
  final IconData priceIcon;
  final VoidCallback onOpen;
  final VoidCallback onBuy;
  final VoidCallback onEquip;

  @override
  Widget build(BuildContext context) {
    final tier = tierFor(item);
    final isBundle = item.category == 'bundle';
    final missing = item.price - balance;
    final canEquip = owned && !isBundle;
    return GameCard(
      gradient: tier.gradient,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // `Wrap`, não `Row`: com os dois selos e a fonte ampliada, a linha
          // única passava da borda do cartão e o `Clip` do gradiente comia o
          // selo de parceria. Sem espaço, o segundo selo desce de linha.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 6,
            runSpacing: 4,
            children: [
              _TierSeal(label: tier.label),
              if (item.payload['collection'] == 'parceria')
                const _TierSeal(label: 'Parceria', color: Pal.purple),
            ],
          ),
          const SizedBox(height: 10),
          Center(child: _OfferArtTile(item: item)),
          const SizedBox(height: 8),
          Text(
            item.name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: Colors.white,
              shadows: kTextShadow,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: Colors.white70),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const Spacer(),
          Center(
            child: canEquip
                ? equipped
                      ? _GradientOwnButton(
                          label: 'Equipada',
                          icon: Icons.check,
                          onPressed: busy ? null : onEquip,
                        )
                      : _GradientOwnButton(
                          label: 'Equipar',
                          onPressed: busy ? null : onEquip,
                        )
                : owned
                ? const _GradientOwnedPill(label: 'Na coleção')
                : _GradientBuyButton(
                    item: item,
                    busy: busy,
                    locked: locked,
                    priceIcon: priceIcon,
                    onBuy: onBuy,
                  ),
          ),
          if (!owned && missing > 0) ...[
            const SizedBox(height: 4),
            Text(
              'Faltam ${formatPoints(missing)}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                shadows: kTextShadow,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OfferPill extends StatelessWidget {
  const _OfferPill({required this.label, required this.color, this.ink});

  final String label;

  /// Fundo do selo.
  final Color color;

  /// Tinta do rótulo. Sem ela o selo é um enchimento sólido de cor externa e a
  /// tinta vem de `inkOnAccent`; os selos de posse passam a do [Pal].
  final Color? ink;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: ink ?? inkOnAccent(color),
        ),
      ),
    );
  }
}

class _OfferOwnedChip extends StatelessWidget {
  const _OfferOwnedChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Pal.successFill(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle,
            size: 16,
            color: Pal.successInk(context),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Pal.successInk(context),
            ),
          ),
        ],
      ),
    );
  }
}
