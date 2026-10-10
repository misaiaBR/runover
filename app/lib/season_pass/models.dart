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
class Reward {
  const Reward({required this.title, required this.icon});

  final String title;
  final IconData icon;
}

/// Um nível da temporada: recompensa grátis (cima) e do passe (baixo).
class SeasonLevel {
  const SeasonLevel({required this.level, required this.free, required this.pass});

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
    this.hasPass = false,
    this.premiumPriceCoins = 0,
    this.claimed = const {},
  });

  final String name;
  final DateTime endsAt;
  final List<SeasonLevel> levels;
  final int currentLevel;
  final int points;
  final int pointsForNext;
  final bool hasPass;

  /// Preço em dracmas para desbloquear a faixa do passe (0 = desconhecido).
  final int premiumPriceCoins;

  /// Itens já resgatados, no formato "nivel-faixa", por exemplo "1-free".
  final Set<String> claimed;
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
