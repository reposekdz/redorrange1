
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/api_service.dart';
import '../../../core/models/models.dart';
import '../../../shared/widgets/app_avatar.dart';
import '../../../shared/utils/format_utils.dart';

final _reelDetailProv = FutureProvider.family.autoDispose<Map<String,dynamic>, String>((ref, id) async {
  final r = await ref.read(apiServiceProvider).get('/reels/$id');
  return Map<String,dynamic>.from(r.data);
});

class ReelDetailScreen extends ConsumerStatefulWidget {
  final String reelId;
  const ReelDetailScreen({super.key, required this.reelId});
  @override ConsumerState<ReelDetailScreen> createState() => _S();
}
class _S extends ConsumerState<ReelDetailScreen> {
  VideoPlayerController? _vc;
  final _commentCtrl = TextEditingController();
  bool _liked = false; int _likes = 0; bool _saved = false;
  bool _sendingComment = false; bool _showComments = false;

  @override void dispose() { _vc?.dispose(); _commentCtrl.dispose(); super.dispose(); }

  void _initVideo(String url) {
    _vc = VideoPlayerController.networkUrl(Uri.parse(url))
      ..initialize().then((_) { if (mounted) { setState(() {}); _vc?.play(); _vc?.setLooping(true); } });
  }

  Future<void> _like() async {
    setState(() { _liked = !_liked; _likes += _liked ? 1 : -1; });
    await ref.read(apiServiceProvider).post('/reels/${widget.reelId}/like').catchError((_) => setState(() { _liked = !_liked; _likes += _liked ? 1 : -1; }));
  }

