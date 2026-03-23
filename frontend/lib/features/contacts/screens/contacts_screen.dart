import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/models/models.dart';
import '../../../shared/widgets/app_avatar.dart';
import '../../../shared/utils/format_utils.dart';

final _contactsProv = StateNotifierProvider<_CN, AsyncValue<List<ContactModel>>>((ref) => _CN(ref));

class _CN extends StateNotifier<AsyncValue<List<ContactModel>>> {
  final Ref _ref;
  _CN(this._ref) : super(const AsyncValue.loading()) {
    load();
    _ref.read(socketServiceProvider).on('user_online', (d) {
      if (d is Map && state.hasValue) {
        final uid = d['user_id'] as String?;
        final online = d['is_online'] == true;
        state = AsyncValue.data(state.value!.map((c) => c.id == uid ? ContactModel(id: c.id, username: c.username, displayName: c.displayName, avatarUrl: c.avatarUrl, statusText: c.statusText, nickname: c.nickname, lastSeen: online ? null : DateTime.now().toIso8601String(), isOnline: online, isVerified: c.isVerified) : c).toList());
      }
    });
    _ref.read(socketServiceProvider).on('user_status_update', (d) {
      if (d is Map && state.hasValue) {
        final uid = d['user_id'] as String?;
        final st = d['status_text'] as String?;
        state = AsyncValue.data(state.value!.map((c) => c.id == uid ? ContactModel(id: c.id, username: c.username, displayName: c.displayName, avatarUrl: c.avatarUrl, statusText: st, nickname: c.nickname, lastSeen: c.lastSeen, isOnline: c.isOnline, isVerified: c.isVerified) : c).toList());
      }
    });
  }
  Future<void> load([String? q]) async {
    if (!state.hasValue) state = const AsyncValue.loading();
    try {
      final params = q != null && q.isNotEmpty ? {'q': q} : null;
      final r = await _ref.read(apiServiceProvider).get('/contacts', q: params);
      state = AsyncValue.data((r.data['contacts'] as List).map((c) => ContactModel.fromJson(Map<String,dynamic>.from(c))).toList());
    } catch (e, s) { state = AsyncValue.error(e, s); }
  }
}

class ContactsScreen extends ConsumerStatefulWidget {
  const ContactsScreen({super.key});
  @override ConsumerState<ContactsScreen> createState() => _S();
}

class _S extends ConsumerState<ContactsScreen> with SingleTickerProviderStateMixin {
  late TabController _tc;
  final _searchCtrl = TextEditingController();
  Timer? _deb;
  String _q = '';

  @override
  void initState() { super.initState(); _tc = TabController(length: 3, vsync: this); }
  @override void dispose() { _tc.dispose(); _searchCtrl.dispose(); _deb?.cancel(); super.dispose(); }

  Future<void> _openChat(String uid) async {
    final r = await ref.read(apiServiceProvider).post('/messages/conversations', data: {'type': 'direct', 'user_id': uid});
    if (mounted) context.push('/chat/${r.data['conversation']['id']}');
  }

  Future<void> _deleteContact(String uid) async {
    await ref.read(apiServiceProvider).delete('/contacts/$uid').catchError((_){});
    ref.read(_contactsProv.notifier).load();
  }

