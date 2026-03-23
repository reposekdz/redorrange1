import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/widgets/app_avatar.dart';
import '../../../shared/utils/format_utils.dart';

final _channelsProv = FutureProvider.autoDispose<Map<String,dynamic>>((ref) async {
  final [all, sub] = await Future.wait([
    ref.read(apiServiceProvider).get('/channels'),
    ref.read(apiServiceProvider).get('/channels/subscribed'),
  ]);
  return {'all': all.data['channels'] ?? [], 'subscribed': sub.data['channels'] ?? []};
});

class ChannelsScreen extends ConsumerStatefulWidget {
  const ChannelsScreen({super.key});
  @override ConsumerState<ChannelsScreen> createState() => _S();
}
class _S extends ConsumerState<ChannelsScreen> with SingleTickerProviderStateMixin {
  late TabController _tc;
  @override void initState() { super.initState(); _tc = TabController(length: 2, vsync: this); }
  @override void dispose() { _tc.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final data = ref.watch(_channelsProv);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('Channels', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [IconButton(icon: const Icon(Icons.add_rounded), onPressed: () => context.push('/channels/create'), tooltip: 'Create Channel')],
        bottom: TabBar(controller: _tc, indicatorColor: AppTheme.orange, labelColor: AppTheme.orange, unselectedLabelColor: Colors.grey, tabs: const [Tab(text: 'Explore'), Tab(text: 'Following')])),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.orange)),
        error: (e, _) => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.podcasts_rounded, size: 64, color: Colors.grey), const SizedBox(height: 12), ElevatedButton(onPressed: () => ref.refresh(_channelsProv), child: const Text('Retry'))])),
        data: (d) => TabBarView(controller: _tc, children: [
          _ChannelList(channels: d['all'] as List, empty: 'No channels yet'),
          _ChannelList(channels: d['subscribed'] as List, empty: 'Not following any channels yet', emptyAction: () => _tc.animateTo(0), emptyActionLabel: 'Explore Channels'),
        ]),
      ),
    );
  }
}
class _ChannelList extends ConsumerStatefulWidget {
  final List channels; final String empty; final VoidCallback? emptyAction; final String? emptyActionLabel;
  const _ChannelList({required this.channels, required this.empty, this.emptyAction, this.emptyActionLabel});
  @override ConsumerState<_ChannelList> createState() => _CLS();
}
class _CLS extends ConsumerState<_ChannelList> {
  final Map<String, bool> _subState = {};
  Future<void> _toggleSub(String id, bool current) async {
    setState(() => _subState[id] = !current);
    try {
      await ref.read(apiServiceProvider).post('/channels/$id/${!current ? 'subscribe' : 'unsubscribe'}');
    } catch (_) { if (mounted) setState(() => _subState[id] = current); }
  }
  @override Widget build(BuildContext context) {
    if (widget.channels.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.podcasts_rounded, size: 72, color: Colors.grey), const SizedBox(height: 16),
      Text(widget.empty, style: const TextStyle(fontSize: 16, color: Colors.grey)),
      if (widget.emptyAction != null) ...[const SizedBox(height: 12), ElevatedButton(onPressed: widget.emptyAction, child: Text(widget.emptyActionLabel ?? 'Explore'))],
    ]));
    return ListView.builder(padding: const EdgeInsets.symmetric(vertical: 4), itemCount: widget.channels.length, itemBuilder: (_, i) {
      final c = widget.channels[i];
      final subbed = _subState[c['id']] ?? (c['is_subscribed'] == 1 || c['is_subscribed'] == true);
      return ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: AppAvatar(url: c['avatar_url'], size: 52, username: c['name']),
        title: Row(children: [Flexible(child: Text(c['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14), overflow: TextOverflow.ellipsis)), if (c['is_verified'] == 1 || c['is_verified'] == true) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.verified_rounded, color: AppTheme.orange, size: 14))]),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (c['description'] != null && (c['description'] as String).isNotEmpty) Text(c['description'], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
          Text('${FormatUtils.count(c['subscribers_count'] as int? ?? 0)} subscribers', style: const TextStyle(fontSize: 11)),
        ]),
        trailing: SizedBox(height: 34, child: subbed
          ? OutlinedButton(onPressed: () => _toggleSub(c['id'], true), style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12), textStyle: const TextStyle(fontSize: 12)), child: const Text('Following'))
          : ElevatedButton(onPressed: () => _toggleSub(c['id'], false), style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12), textStyle: const TextStyle(fontSize: 12)), child: const Text('Follow'))),
        onTap: () => context.push('/channels/${c['id']}'),
      );
    });
  }
}
