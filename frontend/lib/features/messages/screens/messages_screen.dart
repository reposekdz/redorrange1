import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import 'dart:async';
import '../../../core/theme/app_theme.dart';
import '../../ads/widgets/ad_widgets.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/models/models.dart';
import '../../../shared/widgets/app_avatar.dart';
import '../../../shared/utils/format_utils.dart';

// Provider
final _convsProvider = StateNotifierProvider<_ConvNotifier, _ConvState>((ref) => _ConvNotifier(ref));

class _ConvState {
  final List<ConversationModel> chats, groups;
  final bool loading;
  const _ConvState({this.chats = const [], this.groups = const [], this.loading = true});
  _ConvState copyWith({List<ConversationModel>? chats, List<ConversationModel>? groups, bool? loading}) =>
    _ConvState(chats: chats ?? this.chats, groups: groups ?? this.groups, loading: loading ?? this.loading);
}

class _ConvNotifier extends StateNotifier<_ConvState> {
  final Ref _ref;
  _ConvNotifier(this._ref) : super(const _ConvState()) {
    load();
    _listenSocket();
  }

  void _listenSocket() {
    final s = _ref.read(socketServiceProvider);
    s.on('new_message', (d) {
      if (d is! Map) return;
      final msg  = d['message'] as Map?;
      final cid  = msg?['conversation_id'] as String?;
      if (cid == null) return;
      _bumpConv(cid, msg);
    });
    s.on('new_conversation', (_) => load());
    s.on('messages_read', (d) {
      if (d is! Map) return;
      final cid = d['conversation_id'] as String?;
      if (cid == null) return;
      _zeroUnread(cid);
    });
    s.on('user_online', (d) {
      if (d is! Map) return;
      final uid = d['user_id'] as String?;
      final on  = d['is_online'] == true;
      if (uid == null) return;
      _updateOnline(uid, on);
    });
    s.on('user_status_update', (d) {
      if (d is! Map) return;
      final uid = d['user_id'] as String?;
      final st  = d['status_text'] as String?;
      if (uid == null) return;
      _updateStatus(uid, st);
    });
  }

  void _bumpConv(String cid, Map? msg) {
    final update = (List<ConversationModel> list) {
      final idx = list.indexWhere((c) => c.id == cid);
      if (idx < 0) return list;
      final c = list[idx];
      final updated = ConversationModel(id: c.id, type: c.type, name: c.name, avatarUrl: c.avatarUrl, description: c.description, lmContent: msg?['content'] as String?, lmType: msg?['type'] as String?, lmSenderId: msg?['sender_id'] as String?, lmSenderName: c.lmSenderName, lmAt: msg?['created_at'] as String? ?? DateTime.now().toIso8601String(), unreadCount: c.unreadCount + 1, membersCount: c.membersCount, otherId: c.otherId, otherUsername: c.otherUsername, otherDisplayName: c.otherDisplayName, otherAvatarUrl: c.otherAvatarUrl, otherLastSeen: c.otherLastSeen, otherStatusText: c.otherStatusText, otherIsOnline: c.otherIsOnline, otherIsVerified: c.otherIsVerified, membersPreview: c.membersPreview, isMuted: c.isMuted);
      final newList = [...list];
      newList.removeAt(idx);
      newList.insert(0, updated);
      return newList;
    };
    state = state.copyWith(chats: update(state.chats), groups: update(state.groups));
  }

  void _zeroUnread(String cid) {
    final fix = (List<ConversationModel> list) => list.map((c) => c.id == cid ? ConversationModel(id: c.id, type: c.type, name: c.name, avatarUrl: c.avatarUrl, description: c.description, lmContent: c.lmContent, lmType: c.lmType, lmSenderId: c.lmSenderId, lmSenderName: c.lmSenderName, lmAt: c.lmAt, unreadCount: 0, membersCount: c.membersCount, otherId: c.otherId, otherUsername: c.otherUsername, otherDisplayName: c.otherDisplayName, otherAvatarUrl: c.otherAvatarUrl, otherLastSeen: c.otherLastSeen, otherStatusText: c.otherStatusText, otherIsOnline: c.otherIsOnline, otherIsVerified: c.otherIsVerified, membersPreview: c.membersPreview, isMuted: c.isMuted) : c).toList();
    state = state.copyWith(chats: fix(state.chats), groups: fix(state.groups));
  }

