// channel_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/widgets/app_avatar.dart';
import '../../../shared/utils/format_utils.dart';

class ChannelDetailScreen extends ConsumerStatefulWidget {
  final String channelId;
  const ChannelDetailScreen({super.key, required this.channelId});
  @override ConsumerState<ChannelDetailScreen> createState() => _S();
}
class _S extends ConsumerState<ChannelDetailScreen> {
  Map<String,dynamic>? _channel; List<dynamic> _posts = []; bool _l = true;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final r = await ref.read(apiServiceProvider).get('/channels/${widget.channelId}');
    setState(() { _channel = r.data['channel']; _posts = r.data['posts'] ?? []; _l = false; });
  }
  Future<void> _subscribe() async {
    await ref.read(apiServiceProvider).post('/channels/${widget.channelId}/subscribe');
    _load();
  }
  @override
  Widget build(BuildContext context) {
    if (_l) return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppTheme.orange)));
    if (_channel == null) return const Scaffold(body: Center(child: Text('Channel not found')));
    final ch = _channel!;
    final me = ref.watch(currentUserProvider);
    final isOwner = ch['owner_id'] == me?.id;
    final subscribed = ch['is_subscribed'] == true || ch['is_subscribed'] == 1;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverAppBar(expandedHeight: 180, pinned: true,
          leading: IconButton(icon: const Icon(Icons.arrow_back_rounded, color: Colors.white), onPressed: () => context.pop()),
          actions: [if (isOwner) IconButton(icon: const Icon(Icons.edit_rounded, color: Colors.white), onPressed: () {})],
          flexibleSpace: FlexibleSpaceBar(background: ch['cover_url'] != null
            ? CachedNetworkImage(imageUrl: ch['cover_url'], fit: BoxFit.cover)
            : Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [AppTheme.orange, AppTheme.orangeDark])))),
        ),

        SliverToBoxAdapter(child: Column(children: [
          // Channel info header
          Container(color: dark ? AppTheme.dSurf : Colors.white, padding: const EdgeInsets.all(16), child: Row(children: [
            Container(decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: dark ? AppTheme.dSurf : Colors.white, width: 3), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 8)]),
              child: AppAvatar(url: ch['avatar_url'], size: 64, username: ch['name'])),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(ch['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18), overflow: TextOverflow.ellipsis)),
                if (ch['is_verified'] == 1) const Padding(padding: EdgeInsets.only(left: 5), child: Icon(Icons.verified_rounded, color: AppTheme.orange, size: 17)),
              ]),
              if (ch['description'] != null) Text(ch['description'], maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 4),
              Text('${FormatUtils.count(ch['subscribers_count'] as int? ?? 0)} subscribers  •  ${ch['posts_count'] ?? 0} posts', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ])),
          ])),

          // Action buttons
          Container(color: dark ? AppTheme.dSurf : Colors.white, padding: const EdgeInsets.fromLTRB(16, 0, 16, 12), child: Row(children: [
            Expanded(child: ElevatedButton.icon(onPressed: _subscribe,
              style: subscribed ? ElevatedButton.styleFrom(backgroundColor: dark ? AppTheme.dCard : const Color(0xFFF0F0F0), foregroundColor: dark ? AppTheme.dText : AppTheme.lText) : null,
              icon: Icon(subscribed ? Icons.notifications_off_rounded : Icons.notifications_active_rounded, size: 18),
              label: Text(subscribed ? 'Unfollow' : 'Follow'))),
            if (isOwner) ...[const SizedBox(width: 10), OutlinedButton.icon(onPressed: () => _showPostCreate(context), icon: const Icon(Icons.add_rounded, size: 18), label: const Text('New Post'))],
          ])),
          const Divider(height: 1),
        ])),

        // Posts
        _posts.isEmpty
          ? const SliverFillRemaining(child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.podcasts_rounded, size: 64, color: Colors.grey), SizedBox(height: 12), Text('No posts yet', style: TextStyle(color: Colors.grey))])))
          : SliverList(delegate: SliverChildBuilderDelegate(
              (_, i) {
                final p = _posts[i];
                return Container(
                  color: dark ? AppTheme.dSurf : Colors.white,
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [AppAvatar(url: ch['avatar_url'], size: 36, username: ch['name']), const SizedBox(width: 10), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(ch['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)), Text(FormatUtils.relativeTime(p['created_at']), style: const TextStyle(fontSize: 11, color: Colors.grey))])]),
                      if (p['content'] != null && (p['content'] as String).isNotEmpty) ...[const SizedBox(height: 10), Text(p['content'], style: const TextStyle(fontSize: 14, height: 1.5))],
                      if (p['media_url'] != null) ...[const SizedBox(height: 10), ClipRRect(borderRadius: BorderRadius.circular(10), child: CachedNetworkImage(imageUrl: p['media_url'], width: double.infinity, fit: BoxFit.cover))],
                      const SizedBox(height: 8),
                      Row(children: [const Icon(Icons.remove_red_eye_rounded, size: 14, color: Colors.grey), const SizedBox(width: 4), Text('${p['views_count'] ?? 0} views', style: const TextStyle(fontSize: 12, color: Colors.grey))]),
                    ])),
                    const Divider(height: 1),
                  ]),
                );
              }, childCount: _posts.length)),
      ]),
    );
  }

  void _showPostCreate(BuildContext context) {
    final ctrl = TextEditingController();
    showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(padding: const EdgeInsets.all(16), child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('New Channel Post', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 12),
        TextField(controller: ctrl, maxLines: 5, decoration: const InputDecoration(hintText: 'Write something...')),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () async {
          if (ctrl.text.trim().isEmpty) return;
          await ref.read(apiServiceProvider).post('/channels/${widget.channelId}/post', data: {'content': ctrl.text.trim()});
          if (mounted) { Navigator.pop(context); _load(); }
        }, child: const Text('Post'))),
      ])),
    ));
  }
}

