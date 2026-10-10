import 'package:flutter/material.dart';

import '../gold.dart';
import '../models.dart';

/// Cartão de uma recompensa da trilha (faixa grátis em cima, passe embaixo).
///
/// O cartão inteiro é a área de toque (84 × 112, acima do mínimo de 48 px) e
/// só reage ao toque quando [state] é [RewardState.claimable]. O rótulo de
/// acessibilidade combina título e estado em português.
class SeasonPassRewardCard extends StatelessWidget {
  const SeasonPassRewardCard({
    super.key,
    required this.reward,
    required this.state,
    required this.level,
    required this.premium,
    required this.onClaim,
  });

  final Reward reward;
  final RewardState state;
  final int level;
  final bool premium;
  final VoidCallback onClaim;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final claimable = state == RewardState.claimable;
    final locked =
        state == RewardState.locked || state == RewardState.needsPass;
    final status = switch (state) {
      RewardState.claimed => 'Resgatado',
      RewardState.claimable => 'Resgatar',
      RewardState.locked => 'Nível $level',
      RewardState.needsPass => 'Requer passe',
    };

    return Semantics(
      button: claimable,
      label: '${reward.title}, $status',
      excludeSemantics: true,
      child: Material(
        color: premium ? seasonPassGoldBg : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: claimable
                ? scheme.primary
                : (premium ? seasonPassGoldBorder : scheme.outlineVariant),
            width: 1.5,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: claimable ? onClaim : null,
          child: SizedBox(
            width: 84,
            height: 112,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
              child: Column(
                children: [
                  Icon(
                    locked ? Icons.lock_outline : reward.icon,
                    size: 26,
                    color: premium ? seasonPassGold : scheme.primary,
                  ),
                  const SizedBox(height: 4),
                  // Ocupa a sobra e nunca estoura: com fonte maior o título
                  // ganha elipse em vez de vazar o cartão.
                  Expanded(
                    child: Center(
                      child: Text(
                        reward.title,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, height: 1.2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: claimable ? scheme.primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: claimable
                            ? scheme.onPrimary
                            : (state == RewardState.claimed
                                  ? scheme.secondary
                                  : scheme.onSurfaceVariant),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
