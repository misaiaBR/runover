import 'package:flutter/material.dart';

import '../../format.dart';
import '../gold.dart';

/// Banner de venda do passe, visível só quando o jogador não tem o passe.
///
/// Deixa claro que as recompensas do passe são só visuais e mostra o preço: o
/// botão abre a confirmação de compra, então o rótulo diz "desbloquear" — não
/// "ver", que prometia uma tela que não existe.
///
/// Em linha larga o texto fica de um lado e o botão do outro (a linha do topo
/// da tela precisa sobrar altura para a trilha); em coluna estreita os dois
/// se empilham. O botão traz o próprio espaçamento: o tema do app só define o
/// vertical, e sem horizontal o texto encosta na borda.
class SeasonPassBanner extends StatelessWidget {
  const SeasonPassBanner({
    super.key,
    required this.name,
    required this.priceCoins,
    this.onTap,
  });

  final String name;

  /// Preço do passe em dracmas (0 = o servidor não informou).
  final int priceCoins;

  final VoidCallback? onTap;

  /// Abaixo disso o botão não divide a linha com o texto: o texto é que
  /// sobra espremido, e ele é a explicação do que se está comprando.
  static const double _rowMinWidth = 460;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: seasonPassGoldBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: seasonPassGoldBorder, width: 1.5),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final text = _text(context);
          if (constraints.maxWidth < _rowMinWidth) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                text,
                const SizedBox(height: 10),
                // Coluna estreita: o botão ocupa a largura toda.
                SizedBox(width: double.infinity, child: _button()),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [Expanded(child: text), const SizedBox(width: 12), _button()],
          );
        },
      ),
    );
  }

  Widget _text(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.workspace_premium_outlined,
              size: 18,
              color: seasonPassGold,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Passe $name',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: seasonPassGold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Só itens visuais: nada que dê vantagem no mapa ou no ranking.',
          style: const TextStyle(fontSize: 12, color: seasonPassOnGoldDim),
        ),
        if (priceCoins > 0) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(
                Icons.monetization_on_outlined,
                size: 15,
                color: seasonPassOnGoldDim,
              ),
              const SizedBox(width: 6),
              // O preço é informação de decisão: encolhe a fonte em vez de
              // cortar o número.
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${formatPoints(priceCoins)} dracmas',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: seasonPassGold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _button() {
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: seasonPassGold,
        foregroundColor: seasonPassOnGold,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        minimumSize: const Size(0, 44),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      onPressed: onTap,
      // Largura total na coluna estreita; o texto encolhe em vez de estourar.
      child: const FittedBox(
        fit: BoxFit.scaleDown,
        child: Text('Desbloquear passe'),
      ),
    );
  }
}