// channel_create_screen.dart
class ChannelCreateScreen extends ConsumerStatefulWidget {
  const ChannelCreateScreen({super.key});
  @override ConsumerState<ChannelCreateScreen> createState() => _CC();
}
class _CC extends ConsumerState<ChannelCreateScreen> {
  final _nameCtrl = TextEditingController(); final _descCtrl = TextEditingController();
  String _category = 'Entertainment'; bool _saving = false;
  final _cats = ['Entertainment','Music','Sports','Technology','News','Education','Fashion','Health','Travel','Food','Art','Business','Other'];
  @override void dispose() { _nameCtrl.dispose(); _descCtrl.dispose(); super.dispose(); }
  Future<void> _create() async {
    if (_nameCtrl.text.trim().isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Channel name required'))); return; }
    setState(() => _saving = true);
    try {
      final r = await ref.read(apiServiceProvider).post('/channels', data: {'name': _nameCtrl.text.trim(), 'description': _descCtrl.text.trim(), 'category': _category});
      if (r.data['success'] == true && mounted) { context.pop(); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Channel created!'))); }
    } catch (e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'))); }
    finally { if (mounted) setState(() => _saving = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Create Channel', style: TextStyle(fontWeight: FontWeight.w800)),
      actions: [TextButton(onPressed: _saving ? null : _create, child: Text(_saving ? 'Creating...' : 'Create', style: const TextStyle(color: AppTheme.orange, fontWeight: FontWeight.w700, fontSize: 16)))]),
    body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: AppTheme.orangeSurf, borderRadius: BorderRadius.circular(12)), child: Row(children: [const Icon(Icons.info_outline_rounded, color: AppTheme.orange, size: 20), const SizedBox(width: 10), const Expanded(child: Text('Channels let you broadcast messages to your subscribers. Only you can post.', style: TextStyle(fontSize: 13, color: AppTheme.orangeDark)))])),
      const SizedBox(height: 20),
      const Text('Channel Name *', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)), const SizedBox(height: 6),
      TextField(controller: _nameCtrl, decoration: const InputDecoration(hintText: 'My Awesome Channel', prefixIcon: Icon(Icons.podcasts_rounded))),
      const SizedBox(height: 14),
      const Text('Description', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)), const SizedBox(height: 6),
      TextField(controller: _descCtrl, maxLines: 3, decoration: const InputDecoration(hintText: 'What is your channel about?')),
      const SizedBox(height: 14),
      const Text('Category', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)), const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 6, children: _cats.map((c) => ChoiceChip(label: Text(c, style: const TextStyle(fontSize: 12)), selected: _category == c, onSelected: (_) => setState(() => _category = c), selectedColor: AppTheme.orange, labelStyle: TextStyle(color: _category == c ? Colors.white : null))).toList()),
      const SizedBox(height: 24),
      SizedBox(width: double.infinity, child: ElevatedButton.icon(onPressed: _saving ? null : _create, icon: const Icon(Icons.podcasts_rounded), label: const Text('Create Channel'))),
    ])),
  );
}
