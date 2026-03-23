
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/widgets/app_avatar.dart';

class MutualFollowersScreen extends ConsumerStatefulWidget {
  final String userId;
  const MutualFollowersScreen({super.key, required this.userId});
  @override ConsumerState<MutualFollowersScreen> createState() => _S();
}
class _S extends ConsumerState<MutualFollowersScreen> {
  List<dynamic> _list = []; bool _l = true;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async { try { final r = await ref.read(apiServiceProvider).get('/users/${widget.userId}/mutual'); setState(() { _list = r.data['mutual'] ?? []; _l = false; }); } catch (_) { setState(() => _l = false); } }
  @override Widget build(BuildContext ctx) => Scaffold(
    appBar: AppBar(title: Text('${_list.length} Mutual Followers', style: const TextStyle(fontWeight: FontWeight.w800))),
    body: _l ? const Center(child: CircularProgressIndicator(color: AppTheme.orange))
      : _list.isEmpty ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.people_outline_rounded, size: 64, color: Colors.grey), SizedBox(height: 12), Text('No mutual followers', style: TextStyle(color: Colors.grey))]))
      : ListView.builder(itemCount: _list.length, itemBuilder: (_, i) {
          final u = _list[i];
          return ListTile(leading: AppAvatar(url: u['avatar_url'], size: 48, username: u['username']), title: Text(u['display_name'] ?? u['username'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text('@${u['username'] ?? ''}'), onTap: () => ctx.push('/profile/${u['id']}'));
        }),
  );
}
