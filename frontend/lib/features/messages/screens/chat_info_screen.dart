import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/api_service.dart';
import '../../../core/models/models.dart';
import '../../../shared/widgets/app_avatar.dart';
import '../../../shared/utils/format_utils.dart';

final _chatInfoProv = FutureProvider.family<Map<String,dynamic>, String>((ref, cid) async {
  final api = ref.read(apiServiceProvider);
  final [cr, mr, pr] = await Future.wait([
    api.get('/messages/conversations/$cid'),
    api.get('/messages/conversations/$cid/media'),
    api.get('/messages/conversations/$cid/pinned'),
  ]);
  return {
    'conversation': cr.data['conversation'] ?? {},
    'media': mr.data['messages'] ?? [],
    'pinned': pr.data['messages'] ?? [],
  };
});

class ChatInfoScreen extends ConsumerStatefulWidget {
  final String convId;
  const ChatInfoScreen({super.key, required this.convId});
  @override ConsumerState<ChatInfoScreen> createState() => _S();
}
class _S extends ConsumerState<ChatInfoScreen> with SingleTickerProviderStateMixin {
  late TabController _tc;
  bool _notifs = true, _muted = false;

  @override void initState() { super.initState(); _tc = TabController(length: 3, vsync: this); }
  @override void dispose() { _tc.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final info = ref.watch(_chatInfoProv(widget.convId));
    final me   = ref.watch(currentUserProvider);
    final dark = Theme.of(context).brightness == Brightness.dark;

    return info.when(
      loading: () => Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator(color: AppTheme.orange))),
      error: (e, _) => Scaffold(appBar: AppBar(), body: Center(child: Text('$e'))),
      data: (data) {
        final conv    = Map<String,dynamic>.from(data['conversation'] as Map? ?? {});
        final media   = List<Map<String,dynamic>>.from(data['media'] as List? ?? []);
        final pinned  = List<Map<String,dynamic>>.from(data['pinned'] as List? ?? []);
        final isGroup = conv['type'] == 'group';
        final members = List<dynamic>.from(conv['members'] ?? []);
        final otherId = conv['other_id'] as String?;
        final isAdmin = members.any((m) => m['id'] == me?.id && (m['role'] == 'owner' || m['role'] == 'admin'));

        return Scaffold(
          body: CustomScrollView(slivers: [
            // Header with avatar + name
            SliverAppBar(
              expandedHeight: isGroup ? 220 : 280,
              pinned: true,
              leading: IconButton(icon: const Icon(Icons.arrow_back_rounded, color: Colors.white), onPressed: () => context.pop()),
              actions: [IconButton(icon: const Icon(Icons.more_vert_rounded, color: Colors.white), onPressed: () => _moreOptions(context, conv, isGroup, isAdmin))],
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(fit: StackFit.expand, children: [
                  // Background
                  conv['other_avatar_url'] != null || conv['avatar_url'] != null
                    ? CachedNetworkImage(imageUrl: (isGroup ? conv['avatar_url'] : conv['other_avatar_url']) ?? '', fit: BoxFit.cover, errorWidget: (_, __, ___) => Container(color: AppTheme.orange))
                    : Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [AppTheme.orange, AppTheme.orangeDark]))),
                  Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black.withOpacity(0.7)]))),
                  Positioned(bottom: 20, left: 0, right: 0, child: Column(children: [
                    if (!isGroup) AppAvatar(url: conv['other_avatar_url'], size: 80, username: conv['other_display_name'] ?? conv['other_username']),
                    if (!isGroup) const SizedBox(height: 8),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(isGroup ? (conv['name'] ?? 'Group') : (conv['other_display_name'] ?? conv['other_username'] ?? ''), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 22)),
                      if (conv['other_is_verified'] == true || conv['other_is_verified'] == 1) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.verified_rounded, color: AppTheme.orange, size: 18)),
                    ]),
                    const SizedBox(height: 4),
                    if (!isGroup) Text(conv['other_is_online'] == true ? '🟢 Online now' : 'Offline', style: const TextStyle(color: Colors.white70, fontSize: 13))
                    else Text('${members.length} members', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  ])),
                ]),
              ),
            ),

            SliverToBoxAdapter(child: Column(children: [
              // Quick actions
              Container(color: dark ? AppTheme.dCard : Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                _QA(Icons.call_rounded,        'Audio', () { if (otherId != null) context.push('/call/audio', extra: {'user_id': otherId, 'user_name': conv['other_display_name'] ?? '', 'avatar': conv['other_avatar_url'], 'is_incoming': false}); }),
                _QA(Icons.videocam_rounded,     'Video', () { if (otherId != null) context.push('/call/video',  extra: {'user_id': otherId, 'user_name': conv['other_display_name'] ?? '', 'avatar': conv['other_avatar_url'], 'is_incoming': false}); }),
                _QA(Icons.search_rounded,       'Search', () {}),
                _QA(Icons.notifications_rounded, _notifs ? 'Mute' : 'Unmute', () { setState(() => _notifs = !_notifs); }),
                if (!isGroup) _QA(Icons.person_rounded, 'Profile', () { if (otherId != null) context.push('/profile/$otherId'); }),
                if (isGroup && isAdmin) _QA(Icons.group_add_rounded, 'Add', () {}),
              ])),
              const Divider(height: 0.5),

              // Disappearing messages
              _SettingRow(Icons.timer_rounded, 'Disappearing Messages', '${conv['disappearing_timer'] ?? 0 > 0 ? FormatUtils.dur(conv['disappearing_timer'] ?? 0) : 'Off'}', onTap: () => context.push('/chat/${widget.convId}/disappearing')),

              // Notifications
              _SwitchRow(Icons.notifications_outlined, 'Notifications', !_muted, (v) { setState(() => _muted = !v); ref.read(apiServiceProvider).post('/messages/conversations/${widget.convId}/mute', data: {'duration_hours': v ? 0 : 8}).catchError((_){}); }),

              // Encryption
              Container(color: dark ? AppTheme.dCard : Colors.white, margin: const EdgeInsets.only(top: 8), padding: const EdgeInsets.all(14), child: Row(children: [const Icon(Icons.lock_rounded, color: AppTheme.orange, size: 18), const SizedBox(width: 10), const Expanded(child: Text('Messages are end-to-end encrypted. Only you and the recipient can read them.', style: TextStyle(fontSize: 13, color: Colors.grey)))])),

              // Media tabs
              const SizedBox(height: 12),
              Container(color: dark ? AppTheme.dCard : Colors.white, child: Column(children: [
                TabBar(controller: _tc, indicatorColor: AppTheme.orange, labelColor: AppTheme.orange, unselectedLabelColor: Colors.grey, tabs: [
                  Tab(text: 'Media (${media.where((m) => ['image','video'].contains(m['type'])).length})'),
                  Tab(text: 'Files (${media.where((m) => m['type'] == 'file').length})'),
                  Tab(text: 'Links'),
                ]),
                SizedBox(height: 200, child: TabBarView(controller: _tc, children: [
                  _MediaGrid(items: media.where((m) => ['image','video'].contains(m['type'])).toList()),
                  _FilesList(items: media.where((m) => m['type'] == 'file').toList()),
                  const Center(child: Text('No links shared', style: TextStyle(color: Colors.grey))),
                ])),
              ])),

              // Pinned messages
              if (pinned.isNotEmpty) ...[
                const SizedBox(height: 12),
                _Section('Pinned Messages', dark),
                ...pinned.take(3).map((m) => Container(color: dark ? AppTheme.dCard : Colors.white, child: ListTile(
                  leading: const Icon(Icons.push_pin_rounded, color: AppTheme.orange, size: 20),
                  title: Text(m['content'] ?? m['type'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                  subtitle: Text('Pinned by ${m['display_name'] ?? 'User'}', style: const TextStyle(fontSize: 11)),
                  trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 18),
                ))),
              ],

              // Members (group)
              if (isGroup) ...[
                const SizedBox(height: 12),
                Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 4), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('${members.length} Members', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)), if (isAdmin) TextButton.icon(onPressed: () {}, icon: const Icon(Icons.person_add_rounded, size: 16), label: const Text('Add'))])),
                ...members.take(5).map((m) => Container(color: dark ? AppTheme.dCard : Colors.white, child: ListTile(
                  leading: AppAvatar(url: m['avatar_url'], size: 44, username: m['username'], showOnline: true, isOnline: m['is_online'] == 1 || m['is_online'] == true),
                  title: Row(children: [Text(m['display_name'] ?? m['username'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)), if (m['role'] != 'member' && m['role'] != null) Padding(padding: const EdgeInsets.only(left: 8), child: Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2), decoration: BoxDecoration(color: AppTheme.orangeSurf, borderRadius: BorderRadius.circular(8)), child: Text((m['role'] as String).toUpperCase(), style: const TextStyle(color: AppTheme.orange, fontSize: 9, fontWeight: FontWeight.w800))))]),
                  subtitle: Text('@${m['username'] ?? ''}', style: const TextStyle(fontSize: 12)),
                  onTap: () => context.push('/profile/${m['id']}'),
                ))),
                if (members.length > 5) TextButton(onPressed: () => context.push('/group/${widget.convId}/settings'), child: Text('View all ${members.length} members', style: const TextStyle(color: AppTheme.orange))),
              ],

              // Danger zone
              const SizedBox(height: 12),
              if (!isGroup) ...[
                _DangerBtn(Icons.block_rounded, 'Block ${conv['other_display_name'] ?? 'User'}', Colors.red, () async { await ref.read(apiServiceProvider).post('/users/${otherId}/block').catchError((_){}); if (mounted) context.pop(); }),
                _DangerBtn(Icons.flag_rounded, 'Report ${conv['other_display_name'] ?? 'User'}', Colors.orange, () => context.push('/report/user/$otherId')),
              ],
              if (isGroup) _DangerBtn(Icons.exit_to_app_rounded, 'Leave Group', Colors.red, () async { await ref.read(apiServiceProvider).post('/messages/conversations/${widget.convId}/leave').catchError((_){}); if (mounted) context.go('/messages'); }),
              const SizedBox(height: 30),
            ])),
          ]),
        );
      },
    );
  }

  void _moreOptions(BuildContext ctx, Map conv, bool isGroup, bool isAdmin) {
    showModalBottomSheet(context: ctx, builder: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
      const SizedBox(height: 8),
      if (isGroup && isAdmin) ListTile(leading: const Icon(Icons.edit_rounded, color: AppTheme.orange), title: const Text('Edit Group'), onTap: () { Navigator.pop(ctx); context.push('/group/${widget.convId}/settings'); }),
      ListTile(leading: const Icon(Icons.archive_rounded), title: const Text('Archive Chat'), onTap: () { Navigator.pop(ctx); ref.read(apiServiceProvider).post('/messages/conversations/${widget.convId}/archive', data: {'archived': true}).catchError((_){}); context.go('/messages'); }),
      ListTile(leading: const Icon(Icons.schedule_send_rounded, color: AppTheme.orange), title: const Text('Scheduled Messages'), onTap: () { Navigator.pop(ctx); context.push('/chat/${widget.convId}/schedule'); }),
      ListTile(leading: const Icon(Icons.collections_rounded, color: AppTheme.orange), title: const Text('Shared Media'), onTap: () { Navigator.pop(ctx); context.push('/chat-media/${widget.convId}'); }),
      ListTile(leading: const Icon(Icons.star_rounded, color: AppTheme.orange), title: const Text('Starred Messages'), onTap: () { Navigator.pop(ctx); context.push('/starred-messages'); }),
      const SizedBox(height: 14),
    ]));
  }
}

