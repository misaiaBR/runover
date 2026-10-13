import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../format.dart';
import '../models.dart';
import '../services/api_client.dart';
import '../state/app_state.dart';
import '../widgets/centered_content.dart';
import '../widgets/offer_row.dart';
import '../widgets/runover_ui.dart';
import 'app_footer.dart';

/// Loja da equipe: decoração, molduras, efeitos, faixas e nomes com valores
/// altos em pontos. O saldo é o cofre — soma dos pontos dos integrantes
/// menos o já gasto; ninguém perde pontos, nível ou moedas. Só o dono ou
/// admins compram e equipam (o servidor barra o resto com 403).
class TeamShopScreen extends StatefulWidget {
  const TeamShopScreen({super.key, required this.teamId});

  final String teamId;

  @override
  State<TeamShopScreen> createState() => _TeamShopScreenState();
}

class _TeamShopData {
  const _TeamShopData({
    required this.team,
    required this.wallet,
    required this.inventory,
    required this.catalog,
  });

  final TeamDetail team;
  final TeamWallet wallet;
  final TeamInventory inventory;
  final List<ShopItem> catalog;
}

String? _grantsLabel(ShopItem item) {
  if (item.category != 'bundle') return null;
  final grants = (item.payload['grants'] as List? ?? const []).length;
  if (grants == 0) return null;
  return '$grants itens inclusos';
}

class _TeamShopScreenState extends State<TeamShopScreen> {
  late Future<_TeamShopData> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _load(context.read<AppState>().api);
  }

  Future<_TeamShopData> _load(ApiClient api) async {
    final results = await Future.wait([
      api.getTeam(widget.teamId),
      api.getTeamWallet(widget.teamId),
      api.getTeamInventory(widget.teamId),
      api.getShopCatalog(scope: 'team'),
    ]);
    return _TeamShopData(
      team: results[0] as TeamDetail,
      wallet: results[1] as TeamWallet,
      inventory: results[2] as TeamInventory,
      catalog: results[3] as List<ShopItem>,
    );
  }

  void _reload() {
    setState(() {
      _future = _load(context.read<AppState>().api);
    });
  }

  Future<void> _buy(ShopItem item, _TeamShopData data) async {
    if (!data.team.isAdmin) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Só o dono ou admins compram para a equipe.'),
        ),
      );
      return;
    }
    if (data.wallet.balance < item.price) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pontos da equipe insuficientes. Corram juntos!'),
        ),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<AppState>().api.purchaseTeamItem(
        widget.teamId,
        item.id,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${item.name} é da equipe agora!')),
      );
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _equip(ShopItem item, TeamInventory inventory) async {
    setState(() => _busy = true);
    try {
      final equipped = inventory.isEquipped(item);
      await context.read<AppState>().api.equipTeamItem(
        widget.teamId,
        item.category,
        equipped ? null : item.id,
      );
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openDetail(ShopItem item, _TeamShopData data) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => _TeamItemDetailSheet(
        item: item,
        wallet: data.wallet,
        inventory: data.inventory,
        catalog: data.catalog,
        canManage: data.team.isAdmin,
        busy: _busy,
        onBuy: () {
          Navigator.of(sheetContext).pop();
          _buy(item, data);
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
      appBar: AppBar(title: const Text('Loja da equipe')),
      body: CenteredContent(
        maxWidth: 1080,
        child: FutureBuilder<_TeamShopData>(
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
                    const Text(
                      'Não foi possível carregar a loja da equipe.',
                    ),
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
            final canManage = data.team.isAdmin;
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: _TeamWalletHero(
                      team: data.team,
                      wallet: data.wallet,
                      canManage: canManage,
                    ),
                  ),
                ),
                if (data.catalog.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: 40,
                        horizontal: 32,
                      ),
                      child: Center(
                        child: Text(
                          'Nenhum item para equipes ainda.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    sliver: SliverList.separated(
                      itemCount: data.catalog.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final item = data.catalog[index];
                        final owned = data.inventory.owned.contains(
                          item.id,
                        );
                        return OfferRow(
                          item: item,
                          subtitle: _grantsLabel(item),
                          owned: owned,
                          equipped: data.inventory.isEquipped(item),
                          busy: _busy,
                          locked: !canManage,
                          priceIcon: Icons.emoji_events,
                          onOpen: () => _openDetail(item, data),
                          onBuy: () => _buy(item, data),
                          onEquip: () => _equip(item, data.inventory),
                        );
                      },
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

/// Cofre: saldo em pontos, soma dos integrantes e aviso de permissão.
class _TeamWalletHero extends StatelessWidget {
  const _TeamWalletHero({
    required this.team,
    required this.wallet,
    required this.canManage,
  });

  final TeamDetail team;
  final TeamWallet wallet;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF8B7CFF), Color(0xFF2A2240)],
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
                Text(
                  'COFRE · ${team.name}'.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      formatPoints(wallet.balance),
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'pontos',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Soma dos pontos dos integrantes · já gastos ${formatPoints(wallet.spentPoints)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white70,
                  ),
                ),
                if (!canManage) ...[
                  const SizedBox(height: 4),
                  const Text(
                    'Só o dono ou admins compram e equipam.',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
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
              Icons.emoji_events,
              color: Colors.white,
              size: 40,
            ),
          ),
        ],
      ),
    );
  }
}

