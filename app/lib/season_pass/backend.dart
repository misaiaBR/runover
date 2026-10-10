import 'package:flutter/material.dart';

import '../format.dart';
import '../screens/pass_screen.dart' show seasonLabel;
import '../services/api_client.dart';
import 'models.dart';

/// Liga o Passe de Temporada ao backend.
///
/// O servidor (`GET /pass`) devolve a temporada com os tiers, e o catálogo da
/// loja (`GET /shop/catalog?scope=pass`) dá nome aos itens cosméticos. Cada
/// tier vira um [SeasonLevel]: faixa grátis em cima, faixa do passe embaixo.
///
/// O catálogo é opcional: se falhar, os itens aparecem como "Exclusivo" e o
/// resto da trilha continua legível.

/// Trilha do servidor para resgate: grátis ou premium.
String passTrack(RewardLane lane) =>
    lane == RewardLane.pass ? 'premium' : 'free';

/// Baixa a temporada e monta a trilha pronta para a tela.
Future<Season> loadSeasonPass(ApiClient api) async {
  final status = await api.getPassRunover();
  final names = await _namesOrEmpty(api);
  return seasonFromStatus(status, names);
}

Future<Map<String, String>> _namesOrEmpty(ApiClient api) async {
  try {
    final catalog = await api.getShopCatalog(scope: 'pass');
    return {for (final item in catalog) item.id: item.name};
  } catch (_) {
    return const {};
  }
}

/// Converte o `GET /pass` em [Season].
///
/// `pointsForNext` é o limiar do primeiro tier ainda bloqueado; com tudo
/// desbloqueado, a barra aparece cheia.
Season seasonFromStatus(
  Map<String, dynamic> status,
  Map<String, String> names,
) {
  final tiers = (status['tiers'] as List? ?? const [])
      .whereType<Map>()
      .toList();
  var pointsForNext =
      (status['seasonal_points'] as num?)?.toInt() ?? 0;
  for (final tier in tiers) {
    if (tier['unlocked'] != true) {
      pointsForNext = (tier['threshold'] as num).toInt();
      break;
    }
  }
  final claimed = <String>{};
  for (final tier in tiers) {
    final number = (tier['tier'] as num).toInt();
    if (tier['free']?['claimed'] == true) claimed.add('$number-free');
    if (tier['premium']?['claimed'] == true) claimed.add('$number-pass');
  }
  return Season(
    name: seasonLabel('${status['season_id']}'),
    endsAt:
        DateTime.tryParse('${status['ends_at']}') ??
        DateTime.now().add(const Duration(days: 30)),
    levels: [
      for (final tier in tiers)
        SeasonLevel(
          level: (tier['tier'] as num).toInt(),
          free: _reward(tier['free'], premium: false, names: names),
          pass: _reward(tier['premium'], premium: true, names: names),
        ),
    ],
    currentLevel: (status['unlocked_tier'] as num?)?.toInt() ?? 0,
    points: (status['seasonal_points'] as num?)?.toInt() ?? 0,
    pointsForNext: pointsForNext,
    hasPass: status['premium_unlocked'] == true,
    premiumPriceCoins:
        (status['premium_price_coins'] as num?)?.toInt() ?? 0,
    claimed: claimed,
  );
}

/// Rótulo da recompensa, igual ao da trilha antiga: moedas formatadas pt-BR
/// mais o nome do item do catálogo.
Reward _reward(
  Map? reward, {
  required bool premium,
  required Map<String, String> names,
}) {
  final parts = <String>[];
  final coins = (reward?['coins'] as num?)?.toInt() ?? 0;
  if (coins > 0) parts.add('+${formatPoints(coins)} 🪙');
  final itemId = '${reward?['item_id'] ?? ''}';
  if (itemId.isNotEmpty) parts.add(names[itemId] ?? 'Exclusivo');
  return Reward(
    title: parts.isEmpty ? '—' : parts.join(' · '),
    icon: itemId.isEmpty
        ? Icons.monetization_on_outlined
        : (premium
              ? Icons.workspace_premium_outlined
              : Icons.redeem),
  );
}
