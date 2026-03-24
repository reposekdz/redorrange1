
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/widgets/app_avatar.dart';
import '../../../shared/utils/format_utils.dart';

class ReactionsScreen extends ConsumerStatefulWidget {
  final String postId;
  const ReactionsScreen({super.key, required this.postId});
  @override ConsumerState<ReactionsScreen> createState() => _S();
}
class _S extends ConsumerState<ReactionsScreen> with SingleTickerProviderStateMixin {
  late TabController _tc;
  Map<String, List<dynamic>> _d = {}; bool _l = true;
  static const _reacts = [['all', '❤️ All'], ['like', '👍 Like'], ['love', '❤️ Love'], ['haha', '😂 Haha'], ['wow', '😮 Wow'], ['sad', '😢 Sad'], ['angry', '😡 Angry']];

  @override void initState() { super.initState(); _tc = TabController(length: _reacts.length, vsync: this); _load(); }
  @override void dispose() { _tc.dispose(); super.dispose(); }

  Future<void> _load() async {
    try {
      final r = await ref.read(apiServiceProvider).get('/interactions/posts/${widget.postId}/likes');
      final all = List<dynamic>.from(r.data['users'] ?? []);
      setState(() {
        _d['all'] = all;
        for (final e in _reacts.skip(1)) { final type = e[0] as String; _d[type] = all.where((u) => u['reaction_type'] == type).toList(); }
        _l = false;
      });
    } catch (_) { setState(() => _l = false); }
  }

  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('${FormatUtils.count(_d['all']?.length ?? 0)} Reactions', style: const TextStyle(fontWeight: FontWeight.w800)),
      bottom: _l ? null : TabBar(controller: _tc, isScrollable: true, tabAlignment: TabAlignment.start, indicatorColor: AppTheme.orange, labelColor: AppTheme.orange, unselectedLabelColor: Colors.grey,
        tabs: _reacts.map((e) { final type = e[0] as String; final label = e[1] as String;
          final count = _d[type]?.length ?? 0;
          return Tab(text: '$label (${count > 0 ? FormatUtils.count(count) : ''})'.replaceAll(' ()', ''));
        }).toList())),
    body: _l ? const Center(child: CircularProgressIndicator(color: AppTheme.orange)) : TabBarView(controller: _tc, children: _reacts.map((e) { final type = e[0] as String;
      final users = _d[type] ?? [];
      if (users.isEmpty) return const Center(child: Text('No reactions', style: TextStyle(color: Colors.grey)));
      return ListView.builder(itemCount: users.length, itemBuilder: (_, i) {
        final u = users[i];
        return ListTile(leading: AppAvatar(url: u['avatar_url'], size: 46, username: u['username']), title: Row(children: [Text(u['display_name'] ?? u['username'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700)), if (u['is_verified'] == 1) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.verified_rounded, color: AppTheme.orange, size: 13))]), subtitle: Text('@${u['username'] ?? ''}'), trailing: Text(_reactEmoji(u['reaction_type'] ?? 'like'), style: const TextStyle(fontSize: 20)), onTap: () => context.push('/profile/${u['id']}'));
      });
    }).toList()),
  );
  String _reactEmoji(String t) { const m = {'like': '👍', 'love': '❤️', 'haha': '😂', 'wow': '😮', 'sad': '😢', 'angry': '😡'}; return m[t] ?? '👍'; }
}