/// Ficha de detalhes do item da equipe.
class _TeamItemDetailSheet extends StatelessWidget {
  const _TeamItemDetailSheet({
    required this.item,
    required this.wallet,
    required this.inventory,
    required this.catalog,
    required this.canManage,
    required this.busy,
    required this.onBuy,
    required this.onEquip,
  });

  final ShopItem item;
  final TeamWallet wallet;
  final TeamInventory inventory;

  /// Catálogo da loja da equipe: é por ele que a lista "Inclui" resolve os
  /// `grants` do pacote em nomes.
  final List<ShopItem> catalog;
  final bool canManage;
  final bool busy;
  final VoidCallback onBuy;
  final VoidCallback onEquip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final owned = inventory.owned.contains(item.id);
    final equipped = inventory.isEquipped(item);
    final isBundle = item.category == 'bundle';
    final missing = item.price - wallet.balance;
    final included = grantNames(item, catalog);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(child: OfferArt(item: item)),
            const SizedBox(height: 16),
            Text(
              item.name,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Cosmético da equipe. Só dono ou admins compram e equipam.',
              style: TextStyle(
                fontSize: 14,
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (included.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Inclui',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              for (final name in included)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 18,
                        color: Pal.successInk(context),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          name,
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
                // O roxo da equipe é cor de acento do mock: como ícone de preço
                // sobre a superfície ele precisa de tinta queimada no claro.
                Icon(
                  Icons.emoji_events,
                  color: legibleInk(Pal.purple, context),
                  size: 18,
                ),
                const SizedBox(width: 4),
                Text(
                  formatPoints(item.price),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Cofre: ${formatPoints(wallet.balance)}',
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
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
                      onPressed: busy
                          ? null
                          : () {
                              if (!canManage) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Só o dono ou admins compram para a equipe.',
                                    ),
                                  ),
                                );
                                return;
                              }
                              onBuy();
                            },
                      icon: const Icon(Icons.shopping_bag_outlined),
                      label: Text(
                        'Comprar por ${formatPoints(item.price)}',
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  )
                else if (!isBundle)
                  Expanded(
                    child: equipped
                        ? OutlinedButton.icon(
                            onPressed: !canManage || busy ? null : onEquip,
                            icon: const Icon(Icons.checkroom_outlined),
                            label: const Text('Tirar'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                vertical: 14,
                              ),
                            ),
                          )
                        : FilledButton.icon(
                            onPressed:
                                !canManage || busy ? null : onEquip,
                            icon: const Icon(Icons.check),
                            label: const Text('Equipar agora'),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                vertical: 14,
                              ),
                            ),
                          ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: Pal.successFill(context),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.check_circle,
                          size: 18,
                          color: Pal.successInk(context),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Na coleção',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Pal.successInk(context),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
