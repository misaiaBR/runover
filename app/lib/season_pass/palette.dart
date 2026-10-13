import 'package:flutter/material.dart';

/// Paleta do Passe de Temporada.
///
/// Duas metades, e a linha que as separa é uma só:
///
/// - **Superfície e tinta** (fundo da tela, barra, nó apagado, texto do nó)
///   vêm do tema — `Pal.of(context).panel`, `.chip`, `.muted`, `.track`. O
///   passe não tem mais roxo fixo: no escuro ele continua desenhado sobre o
///   mesmo `#14102E` de sempre, e no claro ele abre sobre o painel claro do
///   app em vez de ficar preso no modo escuro.
/// - **As faixas** (grátis, passe, cabeçalho da temporada, dourado do resgate,
///   verde do concluído) carregam o próprio fundo saturado e o texto branco
///   sobre ele, então continuam fixas nas duas claridades — é o que faz o
///   cartão ler "prêmio" em qualquer tema.
///
/// Faixa do trilho, atrás dos nós: use `Pal.of(context).track`.

// Faixa grátis — laranja de rota, a cor do app.
const trailFreeTop = Color(0xFFFFA040);
const trailFreeBottom = Color(0xFFF2552C);

// Faixa do passe — violeta, a cor do premium.
const trailPassTop = Color(0xFF5A42D4);
const trailPassBottom = Color(0xFF2A1F78);

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
