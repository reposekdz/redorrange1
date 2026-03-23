
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
import '../../../shared/widgets/app_avatar.dart';
import '../../../shared/utils/format_utils.dart';

final _reelsFeedProv = StateNotifierProvider<_RN, List<Map<String,dynamic>>>((ref) => _RN(ref));

class _RN extends StateNotifier<List<Map<String,dynamic>>> {
  final Ref _ref; int _page = 1; bool _loading = false; bool _hasMore = true;
  _RN(this._ref) : super([]) { load(); }
  Future<void> load({bool more = false}) async {
    if (_loading || (more && !_hasMore)) return;
    _loading = true;
    try {
      final r = await _ref.read(apiServiceProvider).get('/reels/feed', q: {'page': '$_page', 'limit': '10'});
      final list = List<Map<String,dynamic>>.from(r.data['reels'] ?? []);
      _hasMore = list.length == 10;
      
      // Intersperse ads every 6 items
      List<Map<String,dynamic>> processed = [];
      int currentTotal = more ? state.length : 0;
      for (var item in list) {
        processed.add(item);
        currentTotal++;
        if (currentTotal % 6 == 0) {
          processed.add({'is_ad': true, 'id': 'ad_${DateTime.now().millisecondsSinceEpoch}_$currentTotal'});
          currentTotal++;
        }
      }
      
      state = more ? [...state, ...processed] : processed;
      if (more) _page++;
    } catch (_) {}
    _loading = false;
  }
  void toggleLike(String id) {
    state = state.map((r) {
      if (r['id'] != id) return r;
      final liked = !(r['is_liked'] == true || r['is_liked'] == 1);
      final cnt   = (r['likes_count'] as int? ?? 0) + (liked ? 1 : -1);
      return {...r, 'is_liked': liked, 'likes_count': cnt};
    }).toList();
  }
  void toggleSave(String id) {
    state = state.map((r) {
      if (r['id'] != id) return r;
      final saved = !(r['is_saved'] == true || r['is_saved'] == 1);
      return {...r, 'is_saved': saved};
    }).toList();
  }
}

class ReelsScreen extends ConsumerStatefulWidget {
  const ReelsScreen({super.key});
  @override ConsumerState<ReelsScreen> createState() => _S();
}
class _S extends ConsumerState<ReelsScreen> {
  final _pc = PageController();
  final Map<int, VideoPlayerController> _vcs = {};
  int _cur = 0;
  bool _showCmts = false;

  @override void initState() { super.initState(); SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: Colors.transparent)); }
  @override void dispose() { for (final v in _vcs.values) v.dispose(); _pc.dispose(); super.dispose(); }

  Future<void> _init(int i, String url) async {
    if (_vcs.containsKey(i)) return;
    final vc = VideoPlayerController.networkUrl(Uri.parse(url));
    _vcs[i] = vc;
    await vc.initialize();
    if (mounted && _cur == i) { setState(() {}); vc.play(); vc.setLooping(true); }
  }

  void _onPage(int i) {
    final reels = ref.read(_reelsFeedProv);
    _vcs[_cur]?.pause();
    setState(() { _cur = i; _showCmts = false; });
    
    if (i < reels.length && reels[i]['is_ad'] == true) {
      // Ad page, no video to init here (ad widget handles itself)
    } else if (_vcs.containsKey(i)) {
      _vcs[i]!.play();
    } else if (i < reels.length && reels[i]['video_url'] != null) {
      _init(i, reels[i]['video_url']);
    }
    
    // Preload next
    if (i + 1 < reels.length && reels[i+1]['is_ad'] != true && !_vcs.containsKey(i+1) && reels[i+1]['video_url'] != null) {
      _init(i+1, reels[i+1]['video_url']);
    }
    
    if (i >= reels.length - 3) ref.read(_reelsFeedProv.notifier).load(more: true);
  }

  @override
  Widget build(BuildContext context) {
    final reels = ref.watch(_reelsFeedProv);
    if (reels.isEmpty) return Scaffold(backgroundColor: Colors.black, body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const CircularProgressIndicator(color: AppTheme.orange), const SizedBox(height: 16), const Text('Loading reels...', style: TextStyle(color: Colors.white70)), const SizedBox(height: 12), ElevatedButton(onPressed: () => ref.read(_reelsFeedProv.notifier).load(), child: const Text('Refresh'))])));
    if (!_vcs.containsKey(0) && reels[0]['is_ad'] != true && reels[0]['video_url'] != null) WidgetsBinding.instance.addPostFrameCallback((_) => _init(0, reels[0]['video_url']));
    return Scaffold(backgroundColor: Colors.black, extendBodyBehindAppBar: true,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, leading: IconButton(icon: const Icon(Icons.arrow_back_rounded, color: Colors.white), onPressed: () => context.pop()), title: const Text('Reels', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)), actions: [IconButton(icon: const Icon(Icons.add_rounded, color: Colors.white), onPressed: () => context.push('/create'))]),
      body: PageView.builder(controller: _pc, scrollDirection: Axis.vertical, itemCount: reels.length, onPageChanged: _onPage, itemBuilder: (_, i) {
        final r = reels[i]; 
        if (r['is_ad'] == true) return const ReelAdOverlay();
        
        final vc = _vcs[i];
        return _Page(reel: r, vc: vc, isActive: _cur == i, showCmts: _showCmts && _cur == i,
          onTap: () { if (vc?.value.isInitialized == true) { if (vc!.value.isPlaying) vc.pause(); else vc.play(); setState(() {}); }},
          onLike: () async { ref.read(_reelsFeedProv.notifier).toggleLike(r['id']); await ref.read(apiServiceProvider).post('/reels/${r['id']}/like').catchError((_){}); },
          onSave: () async { ref.read(_reelsFeedProv.notifier).toggleSave(r['id']); await ref.read(apiServiceProvider).post('/reels/${r['id']}/save').catchError((_){}); },
          onComment: () => setState(() => _showCmts = !_showCmts),
          onShare: () async { await ref.read(apiServiceProvider).post('/reels/${r['id']}/share').catchError((_){}); });
      }));
  }
}

