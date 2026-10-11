import 'package:flutter/material.dart';

/// Passe de Temporada: modelos da trilha horizontal de níveis.
///
/// Cada nível tem uma recompensa grátis (faixa de cima) e uma do passe
/// (faixa de baixo). O jogador sobe de nível com pontos de temporada
/// (corrida concluída, território conquistado, meta da semana).
///
/// As recompensas do passe são só visuais: nada que dê vantagem no mapa
/// ou no ranking.

/// Faixa da recompensa na trilha.
enum RewardLane { free, pass }

/// Estado de cada recompensa na trilha.
enum RewardState {
  /// Já foi resgatada.
  claimed,

  /// Nível alcançado e (faixa grátis, ou o jogador tem o passe).
  claimable,

  /// Nível ainda não alcançado. Mostra "Nível N".
  locked,

  /// Faixa do passe, nível alcançado, jogador sem passe.
  needsPass,
}

/// Recompensa de um nível da temporada (só visual, sem vantagem no jogo).
///
/// [title] é o rótulo completo (acessibilidade e o caso em que só há uma
/// linha). [coins] e [itemName] vêm do servidor separados para o cartão poder
/// pôr cada parte em sua linha em vez de espremer tudo numa frase só.
class Reward {
  const Reward({
    required this.title,
    required this.icon,
    this.coins = 0,
    this.itemName,
  });

  final String title;
  final IconData icon;

  /// Dracmas da recompensa (0 = nenhuma).
  final int coins;

  /// Nome do cosmético, quando o catálogo da loja o conhece.
  final String? itemName;
}

/// Um nível da temporada: recompensa grátis (cima) e do passe (baixo).
class SeasonLevel {
  const SeasonLevel({
    required this.level,
    required this.free,
    required this.pass,
  });

  final int level;
  final Reward free;
  final Reward pass;
}

/// Temporada do passe: nome, fim, níveis, progresso e o que já foi resgatado.
class Season {
  const Season({
    required this.name,
    required this.endsAt,
    required this.levels,
    required this.currentLevel,
    required this.points,
    required this.pointsForNext,
    this.levelStartPoints = 0,
    this.hasPass = false,
    this.premiumPriceCoins = 0,
    this.claimed = const {},
  });

  final String name;
  final DateTime endsAt;
  final List<SeasonLevel> levels;
  final int currentLevel;

  /// Pontos acumulados da temporada — o total que o servidor soma.
  final int points;

  /// Limiar acumulado do próximo nível ainda não alcançado.
  final int pointsForNext;

  /// Limiar acumulado do nível atual; zero quando o nível 1 ainda não abriu.
  final int levelStartPoints;
  final bool hasPass;

  /// Preço em dracmas para desbloquear a faixa do passe (0 = desconhecido).
  final int premiumPriceCoins;

  /// Itens já resgatados, no formato "nivel-faixa", por exemplo "1-free".
  final Set<String> claimed;

  /// Barra do nível atual (0..1): só conta os pontos ganhos desde que o
  /// último nível abriu — os números do card são acumulados, a barra não.
  double get levelProgress {
    final window = pointsForNext - levelStartPoints;
    if (window <= 0) return 1;
    final inside = (points - levelStartPoints) / window;
    return inside.clamp(0.0, 1.0).toDouble();
  }

  /// Quantos pontos faltam para o próximo nível (0 = trilha completa).
  int get pointsToNextLevel {
    final missing = pointsForNext - points;
    return missing < 0 ? 0 : missing;
  }
}

/// Chave de resgate no formato "nivel-faixa", por exemplo "1-free".
String seasonRewardKey(int level, RewardLane lane) => '$level-${lane.name}';

/// Regra de negócio dos quatro estados de recompensa:
/// - resgatado: a chave está em [claimed];
/// - bloqueado: `nivel > nivelAtual`;
/// - requer passe: faixa do passe, nível alcançado, jogador sem passe;
/// - resgatável: nível alcançado e (faixa grátis, ou o jogador tem o passe).
RewardState rewardStateOf({
  required Season season,
  required Set<String> claimed,
  required SeasonLevel level,
  required RewardLane lane,
}) {
  if (claimed.contains(seasonRewardKey(level.level, lane))) {
    return RewardState.claimed;
  }
  if (level.level > season.currentLevel) return RewardState.locked;
  if (lane == RewardLane.pass && !season.hasPass) return RewardState.needsPass;
  return RewardState.claimable;
}