  void _updateOnline(String uid, bool online) {
    final fix = (List<ConversationModel> list) => list.map((c) => c.otherId == uid ? ConversationModel(id: c.id, type: c.type, name: c.name, avatarUrl: c.avatarUrl, description: c.description, lmContent: c.lmContent, lmType: c.lmType, lmSenderId: c.lmSenderId, lmSenderName: c.lmSenderName, lmAt: c.lmAt, unreadCount: c.unreadCount, membersCount: c.membersCount, otherId: c.otherId, otherUsername: c.otherUsername, otherDisplayName: c.otherDisplayName, otherAvatarUrl: c.otherAvatarUrl, otherLastSeen: c.otherLastSeen, otherStatusText: c.otherStatusText, otherIsOnline: online, otherIsVerified: c.otherIsVerified, membersPreview: c.membersPreview, isMuted: c.isMuted) : c).toList();
    state = state.copyWith(chats: fix(state.chats));
  }

  void _updateStatus(String uid, String? st) {
    final fix = (List<ConversationModel> list) => list.map((c) => c.otherId == uid ? ConversationModel(id: c.id, type: c.type, name: c.name, avatarUrl: c.avatarUrl, description: c.description, lmContent: c.lmContent, lmType: c.lmType, lmSenderId: c.lmSenderId, lmSenderName: c.lmSenderName, lmAt: c.lmAt, unreadCount: c.unreadCount, membersCount: c.membersCount, otherId: c.otherId, otherUsername: c.otherUsername, otherDisplayName: c.otherDisplayName, otherAvatarUrl: c.otherAvatarUrl, otherLastSeen: c.otherLastSeen, otherStatusText: st, otherIsOnline: c.otherIsOnline, otherIsVerified: c.otherIsVerified, membersPreview: c.membersPreview, isMuted: c.isMuted) : c).toList();
    state = state.copyWith(chats: fix(state.chats));
  }

  Future<void> load() async {
    try {
      final r = await _ref.read(apiServiceProvider).get('/messages/conversations');
      final all = (r.data['conversations'] as List).map((c) => ConversationModel.fromJson(Map<String,dynamic>.from(c))).toList();
      state = state.copyWith(
        chats:  all.where((c) => c.type == 'direct').toList(),
        groups: all.where((c) => c.type == 'group').toList(),
        loading: false,
      );
    } catch (_) { state = state.copyWith(loading: false); }
  }

  void remove(String id) => state = state.copyWith(chats: state.chats.where((c) => c.id != id).toList(), groups: state.groups.where((c) => c.id != id).toList());
}

class MessagesScreen extends ConsumerStatefulWidget {
  const MessagesScreen({super.key});
  @override ConsumerState<MessagesScreen> createState() => _S();
}

class _S extends ConsumerState<MessagesScreen> with SingleTickerProviderStateMixin {
  late TabController _tc;
  final _searchCtrl = TextEditingController();
  String _q = '';
  bool _searching = false;
  List<dynamic> _searchRes = [];
  Timer? _deb;

  @override void initState() { super.initState(); _tc = TabController(length: 3, vsync: this); }
  @override void dispose() { _tc.dispose(); _searchCtrl.dispose(); _deb?.cancel(); super.dispose(); }

  void _onSearch(String q) {
    setState(() => _q = q);
    _deb?.cancel();
    if (q.trim().isEmpty) { setState(() { _searching = false; _searchRes = []; }); return; }
    setState(() => _searching = true);
    _deb = Timer(const Duration(milliseconds: 400), () async {
      try {
        final r = await ref.read(apiServiceProvider).get('/search', q: {'q': q, 'type': 'users'});
        if (mounted) setState(() { _searchRes = r.data['users'] ?? []; _searching = false; });
      } catch (_) { if (mounted) setState(() => _searching = false); }
    });
  }

  Future<void> _openChat(String uid) async {
    final r = await ref.read(apiServiceProvider).post('/messages/conversations', data: {'type': 'direct', 'user_id': uid});
    if (mounted) { _searchCtrl.clear(); setState(() => _q = ''); context.push('/chat/${r.data['conversation']['id']}'); }
  }

