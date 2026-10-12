import 'package:flutter/material.dart';

import '../../format.dart';
import '../palette.dart';
import 'season_pass_hex_node.dart';

/// Barra do topo do Passe de Temporada: nome da temporada, contagem regressiva,
/// saldo de dracmas e o selo de passe ativo.
///
/// É o cartão de abertura da tela, então ele carrega a gradiente laranja→rosa
/// do mock e texto branco: a temporada precisa parecer um evento, não mais um
/// card cinza da lista.
///
/// O saldo ([dracmas]) vem do perfil e só existe quando a tela está ligada ao
/// backend; em modo controlado (demonstração e testes) o pill é omitido em vez
/// de mostrar um número inventado.
class SeasonPassHeaderBar extends StatelessWidget {
  const SeasonPassHeaderBar({
    super.key,
    required this.seasonName,
    required this.remaining,
    required this.hasPass,
    this.dracmas,
  });

  final String seasonName;

  /// "Termina em 20 d 4 h", já formatado por quem conhece a hora local.
  final String remaining;
  final bool hasPass;

  /// Saldo de dracmas do jogador; `null` quando a tela não sabe.
  final int? dracmas;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [trailHeaderTop, trailHeaderBottom],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          SeasonPassHexNode(
            label: Icon(Icons.workspace_premium, size: 23, color: trailAccent),
            color: Colors.black.withValues(alpha: 0.3),
            size: 44,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'TEMPORADA',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.6,
                    color: Colors.white70,
                  ),
                ),
                Text(
                  seasonName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                Text(
                  remaining,
                  style: const TextStyle(fontSize: 12.5, color: Colors.white70),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              alignment: WrapAlignment.end,
              children: [
                if (dracmas != null) _pill(coinIcon: true, label: formatPoints(dracmas!)),
                if (hasPass)
                  _pill(label: 'Passe ativo', filled: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Pílula translúcida do mock: fundo preto sobre a gradiente, texto branco.
  Widget _pill({
    required String label,
    bool coinIcon = false,
    bool filled = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: filled ? trailAccent : Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(999),
        border: filled
            ? null
            : Border.all(color: Colors.white.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (coinIcon) ...[
            Icon(
              Icons.monetization_on,
              size: 15,
              color: filled ? trailAccentInk : trailAccent,
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: filled ? trailAccentInk : Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

