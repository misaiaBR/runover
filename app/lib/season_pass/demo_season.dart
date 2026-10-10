import 'package:flutter/material.dart';

import 'models.dart';

/// Temporada de exemplo para visualizar o Passe de Temporada antes de ligar
/// ao backend.
///
/// Nível 4 alcançado, faixas grátis dos níveis 1–3 já resgatadas e passe não
/// adquirido — assim os quatro estados aparecem: resgatado (1–3 grátis),
/// resgatável (4 grátis), requer passe (1–4 do passe) e bloqueado (5–7).
Season demoSeason() {
  return Season(
    name: 'Aurora',
    endsAt: DateTime.now().add(const Duration(days: 17, hours: 21)),
    currentLevel: 4,
    points: 320,
    pointsForNext: 500,
    claimed: const {'1-free', '2-free', '3-free'},
    levels: const [
      SeasonLevel(
        level: 1,
        free: Reward(title: '100 moedas', icon: Icons.monetization_on_outlined),
        pass: Reward(
          title: 'Moldura de avatar',
          icon: Icons.account_circle_outlined,
        ),
      ),
      SeasonLevel(
        level: 2,
        free: Reward(title: 'Cor de zona', icon: Icons.hexagon_outlined),
        pass: Reward(
          title: 'Efeito de conquista',
          icon: Icons.auto_awesome,
        ),
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
        free: Reward(title: 'Baú de moedas', icon: Icons.redeem),
        pass: Reward(title: 'Cor exclusiva', icon: Icons.palette_outlined),
      ),
      SeasonLevel(
        level: 5,
        free: Reward(title: '300 moedas', icon: Icons.monetization_on_outlined),
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
        free: Reward(title: 'Baú de moedas', icon: Icons.redeem),
        pass: Reward(title: 'Base animada', icon: Icons.hexagon),
      ),
    ],
  );
}
