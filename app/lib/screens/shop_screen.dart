import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../format.dart';
import '../models.dart';
import '../services/api_client.dart';
import '../state/app_state.dart';
import '../widgets/centered_content.dart';
import '../widgets/cosmetics.dart';
import '../widgets/offer_row.dart';
import 'app_footer.dart';

/// Mercado interno: moedinhas, catálogo (via API), compra e equipamento.
///
/// Vitrine estilo loja de aplicativo: saldo em destaque, busca, abas por
/// categoria com contadores, carrossel de pacotes em destaque, grade de
/// produtos com prévia generosa e ficha de detalhes ao tocar.
class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

/// Acentos fixos da loja (iguais no claro e no escuro).
class _ShopColors {
  static const gold = Color(0xFFFFC93C);
  static const orange = Color(0xFFFF7F4D);
  static const teal = Color(0xFF3DDBB0);
  static const purple = Color(0xFF8B7CFF);
  static const onAccent = Color(0xFF1A0E08);
}

/// Seções da biblioteca da loja.
class _ShopSection {
  const _ShopSection(this.value, this.label, this.icon);
  final String value;
  final String label;
  final IconData icon;
}

const _sections = [
  _ShopSection('tudo', 'Tudo', Icons.storefront),
  _ShopSection('avatar', 'Avatares', Icons.face),
  _ShopSection('placas', 'Placas', Icons.badge),
  _ShopSection('effect', 'Efeitos', Icons.auto_awesome),
  _ShopSection('frame', 'Molduras', Icons.crop_square),
  _ShopSection('emoticon', 'Emoticons', Icons.emoji_emotions),
  _ShopSection('bundle', 'Pacotes', Icons.inventory_2),
  _ShopSection('orbs', 'Dracmas', Icons.monetization_on),
  _ShopSection('parceria', 'Parcerias', Icons.handshake),
];

const _sortOptions = [
  ('relevancia', 'Destaques'),
  ('preco_asc', 'Menor preço'),
  ('preco_desc', 'Maior preço'),
  ('nome', 'Nome A–Z'),
];

const _categoryLabels = {
  'avatar': 'Avatar',
  'frame': 'Moldura',
  'effect': 'Efeito',
  'banner': 'Faixa',
  'name_style': 'Nome',
  'emoticon': 'Emoticon',
  'bundle': 'Pacote',
};

/// Cor de destaque por categoria (fundo da prévia + selos).
Color _accentFor(ShopItem item) {
  return switch (item.category) {
    'avatar' => _ShopColors.purple,
    'frame' => _ShopColors.orange,
    'effect' => _ShopColors.teal,
    'banner' => const Color(0xFF0EA5E9),
    'name_style' => _ShopColors.gold,
    'emoticon' => const Color(0xFFEC4899),
    'bundle' => const Color(0xFF22C55E),
    _ => _ShopColors.gold,
  };
}

bool _inSection(ShopItem item, String section, int balance) {
  return switch (section) {
    'tudo' => true,
    'avatar' => item.category == 'avatar',
    'placas' => item.category == 'banner' || item.category == 'name_style',
    'effect' => item.category == 'effect',
    'frame' => item.category == 'frame',
    'emoticon' => item.category == 'emoticon',
    'bundle' => item.category == 'bundle',
    // Orbs = moedinhas: o que dá para comprar com o saldo atual.
    'orbs' => item.price > 0 && item.price <= balance,
    'parceria' => item.payload['collection'] == 'parceria',
    _ => true,
  };
}

class _ShopScreenState extends State<ShopScreen> {
  late Future<_ShopData> _future;
  String _section = 'tudo';
  String _query = '';
  String _sort = 'relevancia';
  bool _busy = false;
  late final TextEditingController _searchController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    _future = _load(context.read<AppState>().api);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<_ShopData> _load(ApiClient api) async {
    final results = await Future.wait([
      // Só itens do usuário: equipe e passe têm vitrines próprias e a
      // compra aqui recusaria com 400.
      api.getShopCatalog(scope: 'user'),
      api.getInventory(),
      api.getWallet(),
    ]);
    return _ShopData(
      catalog: results[0] as List<ShopItem>,
      inventory: results[1] as Inventory,
      wallet: Map<String, dynamic>.from(results[2] as Map),
    );
  }

