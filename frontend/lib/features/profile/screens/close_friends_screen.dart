
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/widgets/app_avatar.dart';

final _cfProv = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  final r = await ref.read(apiServiceProvider).get('/close-friends');
  return List<dynamic>.from(r.data['friends'] ?? []);
});

class CloseFriendsScreen extends ConsumerWidget {
  const CloseFriendsScreen({super.key});
  @override Widget build(BuildContext ctx, WidgetRef ref) {
    final friends = ref.watch(_cfProv);
    return Scaffold(
      appBar: AppBar(title: const Text('Close Friends', style: TextStyle(fontWeight: FontWeight.w800)), actions: [TextButton(onPressed: () => ctx.push('/contacts'), child: const Text('Add', style: TextStyle(color: AppTheme.orange)))]),
      body: Column(children: [
        Container(margin: const EdgeInsets.all(12), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF4CAF50).withOpacity(0.1), borderRadius: BorderRadius.circular(12)), child: const Row(children: [Icon(Icons.people_rounded, color: Color(0xFF4CAF50), size: 20), SizedBox(width: 8), Expanded(child: Text('Only close friends can see stories you share with this list.', style: TextStyle(color: Color(0xFF4CAF50), fontSize: 12)))])),
        Expanded(child: friends.when(
          loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.orange)),
          error: (_, __) => const Center(child: Text('Error')),
          data: (list) {
            if (list.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.group_rounded, size: 64, color: Colors.grey), const SizedBox(height: 12), const Text('No close friends yet', style: TextStyle(color: Colors.grey)), const SizedBox(height: 12), ElevatedButton(onPressed: () => ctx.push('/contacts'), child: const Text('Add People'))]));
            return ListView.builder(itemCount: list.length, itemBuilder: (_, i) {
              final u = list[i];
              return ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                leading: AppAvatar(url: u['avatar_url'], size: 50, username: u['username'], showOnline: true, isOnline: u['is_online'] == 1 || u['is_online'] == true),
                title: Text(u['display_name'] ?? u['username'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('@${u['username'] ?? ''}'),
                trailing: TextButton(onPressed: () async { await ref.read(apiServiceProvider).delete('/close-friends/${u['id']}').catchError((_){}); ref.refresh(_cfProv); }, child: const Text('Remove', style: TextStyle(color: Colors.red, fontSize: 12))),
                onTap: () => ctx.push('/profile/${u['id']}'),
              );
            });
          },
        )),
      ]),
    );
  }
}
