
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/widgets/app_avatar.dart';

class NewChatScreen extends ConsumerStatefulWidget {
  const NewChatScreen({super.key});
  @override ConsumerState<NewChatScreen> createState() => _S();
}
class _S extends ConsumerState<NewChatScreen> {
  final _ctrl = TextEditingController();
  List<dynamic> _contacts = [], _search = [];
  bool _l = true, _searching = false;
  Timer? _deb;

  @override void initState() { super.initState(); _loadContacts(); }
  @override void dispose() { _ctrl.dispose(); _deb?.cancel(); super.dispose(); }

  Future<void> _loadContacts() async {
    try { final r = await ref.read(apiServiceProvider).get('/contacts'); setState(() { _contacts = r.data['contacts'] ?? []; _l = false; }); } catch (_) { setState(() => _l = false); }
  }

  void _onSearch(String q) {
    _deb?.cancel();
    if (q.isEmpty) { setState(() { _search = []; _searching = false; }); return; }
    setState(() => _searching = true);
    _deb = Timer(const Duration(milliseconds: 350), () async {
      try { final r = await ref.read(apiServiceProvider).get('/search', q: {'q': q, 'type': 'users'}); if (mounted) setState(() { _search = r.data['users'] ?? []; _searching = false; }); } catch (_) { if (mounted) setState(() => _searching = false); }
    });
  }

  Future<void> _open(String uid) async {
    final r = await ref.read(apiServiceProvider).post('/messages/conversations', data: {'type': 'direct', 'user_id': uid});
    if (mounted) context.push('/chat/${r.data['conversation']['id']}');
  }

  @override
  Widget build(BuildContext context) {
    final list = _ctrl.text.isEmpty ? _contacts : _search;
    return Scaffold(
      appBar: AppBar(title: const Text('New Message', style: TextStyle(fontWeight: FontWeight.w800))),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: TextField(controller: _ctrl, onChanged: _onSearch, decoration: InputDecoration(hintText: 'Search people...', prefixIcon: _searching ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.orange))) : const Icon(Icons.search_rounded, size: 20), suffixIcon: _ctrl.text.isNotEmpty ? IconButton(icon: const Icon(Icons.close_rounded, size: 18), onPressed: () { _ctrl.clear(); _onSearch(''); }) : null))),
        _l ? const Center(child: CircularProgressIndicator(color: AppTheme.orange))
          : list.isEmpty ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.person_search_rounded, size: 64, color: Colors.grey), const SizedBox(height: 12),
              Text(_ctrl.text.isEmpty ? 'No contacts yet' : 'No results for "${_ctrl.text}"', style: const TextStyle(color: Colors.grey)),
              if (_ctrl.text.isEmpty) ...[const SizedBox(height: 12), ElevatedButton(onPressed: () => context.push('/add-contact'), child: const Text('Add Contact'))],
            ]))
          : Expanded(child: ListView.builder(itemCount: list.length, itemBuilder: (_, i) {
              final u = list[i];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                leading: AppAvatar(url: u['avatar_url'], size: 50, username: u['username'] ?? u['display_name'], showOnline: true, isOnline: u['is_online'] == 1 || u['is_online'] == true),
                title: Row(children: [Flexible(child: Text(u['display_name'] ?? u['username'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)), if (u['is_verified'] == 1 || u['is_verified'] == true) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.verified_rounded, color: AppTheme.orange, size: 14))]),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('@${u['username'] ?? ''}', style: const TextStyle(fontSize: 12)),
                  if (u['status_text'] != null && (u['status_text'] as String).isNotEmpty) Text(u['status_text'], style: const TextStyle(fontSize: 11, color: AppTheme.orange), maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
                trailing: ElevatedButton(onPressed: () => _open(u['id'] as String), style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), textStyle: const TextStyle(fontSize: 12)), child: const Text('Message')),
                onTap: () => _open(u['id'] as String),
              );
            })),
      ]),
    );
  }
}