  void _reload() {
    setState(() {
      _future = _load(context.read<AppState>().api);
    });
  }

  /// Fileira compacta no celular, card de grade no web — mesmos dados e
  /// ações, só muda a geometria.
  Widget _offerTile(ShopItem item, _ShopData data, int balance, bool wide) {
    final owned = data.inventory.owned.contains(item.id);
    final equipped = data.inventory.isEquipped(item);
    void onOpen() => _openDetail(item, data, balance, data.catalog);
    void onBuy() => _buy(item, balance);
    void onEquip() => _equip(item, data.inventory);
    final subtitle = _bundleSubtitle(item, data.catalog);
    return wide
        ? OfferCard(
            item: item,
            subtitle: subtitle,
            owned: owned,
            equipped: equipped,
            busy: _busy,
            priceIcon: Icons.monetization_on,
            onOpen: onOpen,
            onBuy: onBuy,
            onEquip: onEquip,
          )
        : OfferRow(
            item: item,
            subtitle: subtitle,
            owned: owned,
            equipped: equipped,
            busy: _busy,
            priceIcon: Icons.monetization_on,
            onOpen: onOpen,
            onBuy: onBuy,
            onEquip: onEquip,
          );
  }

  Future<void> _buy(ShopItem item, int balance) async {
    if (balance < item.price) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dracmas insuficientes. Corra para ganhar mais!')),
      );
      return;
    }
    final app = context.read<AppState>();
    setState(() => _busy = true);
    try {
      await app.api.purchaseItem(item.id);
      await app.refreshProfile();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${item.name} comprado!')),
      );
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _equip(ShopItem item, Inventory inventory) async {
    final app = context.read<AppState>();
    setState(() => _busy = true);
    try {
      final equipped = inventory.isEquipped(item);
      await app.api.equipItem(item.category, equipped ? null : item.id);
      await app.refreshProfile();
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<ShopItem> _visible(List<ShopItem> catalog, int balance) {
    final q = _query.trim().toLowerCase();
    var items = catalog.where((i) => _inSection(i, _section, balance));
    if (q.isNotEmpty) {
      items = items.where((i) => i.name.toLowerCase().contains(q));
    }
    final list = items.toList();
    switch (_sort) {
      case 'preco_asc':
        list.sort((a, b) => a.price.compareTo(b.price));
      case 'preco_desc':
        list.sort((a, b) => b.price.compareTo(a.price));
      case 'nome':
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    return list;
  }

  void _openDetail(
    ShopItem item,
    _ShopData data,
    int balance,
    List<ShopItem> catalog,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => _ItemDetailSheet(
        item: item,
        balance: balance,
        catalog: catalog,
        owned: data.inventory.owned.contains(item.id),
        equipped: data.inventory.isEquipped(item),
        busy: _busy,
        onBuy: () {
          Navigator.of(sheetContext).pop();
          _buy(item, balance);
        },
        onEquip: () {
          Navigator.of(sheetContext).pop();
          _equip(item, data.inventory);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mercado')),
      body: CenteredContent(
        maxWidth: 1080,
        child: FutureBuilder<_ShopData>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    const Text('Não foi possível carregar o mercado.'),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              );
            }
            final data = snapshot.data!;
            final balance = (data.wallet['balance'] as num).toInt();
            final items = _visible(data.catalog, balance);
            final searching = _query.trim().isNotEmpty;
            final featured = (!searching &&
                    (_section == 'tudo' || _section == 'bundle'))
                ? items.where((i) => i.category == 'bundle').take(8).toList()
                : const <ShopItem>[];
            final counts = {
              for (final s in _sections)
                s.value: data.catalog
                    .where((i) => _inSection(i, s.value, balance))
                    .length,
            };
            // Largura da janela, não do conteúdo: o teto de 1080 só vale
            // acima do ponto de corte, então as duas medidas coincidem aqui.
            final wide = MediaQuery.sizeOf(context).width >= 720;
            // Altura fixa tem que acompanhar a escala de texto: com fonte
            // ampliada o card precisa de mais espaço para o botão não
            // cortar.
            final textScale = MediaQuery.textScalerOf(context).scale(1.0);

            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: _WalletHero(
                      balance: balance,
                      wallet: data.wallet,
                      catalog: data.catalog,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: _SearchSortRow(
                      query: _query,
                      controller: _searchController,
                      sort: _sort,
                      onQuery: (v) => setState(() => _query = v),
                      onSort: (v) => setState(() => _sort = v),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: _SectionTabs(
                    section: _section,
                    counts: counts,
                    onSelect: (v) => setState(() => _section = v),
                  ),
                ),
                if (featured.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _FeaturedBundles(
                      bundles: featured,
                      catalog: data.catalog,
                      inventory: data.inventory,
                      balance: balance,
                      busy: _busy,
                      onOpen: (item) =>
                          _openDetail(item, data, balance, data.catalog),
                      onBuy: (item) => _buy(item, balance),
                    ),
                  ),
                if (items.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 40, horizontal: 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            searching
                                ? Icons.search_off_outlined
                                : Icons.storefront_outlined,
                            size: 48,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            searching
                                ? 'Nenhum item encontrado para "$_query".'
                                : 'Nada por aqui ainda — corra para juntar dracmas!',
                            textAlign: TextAlign.center,
                          ),
                          if (searching) ...[
                            const SizedBox(height: 12),
                            OutlinedButton(
                              onPressed: () =>
                                  setState(() => _query = ''),
                              child: const Text('Limpar busca'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding:
                        const EdgeInsets.fromLTRB(20, 4, 20, 12),
                    sliver: wide
                        ? SliverGrid(
                            gridDelegate:
                                SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 300,
                              mainAxisExtent: 340 * textScale,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                            ),
                            delegate: SliverChildBuilderDelegate(
                              (context, index) => _offerTile(
                                  items[index], data, balance, wide),
                              childCount: items.length,
                            ),
                          )
                        : SliverList.separated(
                            itemCount: items.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) => _offerTile(
                                items[index], data, balance, wide),
                          ),
                  ),
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, 12, 20, 32),
                    child: AppFooter(),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ShopData {
  const _ShopData({
    required this.catalog,
    required this.inventory,
    required this.wallet,
  });
  final List<ShopItem> catalog;
  final Inventory inventory;
  final Map<String, dynamic> wallet;
}

/// "Inclui: A, B e C" para pacotes; null nas demais categorias.
String? _bundleSubtitle(ShopItem item, List<ShopItem> catalog) {
  if (item.category != 'bundle') return null;
  final grants = (item.payload['grants'] as List? ?? const []).map((e) => '$e');
  final names = [
    for (final id in grants)
      catalog.where((c) => c.id == id).map((c) => c.name).firstOrNull ??
          id,
  ];
  if (names.isEmpty) return null;
  return 'Inclui: ${names.join(', ')}';
}

/// Motivo do extrato em pt-BR. O servidor grava chaves internas
/// (`compra:avatar_corredor`, `passe:season:t3:cosmetic`), e id/chave
/// interna não aparece na UI: compra resolve pelo catálogo e o resto cai
/// num rótulo legível.
String walletReasonLabel(String reason, List<ShopItem> catalog) {
  final parts = reason.split(':');
  return switch (parts) {
    ['compra', final id] => findItem(catalog, id)?.name ?? 'Compra no mercado',
    ['passe', _, final tier, _] when tier.startsWith('t') =>
      'Recompensa do passe · nível ${tier.substring(1)}',
    ['passe', ...] => 'Compra do passe',
    ['distancia'] => 'Distância percorrida',
    ['conquista'] => 'Conquista de território',
    ['missao_diaria'] => 'Missão diária',
    ['streak'] => 'Sequência de dias',
    _ => 'Outro movimento',
  };
}

/// Saldo em destaque: cartão dourado com extrato recente.
class _WalletHero extends StatelessWidget {
  const _WalletHero({
    required this.balance,
    required this.wallet,
    required this.catalog,
  });
  final int balance;
  final Map<String, dynamic> wallet;
  final List<ShopItem> catalog;

  @override
  Widget build(BuildContext context) {
    // Transação malformada não derruba o cartão: valida antes de pegar as
    // duas mais recentes.
    final entries = <String>[];
    for (final t
        in (wallet['transactions'] as List? ?? const []).whereType<Map>()) {
      final rawDelta = t['delta'];
      if (rawDelta is! num) continue;
      final delta = rawDelta.toInt();
      final sign = delta > 0 ? '+' : '−';
      entries.add(
        '$sign${formatPoints(delta.abs())} · '
        '${walletReasonLabel('${t['reason']}', catalog)}',
      );
      if (entries.length == 2) break;
    }
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFC93C), Color(0xFFFF7F4D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SEU SALDO · DRACMAS',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: _ShopColors.onAccent,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      formatPoints(balance),
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: _ShopColors.onAccent,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'dracmas',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _ShopColors.onAccent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Ganhe correndo: km + conquistas + missão diária + sequência.',
                  style: TextStyle(
                      fontSize: 12, color: _ShopColors.onAccent),
                ),
                if (entries.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (final entry in entries)
                    Text(
                      entry,
                      style: const TextStyle(
                        fontSize: 11,
                        color: _ShopColors.onAccent,
                      ),
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.25),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.monetization_on,
              color: _ShopColors.onAccent,
              size: 40,
            ),
          ),
        ],
      ),
    );
  }
}

