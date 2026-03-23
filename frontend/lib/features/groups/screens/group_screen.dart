import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/widgets/app_avatar.dart';
import '../../../shared/utils/format_utils.dart';

final _groupProv = FutureProvider.family.autoDispose<Map<String,dynamic>, String>((ref, id) async {
  final r = await ref.read(apiServiceProvider).get('/groups/$id');
  return Map<String,dynamic>.from(r.data['group'] ?? {});
});

class GroupScreen extends ConsumerStatefulWidget {
  final String groupId;
  const GroupScreen({super.key, required this.groupId});
  @override ConsumerState<GroupScreen> createState() => _S();
}
class _S extends ConsumerState<GroupScreen> with SingleTickerProviderStateMixin {
  late TabController _tc;
  @override void initState() { super.initState(); _tc = TabController(length: 3, vsync: this); }
  @override void dispose() { _tc.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(_groupProv(widget.groupId));
    final me   = ref.watch(currentUserProvider);
    final dark = Theme.of(context).brightness == Brightness.dark;

    return data.when(
      loading: () => Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator(color: AppTheme.orange))),
      error: (e, _) => Scaffold(appBar: AppBar(), body: Center(child: Text('$e'))),
      data: (group) {
        final members = List<dynamic>.from(group['members'] ?? []);
        final myMember = members.firstWhere((m) => m['id'] == me?.id, orElse: () => null);
        final isAdmin  = myMember?['role'] == 'owner' || myMember?['role'] == 'admin';
        final convId   = group['conversation_id'] as String?;

        return Scaffold(
          body: NestedScrollView(
            headerSliverBuilder: (_, __) => [
              SliverAppBar(
                expandedHeight: 200,
                pinned: true,
                title: Text(group['name'] ?? 'Group', style: const TextStyle(fontWeight: FontWeight.w800)),
                actions: [
                  if (isAdmin) IconButton(icon: const Icon(Icons.settings_rounded), onPressed: () => context.push('/group/${widget.groupId}/settings')),
                  PopupMenuButton<String>(onSelected: (v) async {
                    if (v == 'leave') { await ref.read(apiServiceProvider).post('/groups/${widget.groupId}/leave').catchError((_){}); if (context.mounted) context.go('/messages'); }
                    if (v == 'share') {}
                  }, itemBuilder: (_) => [const PopupMenuItem(value: 'share', child: Text('Share Group')), const PopupMenuItem(value: 'leave', child: Text('Leave Group', style: TextStyle(color: Colors.red)))]),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(fit: StackFit.expand, children: [
                    group['avatar_url'] != null
                      ? CachedNetworkImage(imageUrl: group['avatar_url'], fit: BoxFit.cover)
                      : Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [AppTheme.orange, AppTheme.orangeDark]))),
                    Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black.withOpacity(0.6)]))),
                    Positioned(bottom: 16, left: 16, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: AppTheme.orange, borderRadius: BorderRadius.circular(10)), child: Text(group['category'] ?? 'Group', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700))),
                        const SizedBox(width: 8),
                        Text('${members.length} members', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      ]),
                    ])),
                  ]),
                ),
                bottom: PreferredSize(preferredSize: const Size.fromHeight(48), child: TabBar(controller: _tc, indicatorColor: AppTheme.orange, labelColor: AppTheme.orange, unselectedLabelColor: Colors.grey, tabs: const [Tab(text: 'About'), Tab(text: 'Members'), Tab(text: 'Media')])),
              ),
            ],
            body: TabBarView(controller: _tc, children: [
              // About tab
              SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (group['description'] != null) ...[
                  const Text('Description', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 8),
                  Text(group['description'] ?? '', style: const TextStyle(fontSize: 14, height: 1.5)),
                  const SizedBox(height: 16),
                ],
                // Quick actions
                Row(children: [
                  Expanded(child: ElevatedButton.icon(onPressed: convId != null ? () => context.push('/chat/$convId') : null, icon: const Icon(Icons.chat_rounded, size: 18), label: const Text('Open Chat', style: TextStyle(fontWeight: FontWeight.w700)), style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)))),
                  const SizedBox(width: 10),
                  if (isAdmin) Expanded(child: OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.person_add_rounded, size: 18), label: const Text('Invite', style: TextStyle(fontWeight: FontWeight.w700)), style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)))),
                ]),
                const SizedBox(height: 16),
                // Stats
                Row(children: [
                  _GStat(members.length.toString(), 'Members', Icons.people_rounded),
                  const SizedBox(width: 16),
                  _GStat(FormatUtils.date(group['created_at']), 'Created', Icons.calendar_today_rounded),
                ]),
              ])),

              // Members tab
              Column(children: [
                if (isAdmin) Padding(padding: const EdgeInsets.all(12), child: ElevatedButton.icon(onPressed: () {}, icon: const Icon(Icons.person_add_rounded, size: 18), label: const Text('Add Members'), style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 44)))),
                Expanded(child: ListView.builder(itemCount: members.length, itemBuilder: (_, i) {
                  final m = members[i];
                  final isMe2 = m['id'] == me?.id;
                  return ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    leading: AppAvatar(url: m['avatar_url'], size: 46, username: m['username'], showOnline: true, isOnline: m['is_online'] == 1 || m['is_online'] == true),
                    title: Row(children: [
                      Flexible(child: Text(m['display_name'] ?? m['username'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
                      if (m['role'] != 'member' && m['role'] != null) Container(margin: const EdgeInsets.only(left: 6), padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2), decoration: BoxDecoration(color: AppTheme.orangeSurf, borderRadius: BorderRadius.circular(8)), child: Text((m['role'] as String).toUpperCase(), style: const TextStyle(color: AppTheme.orange, fontSize: 9, fontWeight: FontWeight.w800))),
                    ]),
                    subtitle: Text('@${m['username'] ?? ''}', style: const TextStyle(fontSize: 12)),
                    trailing: isMe2 ? null : (isAdmin ? PopupMenuButton<String>(onSelected: (v) async {
                      if (v == 'remove') await ref.read(apiServiceProvider).delete('/messages/conversations/$convId/members/${m['id']}').catchError((_){});
                      if (v == 'promote') await ref.read(apiServiceProvider).put('/groups/${widget.groupId}/members/${m['id']}', data: {'role': 'admin'}).catchError((_){});
                      ref.refresh(_groupProv(widget.groupId));
                    }, itemBuilder: (_) => [const PopupMenuItem(value: 'promote', child: Text('Promote to Admin')), const PopupMenuItem(value: 'remove', child: Text('Remove', style: TextStyle(color: Colors.red)))]) : null),
                    onTap: () => context.push('/profile/${m['id']}'),
                  );
                })),
              ]),

              // Media tab
              _GroupMedia(convId: convId ?? ''),
            ]),
          ),
        );
      },
    );
  }
}

