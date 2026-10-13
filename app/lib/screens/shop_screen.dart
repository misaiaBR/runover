import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../format.dart';
import '../models.dart';
import '../services/api_client.dart';
import '../state/app_state.dart';
import '../widgets/centered_content.dart';
import '../widgets/cosmetics.dart';
import '../widgets/offer_row.dart';
import '../widgets/runover_ui.dart';
import 'app_footer.dart';
import 'wallet_history_screen.dart';

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
      // O Mercado é a loja pessoal: o servidor conhece três escopos (pessoal,
      // equipe e Passe), e cada loja se mostra sozinha. Pedir o catálogo
      // inteiro encheria a vitrine de itens que a compra recusa — emblema e
      // faixa da equipe não têm nada a ver aqui, e o item do Passe só sai da
      // trilha. A Loja da equipe já pede o escopo dela.
      api.getShopCatalog(scope: 'user'),
      api.getInventory(),
      api.getWallet(),
    ]);
    final wallet = Map<String, dynamic>.from(results[2] as Map);
    // O saldo é o único número que a vitrine inteira usa para decidir o que a
    // pessoa pode comprar: sem ele a tela não tem como falar "insuficiente",
    // então cai no estado de falha em vez de assumir zero.
    final rawBalance = wallet['balance'];
    if (rawBalance is! num) throw const FormatException('saldo ausente');
    return _ShopData(
      catalog: results[0] as List<ShopItem>,
      inventory: results[1] as Inventory,
      balance: rawBalance.toInt(),
      rates: _EarnRates.parse(wallet['rates']),
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
            balance: balance,
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

  /// Folha "Como ganhar": as fontes de dracmas com o que cada uma paga.
  ///
  /// Os números vêm do `/wallet`, não do app. Uma taxa escrita aqui seria uma
  /// segunda fonte de verdade, e a primeira mudaria sem a segunda acompanhar.
  void _openEarnSheet(_EarnRates? rates) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _EarnSheet(rates: rates),
    );
  }

  void _openHistory() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const WalletHistoryScreen()));
  }

  @override
  Widget build(BuildContext context) {
    // O `FutureBuilder` envolve o `Scaffold` inteiro porque o saldo mora no
    // cabeçalho: desenhado fora do builder, o cabeçalho não teria número
    // nenhum para mostrar enquanto a carteira não vem.
    return FutureBuilder<_ShopData>(
      future: _future,
      builder: (context, snapshot) {
        final done = snapshot.connectionState == ConnectionState.done;
        final data = (done && !snapshot.hasError) ? snapshot.data : null;
        return Scaffold(
          appBar: _ShopAppBar(balance: data?.balance),
          body: CenteredContent(
            maxWidth: 1080,
            child: data == null
                ? _placeholder(done)
                : _vitrine(context, data),
          ),
        );
      },
    );
  }

  /// Espera e falha ocupam o lugar da vitrine, sem cabeçalho falso.
  Widget _placeholder(bool done) {
    if (!done) {
      return const Padding(
        padding: EdgeInsets.all(48),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: ErrorBanner(
        message: 'Não foi possível carregar o mercado.',
        onRetry: _reload,
      ),
    );
  }

  Widget _vitrine(BuildContext context, _ShopData data) {
    final balance = data.balance;
    final items = _visible(data.catalog, balance);
    final searching = _query.trim().isNotEmpty;
    final featured =
        (!searching && (_section == 'tudo' || _section == 'bundle'))
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
            child: _WelcomeCard(
              onEarn: () => _openEarnSheet(data.rates),
              onHistory: _openHistory,
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
              onOpen: (item) => _openDetail(item, data, balance, data.catalog),
              onBuy: (item) => _buy(item, balance),
            ),
          ),
        if (items.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    searching
                        ? Icons.search_off_outlined
                        : Icons.storefront_outlined,
                    size: 48,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                      onPressed: () => setState(() => _query = ''),
                      child: const Text('Limpar busca'),
                    ),
                  ],
                ],
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            sliver: wide
                ? SliverGrid(
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 300,
                      mainAxisExtent: 340 * textScale,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) =>
                          _offerTile(items[index], data, balance, wide),
                      childCount: items.length,
                    ),
                  )
                : SliverList.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) =>
                        _offerTile(items[index], data, balance, wide),
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
  }
}

class _ShopData {
  const _ShopData({
    required this.catalog,
    required this.inventory,
    required this.balance,
    required this.rates,
  });
  final List<ShopItem> catalog;
  final Inventory inventory;
  final int balance;