/// Busca por nome + ordenação.
class _SearchSortRow extends StatelessWidget {
  const _SearchSortRow({
    required this.controller,
    required this.query,
    required this.sort,
    required this.onQuery,
    required this.onSort,
  });
  final TextEditingController controller;
  final String query;
  final String sort;
  final ValueChanged<String> onQuery;
  final ValueChanged<String> onSort;

  @override
  Widget build(BuildContext context) {
    if (controller.text != query) controller.text = query;
    final sortLabel = _sortOptions
        .where((o) => o.$1 == sort)
        .map((o) => o.$2)
        .firstOrNull ?? 'Destaques';
    return Row(
      children: [
        Expanded(
          child: SearchBar(
            controller: controller,
            hintText: 'Buscar na loja…',
            leading: const Icon(Icons.search),
            trailing: query.isEmpty
                ? null
                : [
                    IconButton(
                      tooltip: 'Limpar busca',
                      icon: const Icon(Icons.close),
                      onPressed: () => onQuery(''),
                    ),
                  ],
            onChanged: onQuery,
            elevation: const WidgetStatePropertyAll(0),
          ),
        ),
        const SizedBox(width: 8),
        PopupMenuButton<String>(
          tooltip: 'Ordenar',
          initialValue: sort,
          onSelected: onSort,
          itemBuilder: (context) => [
            for (final o in _sortOptions)
              CheckedPopupMenuItem<String>(
                value: o.$1,
                checked: o.$1 == sort,
                child: Text(o.$2),
              ),
          ],
          child: Chip(
            avatar: const Icon(Icons.sort, size: 18),
            label: Text(sortLabel),
          ),
        ),
      ],
    );
  }
}

