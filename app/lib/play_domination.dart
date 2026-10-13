/// Entrada do modo Dominação: escolhe a mecânica e abre o lugar certo.
///
/// É o toque do botão JOGAR da home e o "Dominação" do estado vazio de
/// Corridas: um caminho só, para as duas telas não abrirem o jogo de jeitos
/// diferentes. Laço livre vai direto para o tracking, já com a conquista ligada
/// (a folha promete um território); caçar selvagem e desafiar dono passam pelo
/// mapa já focado na mecânica (dica + camadas).
library;

import 'package:flutter/material.dart';

import 'screens/map_screen.dart';
import 'screens/tracking_screen.dart';
import 'widgets/play_mode_sheet.dart';

Future<void> playDomination(BuildContext context) {
  return showPlayModeSheet(
    context,
    onSelect: (mode) {
      switch (mode) {
        case PlayMode.freeLoop:
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const TrackingScreen(mode: PlayMode.freeLoop),
            ),
          );
        case PlayMode.huntWild:
        case PlayMode.challenge:
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => MapScreen(focus: mode)),
          );
      }
    },
  );
}