  @override
  Widget build(BuildContext context) {
    final st   = ref.watch(_convsProvider);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final totalUnread = [...st.chats, ...st.groups].fold(0, (s, c) => s + c.unreadCount);

    return Scaffold(
      backgroundColor: dark ? AppTheme.dBg : const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: dark ? AppTheme.dSurf : Colors.white,
        elevation: 0,
        title: Row(children: [
          const Text('Messages', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22)),
          if (totalUnread > 0) Container(margin: const EdgeInsets.only(left: 8), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: AppTheme.orange, borderRadius: BorderRadius.circular(10)), child: Text('$totalUnread', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700))),
        ]),
        actions: [
          IconButton(icon: const Icon(Icons.edit_rounded), onPressed: () => context.push('/new-chat'), tooltip: 'New Message'),
          IconButton(icon: const Icon(Icons.group_add_rounded), onPressed: () => context.push('/new-group'), tooltip: 'New Group'),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'starred')  context.push('/starred-messages');
              if (v == 'add')      context.push('/add-contact');
              if (v == 'settings') context.push('/settings');
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'starred',  child: Row(children: [Icon(Icons.star_rounded, size: 18, color: AppTheme.orange), SizedBox(width: 10), Text('Starred')])),
              const PopupMenuItem(value: 'add',      child: Row(children: [Icon(Icons.person_add_rounded, size: 18, color: AppTheme.orange), SizedBox(width: 10), Text('Add Contact')])),
              const PopupMenuItem(value: 'settings', child: Row(children: [Icon(Icons.settings_rounded, size: 18), SizedBox(width: 10), Text('Settings')])),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(96),
          child: Column(children: [
            Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 8), child: Container(
              decoration: BoxDecoration(color: dark ? AppTheme.dCard : const Color(0xFFF0F0F0), borderRadius: BorderRadius.circular(14)),
              child: TextField(
                controller: _searchCtrl, onChanged: _onSearch,
                decoration: InputDecoration(
                  hintText: 'Search people and messages...',
                  hintStyle: TextStyle(fontSize: 14, color: dark ? AppTheme.dSub : AppTheme.lSub),
                  prefixIcon: _searching ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.orange))) : Icon(Icons.search_rounded, color: dark ? AppTheme.dSub : AppTheme.lSub, size: 20),
                  suffixIcon: _q.isNotEmpty ? IconButton(icon: const Icon(Icons.close_rounded, size: 18), onPressed: () { _searchCtrl.clear(); _onSearch(''); }) : null,
                  border: InputBorder.none, filled: false,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            )),
            TabBar(controller: _tc, indicatorColor: AppTheme.orange, labelColor: AppTheme.orange, unselectedLabelColor: Colors.grey, labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              tabs: [
                Tab(text: 'Chats${st.chats.isNotEmpty ? ' (${st.chats.length})' : ''}'),
                Tab(text: 'Groups${st.groups.isNotEmpty ? ' (${st.groups.length})' : ''}'),
                const Tab(text: 'Channels'),
              ]),
          ]),
        ),
      ),
      body: _q.isNotEmpty
        ? _SearchPanel(results: _searchRes, onTap: _openChat)
        : TabBarView(controller: _tc, children: [
            _ConvList(convs: st.chats,  loading: st.loading, emptyIcon: Icons.chat_bubble_outline_rounded, emptyText: 'No messages yet', emptyBtn: 'Find People', emptyAction: () => context.push('/add-contact'), onRemove: (id) => ref.read(_convsProvider.notifier).remove(id)),
            _ConvList(convs: st.groups, loading: st.loading, emptyIcon: Icons.group_outlined, emptyText: 'No groups yet', emptyBtn: 'Create Group', emptyAction: () => context.push('/new-group'), onRemove: (id) => ref.read(_convsProvider.notifier).remove(id)),
            _ChannelsTab(),
          ]),
      floatingActionButton: FloatingActionButton(onPressed: () => context.push('/new-chat'), backgroundColor: AppTheme.orange, elevation: 3, child: const Icon(Icons.chat_rounded, color: Colors.white)),
    );
  }
}

class _SearchPanel extends StatelessWidget {
  final List<dynamic> results; final Future<void> Function(String) onTap;
  const _SearchPanel({required this.results, required this.onTap});
  @override Widget build(BuildContext context) => results.isEmpty ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.search_rounded, size: 56, color: Colors.grey), SizedBox(height: 12), Text('Search for people to message', style: TextStyle(color: Colors.grey))]))
    : ListView.builder(itemCount: results.length, itemBuilder: (_, i) {
        final u = results[i];
        return ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: AppAvatar(url: u['avatar_url'], size: 48, username: u['username']),
          title: Text(u['display_name'] ?? u['username'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('@${u['username'] ?? ''}'),
          trailing: ElevatedButton(onPressed: () => onTap(u['id'] as String), style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), textStyle: const TextStyle(fontSize: 12)), child: const Text('Chat')),
          onTap: () => onTap(u['id'] as String));
      });
}

