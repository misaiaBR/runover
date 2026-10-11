import 'package:flutter/material.dart';
import 'package:runover_app/season_pass/models.dart';

/// Temporada longa, para os testes de rolagem da trilha.
///
/// Cada cartão tem um título próprio ("L12 grátis"), então dá para afirmar o
/// que de fato está visível na janela — com 30 níveis iguais a tela só diria
/// "algo aparece".
Season longSeason({int levels = 30, int currentLevel = 12}) {
  return Season(
    name: 'Longa',
    endsAt: DateTime.now().add(const Duration(days: 10)),
    currentLevel: currentLevel,
    points: currentLevel * 200,
    pointsForNext: (currentLevel + 1) * 200,
    levelStartPoints: currentLevel * 200,
    premiumPriceCoins: 1200,
    levels: [
      for (var level = 1; level <= levels; level++)
        SeasonLevel(
          level: level,
          free: Reward(title: 'L$level grátis', icon: Icons.redeem),
          pass: Reward(
            title: 'L$level passe',
            icon: Icons.workspace_premium_outlined,
          ),
        ),
    ],
  );
}

/// Temporada de exemplo usada só pelos testes do Passe de Temporada.
///
/// Nível 4 alcançado, faixas grátis dos níveis 1–3 já resgatadas e passe não
/// adquirido — assim os quatro estados aparecem: resgatado (1–3 grátis),
/// resgatável (4 grátis), requer passe (1–4 do passe) e bloqueado (5–7).
///
/// O que a tela mostra em produção vem de `GET /pass` (`season_pass/backend.dart`);
/// nada aqui é catálogo do jogo.
Season demoSeason() {
  return Season(
    name: 'Aurora',
    endsAt: DateTime.now().add(const Duration(days: 17, hours: 21)),
    currentLevel: 4,
    points: 320,
    pointsForNext: 500,
    // O nível 4 abriu em 300 pts: a barra do card mede o trecho 300→500.
    levelStartPoints: 300,
    claimed: const {'1-free', '2-free', '3-free'},
    levels: const [
      SeasonLevel(
        level: 1,
        free: Reward(
          title: '100 dracmas',
          icon: Icons.monetization_on_outlined,
        ),
        pass: Reward(
          title: 'Moldura de avatar',
          icon: Icons.account_circle_outlined,
        ),
      ),
      SeasonLevel(
        level: 2,
        free: Reward(title: 'Cor de zona', icon: Icons.hexagon_outlined),
        pass: Reward(title: 'Efeito de conquista', icon: Icons.auto_awesome),
      ),
      SeasonLevel(
        level: 3,
        free: Reward(
          title: 'Título “Madrugador”',
          icon: Icons.military_tech_outlined,
        ),
        pass: Reward(title: 'Emblema de equipe', icon: Icons.shield_outlined),
      ),
      SeasonLevel(
        level: 4,
        free: Reward(title: 'Baú de dracmas', icon: Icons.redeem),
        pass: Reward(title: 'Cor exclusiva', icon: Icons.palette_outlined),
      ),
      SeasonLevel(
        level: 5,
        free: Reward(
          title: '300 dracmas',
          icon: Icons.monetization_on_outlined,
        ),
        pass: Reward(title: 'Moldura de equipe', icon: Icons.shield_outlined),
      ),
      SeasonLevel(
        level: 6,
        free: Reward(title: 'Cor de zona', icon: Icons.hexagon_outlined),
        pass: Reward(
          title: 'Título exclusivo',
          icon: Icons.military_tech_outlined,
        ),
      ),
      SeasonLevel(
        level: 7,
        free: Reward(title: 'Baú de dracmas', icon: Icons.redeem),
        pass: Reward(title: 'Base animada', icon: Icons.hexagon),
      ),
    ],
  );
}