class _GStat extends StatelessWidget {
  final String value, label; final IconData icon;
  const _GStat(this.value, this.label, this.icon);
  @override Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(12)), child: Row(children: [Icon(icon, color: AppTheme.orange, size: 20), const SizedBox(width: 8), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppTheme.orange)), Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey))])])));
  }
}

class _GroupMedia extends ConsumerStatefulWidget {
  final String convId;
  const _GroupMedia({required this.convId});
  @override ConsumerState<_GroupMedia> createState() => _GMS();
}
class _GMS extends ConsumerState<_GroupMedia> {
  List<dynamic> _media = []; bool _l = true;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async { if (widget.convId.isEmpty) { setState(() => _l = false); return; } try { final r = await ref.read(apiServiceProvider).get('/messages/conversations/${widget.convId}/media', q: {'type': 'media'}); setState(() { _media = r.data['messages'] ?? []; _l = false; }); } catch (_) { setState(() => _l = false); } }
  @override Widget build(BuildContext context) => _l ? const Center(child: CircularProgressIndicator(color: AppTheme.orange))
    : _media.isEmpty ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.photo_library_outlined, size: 56, color: Colors.grey), SizedBox(height: 12), Text('No shared media yet', style: TextStyle(color: Colors.grey))]))
    : GridView.builder(padding: const EdgeInsets.all(2), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 2, mainAxisSpacing: 2), itemCount: _media.length, itemBuilder: (_, i) {
        final m = _media[i];
        return GestureDetector(onTap: () => context.push('/media-viewer', extra: {'media': _media.map((x) => {'media_url': x['media_url'], 'media_type': x['type']}).toList(), 'index': i}), child: m['media_url'] != null ? CachedNetworkImage(imageUrl: m['media_url'], fit: BoxFit.cover, errorWidget: (_, __, ___) => Container(color: AppTheme.orangeSurf)) : Container(color: AppTheme.orangeSurf, child: const Icon(Icons.image_rounded, color: AppTheme.orange)));
      });
}
