import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../format.dart';
import '../models.dart';
import '../services/api_client.dart';
import '../state/app_state.dart';
import '../theme.dart';

/// Placar da Dominação Relâmpago: contagem regressiva, tomadas, pontos,
/// espólio, MVP e participantes. Sem relógio próprio: atualiza no
/// arrastar-para-recarregar (um `Timer` periódico quebraria os testes de
/// widget com `pumpAndSettle`).
class LightningScreen extends StatefulWidget {
  const LightningScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  State<LightningScreen> createState() => _LightningScreenState();
}

class _LightningScreenState extends State<LightningScreen> {
  late Future<LightningBoard> _future = _startLoad();
  bool _busy = false;

  Future<LightningBoard> _startLoad() {
    final future = context
        .read<AppState>()
        .api
        .getLightning(widget.sessionId);
    future.then<void>((_) {}, onError: (Object _) {});
    return future;
  }

  void _reload() {
    setState(() {
      _future = _startLoad();
    });
  }

  Future<void> _join() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await context.read<AppState>().api.joinLightning(widget.sessionId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Você entrou no relâmpago!')),
      );
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _remaining(DateTime endsAt) {
    final left = endsAt.difference(DateTime.now());
    if (left.isNegative) return 'Encerrado';
    final minutes = left.inMinutes;
    final seconds = left.inSeconds % 60;
    if (minutes > 0) return 'Termina em $minutes min $seconds s';
    return 'Termina em $seconds s';
  }

  @override
  Widget build(BuildContext context) {
    final username = context.watch<AppState>().profile?.username;
    return Scaffold(
      appBar: AppBar(title: const Text('Dominação Relâmpago')),
      body: FutureBuilder<LightningBoard>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Não foi possível carregar o relâmpago.'),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Tentar novamente'),
                  ),
                ],
              ),
            );
          }
          final board = snapshot.data!;
          final joined =
              username != null && board.participants.contains(username);
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Card(
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.bolt_outlined,
                              color: board.open
                                  ? RunoverColors.route
                                  : Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                board.open
                                    ? 'Relâmpago aberto!'
                                    : 'Relâmpago encerrado',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          board.open
                              ? '${_remaining(board.endsAt)} · ${board.durationMin} min de partida'
                              : board.finalized
                              ? 'Espólio pago: +${formatPoints(board.bonusPoints)} pontos no cofre'
                              : 'Aguarde a apuração do espólio',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _Score(
                                value: '${board.takes}',
                                label: 'Tomadas',
                              ),
                            ),
                            Expanded(
                              child: _Score(
                                value: formatPoints(board.points),
                                label: 'Pontos',
                              ),
                            ),
                            if (board.mvp != null)
                              Expanded(
                                child: _Score(
                                  value: '@${board.mvp}',
                                  label: 'MVP',
                                ),
                              ),
                          ],
                        ),
                        if (board.open && !joined) ...[
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _busy ? null : _join,
                              icon: const Icon(Icons.directions_run),
                              label: const Text('Participar'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Participantes (${board.participants.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (board.entries.isEmpty)
                  const Text('Ninguém entrou ainda.')
                else
                  for (final entry in board.entries)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        child: Text(
                          entry.username.isNotEmpty
                              ? entry.username[0].toUpperCase()
                              : '?',
                        ),
                      ),
                      title: Text('@${entry.username}'),
                      trailing: Text(
                        '${entry.takes} tomadas · ${formatPoints(entry.points)} pts',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Score extends StatelessWidget {
  const _Score({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