  @override
  Widget build(BuildContext context) {
    final contacts = ref.watch(_contactsProv);
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contacts', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(icon: const Icon(Icons.group_add_rounded), onPressed: () => context.push('/new-group'), tooltip: 'New Group'),
          IconButton(icon: const Icon(Icons.person_add_rounded), onPressed: () => context.push('/add-contact'), tooltip: 'Add Contact'),
          PopupMenuButton<String>(onSelected: (v) { if (v == 'requests') context.push('/follow-requests'); }, itemBuilder: (_) => [const PopupMenuItem(value: 'requests', child: Text('Follow Requests'))]),
        ],
        bottom: TabBar(
          controller: _tc, indicatorColor: AppTheme.orange, labelColor: AppTheme.orange, unselectedLabelColor: Colors.grey,
          tabs: const [Tab(text: 'All'), Tab(text: 'Online'), Tab(text: 'Groups')],
        ),
      ),
      body: Column(children: [
        // Search bar
        Padding(padding: const EdgeInsets.fromLTRB(12, 10, 12, 4), child: TextField(
          controller: _searchCtrl,
          onChanged: (q) {
            setState(() => _q = q);
            _deb?.cancel();
            _deb = Timer(const Duration(milliseconds: 350), () => ref.read(_contactsProv.notifier).load(q.trim().isEmpty ? null : q.trim()));
          },
          decoration: InputDecoration(
            hintText: 'Search contacts...',
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            suffixIcon: _q.isNotEmpty ? IconButton(icon: const Icon(Icons.close_rounded, size: 18), onPressed: () { _searchCtrl.clear(); setState(() => _q = ''); ref.read(_contactsProv.notifier).load(); }) : null,
          ),
        )),

        Expanded(child: contacts.when(
          loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.orange)),
          error: (e, _) => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.error_outline_rounded, size: 48, color: Colors.grey), const SizedBox(height: 12),
            Text('$e', style: const TextStyle(color: Colors.grey)), const SizedBox(height: 12),
            ElevatedButton(onPressed: () => ref.read(_contactsProv.notifier).load(), child: const Text('Retry')),
          ])),
          data: (all) {
            final online  = all.where((c) => c.isOnline).toList();
            return TabBarView(controller: _tc, children: [
              _ContactList(contacts: all, onChat: _openChat, onDelete: _deleteContact),
              _OnlineSection(contacts: online, onChat: _openChat),
              _GroupsSection(),
            ]);
          },
        )),
      ]),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/add-contact'),
        backgroundColor: AppTheme.orange,
        child: const Icon(Icons.person_add_rounded, color: Colors.white),
      ),
    );
  }
}

// ── Contact list (alphabetically grouped)
class _ContactList extends StatelessWidget {
  final List<ContactModel> contacts;
  final Future<void> Function(String) onChat;
  final Future<void> Function(String) onDelete;
  const _ContactList({required this.contacts, required this.onChat, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    if (contacts.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.people_outline_rounded, size: 72, color: Colors.grey),
      const SizedBox(height: 16), const Text('No contacts yet', style: TextStyle(fontSize: 16, color: Colors.grey)),
      const SizedBox(height: 10), ElevatedButton.icon(onPressed: () => context.push('/add-contact'), icon: const Icon(Icons.person_add_rounded), label: const Text('Add Contact')),
    ]));

    // Group by first letter
    final grouped = <String, List<ContactModel>>{};
    for (final c in contacts) {
      final letter = (c.nameToDisplay[0]).toUpperCase();
      grouped.putIfAbsent(letter, () => []).add(c);
    }
    final keys = grouped.keys.toList()..sort();

    return RefreshIndicator(
      color: AppTheme.orange,
      onRefresh: () async => {},
      child: ListView.builder(
        itemCount: keys.length,
        itemBuilder: (_, i) {
          final letter = keys[i];
          final group = grouped[letter]!;
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4), child: Text(letter, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppTheme.orange, letterSpacing: 1))),
            ...group.map((c) => _ContactTile(contact: c, onChat: () => onChat(c.id), onDelete: () => onDelete(c.id))),
          ]);
        },
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  final ContactModel contact;
  final VoidCallback onChat, onDelete;
  const _ContactTile({required this.contact, required this.onChat, required this.onDelete});

  @override
  Widget build(BuildContext context) => Dismissible(
    key: Key(contact.id),
    direction: DismissDirection.endToStart,
    background: Container(color: Colors.red, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete_outline_rounded, color: Colors.white)),
    confirmDismiss: (_) async {
      return await showDialog<bool>(context: context, builder: (_) => AlertDialog(
        title: const Text('Remove Contact'),
        content: Text('Remove ${contact.nameToDisplay} from contacts?'),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove', style: TextStyle(color: Colors.red)))],
      ));
    },
    onDismissed: (_) => onDelete(),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      onTap: () => context.push('/profile/${contact.id}'),
      leading: AppAvatar(url: contact.avatarUrl, size: 50, username: contact.username, showOnline: true, isOnline: contact.isOnline),
      title: Row(children: [
        Flexible(child: Text(contact.nameToDisplay, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14), overflow: TextOverflow.ellipsis)),
        if (contact.isVerified) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.verified_rounded, color: AppTheme.orange, size: 14)),
      ]),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('@${contact.username ?? ''}', style: const TextStyle(fontSize: 12)),
        if (contact.statusText != null && contact.statusText!.isNotEmpty)
          Text(contact.statusText!, style: const TextStyle(fontSize: 11, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis)
        else if (!contact.isOnline && contact.lastSeen != null)
          Text('last seen ${FormatUtils.relativeTime(contact.lastSeen)}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ]),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        _CircleIconBtn(Icons.call_rounded, AppTheme.orange, () => context.push('/call/audio', extra: {'user_id': contact.id, 'user_name': contact.nameToDisplay, 'avatar': contact.avatarUrl, 'is_incoming': false})),
        const SizedBox(width: 4),
        _CircleIconBtn(Icons.videocam_rounded, const Color(0xFF2196F3), () => context.push('/call/video', extra: {'user_id': contact.id, 'user_name': contact.nameToDisplay, 'avatar': contact.avatarUrl, 'is_incoming': false})),
        const SizedBox(width: 4),
        _CircleIconBtn(Icons.chat_rounded, const Color(0xFF4CAF50), onChat),
      ]),
    ),
  );
}

