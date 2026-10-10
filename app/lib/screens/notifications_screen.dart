import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/centered_content.dart';

/// RF18/RN16 — UC "Receber Notificação".
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late Future<List<NotificationEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<AppState>().api.getNotifications();
  }

  Future<void> _open(NotificationEntry n) async {
    if (!n.isRead) {
      await context.read<AppState>().api.markNotificationRead(
        n.id,
      ); // "Marca notificação como lida"
      setState(() {
        _future = context.read<AppState>().api.getNotifications();
      });
    }
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'conquista':
        return Icons.emoji_events;
      case 'perda':
        return Icons.trending_down;
      case 'nivel':
        return Icons.arrow_upward;
      case 'ranking':
        return Icons.leaderboard;
      case 'liga':
        return Icons.military_tech;
      default:
        return Icons.campaign;
    }
  }

  Color _colorFor(String type) {
    switch (type) {
      case 'conquista':
        return RunoverColors.territory;
      case 'perda':
        return Colors.redAccent;
      case 'nivel':
        return RunoverColors.route;
      case 'ranking':
        return RunoverColors.territory;
      case 'liga':
        return const Color(0xFFFFB020); // dourado de troféu das ligas
      default:
        return RunoverColors.route;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notificações')),
      body: FutureBuilder<List<NotificationEntry>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: RunoverColors.route),
            );
          }
          final items = snapshot.data!;
          if (items.isEmpty) {
            return const Center(child: Text('Nenhuma notificação ainda.'));
          }
          return CenteredContent(
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final n = items[i];
                return ListTile(
                  onTap: () => _open(n),
                  tileColor: n.isRead
                      ? null
                      : RunoverColors.route.withValues(alpha: 0.06),
                  leading: Icon(_iconFor(n.type), color: _colorFor(n.type)),
                  title: Text(
                    n.message,
                    style: TextStyle(
                      fontWeight: n.isRead
                          ? FontWeight.normal
                          : FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    '${n.createdAt.day}/${n.createdAt.month} às ${n.createdAt.hour}:${n.createdAt.minute.toString().padLeft(2, '0')}',
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
