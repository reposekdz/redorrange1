
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/widgets/app_avatar.dart';

final _reqsProv = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  final r = await ref.read(apiServiceProvider).get('/users/follow-requests');
  return List<dynamic>.from(r.data['requests'] ?? []);
});

class FollowRequestsScreen extends ConsumerWidget {
  const FollowRequestsScreen({super.key});
  @override Widget build(BuildContext ctx, WidgetRef ref) {
    final reqs = ref.watch(_reqsProv);
    return Scaffold(
      appBar: AppBar(title: const Text('Follow Requests', style: TextStyle(fontWeight: FontWeight.w800))),
      body: reqs.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.orange)),
        error: (_, __) => const Center(child: Text('Error loading requests')),
        data: (list) {
          if (list.isEmpty) return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.person_add_disabled_rounded, size: 64, color: Colors.grey), SizedBox(height: 12), Text('No pending requests', style: TextStyle(color: Colors.grey))]));
          return ListView.builder(itemCount: list.length, itemBuilder: (_, i) {
            final u = list[i];
            return _ReqTile(user: u, onAction: () => ref.refresh(_reqsProv));
          });
        },
      ),
    );
  }
}
class _ReqTile extends ConsumerStatefulWidget {
  final dynamic user; final VoidCallback onAction;
  const _ReqTile({required this.user, required this.onAction});
  @override ConsumerState<_ReqTile> createState() => _RTS();
}
class _RTS extends ConsumerState<_ReqTile> {
  bool _loading = false, _done = false;
  Future<void> _respond(bool accept) async {
    setState(() => _loading = true);
    await ref.read(apiServiceProvider).post('/users/${widget.user['id']}/follow-respond', data: {'action': accept ? 'accept' : 'reject'}).catchError((_){});
    if (mounted) { setState(() { _loading = false; _done = true; }); widget.onAction(); }
  }
  @override Widget build(BuildContext _) {
    if (_done) return const SizedBox.shrink();
    return ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: AppAvatar(url: widget.user['avatar_url'], size: 50, username: widget.user['username']),
      title: Text(widget.user['display_name'] ?? widget.user['username'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
      subtitle: Text('@${widget.user['username'] ?? ''}'),
      trailing: _loading ? const SizedBox(width: 24, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.orange)) : Row(mainAxisSize: MainAxisSize.min, children: [
        ElevatedButton(onPressed: () => _respond(true), style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), textStyle: const TextStyle(fontSize: 12)), child: const Text('Accept')),
        const SizedBox(width: 6),
        OutlinedButton(onPressed: () => _respond(false), style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), textStyle: const TextStyle(fontSize: 12)), child: const Text('Decline')),
      ]),
      onTap: () => context.push('/profile/${widget.user['id']}'),
    );
  }
}