class _Page extends ConsumerWidget {
  final Map<String,dynamic> reel; final VideoPlayerController? vc;
  final bool isActive, showCmts;
  final VoidCallback onTap, onLike, onSave, onComment, onShare;
  const _Page({required this.reel, this.vc, required this.isActive, required this.showCmts, required this.onTap, required this.onLike, required this.onSave, required this.onComment, required this.onShare});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liked = reel['is_liked'] == true || reel['is_liked'] == 1;
    final saved = reel['is_saved'] == true || reel['is_saved'] == 1;
    return GestureDetector(onTap: onTap, onDoubleTap: onLike, child: Stack(fit: StackFit.expand, children: [
      vc?.value.isInitialized == true ? FittedBox(fit: BoxFit.cover, child: SizedBox(width: vc!.value.size.width, height: vc!.value.size.height, child: VideoPlayer(vc!))) : (reel['thumbnail_url'] != null ? CachedNetworkImage(imageUrl: reel['thumbnail_url'], fit: BoxFit.cover) : Container(color: const Color(0xFF111111))),
      Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black.withOpacity(0.35), Colors.transparent, Colors.transparent, Colors.black.withOpacity(0.85)], stops: const [0, 0.15, 0.6, 1])))),
      if (vc?.value.isInitialized == true) Positioned(bottom: 0, left: 0, right: 0, child: AnimatedBuilder(animation: vc!, builder: (_, __) { final tot = vc!.value.duration.inMilliseconds; final pos = vc!.value.position.inMilliseconds; return LinearProgressIndicator(value: tot > 0 ? (pos/tot).clamp(0.0,1.0) : 0.0, backgroundColor: Colors.white24, valueColor: const AlwaysStoppedAnimation(AppTheme.orange), minHeight: 2); })),
      Positioned(bottom: 85, left: 14, right: 80, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (reel['music_title'] != null) Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(16)), child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.music_note_rounded, color: Colors.white, size: 12), const SizedBox(width: 4), Flexible(child: Text('${reel['music_title']}', style: const TextStyle(color: Colors.white, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis))])),
        GestureDetector(onTap: () => context.push('/profile/${reel['user_id']}'), child: Row(children: [
          AppAvatar(url: reel['avatar_url'], size: 34, username: reel['username']),
          const SizedBox(width: 8),
          Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Flexible(child: Text(reel['display_name'] ?? reel['username'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14), overflow: TextOverflow.ellipsis)), if (reel['is_verified'] == 1 || reel['is_verified'] == true) const Padding(padding: EdgeInsets.only(left: 3), child: Icon(Icons.verified_rounded, color: AppTheme.orange, size: 13))]), Text(timeago.format(DateTime.tryParse(reel['created_at'] ?? '') ?? DateTime.now()), style: const TextStyle(color: Colors.white60, fontSize: 10))])),
        ])),
        if (reel['caption'] != null && (reel['caption'] as String).isNotEmpty) ...[const SizedBox(height: 6), Text(reel['caption'], style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4), maxLines: 2, overflow: TextOverflow.ellipsis)],
      ])),
      Positioned(right: 12, bottom: 90, child: Column(children: [
        _AB(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded, FormatUtils.count(reel['likes_count'] as int? ?? 0), liked ? Colors.red : Colors.white, onLike),
        const SizedBox(height: 18),
        _AB(Icons.chat_bubble_outline_rounded, FormatUtils.count(reel['comments_count'] as int? ?? 0), Colors.white, onComment),
        const SizedBox(height: 18),
        _AB(Icons.send_outlined, '', Colors.white, onShare),
        const SizedBox(height: 18),
        _AB(saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, '', saved ? AppTheme.orange : Colors.white, onSave),
        const SizedBox(height: 18),
        GestureDetector(onTap: () => context.push('/profile/${reel['user_id']}'), child: Column(children: [const Icon(Icons.person_rounded, color: Colors.white, size: 26), const SizedBox(height: 3), const Text('Profile', style: TextStyle(color: Colors.white, fontSize: 10))])),
      ])),
      if (showCmts) Positioned.fill(top: null, child: _CmtPanel(reelId: reel['id'] as String? ?? '')),
    ]));
  }
}

