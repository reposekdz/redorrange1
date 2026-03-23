
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/widgets/app_avatar.dart';
import '../../../shared/utils/format_utils.dart';

class PostLikesScreen extends ConsumerStatefulWidget {
  final String postId;
  const PostLikesScreen({super.key, required this.postId});
  @override ConsumerState<PostLikesScreen> createState() => _S();
}
class _S extends ConsumerState<PostLikesScreen> {
  List<dynamic> _users = []; bool _l = true; String _q = '';
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async { try { final r = await ref.read(apiServiceProvider).get('/interactions/posts/${widget.postId}/likes'); setState(() { _users = r.data['users'] ?? []; _l = false; }); } catch (_) { setState(() => _l = false); } }
  @override Widget build(BuildContext context) {
    final filtered = _q.isEmpty ? _users : _users.where((u) => (u['display_name'] ?? u['username'] ?? '').toString().toLowerCase().contains(_q.toLowerCase())).toList();
    return Scaffold(
      appBar: AppBar(title: Text('${FormatUtils.count(_users.length)} Likes', style: const TextStyle(fontWeight: FontWeight.w800))),
      body: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 4), child: TextField(onChanged: (v) => setState(() => _q = v), decoration: const InputDecoration(hintText: 'Search...', prefixIcon: Icon(Icons.search_rounded, size: 18), isDense: true))),
        Expanded(child: _l ? const Center(child: CircularProgressIndicator(color: AppTheme.orange)) : filtered.isEmpty ? const Center(child: Text('No likes yet', style: TextStyle(color: Colors.grey)))
          : ListView.builder(itemCount: filtered.length, itemBuilder: (_, i) {
              final u = filtered[i];
              final me = ref.watch(currentUserProvider);
              return ListTile(
                leading: AppAvatar(url: u['avatar_url'], size: 46, username: u['username']),
                title: Row(children: [Flexible(child: Text(u['display_name'] ?? u['username'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)), if (u['is_verified'] == 1 || u['is_verified'] == true) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.verified_rounded, color: AppTheme.orange, size: 13))]),
                subtitle: Text('@${u['username'] ?? ''}'),
                trailing: Text(_reactEmoji(u['reaction_type'] ?? 'like'), style: const TextStyle(fontSize: 22)),
                onTap: () => context.push('/profile/${u['id']}'),
              );
            })),
      ]),
    );
  }
  String _reactEmoji(String t) { const m = {'like': '👍', 'love': '❤️', 'haha': '😂', 'wow': '😮', 'sad': '😢', 'angry': '😡'}; return m[t] ?? '❤️'; }
}
