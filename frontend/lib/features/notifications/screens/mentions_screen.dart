
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../core/theme/app_theme.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/widgets/app_avatar.dart';

final _mentionsProv = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  final r = await ref.read(apiServiceProvider).get('/notifications', q: {'type': 'mention', 'limit': '50'});
  return List<dynamic>.from(r.data['notifications'] ?? []);
});

class MentionsScreen extends ConsumerWidget {
  const MentionsScreen({super.key});
  @override Widget build(BuildContext ctx, WidgetRef ref) {
    final mentions = ref.watch(_mentionsProv);
    return Scaffold(
      appBar: AppBar(title: const Text('Mentions', style: TextStyle(fontWeight: FontWeight.w800))),
      body: mentions.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.orange)),
        error: (_, __) => Center(child: ElevatedButton(onPressed: () => ref.refresh(_mentionsProv), child: const Text('Retry'))),
        data: (list) {
          if (list.isEmpty) return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.alternate_email_rounded, size: 64, color: Colors.grey), SizedBox(height: 12), Text('No mentions yet', style: TextStyle(color: Colors.grey))]));
          return RefreshIndicator(color: AppTheme.orange, onRefresh: () async => ref.refresh(_mentionsProv), child: ListView.builder(itemCount: list.length, itemBuilder: (_, i) {
            final n = list[i];
            return ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              leading: AppAvatar(url: n['actor_avatar'], size: 46, username: n['actor_username']),
              title: RichText(text: TextSpan(style: Theme.of(ctx).textTheme.bodyMedium, children: [TextSpan(text: n['actor_name'] ?? n['actor_username'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700)), const TextSpan(text: ' mentioned you in a '), TextSpan(text: n['target_type'] ?? 'post', style: const TextStyle(color: AppTheme.orange))])),
              subtitle: Text(n['message'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
              trailing: Text(timeago.format(DateTime.tryParse(n['created_at'] ?? '') ?? DateTime.now()), style: const TextStyle(fontSize: 11, color: Colors.grey)),
              onTap: () {
                if (n['target_type'] == 'post') ctx.push('/post/${n['target_id']}');
                else if (n['target_type'] == 'comment') ctx.push('/post/${n['target_id']}');
              },
            );
          }));
        },
      ),
    );
  }
}
