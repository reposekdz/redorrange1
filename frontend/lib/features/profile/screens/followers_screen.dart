import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/widgets/app_avatar.dart';
import '../../../shared/utils/format_utils.dart';

class FollowersScreen extends ConsumerStatefulWidget {
  final String userId, type;
  const FollowersScreen({super.key, required this.userId, this.type = 'followers'});
  @override ConsumerState<FollowersScreen> createState() => _S();
}
class _S extends ConsumerState<FollowersScreen> with SingleTickerProviderStateMixin {
  late TabController _tc;
  List<dynamic> _followers = [], _following = [];
  bool _loading = true;
  @override void initState() { super.initState(); _tc = TabController(length: 2, vsync: this, initialIndex: widget.type == 'following' ? 1 : 0); _load(); }
  @override void dispose() { _tc.dispose(); super.dispose(); }
  Future<void> _load() async {
    try {
      final [fr, fg] = await Future.wait([
        ref.read(apiServiceProvider).get('/users/${widget.userId}/followers'),
        ref.read(apiServiceProvider).get('/users/${widget.userId}/following'),
      ]);
      if (mounted) setState(() { _followers = fr.data['followers'] ?? []; _following = fg.data['following'] ?? []; _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Connections', style: TextStyle(fontWeight: FontWeight.w800)),
      bottom: TabBar(controller: _tc, indicatorColor: AppTheme.orange, labelColor: AppTheme.orange, unselectedLabelColor: Colors.grey,
        tabs: [Tab(text: '${FormatUtils.count(_followers.length)} Followers'), Tab(text: '${FormatUtils.count(_following.length)} Following')])),
    body: _loading ? const Center(child: CircularProgressIndicator(color: AppTheme.orange)) : TabBarView(controller: _tc, children: [
      _UserList(users: _followers, emptyMsg: 'No followers yet'),
      _UserList(users: _following, emptyMsg: 'Not following anyone yet'),
    ]),
  );
}
class _UserList extends ConsumerStatefulWidget {
  final List<dynamic> users; final String emptyMsg;
  const _UserList({required this.users, required this.emptyMsg});
  @override ConsumerState<_UserList> createState() => _ULS();
}
class _ULS extends ConsumerState<_UserList> {
  final _c = TextEditingController(); String _q = '';
  @override void dispose() { _c.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) {
    final me = ref.watch(currentUserProvider);
    final filtered = _q.isEmpty ? widget.users : widget.users.where((u) => (u['display_name'] ?? u['username'] ?? '').toString().toLowerCase().contains(_q.toLowerCase())).toList();
    if (widget.users.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.people_outline_rounded, size: 64, color: Colors.grey), const SizedBox(height: 12), Text(widget.emptyMsg, style: const TextStyle(color: Colors.grey, fontSize: 15))]));
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(12,10,12,4), child: TextField(_c, onChanged: (v) => setState(() => _q = v), decoration: const InputDecoration(hintText: 'Search...', prefixIcon: Icon(Icons.search_rounded, size: 20), isDense: true))),
      Expanded(child: ListView.builder(itemCount: filtered.length, itemBuilder: (_, i) {
        final u = filtered[i]; final isMe = u['id'] == me?.id;
        return ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: AppAvatar(url: u['avatar_url'], size: 48, username: u['username'], showOnline: true, isOnline: u['is_online'] == 1 || u['is_online'] == true),
          title: Row(children: [Flexible(child: Text(u['display_name'] ?? u['username'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)), if (u['is_verified'] == 1 || u['is_verified'] == true) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.verified_rounded, color: AppTheme.orange, size: 14))]),
          subtitle: Text('@${u['username'] ?? ''}'),
          trailing: isMe ? null : _FollowBtn(uid: u['id'] as String, following: u['follow_status'] == 'accepted' || u['is_following'] == true || u['is_following'] == 1),
          onTap: () => context.push('/profile/${u['id']}'));
      })),
    ]);
  }
}
class _FollowBtn extends ConsumerStatefulWidget {
  final String uid; final bool following;
  const _FollowBtn({required this.uid, required this.following});
  @override ConsumerState<_FollowBtn> createState() => _FBS();
}
class _FBS extends ConsumerState<_FollowBtn> {
  late bool _f; bool _l = false;
  @override void initState() { super.initState(); _f = widget.following; }
  @override Widget build(BuildContext _) => SizedBox(height: 32, child: _l ? const SizedBox(width: 24, child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.orange)))
    : _f ? OutlinedButton(onPressed: _toggle, style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12), textStyle: const TextStyle(fontSize: 12)), child: const Text('Following'))
         : ElevatedButton(onPressed: _toggle, style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12), textStyle: const TextStyle(fontSize: 12)), child: const Text('Follow')));
  Future<void> _toggle() async { setState(() => _l = true); await ref.read(apiServiceProvider).post('/users/${widget.uid}/follow').catchError((_){}); if (mounted) setState(() { _f = !_f; _l = false; }); }
}