class _CircleIconBtn extends StatelessWidget {
  final IconData icon; final Color color; final VoidCallback onTap;
  const _CircleIconBtn(this.icon, this.color, this.onTap);
  @override Widget build(BuildContext _) => GestureDetector(onTap: onTap, child: Container(width: 34, height: 34, decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, color: color, size: 17)));
}

// ── Online now section
class _OnlineSection extends StatelessWidget {
  final List<ContactModel> contacts;
  final Future<void> Function(String) onChat;
  const _OnlineSection({required this.contacts, required this.onChat});

  @override
  Widget build(BuildContext context) {
    if (contacts.isEmpty) return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.circle_outlined, size: 64, color: Colors.grey),
      SizedBox(height: 16), Text('No contacts online', style: TextStyle(color: Colors.grey, fontSize: 16)),
    ]));
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: contacts.length,
      itemBuilder: (_, i) {
        final c = contacts[i];
        return ListTile(
          leading: Stack(children: [
            AppAvatar(url: c.avatarUrl, size: 48, username: c.username),
            Positioned(bottom: 0, right: 0, child: Container(width: 13, height: 13, decoration: BoxDecoration(color: const Color(0xFF4CAF50), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)))),
          ]),
          title: Text(c.nameToDisplay, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(c.statusText ?? 'Online now', style: const TextStyle(fontSize: 12, color: Color(0xFF4CAF50))),
          trailing: ElevatedButton(onPressed: () => onChat(c.id), style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), textStyle: const TextStyle(fontSize: 12)), child: const Text('Message')),
          onTap: () => context.push('/profile/${c.id}'),
        );
      },
    );
  }
}

// ── Groups section
class _GroupsSection extends ConsumerStatefulWidget {
  @override ConsumerState<_GroupsSection> createState() => _GS();
}
class _GS extends ConsumerState<_GroupsSection> {
  List<dynamic> _groups = []; bool _l = true;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try {
      final r = await ref.read(apiServiceProvider).get('/messages/conversations', q: {'type': 'group'});
      final all = (r.data['conversations'] as List).where((c) => c['type'] == 'group').toList();
      setState(() { _groups = all; _l = false; });
    } catch (_) { setState(() => _l = false); }
  }
  @override
  Widget build(BuildContext context) {
    if (_l) return const Center(child: CircularProgressIndicator(color: AppTheme.orange));
    if (_groups.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.group_outlined, size: 72, color: Colors.grey),
      const SizedBox(height: 16), const Text('No groups yet', style: TextStyle(color: Colors.grey, fontSize: 16)),
      const SizedBox(height: 12), ElevatedButton.icon(onPressed: () => context.push('/new-group'), icon: const Icon(Icons.group_add_rounded), label: const Text('Create Group')),
    ]));
    return RefreshIndicator(color: AppTheme.orange, onRefresh: _load, child: ListView.builder(
      itemCount: _groups.length + 1,
      itemBuilder: (_, i) {
        if (i == _groups.length) return Padding(padding: const EdgeInsets.all(16), child: OutlinedButton.icon(onPressed: () => context.push('/new-group'), icon: const Icon(Icons.group_add_rounded), label: const Text('Create New Group')));
        final g = _groups[i];
        return ListTile(
          leading: AppAvatar(url: g['avatar_url'], size: 50, username: g['name']),
          title: Text(g['name'] ?? 'Group', style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('${g['members_count'] ?? 0} members', style: const TextStyle(fontSize: 12)),
          trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
          onTap: () => context.push('/chat/${g['id']}'),
          onLongPress: () => context.push('/group/${g['id']}/settings'),
        );
      },
    ));
  }
}
