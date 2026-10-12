import 'package:flutter/material.dart';
import 'package:runover_app/season_pass/models.dart';

/// Prévia de catálogo: o cartão desenha o cosmético de verdade, então os
/// testes precisam de um item realista — mas nada aqui é catálogo do jogo, a
/// tela de produção lê `GET /shop/catalog?scope=pass`.
const bannerReward = ShopItem(
  id: 'test_banner',
  category: 'banner',
  name: 'Faixa de teste',
  price: 0,
  payload: {'colors': ['#2FB7A0', '#1F8D7B']},
);

const frameReward = ShopItem(
  id: 'test_frame',
  category: 'frame',
  name: 'Moldura de teste',
  price: 0,
  payload: {'colors': ['#FFB21A']},
);

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
          threshold: level * 200,
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
/// Nível 4 alcançado (400 pts), faixas grátis dos níveis 1–3 já resgatadas e
/// passe não adquirido — assim os quatro estados aparecem: resgatado (1–3
/// grátis), resgatável (4 grátis), requer passe (1–4 do passe) e bloqueado
/// (5–7). Os limiares vão de 100 em 100 pts e são os números que aparecem nos
/// nós da trilha.
///
/// O nível 4 grátis soma dracmas a uma faixa da galeria: é o cartão que exerce
/// o nome do item, as dracmas na linha de baixo e a prévia real lado a lado.
Season demoSeason() {
  return Season(
    name: 'Aurora',
    endsAt: DateTime.now().add(const Duration(days: 17, hours: 21)),
    currentLevel: 4,
    points: 420,
    pointsForNext: 500,
    // O nível 4 abriu em 400 pts: a barra mede o trecho 400→500.
    levelStartPoints: 400,
    premiumPriceCoins: 1200,
    claimed: const {'1-free', '2-free', '3-free'},
    levels: const [
      SeasonLevel(
        level: 1,
        threshold: 100,
        free: Reward(
          title: '+100 dracmas',
          icon: Icons.monetization_on_outlined,
          coins: 100,
        ),
        pass: Reward(
          title: 'Moldura de avatar',
          icon: Icons.account_circle_outlined,
        ),
      ),
      SeasonLevel(
        level: 2,
        threshold: 200,
        free: Reward(
          title: '+200 dracmas',
          icon: Icons.monetization_on_outlined,
          coins: 200,
        ),
        pass: Reward(
          title: 'Moldura do passe',
          icon: Icons.auto_awesome,
          itemName: 'Moldura de teste',
          item: frameReward,
        ),
      ),
      SeasonLevel(
        level: 3,
        threshold: 300,
        free: Reward(
          title: '+300 dracmas',
          icon: Icons.monetization_on_outlined,
          coins: 300,
        ),
        pass: Reward(
          title: 'Emblema de equipe',
          icon: Icons.shield_outlined,
        ),
      ),
      SeasonLevel(
        level: 4,
        threshold: 400,
        free: Reward(
          title: 'Faixa de teste · +400 dracmas',
          icon: Icons.redeem,
          coins: 400,
          itemName: 'Faixa de teste',
          item: bannerReward,
        ),
        pass: Reward(title: 'Cor exclusiva', icon: Icons.palette_outlined),
      ),
      SeasonLevel(
        level: 5,
        threshold: 500,
        free: Reward(
          title: '+500 dracmas',
          icon: Icons.monetization_on_outlined,
          coins: 500,
        ),
        pass: Reward(title: 'Moldura de equipe', icon: Icons.shield_outlined),
      ),
      SeasonLevel(
        level: 6,
        threshold: 600,
        free: Reward(
          title: '+600 dracmas',
          icon: Icons.monetization_on_outlined,
          coins: 600,
        ),
        pass: Reward(
          title: 'Título exclusivo',
          icon: Icons.military_tech_outlined,
        ),
      ),
      SeasonLevel(
        level: 7,
        threshold: 700,
        free: Reward(
          title: '+700 dracmas',
          icon: Icons.monetization_on_outlined,
          coins: 700,
        ),
        pass: Reward(title: 'Base animada', icon: Icons.hexagon),
      ),
    ],
  );
}
