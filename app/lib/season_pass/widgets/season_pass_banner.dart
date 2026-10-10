import 'package:flutter/material.dart';

import '../gold.dart';

/// Banner de venda do passe, visível só quando o jogador não tem o passe.
///
/// Deixa claro que as recompensas do passe são só visuais. O botão
/// [FilledButton] segue o tema do app (altura mínima acima de 48 px).
class SeasonPassBanner extends StatelessWidget {
  const SeasonPassBanner({super.key, required this.name, this.onTap});

  final String name;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: seasonPassGoldBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: seasonPassGoldBorder, width: 1.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Passe $name',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: seasonPassGold,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Só itens visuais: nada que dê vantagem no mapa ou no ranking.',
                  style: TextStyle(fontSize: 13, color: Color(0xFFD8D2BC)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: seasonPassGold,
              foregroundColor: seasonPassOnGold,
            ),
            onPressed: onTap,
            child: const Text('Ver passe'),
          ),
        ],
      ),
    );
  }
}