class _QA extends StatelessWidget {
  final IconData icon; final String label; final VoidCallback onTap;
  const _QA(this.icon, this.label, this.onTap);
  @override Widget build(BuildContext _) => GestureDetector(onTap: onTap, child: Column(children: [
    Container(width: 52, height: 52, decoration: BoxDecoration(color: AppTheme.orangeSurf, borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: AppTheme.orange, size: 24)),
    const SizedBox(height: 5), Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
  ]));
}

class _SettingRow extends ConsumerWidget {
  final IconData icon; final String label, value; final VoidCallback onTap;
  const _SettingRow(this.icon, this.label, this.value, {required this.onTap});
  @override Widget build(BuildContext ctx, WidgetRef ref) {
    final dark = Theme.of(ctx).brightness == Brightness.dark;
    return Container(color: dark ? AppTheme.dCard : Colors.white, child: ListTile(
      leading: Icon(icon, color: AppTheme.orange, size: 22), title: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [Text(value, style: const TextStyle(color: Colors.grey, fontSize: 13)), const Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 18)]),
      onTap: onTap,
    ));
  }
}

class _SwitchRow extends ConsumerWidget {
  final IconData icon; final String label; final bool val; final void Function(bool) onChange;
  const _SwitchRow(this.icon, this.label, this.val, this.onChange);
  @override Widget build(BuildContext ctx, WidgetRef ref) {
    final dark = Theme.of(ctx).brightness == Brightness.dark;
    return Container(color: dark ? AppTheme.dCard : Colors.white, child: SwitchListTile.adaptive(
      secondary: Icon(icon, color: AppTheme.orange, size: 22), title: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
      value: val, onChanged: onChange, activeColor: AppTheme.orange,
    ));
  }
}

