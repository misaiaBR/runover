import 'package:flutter/material.dart';

/// Paleta fixa do Passe de Temporada.
///
/// Convenção já usada nas telas do passe (`PassSummary` em `pass_screen.dart`):
/// o tema do app não tem dourado nem as cores das faixas na paleta, então o
/// passe traz os próprios valores — iguais nas duas claridades, porque cada
/// faixa carrega o próprio fundo saturado e o texto branco sobre ele continua
/// legível no tema claro e no escuro.
///
/// Fundo da tela do passe: o mesmo roxo-escuro em qualquer tema. As faixas
/// coloridas só fazem sentido sobre um escuro próprio — sobre o branco do
/// tema claro a trilha inteira viraria mancha.
const trailBoard = Color(0xFF14102E);

/// Faixa do trilho, atrás dos nós.
const trailRail = Color(0xFF0F0B26);

// Faixa grátis — laranja de rota, a cor do app.
const trailFreeTop = Color(0xFFFFA040);
const trailFreeBottom = Color(0xFFF2552C);

// Faixa do passe — violeta, a cor do premium.
const trailPassTop = Color(0xFF5A42D4);
const trailPassBottom = Color(0xFF2A1F78);

/// Nó da trilha ainda não alcançado e o texto dentro dele.
const trailNodeIdle = Color(0xFF2E2766);
const trailNodeInk = Color(0xFFB9B2F0);

/// Nó alcançado: verde-água do concluído (a barra de nível vai do tom cheio ao
/// claro).
const trailReached = Color(0xFF3DDBB0);
const trailReachedLight = Color(0xFF8CF2D6);
const trailReachedInk = Color(0xFF06241C);

/// Barra do cabeçalho da temporada (laranja → magenta).
const trailHeaderTop = Color(0xFFFF7F4D);
const trailHeaderBottom = Color(0xFFE5367A);

/// O dourado do passe: marca o nível atual, o selo da faixa do passe e o botão
/// de resgate. [trailAccentInk] é o texto legível sobre ele.
const trailAccent = Color(0xFFFFC93C);
const trailAccentInk = Color(0xFF3A2A00);

/// Gradiente vertical de uma faixa: laranja para a grátis, violeta para a do
/// passe.
LinearGradient trailGradient({required bool premium}) {
  return LinearGradient(
    colors: premium
        ? const [trailPassTop, trailPassBottom]
        : const [trailFreeTop, trailFreeBottom],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}
