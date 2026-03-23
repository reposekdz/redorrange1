
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/widgets/app_avatar.dart';

final _blockedProv = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  final r = await ref.read(apiServiceProvider).get('/users/blocked');
  return List<dynamic>.from(r.data['blocked'] ?? []);
});

class BlockedUsersScreen extends ConsumerWidget {
  const BlockedUsersScreen({super.key});
  @override Widget build(BuildContext ctx, WidgetRef ref) {
    final blocked = ref.watch(_blockedProv);
    return Scaffold(
      appBar: AppBar(title: const Text('Blocked Users', style: TextStyle(fontWeight: FontWeight.w800))),
      body: blocked.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.orange)),
        error: (_, __) => const Center(child: Text('Error')),
        data: (list) {
          if (list.isEmpty) return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.block_rounded, size: 64, color: Colors.grey), SizedBox(height: 12), Text('No blocked users', style: TextStyle(color: Colors.grey))]));
          return ListView.builder(itemCount: list.length, itemBuilder: (_, i) {
            final u = list[i];
            return ListTile(
              leading: AppAvatar(url: u['avatar_url'], size: 48, username: u['username']),
              title: Text(u['display_name'] ?? u['username'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('@${u['username'] ?? ''}'),
              trailing: TextButton(onPressed: () async { await ref.read(apiServiceProvider).post('/users/${u['id']}/block').catchError((_){}); ref.refresh(_blockedProv); }, child: const Text('Unblock', style: TextStyle(color: AppTheme.orange, fontWeight: FontWeight.w600))),
            );
          });
        },
      ),
    );
  }
}
