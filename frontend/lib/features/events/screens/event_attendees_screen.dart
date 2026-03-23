import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/widgets/app_avatar.dart';

class EventAttendeesScreen extends ConsumerStatefulWidget {
  final String eventId;
  const EventAttendeesScreen({super.key, required this.eventId});
  @override ConsumerState<EventAttendeesScreen> createState() => _S();
}
class _S extends ConsumerState<EventAttendeesScreen> with SingleTickerProviderStateMixin {
  late TabController _tc; List<dynamic> _going = [], _interested = []; bool _l = true;
  @override void initState() { super.initState(); _tc = TabController(length: 2, vsync: this); _load(); }
  @override void dispose() { _tc.dispose(); super.dispose(); }
  Future<void> _load() async {
    try {
      final r = await ref.read(apiServiceProvider).get('/events/${widget.eventId}/attendees');
      final all = List<dynamic>.from(r.data['attendees'] ?? []);
      setState(() { _going = all.where((a) => a['status'] == 'going').toList(); _interested = all.where((a) => a['status'] == 'interested').toList(); _l = false; });
    } catch (_) { setState(() => _l = false); }
  }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('${_going.length + _interested.length} Attendees', style: const TextStyle(fontWeight: FontWeight.w800)),
      bottom: TabBar(controller: _tc, indicatorColor: AppTheme.orange, labelColor: AppTheme.orange, unselectedLabelColor: Colors.grey, tabs: [Tab(text: '${_going.length} Going'), Tab(text: '${_interested.length} Interested')])),
    body: _l ? const Center(child: CircularProgressIndicator(color: AppTheme.orange)) : TabBarView(controller: _tc, children: [
      _buildList(_going, 'Nobody has confirmed going yet'),
      _buildList(_interested, 'Nobody is interested yet'),
    ]),
  );
  Widget _buildList(List<dynamic> list, String emptyMsg) => list.isEmpty ? Center(child: Text(emptyMsg, style: const TextStyle(color: Colors.grey))) : ListView.builder(itemCount: list.length, itemBuilder: (_, i) {
    final u = list[i];
    return ListTile(leading: AppAvatar(url: u['avatar_url'], size: 46, username: u['username']), title: Text(u['display_name'] ?? u['username'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text('@${u['username'] ?? ''}'), onTap: () => context.push('/profile/${u['id']}'));
  });
}