class _AB extends StatelessWidget {
  final IconData i; final String l; final Color c; final VoidCallback t;
  const _AB(this.i, this.l, this.c, this.t);
  @override Widget build(BuildContext _) => GestureDetector(onTap: t, child: Column(children: [Icon(i, color: c, size: 28, shadows: const [Shadow(blurRadius: 8)]), if (l.isNotEmpty) ...[const SizedBox(height: 3), Text(l, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600))]]));
}

class _CmtPanel extends ConsumerStatefulWidget {
  final String reelId;
  const _CmtPanel({required this.reelId});
  @override ConsumerState<_CmtPanel> createState() => _CMTS();
}
class _CMTS extends ConsumerState<_CmtPanel> {
  final _ctrl = TextEditingController(); List<dynamic> _cmts = []; bool _l = true, _s = false;
  @override void initState() { super.initState(); _load(); }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }
  Future<void> _load() async { try { final r = await ref.read(apiServiceProvider).get('/reels/${widget.reelId}/comments'); setState(() { _cmts = r.data['comments'] ?? []; _l = false; }); } catch (_) { setState(() => _l = false); } }
  Future<void> _send() async {
    final t = _ctrl.text.trim(); if (t.isEmpty) return;
    setState(() => _s = true);
    try { await ref.read(apiServiceProvider).post('/reels/${widget.reelId}/comments', data: {'content': t}); setState(() { _cmts.insert(0, {'content': t, 'username': 'You', 'avatar_url': null, 'created_at': DateTime.now().toIso8601String()}); }); _ctrl.clear(); } catch (_) {} finally { if (mounted) setState(() => _s = false); }
  }
  @override Widget build(BuildContext context) {
    final me = ref.watch(currentUserProvider);
    return Container(height: MediaQuery.of(context).size.height * 0.65,
      decoration: const BoxDecoration(color: Color(0xFF1A1A1A), borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      child: Column(children: [
        Container(width: 40, height: 4, margin: const EdgeInsets.only(top: 10, bottom: 6), decoration: BoxDecoration(color: Colors.grey.shade700, borderRadius: BorderRadius.circular(2))),
        Text('${_cmts.length} Comments', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
        const Divider(color: Colors.white12),
        Expanded(child: _l ? const Center(child: CircularProgressIndicator(color: AppTheme.orange)) : _cmts.isEmpty ? const Center(child: Text('No comments yet', style: TextStyle(color: Colors.grey))) : ListView.builder(padding: const EdgeInsets.all(12), itemCount: _cmts.length, itemBuilder: (_, i) {
          final c = _cmts[i];
          return Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AppAvatar(url: c['avatar_url'], size: 30, username: c['username']),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              RichText(text: TextSpan(children: [TextSpan(text: '${c['username'] ?? ''} ', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)), TextSpan(text: c['content'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 13))])),
              const SizedBox(height: 3),
              Text(timeago.format(DateTime.tryParse(c['created_at'] ?? '') ?? DateTime.now()), style: const TextStyle(fontSize: 10, color: Colors.grey)),
            ])),
            const Icon(Icons.favorite_border_rounded, size: 14, color: Colors.grey),
          ]));
        })),
        Container(padding: EdgeInsets.only(left: 12, right: 8, top: 8, bottom: MediaQuery.of(context).viewInsets.bottom + 10), decoration: const BoxDecoration(border: Border(top: BorderSide(color: Colors.white12))), child: Row(children: [
          AppAvatar(url: me?.avatarUrl, size: 30, username: me?.username),
          const SizedBox(width: 8),
          Expanded(child: TextField(_ctrl, style: const TextStyle(color: Colors.white, fontSize: 14), decoration: const InputDecoration(hintText: 'Add a comment...', hintStyle: TextStyle(color: Colors.grey), border: InputBorder.none, filled: false))),
          TextButton(onPressed: _s ? null : _send, child: Text(_s ? '...' : 'Post', style: const TextStyle(color: AppTheme.orange, fontWeight: FontWeight.w700))),
        ])),
      ]));
  }
}