  Future<void> _comment(String content) async {
    if (content.trim().isEmpty) return;
    setState(() => _sendingComment = true);
    await ref.read(apiServiceProvider).post('/reels/${widget.reelId}/comments', data: {'content': content.trim()});
    _commentCtrl.clear();
    setState(() => _sendingComment = false);
    ref.refresh(_reelDetailProv(widget.reelId));
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(_reelDetailProv(widget.reelId));
    final me = ref.watch(currentUserProvider);
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.black,
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.orange)),
        error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: Colors.white))),
        data: (data) {
          final reel = data['reel'] is Map ? Map<String,dynamic>.from(data['reel']) : <String,dynamic>{};
          final comments = List<Map<String,dynamic>>.from(data['comments'] ?? []);
          if (_vc == null && reel['video_url'] != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _initVideo(reel['video_url']); });
          }
          _liked = reel['is_liked'] == true || reel['is_liked'] == 1;
          _likes = (reel['likes_count'] as int? ?? 0);

          return Stack(children: [
            // Video
            if (_vc?.value.isInitialized == true)
              Positioned.fill(child: GestureDetector(
                onTap: () { if (_vc!.value.isPlaying) _vc!.pause(); else _vc!.play(); },
                child: FittedBox(fit: BoxFit.cover, child: SizedBox(width: _vc!.value.size.width, height: _vc!.value.size.height, child: VideoPlayer(_vc!))),
              ))
            else if (reel['thumbnail_url'] != null)
              Positioned.fill(child: CachedNetworkImage(imageUrl: reel['thumbnail_url'], fit: BoxFit.cover))
            else Positioned.fill(child: Container(color: Colors.black)),

            // Gradient overlay
            Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black45, Colors.transparent, Colors.transparent, Colors.black87], stops: const [0,0.2,0.6,1])))),

            // Progress bar
            if (_vc?.value.isInitialized == true)
              Positioned(bottom: 0, left: 0, right: 0, child: AnimatedBuilder(animation: _vc!, builder: (_, __) => LinearProgressIndicator(
                value: _vc!.value.duration.inMilliseconds > 0 ? (_vc!.value.position.inMilliseconds / _vc!.value.duration.inMilliseconds).clamp(0.0, 1.0) : 0.0,
                backgroundColor: Colors.white24, valueColor: const AlwaysStoppedAnimation(AppTheme.orange), minHeight: 2,
              ))),

            // Top bar
            SafeArea(child: Row(children: [
              IconButton(icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 26), onPressed: () => context.pop()),
              const Spacer(),
              IconButton(icon: const Icon(Icons.more_vert_rounded, color: Colors.white), onPressed: () {}),
            ])),

            // Right actions
            Positioned(right: 12, bottom: 120, child: Column(children: [
              GestureDetector(onTap: () => context.push('/profile/${reel['user_id']}'), child: AppAvatar(url: reel['avatar_url'], size: 44, username: reel['username'])),
              const SizedBox(height: 20),
              _RightBtn(icon: _liked ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: _liked ? Colors.red : Colors.white, label: FormatUtils.count(_likes), onTap: _like),
              const SizedBox(height: 20),
              _RightBtn(icon: Icons.chat_bubble_outline_rounded, label: FormatUtils.count(reel['comments_count'] as int? ?? 0), onTap: () => setState(() => _showComments = !_showComments)),
              const SizedBox(height: 20),
              _RightBtn(icon: Icons.send_outlined, label: 'Share', onTap: () async { await ref.read(apiServiceProvider).post('/reels/${widget.reelId}/share'); }),
              const SizedBox(height: 20),
              _RightBtn(icon: _saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, color: _saved ? AppTheme.orange : Colors.white, label: 'Save', onTap: () => setState(() => _saved = !_saved)),
            ])),

            // Bottom info
            Positioned(bottom: 80, left: 12, right: 70, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              GestureDetector(onTap: () => context.push('/profile/${reel['user_id']}'), child: Row(children: [
                Text('@${reel['username'] ?? ''}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                if (reel['is_verified'] == 1 || reel['is_verified'] == true) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.verified_rounded, color: AppTheme.orange, size: 14)),
              ])),
              if (reel['caption'] != null && (reel['caption'] as String).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(reel['caption'], style: const TextStyle(color: Colors.white, fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis)),
            ])),

            // Comments panel
            if (_showComments) Positioned.fill(top: null, child: Container(
              height: MediaQuery.of(context).size.height * 0.65,
              decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
              child: Column(children: [
                const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Comments', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                const Divider(height: 1),
                Expanded(child: comments.isEmpty
                  ? const Center(child: Text('No comments yet', style: TextStyle(color: Colors.grey)))
                  : ListView.builder(padding: const EdgeInsets.all(12), itemCount: comments.length, itemBuilder: (_, i) {
                      final c = comments[i];
                      return Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        AppAvatar(url: c['avatar_url'], size: 34, username: c['username']),
                        const SizedBox(width: 8),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          RichText(text: TextSpan(style: Theme.of(context).textTheme.bodyMedium, children: [TextSpan(text: '${c['username'] ?? ''} ', style: const TextStyle(fontWeight: FontWeight.w700)), TextSpan(text: c['content'] ?? '')])),
                          Text(timeago.format(DateTime.tryParse(c['created_at'] ?? '') ?? DateTime.now()), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        ])),
                      ]));
                    })),
                Container(padding: EdgeInsets.only(left: 12, right: 12, top: 8, bottom: MediaQuery.of(context).viewInsets.bottom + 12), decoration: BoxDecoration(border: Border(top: BorderSide(color: dark ? AppTheme.dDiv : AppTheme.lDiv, width: 0.5))),
                  child: Row(children: [
                    AppAvatar(url: me?.avatarUrl, size: 32, username: me?.username),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(_commentCtrl, decoration: const InputDecoration(hintText: 'Add a comment...', border: InputBorder.none, filled: false))),
                    TextButton(onPressed: _sendingComment ? null : () => _comment(_commentCtrl.text), child: const Text('Post', style: TextStyle(color: AppTheme.orange, fontWeight: FontWeight.w700))),
                  ])),
              ]),
            )),
          ]);
        },
      ),
    );
  }
}

class _RightBtn extends StatelessWidget {
  final IconData icon; final String label; final Color? color; final VoidCallback onTap;
  const _RightBtn({required this.icon, required this.label, this.color, required this.onTap});
  @override Widget build(_) => GestureDetector(onTap: onTap, child: Column(children: [
    Icon(icon, color: color ?? Colors.white, size: 28),
    const SizedBox(height: 4),
    Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
  ]));
}
