import 'package:flutter/material.dart';

import '../format.dart';
import '../models.dart';
import '../services/api_client.dart';
import '../services/profile_image_provider.dart';
import 'cosmetics.dart';
import 'runover_ui.dart';

/// Folha de escolha de avatar, a serviço das duas lojas.
///
/// Sem `teamId` é a loja do jogador: duas seções — "Galeria" (os itens
/// históricos de `avatar_<nome>`) e "Gerados" (um por estilo da API,
/// `avatar_gerado_<estilo>`), pagas em dracmas. Com `teamId` é a loja da
/// equipe: a lista inteira de emblemas, paga com pontos do cofre e comprada
/// pelas rotas da equipe.
///
/// Cada rosto é desenhado a partir do payload do próprio item, então o que se
/// escolhe aqui é exatamente o que aparece na vitrine e no cartão de quem
/// equipou. Tocar compra (se preciso) e equipa; foto enviada por upload
/// continua gratuita por ser identidade, não cosmético.
class AvatarShopSheet extends StatefulWidget {
  const AvatarShopSheet({
    super.key,
    required this.api,
    required this.onChanged,
    this.teamId,
  });

  final ApiClient api;
  final Future<void> Function() onChanged;

  /// Equipe dona da folha. Vindo aí, o catálogo pedido é o de escopo `team`, o
  /// saldo é o cofre e a compra passa por `/teams/{id}/purchase`.
  final String? teamId;

  @override
  State<AvatarShopSheet> createState() => _AvatarShopSheetState();
}

class _AvatarShopData {
  const _AvatarShopData({
    required this.catalog,
    required this.owned,
    required this.equippedAvatar,
    required this.balance,
  });

  final List<ShopItem> catalog;
  final Set<String> owned;
  final String? equippedAvatar;
  final int balance;
}

class _AvatarShopSheetState extends State<AvatarShopSheet> {
  late Future<_AvatarShopData> _future = _load();
  String? _busyId;

  bool get _isTeam => widget.teamId != null;

  String get _title => _isTeam ? 'Escolha o emblema' : 'Escolha um avatar';

  String get _subtitle => _isTeam
      ? 'Tudo custa pontos do cofre — a equipe ganha correndo.'
      : 'Tudo custa dracmas — ganhas correndo.';

  String get _loadError => _isTeam
      ? 'Não foi possível carregar os emblemas da equipe.'
      : 'Não foi possível carregar a galeria.';

  Future<_AvatarShopData> _load() async {
    final teamId = widget.teamId;
    // As duas lojas entram pelo mesmo caminho: catálogo do próprio escopo,
    // inventário e saldo. O que muda é a moeda e a rota de compra.
    if (teamId == null) {
      final results = await Future.wait([
        // Só o escopo do jogador: emblema de equipe e item do Passe não se
        // compram com a carteira daqui.
        widget.api.getShopCatalog(scope: 'user', category: 'avatar'),
        widget.api.getInventory(),
        widget.api.getWalletBalance(),
      ]);
      final inventory = results[1] as Inventory;
      return _AvatarShopData(
        catalog: results[0] as List<ShopItem>,
        owned: inventory.owned.toSet(),
        equippedAvatar: inventory.equippedAvatar,
        balance: results[2] as int,
      );
    }
    final results = await Future.wait([
      widget.api.getShopCatalog(scope: 'team', category: 'avatar'),
      widget.api.getTeamInventory(teamId),
      widget.api.getTeamWallet(teamId),
    ]);
    final inventory = results[1] as TeamInventory;
    return _AvatarShopData(
      catalog: results[0] as List<ShopItem>,
      owned: inventory.owned.toSet(),
      equippedAvatar: inventory.equippedAvatar,
      balance: (results[2] as TeamWallet).balance,
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

  /// Os títulos e as listas da folha. Na loja pessoal as seções vêm das duas
  /// famílias que o app conhece; na da equipe, o catálogo de emblemas é uma
  /// lista só — não há "gerados" nem galeria histórica em uma vitrine de cinco
  /// distintivos.
  List<(String, List<ShopItem>)> _sections(_AvatarShopData data) {
    if (_isTeam) return [('Emblemas', data.catalog)];
    return [
      (
        'Galeria',
        [
          for (final preset in presetAvatars)
            ?_byId(data.catalog, 'avatar_${_assetName(preset)}'),
        ],
      ),
      (
        'Gerados',
        [
          for (final style in diceBearAvatarStyles)
            ?_byId(
              data.catalog,
              'avatar_gerado_${style.replaceAll('-', '_')}',
            ),
        ],
      ),
    ];
  }

  Future<void> _select(ShopItem item, bool owned) async {
    if (_busyId != null) return;
    setState(() => _busyId = item.id);
    try {
      final teamId = widget.teamId;
      if (!owned) {
        if (teamId == null) {
          await widget.api.purchaseItem(item.id);
        } else {
          await widget.api.purchaseTeamItem(teamId, item.id);
        }
      }
      if (teamId == null) {
        await widget.api.equipItem('avatar', item.id);
      } else {
        await widget.api.equipTeamItem(teamId, 'avatar', item.id);
      }
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
                    _title,
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
                        _isTeam ? Icons.emoji_events : Icons.monetization_on,
                        size: 16,
                        color: Pal.goldInk(context),
                      ),
                      label: Text(
                        balance == null
                            ? '…'
                            : _isTeam
                            ? '${formatPoints(balance)} pontos'
                            : '$balance dracmas',
                      ),
                      visualDensity: VisualDensity.compact,
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _subtitle,
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
                        Text(_loadError),
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
                  final sections = _sections(data);
                  final hasAny = sections
                      .map((section) => section.$2)
                      .any((items) => items.isNotEmpty);
                  if (!hasAny) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Text(
                        'Nenhum avatar disponível para esta loja ainda.',
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                  return SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final (title, items) in sections) ...[
                          _sectionTitle(title),
                          _grid(data, items),
                          const SizedBox(height: 16),
                        ],
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

  Widget _grid(_AvatarShopData data, List<ShopItem> items) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.8,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final item = items[i];
        // O rosto vem do payload do item, exatamente como na vitrine e no cartão
        // de quem equipou — a folha não desenha uma figura e a loja outra.
        final image = profileAvatarImage(null, item);
        final owned = data.owned.contains(item.id);
        final equipped = data.equippedAvatar == item.id;
        final busy = _busyId == item.id;
        return InkWell(
          key: Key('preset-avatar-${item.name}'),
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
                      child: image == null
                          ? const Center(
                              child: Icon(Icons.face_outlined, size: 32),
                            )
                          : Image(
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
                    ? (equipped ? 'Em uso' : (_isTeam ? 'Da equipe' : 'Meu'))
                    : _isTeam
                    ? '${formatPoints(item.price)} pts'
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