/// Abas de categoria com ícone e contador.
class _SectionTabs extends StatelessWidget {
  const _SectionTabs({
    required this.section,
    required this.counts,
    required this.onSelect,
  });
  final String section;
  final Map<String, int> counts;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          for (final s in _sections)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text('${s.label} · ${counts[s.value] ?? 0}'),
                avatar: Icon(
                  s.icon,
                  size: 18,
                  color: section == s.value
                      ? scheme.onSecondaryContainer
                      : scheme.onSurfaceVariant,
                ),
                selected: section == s.value,
                onSelected: (_) => onSelect(s.value),
              ),
            ),
        ],
      ),
    );
  }
}

/// Carrossel de pacotes em destaque.
class _FeaturedBundles extends StatelessWidget {
  const _FeaturedBundles({
    required this.bundles,
    required this.catalog,
    required this.inventory,
    required this.balance,
    required this.busy,
    required this.onOpen,
    required this.onBuy,
  });
  final List<ShopItem> bundles;
  final List<ShopItem> catalog;
  final Inventory inventory;
  final int balance;
  final bool busy;
  final ValueChanged<ShopItem> onOpen;
  final ValueChanged<ShopItem> onBuy;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Row(
            children: [
              Icon(Icons.star, color: _ShopColors.gold, size: 20),
              SizedBox(width: 6),
              Text(
                'Pacotes em destaque',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
        // Altura fixa acompanha a escala de texto: o card do pacote tem
        // nome, subtítulo, preço e botão, que crescem com a fonte.
        SizedBox(
          height: 176 * MediaQuery.textScalerOf(context).scale(1.0),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: bundles.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final item = bundles[index];
              final owned = inventory.owned.contains(item.id);
              return _FeaturedCard(
                item: item,
                subtitle: _bundleSubtitle(item, catalog),
                owned: owned,
                canAfford: balance >= item.price,
                busy: busy,
                onOpen: () => onOpen(item),
                onBuy: () => onBuy(item),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard({
    required this.item,
    required this.subtitle,
    required this.owned,
    required this.canAfford,
    required this.busy,
    required this.onOpen,
    required this.onBuy,
  });
  final ShopItem item;
  final String? subtitle;
  final bool owned;
  final bool canAfford;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final grants =
        (item.payload['grants'] as List? ?? const []).length;
    return SizedBox(
      width: 280,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: Row(
            children: [
              Container(
                width: 120,
                height: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF22C55E).withValues(alpha: 0.35),
                      const Color(0xFF22C55E).withValues(alpha: 0.08),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Text('📦', style: TextStyle(fontSize: 56)),
                    Positioned(
                      bottom: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '$grants itens',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        item.name,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle!,
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 8),
                      _PriceTag(price: item.price),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: owned
                            ? const _OwnedChip(label: 'Na coleção')
                            : FilledButton(
                                onPressed: busy ? null : onBuy,
                                style: FilledButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                ),
                                child: Text(
                                  item.price == 0
                                      ? 'Resgatar'
                                      : 'Comprar',
                                ),
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

/// Preço em pílula com ícone de moeda.
class _PriceTag extends StatelessWidget {
  const _PriceTag({required this.price});
  final int price;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (price == 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF22C55E).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Text(
          'Grátis',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: Color(0xFF16A34A),
          ),
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.monetization_on,
          color: _ShopColors.gold,
          size: 18,
        ),
        const SizedBox(width: 4),
        Text(
          formatPoints(price),
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: scheme.onSurface,
          ),
        ),
      ],
    );
  }
}

class _OwnedChip extends StatelessWidget {
  const _OwnedChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF22C55E).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle,
              size: 16, color: Color(0xFF16A34A)),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF16A34A),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});
  final String label;
  final Color color;

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
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// Zona de prévia do produto com fundo na cor da categoria.
class _PreviewZone extends StatelessWidget {
  const _PreviewZone({required this.item, required this.height});
  final ShopItem item;
  final double height;

