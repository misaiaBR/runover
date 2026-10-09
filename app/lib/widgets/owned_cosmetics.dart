import 'package:flutter/material.dart';

import '../models.dart';
import '../services/api_client.dart';

/// Os cosméticos já comprados, prontos para equipar dentro do editor de perfil.
///
/// A loja mostra o catálogo inteiro; aqui só entra o que já é do usuário,
/// porque o que faltava na tela era justamente selecionar o que foi pago.
/// Avatar fica de fora: ele já tem galeria própria no editor.
class OwnedCosmeticsPanel extends StatefulWidget {
  const OwnedCosmeticsPanel({
    super.key,
    required this.api,
    required this.onChanged,
  });

  final ApiClient api;
  final Future<void> Function() onChanged;

  @override
  State<OwnedCosmeticsPanel> createState() => _OwnedCosmeticsPanelState();
}

class _OwnedCosmeticsData {
  const _OwnedCosmeticsData({required this.catalog, required this.inventory});

  final List<ShopItem> catalog;
  final Inventory inventory;
}

/// Categoria -> rótulo. `emoticon` é aditivo: equipar soma o pacote, e o único
/// gesto de tirar é limpar todos de uma vez.
const _categories = <String, String>{
  'frame': 'Moldura',
  'banner': 'Banner',
  'effect': 'Efeito',
  'name_style': 'Estilo do nome',
  'emoticon': 'Emoticons',
};

class _OwnedCosmeticsPanelState extends State<OwnedCosmeticsPanel> {
  late Future<_OwnedCosmeticsData> _future = _load();
  String? _busy;

  Future<_OwnedCosmeticsData> _load() async {
    final results = await Future.wait([
      widget.api.getShopCatalog(),
      widget.api.getInventory(),
    ]);
    return _OwnedCosmeticsData(
      catalog: results[0] as List<ShopItem>,
      inventory: results[1] as Inventory,
    );
  }

  Future<void> _apply(String category, String? itemId) async {
    if (_busy != null) return;
    setState(() => _busy = '$category/${itemId ?? ''}');
    try {
      await widget.api.equipItem(category, itemId);
      await widget.onChanged();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
    if (!mounted) return;
    setState(() {
      _busy = null;
      // O inventário é a fonte do estado "em uso", então ele precisa recarregar
      // depois de equipar — o perfil sozinho não basta.
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_OwnedCosmeticsData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Não foi possível carregar seus cosméticos.'),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => setState(() => _future = _load()),
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'),
              ),
            ],
          );
        }
        final data = snapshot.data!;
        final groups = <Widget>[];
        for (final entry in _categories.entries) {
          final owned = data.catalog
              .where(
                (i) =>
                    i.category == entry.key &&
                    data.inventory.owned.contains(i.id),
              )
              .toList();
          if (owned.isEmpty) continue;
          if (groups.isNotEmpty) groups.add(const SizedBox(height: 14));
          groups.add(_group(entry.key, entry.value, owned, data.inventory));
        }
        if (groups.isEmpty) {
          return const Text(
            'Nenhum cosmético comprado ainda. Compre na loja para equipar aqui.',
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: groups,
        );
      },
    );
  }

  Widget _group(
    String category,
    String label,
    List<ShopItem> owned,
    Inventory inventory,
  ) {
    final selectable = _busy == null;
    final anyEquipped = owned.any(inventory.isEquipped);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in owned)
              ChoiceChip(
                key: Key('owned-cosmetic-${item.id}'),
                label: Text(item.name),
                selected: inventory.isEquipped(item),
                onSelected: selectable
                    ? (_) => _apply(category, item.id)
                    : null,
              ),
            if (anyEquipped)
              ActionChip(
                key: Key('unequip-$category'),
                label: Text(category == 'emoticon' ? 'Limpar' : 'Nenhum'),
                onPressed: selectable ? () => _apply(category, null) : null,
              ),
          ],
        ),
      ],
    );
  }
}
