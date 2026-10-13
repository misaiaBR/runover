import 'package:flutter/material.dart';

import '../models.dart';
import '../services/api_client.dart';
import '../services/profile_image_provider.dart';
import 'runover_ui.dart';

/// Galeria de avatares do editor de perfil: tudo custa moedas do jogo.
///
/// Duas seções — "Galeria" (assets prontos, `avatar_<asset>`) e "Gerados"
/// (DiceBear por estilo, `avatar_gerado_<estilo>`, seed = apelido).
/// Tocar compra (se preciso) e equipa o item da loja; foto enviada por
/// upload/link continua gratuita por ser identidade, não cosmético.
class AvatarShopSheet extends StatefulWidget {
  const AvatarShopSheet({
    super.key,
    required this.username,
    required this.api,
    required this.onChanged,
  });

  final String username;
  final ApiClient api;
  final Future<void> Function() onChanged;

  @override
  State<AvatarShopSheet> createState() => _AvatarShopSheetState();
}

class _AvatarShopData {
  const _AvatarShopData({
    required this.catalog,
    required this.inventory,
    required this.balance,
  });

  final List<ShopItem> catalog;
  final Inventory inventory;
  final int balance;
}

class _AvatarShopSheetState extends State<AvatarShopSheet> {
  late Future<_AvatarShopData> _future = _load();
  String? _busyId;

  Future<_AvatarShopData> _load() async {
    final results = await Future.wait([
      // Galeria pessoal: o servidor conhece os três escopos, e aqui só interessam
      // os avatares da loja do jogador. Emblema da equipe e item do Passe aparecem
      // na lista, mas a compra recusa — a vitrine não pode oferecer o que a
      // carteira não libera.
      widget.api.getShopCatalog(scope: 'user'),
      widget.api.getInventory(),
      widget.api.getWalletBalance(),
    ]);
    return _AvatarShopData(
      catalog: results[0] as List<ShopItem>,
      inventory: results[1] as Inventory,
      balance: results[2] as int,
    );
  }

  ShopItem? _byId(List<ShopItem> catalog, String id) =>
      catalog.where((c) => c.id == id).firstOrNull;

  String _assetName(PresetAvatar preset) {
    final file = preset.asset.split('/').last; // avatar_corredor.png
    return file
        .replaceFirst(RegExp(r'^avatar_'), '')
        .replaceFirst(RegExp(r'\.png$'), '');
  }

  Future<void> _select(ShopItem item, bool owned) async {
    if (_busyId != null) return;
    setState(() => _busyId = item.id);
    try {
      if (!owned) {
        await widget.api.purchaseItem(item.id);
      }
      await widget.api.equipItem('avatar', item.id);
      await widget.onChanged();
      if (!mounted) return;
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Escolha um avatar',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                FutureBuilder<_AvatarShopData>(
                  future: _future,
                  builder: (context, snapshot) {
                    final balance = snapshot.data?.balance;
                    return Chip(
                      avatar: Icon(
                        Icons.monetization_on,
                        size: 16,
                        color: Pal.goldInk(context),
                      ),
                      label: Text(
                        balance == null ? '…' : '$balance dracmas',
                      ),
                      visualDensity: VisualDensity.compact,
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Tudo custa dracmas — ganhas correndo.',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: FutureBuilder<_AvatarShopData>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }
                  if (snapshot.hasError || !snapshot.hasData) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Não foi possível carregar a galeria.',
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () => setState(() {
                            _future = _load();
                          }),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Tentar novamente'),
                        ),
                      ],
                    );
                  }
                  final data = snapshot.data!;
                  final gallery = [
                    for (final preset in presetAvatars)
                      (
                        _byId(data.catalog, 'avatar_${_assetName(preset)}'),
                        preset.label,
                        AssetImage(preset.asset) as ImageProvider,
                      ),
                  ].where((e) => e.$1 != null).toList();
                  final generated = [
                    for (final style in diceBearAvatarStyles)
                      (
                        _byId(
                          data.catalog,
                          'avatar_gerado_${style.replaceAll('-', '_')}',
                        ),
                        style,
                        NetworkImage(
                          diceBearAvatarUrl(
                            widget.username,
                            style: style,
                          ),
                        )
                            as ImageProvider,
                      ),
                  ].where((e) => e.$1 != null).toList();
                  return SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _sectionTitle('Galeria'),
                        _grid(data, gallery),
                        const SizedBox(height: 16),
                        _sectionTitle('Gerados'),
                        _grid(data, generated),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
      ),
    );
  }

  Widget _grid(
    _AvatarShopData data,
    List<(ShopItem?, String, ImageProvider)> entries,
  ) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.8,
      ),
      itemCount: entries.length,
      itemBuilder: (_, i) {
        final item = entries[i].$1!;
        final label = entries[i].$2;
        final image = entries[i].$3;
        final owned = data.inventory.owned.contains(item.id);
        final equipped = data.inventory.equippedAvatar == item.id;
        final busy = _busyId == item.id;
        return InkWell(
          key: Key('preset-avatar-$label'),
          borderRadius: BorderRadius.circular(16),
          onTap: busy ? null : () => _select(item, owned),
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image(
                        image: image,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Icon(
                          Icons.face_outlined,
                          size: 32,
                        ),
                      ),
                    ),
                    if (equipped)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Color(0xFF22C55E),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.check,
                            size: 14,
                            // O selo fica sobre a foto do avatar, então o
                            // enchimento continua sólido e a tinta é a de maior
                            // contraste sobre ele.
                            color: inkOnAccent(const Color(0xFF22C55E)),
                          ),
                        ),
                      ),
                    if (busy)
                      const Positioned.fill(
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                owned
                    ? (equipped ? 'Em uso' : 'Meu')
                    : '${item.price} 🪙',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: equipped
                      ? Pal.successInk(context)
                      : Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