class _ConvList extends StatelessWidget {
  final List<ConversationModel> convs; final bool loading;
  final IconData emptyIcon; final String emptyText, emptyBtn;
  final VoidCallback emptyAction;
  final void Function(String) onRemove;
  const _ConvList({required this.convs, required this.loading, required this.emptyIcon, required this.emptyText, required this.emptyBtn, required this.emptyAction, required this.onRemove});
  @override Widget build(BuildContext context) {
    if (loading) return _Skel();
    if (convs.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(emptyIcon, size: 72, color: Colors.grey), const SizedBox(height: 16), Text(emptyText, style: const TextStyle(fontSize: 17, color: Colors.grey, fontWeight: FontWeight.w600)), const SizedBox(height: 12), ElevatedButton(onPressed: emptyAction, child: Text(emptyBtn))]));
    return RefreshIndicator(color: AppTheme.orange, onRefresh: () async {}, child: Column(children: [const ChatAdBanner(), Expanded(child: ListView.builder(itemCount: convs.length, itemBuilder: (_, i) => _ConvTile(conv: convs[i], onRemove: () => onRemove(convs[i].id))))]));
  }
}

class _ConvTile extends ConsumerWidget {
  final ConversationModel conv; final VoidCallback onRemove;
  const _ConvTile({required this.conv, required this.onRemove});

  String _preview() {
    if (conv.lmType == null) return 'Start a conversation';
    switch (conv.lmType) {
      case 'image':      return '📷 Photo';
      case 'video':      return '🎥 Video';
      case 'voice_note': return '🎤 Voice message';
      case 'file':       return '📎 File';
      case 'audio':      return '🎵 Audio';
      case 'location':   return '📍 Location';
      default:           return conv.lmContent ?? '';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me   = ref.watch(currentUserProvider);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final isMe = conv.lmSenderId == me?.id;
    final unread = conv.unreadCount > 0;

    return Dismissible(
      key: Key(conv.id),
      direction: DismissDirection.endToStart,
      background: Container(color: Colors.red, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 16), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 24), const SizedBox(height: 2), const Text('Delete', style: TextStyle(color: Colors.white, fontSize: 10))])),
      confirmDismiss: (_) async => await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('Delete Chat?'), content: const Text('This removes the chat from your list.'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: Colors.red)))])),
      onDismissed: (_) => onRemove(),
      child: Container(
        color: dark ? AppTheme.dBg : const Color(0xFFF5F5F5),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: unread ? (dark ? AppTheme.orange.withOpacity(0.07) : AppTheme.orange.withOpacity(0.04)) : (dark ? AppTheme.dCard : Colors.white),
            borderRadius: BorderRadius.circular(16),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => context.push('/chat/${conv.id}', extra: {'other_user_id': conv.otherId, 'other_display_name': conv.displayName, 'other_avatar_url': conv.displayAvatar, 'other_is_online': conv.otherIsOnline}),
            onLongPress: () => _opts(context, ref),
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), child: Row(children: [
              Stack(children: [
                AppAvatar(url: conv.displayAvatar, size: 52, username: conv.displayName),
                if (conv.otherIsOnline && conv.type == 'direct')
                  Positioned(bottom: 1, right: 1, child: Container(width: 13, height: 13, decoration: BoxDecoration(color: AppTheme.orange, shape: BoxShape.circle, border: Border.all(color: dark ? AppTheme.dCard : Colors.white, width: 2)))),
              ]),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  if (conv.isMuted) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.volume_off_rounded, size: 13, color: Colors.grey)),
                  Flexible(child: Text(conv.displayName, style: TextStyle(fontWeight: unread ? FontWeight.w800 : FontWeight.w600, fontSize: 15), overflow: TextOverflow.ellipsis)),
                  if (conv.otherIsVerified) const Padding(padding: EdgeInsets.only(left: 3), child: Icon(Icons.verified_rounded, color: AppTheme.orange, size: 13)),
                ]),
                const SizedBox(height: 3),
                Row(children: [
                  if (isMe) Padding(padding: const EdgeInsets.only(right: 3), child: Icon(Icons.done_all_rounded, size: 14, color: unread ? AppTheme.orange : Colors.grey)),
                  Expanded(child: Text(_preview(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: unread ? (dark ? AppTheme.dText : AppTheme.lText) : (dark ? AppTheme.dSub : AppTheme.lSub), fontWeight: unread ? FontWeight.w600 : FontWeight.w400))),
                ]),
              ])),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(conv.lmAt != null ? FormatUtils.date(conv.lmAt) : '', style: TextStyle(fontSize: 11, color: unread ? AppTheme.orange : (dark ? AppTheme.dSub : AppTheme.lSub), fontWeight: unread ? FontWeight.w700 : FontWeight.w400)),
                const SizedBox(height: 5),
                unread ? Container(width: 22, height: 22, decoration: const BoxDecoration(color: AppTheme.orange, shape: BoxShape.circle), child: Center(child: Text(conv.unreadCount > 99 ? '99+' : '${conv.unreadCount}', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)))) : const SizedBox(height: 22),
              ]),
            ])),
          ),
        ),
      ),
    );
  }

  void _opts(BuildContext context, WidgetRef ref) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(context: context, backgroundColor: Colors.transparent, builder: (_) => Container(
      margin: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(18)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4, margin: const EdgeInsets.only(top: 10, bottom: 8), decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
        Padding(padding: const EdgeInsets.fromLTRB(14,4,14,8), child: Row(children: [
          AppAvatar(url: conv.displayAvatar, size: 44, username: conv.displayName),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(conv.displayName, style: const TextStyle(fontWeight: FontWeight.w700)), Text(conv.type == 'group' ? '${conv.membersCount} members' : (conv.otherIsOnline ? '🟢 Online' : 'Offline'), style: const TextStyle(fontSize: 12, color: Colors.grey))])),
        ])),
        const Divider(height: 0.5),
        _Opt(Icons.mark_chat_unread_rounded, 'Mark as unread', AppTheme.orange, () { Navigator.pop(context); }),
        _Opt(Icons.push_pin_rounded,         'Pin conversation', AppTheme.orange, () { Navigator.pop(context); }),
        _Opt(Icons.volume_off_rounded,       'Mute', Colors.grey, () { Navigator.pop(context); }),
        _Opt(Icons.archive_rounded,          'Archive', Colors.grey, () async { Navigator.pop(context); await ref.read(apiServiceProvider).post('/messages/conversations/${conv.id}/archive', data: {'archived': true}).catchError((_){}); onRemove(); }),
        _Opt(Icons.person_rounded,           'View Profile', const Color(0xFF2196F3), () { Navigator.pop(context); if (conv.otherId != null) context.push('/profile/${conv.otherId}'); }),
        _Opt(Icons.delete_outline_rounded,   'Delete', Colors.red, () { Navigator.pop(context); onRemove(); }),
        const SizedBox(height: 14),
      ]),
    ));
  }
}

