import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/widgets/app_avatar.dart';
import '../../../shared/utils/format_utils.dart';

final _liveProv = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  final r = await ref.read(apiServiceProvider).get('/live');
  return List<dynamic>.from(r.data['streams'] ?? []);
});

class LiveScreen extends ConsumerStatefulWidget {
  const LiveScreen({super.key});
  @override ConsumerState<LiveScreen> createState() => _S();
}
class _S extends ConsumerState<LiveScreen> {
  bool _goingLive = false;
  final _titleCtrl = TextEditingController();

  @override void dispose() { _titleCtrl.dispose(); super.dispose(); }

  Future<void> _startLive() async {
    if (_titleCtrl.text.trim().isEmpty) return;
    setState(() => _goingLive = true);
    try {
      final r = await ref.read(apiServiceProvider).post('/live/start', data: {'title': _titleCtrl.text.trim()});
      if (mounted) context.push('/live/${r.data['stream']['id']}', extra: {'is_host': true, 'title': _titleCtrl.text.trim()});
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'))); }
    finally { if (mounted) setState(() => _goingLive = false); }
  }

  @override
  Widget build(BuildContext context) {
    final streams = ref.watch(_liveProv);
    final me      = ref.watch(currentUserProvider);
    final dark    = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverAppBar(
          floating: true,
          title: const Text('Live', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
          actions: [
            IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: () => ref.refresh(_liveProv)),
          ],
        ),

        // Go Live card
        SliverToBoxAdapter(child: Container(
          margin: const EdgeInsets.all(14),
          decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFF6B35), Color(0xFFE85520)], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(18)),
          child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CircleAvatar(backgroundImage: me?.avatarUrl != null ? NetworkImage(me!.avatarUrl!) : null, radius: 22, backgroundColor: Colors.white24, child: me?.avatarUrl == null ? Icon(Icons.person_rounded, color: Colors.white, size: 24) : null),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(me?.displayName ?? me?.username ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                const Text('Broadcast to your followers', style: TextStyle(color: Colors.white70, fontSize: 12)),
              ])),
              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(12)), child: const Row(children: [Icon(Icons.fiber_manual_record_rounded, color: Colors.white, size: 10), SizedBox(width: 4), Text('LIVE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12))])),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: _titleCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'What\'s your stream about?',
                hintStyle: const TextStyle(color: Colors.white54),
                filled: true, fillColor: Colors.white24,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                prefixIcon: const Icon(Icons.title_rounded, color: Colors.white54, size: 18),
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: ElevatedButton.icon(
                onPressed: _goingLive ? null : _startLive,
                icon: _goingLive ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.live_tv_rounded, size: 18),
                label: Text(_goingLive ? 'Going Live...' : 'Go Live Now', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppTheme.orange, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              )),
            ]),
          ])),
        )),

        // Streams grid
        streams.when(
          loading: () => const SliverFillRemaining(child: Center(child: CircularProgressIndicator(color: AppTheme.orange))),
          error: (e, _) => SliverFillRemaining(child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.signal_wifi_off_rounded, size: 56, color: Colors.grey), const SizedBox(height: 12), ElevatedButton(onPressed: () => ref.refresh(_liveProv), child: const Text('Retry'))]))),
          data: (list) => list.isEmpty
            ? SliverFillRemaining(child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.live_tv_rounded, size: 72, color: Colors.grey), const SizedBox(height: 16), const Text('No live streams right now', style: TextStyle(fontSize: 16, color: Colors.grey)), const SizedBox(height: 8), const Text('Be the first to go live!', style: TextStyle(color: Colors.grey, fontSize: 13))])))
            : SliverPadding(
                padding: const EdgeInsets.all(10),
                sliver: SliverGrid(
                  delegate: SliverChildBuilderDelegate((_, i) {
                    final s = list[i];
                    return GestureDetector(
                      onTap: () => context.push('/live/${s['id']}', extra: {'is_host': false, 'title': s['title'], 'user_name': s['display_name'] ?? s['username'], 'user_avatar': s['avatar_url']}),
                      child: Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: dark ? AppTheme.dCard : const Color(0xFF1A1A1A)), child: Stack(children: [
                        // Thumbnail/avatar fill
                        Positioned.fill(child: ClipRRect(borderRadius: BorderRadius.circular(14), child: s['thumbnail'] != null
                          ? CachedNetworkImage(imageUrl: s['thumbnail'], fit: BoxFit.cover)
                          : Container(color: const Color(0xFF1A1A1A), child: Center(child: AppAvatar(url: s['avatar_url'], size: 56, username: s['username']))))),

                        Positioned.fill(child: ClipRRect(borderRadius: BorderRadius.circular(14), child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black.withOpacity(0.85)]))))),

                        // LIVE badge
                        Positioned(top: 8, left: 8, child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(8)), child: Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 6, height: 6, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)), const SizedBox(width: 4), const Text('LIVE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 10))]))),

                        // Viewer count
                        Positioned(top: 8, right: 8, child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)), child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.remove_red_eye_rounded, color: Colors.white, size: 11), const SizedBox(width: 3), Text('${s['viewer_count'] ?? 0}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600))]))),

                        // Host info
                        Positioned(bottom: 8, left: 8, right: 8, child: Row(children: [
                          AppAvatar(url: s['avatar_url'], size: 28, username: s['username']),
                          const SizedBox(width: 6),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(s['display_name'] ?? s['username'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                            Text(s['title'] ?? 'Live stream', style: const TextStyle(color: Colors.white70, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ])),
                        ])),
                      ])),
                    );
                  }, childCount: list.length),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 0.75),
                ),
              ),
        ),
      ]),
    );
  }
}