class _Section extends StatelessWidget {
  final String t; final bool dark;
  const _Section(this.t, this.dark);
  @override Widget build(BuildContext _) => Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 6), child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)));
}

class _DangerBtn extends StatelessWidget {
  final IconData icon; final String label; final Color color; final VoidCallback onTap;
  const _DangerBtn(this.icon, this.label, this.color, this.onTap);
  @override Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(color: dark ? AppTheme.dCard : Colors.white, margin: const EdgeInsets.only(top: 4), child: ListTile(leading: Icon(icon, color: color, size: 22), title: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)), onTap: onTap));
  }
}

class _MediaGrid extends StatelessWidget {
  final List<Map<String,dynamic>> items;
  const _MediaGrid({required this.items});
  @override Widget build(BuildContext context) => items.isEmpty
    ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.photo_library_outlined, size: 40, color: Colors.grey), SizedBox(height: 8), Text('No media', style: TextStyle(color: Colors.grey, fontSize: 13))]))
    : GridView.builder(padding: const EdgeInsets.all(4), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 3, mainAxisSpacing: 3), itemCount: items.length, itemBuilder: (_, i) {
        final m = items[i];
        return GestureDetector(onTap: () => context.push('/media-viewer', extra: {'media': items, 'index': i}), child: Stack(fit: StackFit.expand, children: [
          m['media_url'] != null ? CachedNetworkImage(imageUrl: m['media_url'], fit: BoxFit.cover, errorWidget: (_, __, ___) => Container(color: AppTheme.orangeSurf)) : Container(color: AppTheme.orangeSurf),
          if (m['type'] == 'video') const Positioned(bottom: 4, right: 4, child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20)),
        ]));
      });
}

class _FilesList extends StatelessWidget {
  final List<Map<String,dynamic>> items;
  const _FilesList({required this.items});
  @override Widget build(BuildContext context) => items.isEmpty
    ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.folder_open_rounded, size: 40, color: Colors.grey), SizedBox(height: 8), Text('No files', style: TextStyle(color: Colors.grey, fontSize: 13))]))
    : ListView.builder(padding: const EdgeInsets.all(4), itemCount: items.length, itemBuilder: (_, i) {
        final f = items[i];
        return ListTile(dense: true, leading: Container(width: 36, height: 36, decoration: BoxDecoration(color: AppTheme.orangeSurf, borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.insert_drive_file_rounded, color: AppTheme.orange, size: 20)), title: Text(f['media_name'] ?? 'File', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)), subtitle: f['media_size'] != null ? Text(FormatUtils.fileSize(f['media_size'] as int), style: const TextStyle(fontSize: 11)) : null, trailing: const Icon(Icons.download_rounded, size: 18, color: AppTheme.orange));
      });
}