  @override
  Widget build(BuildContext context) {
    final accent = _accentFor(item);
    return Container(
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: 0.28),
            accent.withValues(alpha: 0.06),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Center(child: ShopPreview(item: item)),
          if (item.category == 'effect')
            Positioned.fill(
              child: ProfileEffectOverlay(effect: item),
            ),
          if (item.payload['collection'] == 'parceria')
            const Positioned(
              top: 6,
              left: 6,
              child: _StatusPill(
                  label: 'Parceria', color: _ShopColors.purple),
            ),
        ],
      ),
    );
  }
}

/// Ficha de detalhes do produto.
class _ItemDetailSheet extends StatelessWidget {
  const _ItemDetailSheet({
    required this.item,
    required this.balance,
    required this.catalog,
    required this.owned,
    required this.equipped,
    required this.busy,
    required this.onBuy,
    required this.onEquip,
  });
  final ShopItem item;
  final int balance;
  final List<ShopItem> catalog;
  final bool owned;
  final bool equipped;
  final bool busy;
  final VoidCallback onBuy;
  final VoidCallback onEquip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isBundle = item.category == 'bundle';
    final missing = item.price - balance;
    final grants = (item.payload['grants'] as List? ?? const [])
        .map((e) => '$e')
        .toList();
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _PreviewZone(item: item, height: 190),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                Chip(
                  label: Text(_categoryLabels[item.category] ??
                      item.category),
                  visualDensity: VisualDensity.compact,
                ),
                if (item.payload['collection'] == 'parceria')
                  const Chip(
                    label: Text('Parceria'),
                    visualDensity: VisualDensity.compact,
                  ),
                if (equipped)
                  const Chip(
                    avatar: Icon(Icons.check,
                        size: 16, color: Color(0xFF16A34A)),
                    label: Text('Equipada'),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              item.name,
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              _detailHint(item),
              style: TextStyle(
                  fontSize: 14, color: scheme.onSurfaceVariant),
            ),
            if (grants.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Inclui',
                style:
                    TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              for (final id in grants)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline,
                          size: 18, color: Color(0xFF16A34A)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          catalog
                                  .where((c) => c.id == id)
                                  .map((c) => c.name)
                                  .firstOrNull ??
                              id,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                _PriceTag(price: item.price),
                const SizedBox(width: 12),
                Text(
                  'Saldo: ${formatPoints(balance)}',
                  style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant),
                ),
                if (!owned && missing > 0) ...[
                  const SizedBox(width: 8),
                  Text(
                    'Faltam ${formatPoints(missing)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFDC2626),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (!owned)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: busy ? null : onBuy,
                      icon: Icon(item.price == 0
                          ? Icons.card_giftcard
                          : Icons.shopping_bag_outlined),
                      label: Text(item.price == 0
                          ? 'Resgatar grátis'
                          : 'Comprar por ${formatPoints(item.price)}'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            vertical: 14),
                      ),
                    ),
                  )
                else if (!isBundle)
                  Expanded(
                    child: equipped
                        ? OutlinedButton.icon(
                            onPressed: busy ? null : onEquip,
                            icon: const Icon(Icons.checkroom_outlined),
                            label: const Text('Tirar'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 14),
                            ),
                          )
                        : FilledButton.icon(
                            onPressed: busy ? null : onEquip,
                            icon: const Icon(Icons.check),
                            label: const Text('Equipar agora'),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 14),
                            ),
                          ),
                  )
                else
                  const Expanded(
                      child: _OwnedChip(label: 'Na coleção')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _detailHint(ShopItem item) {
  return switch (item.category) {
    'avatar' => 'Decoração de avatar da galeria pronta.',
    'frame' => 'Moldura ao redor do seu avatar no perfil.',
    'effect' => 'Efeito animado sobre o cartão de perfil.',
    'banner' => 'Faixa de fundo do seu perfil.',
    'name_style' => 'Estilo do seu nome exibido no perfil.',
    'emoticon' => 'Pacote de emoticons exibido no mural do perfil.',
    'bundle' => 'Pacote com desconto: libera todos os itens listados.',
    _ => 'Cosmético do seu perfil.',
  };
}

