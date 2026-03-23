import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../core/theme/app_theme.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/widgets/app_avatar.dart';
import '../../../shared/utils/format_utils.dart';

final _callsProv = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  final r = await ref.read(apiServiceProvider).get('/calls');
  return List<dynamic>.from(r.data['calls'] ?? []);
});

class CallHistoryScreen extends ConsumerWidget {
  const CallHistoryScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final calls = ref.watch(_callsProv);
    final dark  = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('Calls', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [IconButton(icon: const Icon(Icons.call_rounded), onPressed: () => context.push('/add-contact'), tooltip: 'New Call')]),
      body: calls.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.orange)),
        error: (e, _) => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.call_missed_outgoing_rounded, size: 64, color: Colors.grey), const SizedBox(height: 12), ElevatedButton(onPressed: () => ref.refresh(_callsProv), child: const Text('Retry'))])),
        data: (list) => list.isEmpty ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.call_outlined, size: 72, color: Colors.grey), const SizedBox(height: 16), const Text('No calls yet', style: TextStyle(fontSize: 17, color: Colors.grey)), const SizedBox(height: 8), const Text('Your call history will appear here', style: TextStyle(color: Colors.grey, fontSize: 13))]))
          : RefreshIndicator(color: AppTheme.orange, onRefresh: () async => ref.refresh(_callsProv), child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (_, i) {
                final c = list[i];
                final isOut   = c['direction'] == 'outgoing' || c['caller_id'] != c['other_id'];
                final status  = c['status'] as String? ?? 'ended';
                final isVideo = c['type'] == 'video';
                final missed  = status == 'missed' || status == 'rejected';
                final dur     = c['duration'] as int? ?? 0;
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: Stack(children: [
                    AppAvatar(url: c['avatar_url'], size: 50, username: c['other_username'] ?? c['other_display_name']),
                    Positioned(bottom: 0, right: 0, child: Container(width: 20, height: 20, decoration: BoxDecoration(color: isVideo ? const Color(0xFF2196F3) : AppTheme.orange, shape: BoxShape.circle, border: Border.all(color: dark ? AppTheme.dBg : Colors.white, width: 1.5)), child: Icon(isVideo ? Icons.videocam_rounded : Icons.call_rounded, color: Colors.white, size: 11))),
                  ]),
                  title: Text(c['other_display_name'] ?? c['other_username'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  subtitle: Row(children: [
                    Icon(isOut ? Icons.call_made_rounded : Icons.call_received_rounded, size: 13, color: missed ? Colors.red : const Color(0xFF4CAF50)),
                    const SizedBox(width: 4),
                    Text(missed ? 'Missed' : (isOut ? 'Outgoing' : 'Incoming'), style: TextStyle(fontSize: 12, color: missed ? Colors.red : Colors.grey)),
                    if (dur > 0) ...[Text(' • ', style: TextStyle(color: Colors.grey, fontSize: 12)), Text(FormatUtils.dur(dur), style: const TextStyle(fontSize: 12, color: Colors.grey))],
                  ]),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(timeago.format(DateTime.tryParse(c['created_at'] ?? '') ?? DateTime.now()), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      const SizedBox(height: 4),
                      Text(_statusLabel(status), style: TextStyle(fontSize: 10, color: _statusColor(status), fontWeight: FontWeight.w600)),
                    ]),
                    const SizedBox(width: 8),
                    IconButton(icon: Icon(isVideo ? Icons.videocam_rounded : Icons.call_rounded, color: AppTheme.orange, size: 22), onPressed: () => context.push('/call/${isVideo ? 'video' : 'audio'}', extra: {'user_id': c['other_id'], 'user_name': c['other_display_name'] ?? c['other_username'], 'avatar': c['avatar_url'], 'is_incoming': false})),
                  ]),
                  onTap: () => context.push('/profile/${c['other_id']}'),
                );
              },
            )),
      ),
    );
  }
  static String _statusLabel(String s) { switch(s) { case 'missed': return 'Missed'; case 'rejected': return 'Declined'; case 'ended': return 'Completed'; case 'ongoing': return 'Ongoing'; default: return s; } }
  static Color _statusColor(String s) { switch(s) { case 'missed': return Colors.red; case 'rejected': return Colors.orange; case 'ongoing': return Colors.green; default: return Colors.grey; } }
}
