
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../core/theme/app_theme.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/utils/format_utils.dart';

final _logProv = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  final r = await ref.read(apiServiceProvider).get('/users/activity-log');
  return List<dynamic>.from(r.data['log'] ?? []);
});

class ActivityLogScreen extends ConsumerWidget {
  const ActivityLogScreen({super.key});
  @override Widget build(BuildContext ctx, WidgetRef ref) {
    final log = ref.watch(_logProv);
    return Scaffold(
      appBar: AppBar(title: const Text('Activity Log', style: TextStyle(fontWeight: FontWeight.w800))),
      body: log.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.orange)),
        error: (e, _) => Center(child: ElevatedButton(onPressed: () => ref.refresh(_logProv), child: const Text('Retry'))),
        data: (list) {
          if (list.isEmpty) return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.history_rounded, size: 64, color: Colors.grey), SizedBox(height: 12), Text('No activity yet', style: TextStyle(color: Colors.grey))]));
          return RefreshIndicator(color: AppTheme.orange, onRefresh: () async => ref.refresh(_logProv), child: ListView.builder(itemCount: list.length, itemBuilder: (_, i) {
            final l = list[i];
            final icon = _icon(l['action'] as String? ?? '');
            return ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: Container(width: 42, height: 42, decoration: BoxDecoration(color: icon.color.withOpacity(0.12), borderRadius: BorderRadius.circular(12)), child: Icon(icon.icon, color: icon.color, size: 20)),
              title: Text(l['description'] ?? l['action'] ?? '', style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
              subtitle: Row(children: [if (l['ip_address'] != null) Text('${l['ip_address']}  •  ', style: const TextStyle(fontSize: 11, color: Colors.grey)), Text(timeago.format(DateTime.tryParse(l['created_at'] ?? '') ?? DateTime.now()), style: const TextStyle(fontSize: 11, color: Colors.grey))]),
            );
          }));
        },
      ),
    );
  }
  static ({IconData icon, Color color}) _icon(String a) {
    if (a.contains('login'))    return (icon: Icons.login_rounded,         color: const Color(0xFF4CAF50));
    if (a.contains('password')) return (icon: Icons.lock_reset_rounded,    color: Colors.orange);
    if (a.contains('coin'))     return (icon: Icons.monetization_on_rounded,color: AppTheme.orange);
    if (a.contains('follow'))   return (icon: Icons.people_rounded,        color: const Color(0xFF2196F3));
    if (a.contains('post'))     return (icon: Icons.image_rounded,         color: const Color(0xFF9C27B0));
    if (a.contains('gift'))     return (icon: Icons.card_giftcard_rounded,  color: Colors.red);
    if (a.contains('escrow'))   return (icon: Icons.security_rounded,       color: Colors.green);
    if (a.contains('block'))    return (icon: Icons.block_rounded,          color: Colors.red);
    return (icon: Icons.history_rounded, color: Colors.grey);
  }
}