class _Opt extends StatelessWidget {
  final IconData icon; final String label; final Color color; final VoidCallback onTap;
  const _Opt(this.icon, this.label, this.color, this.onTap);
  @override Widget build(BuildContext _) => ListTile(leading: Icon(icon, color: color, size: 22), title: Text(label, style: TextStyle(color: color == Colors.red ? Colors.red : null, fontWeight: FontWeight.w500)), onTap: onTap);
}

class _ChannelsTab extends ConsumerStatefulWidget {
  @override ConsumerState<_ChannelsTab> createState() => _CTS();
}
class _CTS extends ConsumerState<_ChannelsTab> {
  List<dynamic> _c = []; bool _l = true;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try { final r = await ref.read(apiServiceProvider).get('/channels'); setState(() { _c = r.data['channels'] ?? []; _l = false; }); } catch (_) { setState(() => _l = false); }
  }
  @override Widget build(BuildContext context) => _l ? const Center(child: CircularProgressIndicator(color: AppTheme.orange))
    : _c.isEmpty ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.podcasts_rounded, size: 72, color: Colors.grey), const SizedBox(height: 14), const Text('No channels', style: TextStyle(color: Colors.grey, fontSize: 17)), const SizedBox(height: 12), ElevatedButton(onPressed: () => context.push('/channels'), child: const Text('Explore Channels'))]))
    : ListView.builder(itemCount: _c.length, itemBuilder: (_, i) {
        final c = _c[i];
        return ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: AppAvatar(url: c['avatar_url'], size: 50, username: c['name']),
          title: Row(children: [Flexible(child: Text(c['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700))), if (c['is_verified'] == 1) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.verified_rounded, color: AppTheme.orange, size: 14))]),
          subtitle: Text('${c['subscribers_count'] ?? 0} subscribers'),
          trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
          onTap: () => context.push('/channels/${c['id']}'));
      });
}

class _Skel extends StatelessWidget {
  @override Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Shimmer.fromColors(
      baseColor: dark ? const Color(0xFF2A2A2A) : const Color(0xFFE0E0E0),
      highlightColor: dark ? const Color(0xFF383838) : const Color(0xFFF5F5F5),
      child: ListView.builder(itemCount: 8, itemBuilder: (_, __) => Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), child: Row(children: [
        const CircleAvatar(radius: 26, backgroundColor: Colors.white), const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Container(height: 14, width: 150, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))), const SizedBox(height: 7), Container(height: 11, width: 220, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)))])),
        const SizedBox(width: 10), Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Container(height: 11, width: 36, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))), const SizedBox(height: 8), Container(width: 22, height: 22, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle))]),
      ]))),
    );
  }
}