  /// O que cada fonte paga, do `/wallet`. Null quando o servidor não mandou o
  /// bloco — a folha "Como ganhar" diz isso em vez de inventar número.
  final _EarnRates? rates;
}

/// Taxas de ganho como vêm do servidor (`app/services/coins.py` é o dono).
///
/// Campos separáveis de propósito: se uma taxa faltar, só a linha dela some da
/// folha. Copiar estes valores no app seria a mesma regra escrita em dois
/// lugares, e regra em dois lugares é regra que diverge.
class _EarnRates {
  const _EarnRates({
    this.perKm,
    this.conquest,
    this.dailyFirstRun,
    this.streakPerDay,
    this.streakCap,
  });

  final int? perKm;
  final int? conquest;
  final int? dailyFirstRun;
  final int? streakPerDay;
  final int? streakCap;

  static _EarnRates? parse(Object? raw) {
    if (raw is! Map) return null;
    int? read(String key) => (raw[key] as num?)?.toInt();
    return _EarnRates(
      perKm: read('per_km'),
      conquest: read('conquest'),
      dailyFirstRun: read('daily_first_run'),
      streakPerDay: read('streak_per_day'),
      streakCap: read('streak_cap'),
    );
  }

  bool get hasAny =>
      perKm != null ||
      conquest != null ||
      dailyFirstRun != null ||
      streakPerDay != null;
}

/// "Inclui: A, B e C" para pacotes; null nas demais categorias.
///
/// Só entram no texto os itens que o catálogo da loja pessoal conhece. Um
/// `grants` que não resolve (id de outra loja, item fora de catálogo) fica de
/// fora em vez de mostrar o identificador cru: id interno não aparece na
/// interface, e um pacote que não inclui nada visível não ganha linha nenhuma.
String? _bundleSubtitle(ShopItem item, List<ShopItem> catalog) {
  if (item.category != 'bundle') return null;
  final grants = (item.payload['grants'] as List? ?? const []).map((e) => '$e');
  final names = [
    for (final id in grants)
      catalog.where((c) => c.id == id).map((c) => c.name).firstOrNull,
  ].nonNulls.toList();
  if (names.isEmpty) return null;
  return 'Inclui: ${names.join(', ')}';
}

/// Cabeçalho do Mercado: o título sobre a barra em gradiente e o saldo em
/// pílula, no canto de cima.
///
/// O gradiente é fixo nos dois temas (é o mesmo da barra de Corridas), então o
/// branco por cima dele é tinta de gradiente, não de superfície. Sem saldo o
/// pill não aparece: número inventado é pior que cabeçalho sem número.
class _ShopAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _ShopAppBar({this.balance});

  final int? balance;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final balance = this.balance;
    return AppBar(
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      elevation: 0,
      // Sem rolagem o AppBar ganha a tinta de elevação do tema por cima do
      // gradiente, e o cabeçalho fica acinzentado no tema claro.
      scrolledUnderElevation: 0,
      centerTitle: false,
      // `Container`, não `DecoratedBox`: o segundo não tem filho e encolhe a
      // zero — o gradiente pintaria uma faixa invisível atrás da barra.
      flexibleSpace: Container(
        decoration: const BoxDecoration(gradient: RGrad.header),
      ),
      title: const Text(
        'Mercado',
        style: TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
          shadows: kTextShadow,
        ),
      ),
      actions: [
        if (balance != null) _BalancePill(balance: balance),
        const SizedBox(width: 12),
      ],
    );
  }
}

/// O saldo atual, na moeda do jogo: a pílula do canto do cabeçalho.
class _BalancePill extends StatelessWidget {
  const _BalancePill({required this.balance});

  final int balance;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Saldo: ${formatPoints(balance)} dracmas',
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0x40000000),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const DracmaCoin(size: 22),
            const SizedBox(width: 8),
            Text(
              formatPoints(balance),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Boas-vindas ao Mercado: o mascote, a regra do ganho em uma linha e as duas
/// portas da carteira — de onde vem dracma e para onde ela foi.
class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard({required this.onEarn, required this.onHistory});

  final VoidCallback onEarn;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final mascot = Image.asset(
      'assets/images/runner.png',
      height: 56,
      semanticLabel: 'RUNOVER!',
    );
    final message = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: pal.chip,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'BEM-VINDO AO MERCADO',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
              color: legibleInk(Pal.purple, context),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Ganhe dracmas correndo: km, conquistas, missão diária e '
            'sequência.',
            style: TextStyle(fontSize: 13, color: pal.heading),
          ),
        ],
      ),
    );
    final actions = _WalletActions(onEarn: onEarn, onHistory: onHistory);
    return GameCard(
      color: pal.card,
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Com folga a linha é uma só: o texto é elástico e as ações ficam no
          // canto direito. Apertado, as ações descem para a própria linha —
          // dois botões espremidos viram alvo de toque menor que 44 px.
          if (constraints.maxWidth >= 620) {
            return Row(
              children: [
                mascot,
                const SizedBox(width: 12),
                Expanded(child: message),
                const SizedBox(width: 12),
                actions,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  mascot,
                  const SizedBox(width: 12),
                  Expanded(child: message),
                ],
              ),
              const SizedBox(height: 4),
              Align(alignment: Alignment.centerRight, child: actions),
            ],
          );
        },
      ),
    );
  }
}

/// Os dois atalhos dourados do cartão de boas-vindas.
class _WalletActions extends StatelessWidget {
  const _WalletActions({required this.onEarn, required this.onHistory});

  final VoidCallback onEarn;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    final style = TextButton.styleFrom(
      foregroundColor: Pal.goldInk(context),
      minimumSize: const Size(0, 38),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      visualDensity: VisualDensity.compact,
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton(
          key: const Key('wallet-earn'),
          style: style,
          onPressed: onEarn,
          child: const Text('Como ganhar'),
        ),
        TextButton(
          key: const Key('wallet-history'),
          style: style,
          onPressed: onHistory,
          child: const Text('Histórico'),
        ),
      ],
    );
  }
}

/// Folha "Como ganhar": o que cada fonte paga, com o número do servidor.
///
/// Nada aqui é regra própria — a lista é montada campo a campo a partir do
/// bloco `rates` do `/wallet`. Se ele não veio, a folha diz que não há números
/// em vez de mostrar taxa chutada.
class _EarnSheet extends StatelessWidget {
  const _EarnSheet({required this.rates});

  final _EarnRates? rates;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final perKm = rates?.perKm;
    final conquest = rates?.conquest;
    final dailyFirstRun = rates?.dailyFirstRun;
    final streakPerDay = rates?.streakPerDay;
    final streakCap = rates?.streakCap;
    final lines = <(String, String)>[
      if (perKm != null)
        ('Distância percorrida', '+${formatPoints(perKm)} por km'),
      if (conquest != null)
        ('Conquista de território', '+${formatPoints(conquest)}'),
      if (dailyFirstRun != null)
        ('Primeira corrida do dia', '+${formatPoints(dailyFirstRun)}'),
      if (streakPerDay != null)
        (
          'Sequência de dias',
          '+${formatPoints(streakPerDay)} por dia'
              '${streakCap != null ? ', até ${formatPoints(streakCap)}' : ''}',
        ),
    ];
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Como ganhar dracmas',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: pal.heading,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Os valores são os que o servidor paga ao validar a corrida.',
              style: TextStyle(fontSize: 13, color: pal.muted),
            ),
            const SizedBox(height: 16),
            if (lines.isEmpty)
              Text(
                'As fontes de dracmas não vieram junto com a carteira, '
                'então não há números para mostrar.',
                style: TextStyle(fontSize: 14, color: pal.heading),
              )
            else
              for (final (label, value) in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GameCard(
                    color: pal.card,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: pal.heading,
                            ),
                          ),
                        ),
                        Text(
                          value,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: Pal.goldInk(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
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
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Row(
            children: [
              // Estrela sobre a superfície da página: o dourado do mock é cor
              // de enchimento e some no tema claro.
              Icon(Icons.star, color: Pal.goldInk(context), size: 20),
              const SizedBox(width: 6),
              const Text(
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
          color: Pal.successFill(context),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          'Grátis',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: Pal.successInk(context),
          ),
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.monetization_on,
          color: Pal.goldInk(context),
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
        color: Pal.successFill(context),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle,
              size: 16, color: Pal.successInk(context)),
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
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: inkOnAccent(color),
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
                  Chip(
                    avatar: Icon(Icons.check,
                        size: 16, color: Pal.successInk(context)),
                    label: const Text('Equipada'),
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
              cosmeticHint(item.category),
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
                      Icon(Icons.check_circle_outline,
                          size: 18, color: Pal.successInk(context)),
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
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: scheme.error,
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

