
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'dart:async';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/socket_service.dart';
import '../../../shared/widgets/app_avatar.dart';
import '../../../shared/utils/format_utils.dart';
import '../../ads/widgets/ad_widgets.dart';

class StoryViewerScreen extends ConsumerStatefulWidget {
  final String userId;
  const StoryViewerScreen({super.key, required this.userId});
  @override ConsumerState<StoryViewerScreen> createState() => _S();
}
class _S extends ConsumerState<StoryViewerScreen> {
  List<Map<String,dynamic>> _stories = [];
  int _idx = 0;
  Timer? _timer;
  double _progress = 0;
  bool _paused = false, _loading = true;
  VideoPlayerController? _vc;
  final _replyCtrl = TextEditingController();
  bool _showReply = false;
  static const _duration = Duration(seconds: 5);

  @override
  void initState() { super.initState(); SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky); _load(); }
  @override
  void dispose() {
    _timer?.cancel(); _vc?.dispose(); _replyCtrl.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await ref.read(apiServiceProvider).get('/stories/user/${widget.userId}');
      final stories = List<Map<String,dynamic>>.from(r.data['stories'] ?? []);
      if (stories.isEmpty) { if (mounted) context.pop(); return; }
      setState(() { _stories = stories; _loading = false; });
      _initStory(0);
    } catch (_) { if (mounted) context.pop(); }
  }

  void _initStory(int i) {
    _timer?.cancel(); _vc?.dispose(); _vc = null;
    setState(() { _idx = i; _progress = 0; });
    final s = _stories[i];
    // Mark as viewed
    final ownerId = s['user_id'] as String? ?? '';
    ref.read(socketServiceProvider).viewStory(s['id'] as String? ?? '', ownerId);
    ref.read(apiServiceProvider).post('/stories/${s['id']}/view').catchError((_){});
    if (s['media_type'] == 'video' && s['media_url'] != null) {
      _vc = VideoPlayerController.networkUrl(Uri.parse(s['media_url']))
        ..initialize().then((_) {
          if (mounted) { setState(() {}); _vc!.play(); _startTimer(duration: _vc!.value.duration); }
        });
    } else {
      _startTimer();
    }
  }

  void _startTimer({Duration? duration}) {
    final total = duration ?? _duration;
    const interval = Duration(milliseconds: 50);
    final steps = total.inMilliseconds ~/ interval.inMilliseconds;
    int step = 0;
    _timer = Timer.periodic(interval, (t) {
      if (!mounted || _paused) return;
      step++;
      setState(() => _progress = step / steps);
      if (step >= steps) { t.cancel(); _next(); }
    });
  }

  void _next() {
    if (_idx < _stories.length - 1) _initStory(_idx + 1);
    else if (mounted) context.pop();
  }

  void _prev() {
    if (_idx > 0) _initStory(_idx - 1);
  }

  Future<void> _sendReply(String text) async {
    if (text.trim().isEmpty) return;
    await ref.read(apiServiceProvider).post('/stories/${_stories[_idx]['id']}/reply', data: {'content': text.trim()}).catchError((_){});
    _replyCtrl.clear();
    setState(() { _showReply = false; _paused = false; });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reply sent!')));
  }

  Future<void> _react(String emoji) async {
    final s = _stories[_idx];
    ref.read(socketServiceProvider).reactToStory(s['id'] as String? ?? '', s['user_id'] as String? ?? '', emoji);
    await ref.read(apiServiceProvider).post('/stories/${s['id']}/react', data: {'emoji': emoji}).catchError((_){});
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reacted with $emoji')));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator(color: AppTheme.orange)));
    if (_stories.isEmpty) return const Scaffold(backgroundColor: Colors.black);
    
    final s = _stories[_idx];
    if (s['is_ad'] == true) {
      return StoryAdWidget(onSkip: _next);
    }

    final me = ref.watch(currentUserProvider);
    final isMe = s['user_id'] == me?.id;
    final bgColor = _parseBg(s['bg_color']);
    final dark = true;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapDown: (d) { setState(() => _paused = true); _vc?.pause(); },
        onTapUp: (d) {
          if (_showReply) return;
          setState(() => _paused = false); _vc?.play();
          final mid = MediaQuery.of(context).size.width / 2;
          if (d.globalPosition.dx < mid - 40) _prev(); else _next();
        },
        onLongPress: () { setState(() => _paused = true); _vc?.pause(); },
        onLongPressEnd: (_) { if (!_showReply) { setState(() => _paused = false); _vc?.play(); } },
        onVerticalDragEnd: (d) { if (d.primaryVelocity! > 200) context.pop(); },
        child: Stack(children: [
          // Background
          Positioned.fill(child: s['media_type'] == 'text'
            ? Container(color: bgColor, child: Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(s['text_overlay'] ?? '', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700, height: 1.4), textAlign: TextAlign.center))))
            : (_vc?.value.isInitialized == true ? FittedBox(fit: BoxFit.cover, child: SizedBox(width: _vc!.value.size.width, height: _vc!.value.size.height, child: VideoPlayer(_vc!)))
              : s['media_url'] != null ? CachedNetworkImage(imageUrl: s['media_url'], fit: BoxFit.cover, errorWidget: (_, __, ___) => Container(color: bgColor))
              : Container(color: bgColor))),

          // Gradient overlays
          Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black.withOpacity(0.6), Colors.transparent, Colors.transparent, Colors.black.withOpacity(0.4)], stops: const [0, 0.15, 0.7, 1])))),

          // Text overlay on media
          if (s['media_type'] != 'text' && s['text_overlay'] != null && (s['text_overlay'] as String).isNotEmpty)
            Center(child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(10)), child: Text(s['text_overlay'], style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)))),

          // Music
          if (s['music_title'] != null) Positioned(bottom: 120, left: 0, right: 0, child: Center(child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)), child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.music_note_rounded, color: Colors.white, size: 14), const SizedBox(width: 6), Flexible(child: Text('${s['music_title']}', style: const TextStyle(color: Colors.white, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis))])))),

          // Progress bars
          SafeArea(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), child: Row(children: List.generate(_stories.length, (i) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: LinearProgressIndicator(value: i < _idx ? 1 : (i == _idx ? _progress : 0), backgroundColor: Colors.white38, valueColor: const AlwaysStoppedAnimation(Colors.white), minHeight: 2.5, borderRadius: BorderRadius.circular(2)))))))),

          // Header
          Positioned(top: 48, left: 12, right: 12, child: Row(children: [
            AppAvatar(url: s['avatar_url'], size: 38, username: s['username']),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Text(s['display_name'] ?? s['username'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)), if (s['is_verified'] == 1 || s['is_verified'] == true) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.verified_rounded, color: AppTheme.orange, size: 12))]),
              Text(timeago.format(DateTime.tryParse(s['created_at'] ?? '') ?? DateTime.now()), style: const TextStyle(color: Colors.white70, fontSize: 11)),
            ])),
            IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white, size: 26), onPressed: () => context.pop()),
            if (isMe) IconButton(icon: const Icon(Icons.more_vert_rounded, color: Colors.white, size: 22), onPressed: () => _showOptions()),
          ])),

          // Bottom: reactions + reply
          if (!_showReply) Positioned(bottom: 20, left: 12, right: 12, child: Row(children: [
            // Quick reactions
            ...['❤️','😂','😮','😢','🔥','👏'].map((e) => GestureDetector(onTap: () => _react(e), child: Container(margin: const EdgeInsets.only(right: 6), padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.black38, shape: BoxShape.circle), child: Text(e, style: const TextStyle(fontSize: 20))))),
            const Spacer(),
            // Reply input trigger
            GestureDetector(onTap: () { setState(() { _showReply = true; _paused = true; }); _vc?.pause(); }, child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), decoration: BoxDecoration(border: Border.all(color: Colors.white60), borderRadius: BorderRadius.circular(24)), child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.send_rounded, color: Colors.white70, size: 18), SizedBox(width: 6), Text('Reply', style: TextStyle(color: Colors.white70, fontSize: 14))]))),
          ])),

          // Viewers (my story)
          if (isMe && (s['views_count'] as int? ?? 0) > 0) Positioned(bottom: 80, left: 20, child: GestureDetector(onTap: _showViewers, child: Row(children: [const Icon(Icons.remove_red_eye_rounded, color: Colors.white70, size: 16), const SizedBox(width: 4), Text('${s['views_count']} views', style: const TextStyle(color: Colors.white70, fontSize: 13))]))),

          // Reply input
          if (_showReply) Positioned(bottom: 0, left: 0, right: 0, child: SafeArea(top: false, child: Container(color: Colors.black87, padding: const EdgeInsets.fromLTRB(12, 10, 12, 10), child: Row(children: [
            Expanded(child: TextField(controller: _replyCtrl, autofocus: true, style: const TextStyle(color: Colors.white), decoration: InputDecoration(hintText: 'Reply to ${s['username'] ?? ''}...', hintStyle: const TextStyle(color: Colors.grey), filled: true, fillColor: Colors.white12, border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)))),
            const SizedBox(width: 8),
            GestureDetector(onTap: () => _sendReply(_replyCtrl.text), child: Container(width: 44, height: 44, decoration: const BoxDecoration(color: AppTheme.orange, shape: BoxShape.circle), child: const Icon(Icons.send_rounded, color: Colors.white, size: 20))),
          ])))),
        ]),
      ),
    );
  }

  Color _parseBg(String? hex) {
    if (hex == null) return AppTheme.orange;
    try { return Color(int.parse('0xFF${hex.replaceFirst('#', '')}')); } catch (_) { return AppTheme.orange; }
  }

  void _showViewers() {
    showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => DraggableScrollableSheet(initialChildSize: 0.6, expand: false, builder: (_, ctrl) => Container(
      decoration: const BoxDecoration(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      child: Column(children: [const Padding(padding: EdgeInsets.all(16), child: Text('Viewers', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16))), Expanded(child: _ViewersList(storyId: _stories[_idx]['id'] as String? ?? ''))]),
    )));
  }

  void _showOptions() {
    showModalBottomSheet(context: context, builder: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(leading: const Icon(Icons.delete_outline_rounded, color: Colors.red), title: const Text('Delete Story', style: TextStyle(color: Colors.red)), onTap: () async { Navigator.pop(context); await ref.read(apiServiceProvider).delete('/stories/${_stories[_idx]['id']}').catchError((_){}); _stories.removeAt(_idx); if (_stories.isEmpty) { if (mounted) context.pop(); } else { _idx = _idx.clamp(0, _stories.length - 1); _initStory(_idx); } }),
      ListTile(leading: const Icon(Icons.save_alt_rounded), title: const Text('Save to Gallery'), onTap: () { Navigator.pop(context); }),
      ListTile(leading: const Icon(Icons.bookmark_outline_rounded), title: const Text('Add to Highlights'), onTap: () { Navigator.pop(context); context.push('/create-highlight'); }),
      const SizedBox(height: 20),
    ]));
  }
}

class _ViewersList extends ConsumerStatefulWidget {
  final String storyId;
  const _ViewersList({required this.storyId});
  @override ConsumerState<_ViewersList> createState() => _VLS();
}
class _VLS extends ConsumerState<_ViewersList> {
  List<dynamic> _v = []; bool _l = true;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async { try { final r = await ref.read(apiServiceProvider).get('/stories/${widget.storyId}/viewers'); setState(() { _v = r.data['viewers'] ?? []; _l = false; }); } catch (_) { setState(() => _l = false); } }
  @override Widget build(BuildContext context) => _l ? const Center(child: CircularProgressIndicator(color: AppTheme.orange)) : ListView.builder(itemCount: _v.length, itemBuilder: (_, i) {
    final u = _v[i];
    return ListTile(leading: AppAvatar(url: u['avatar_url'], size: 40, username: u['username']), title: Text(u['display_name'] ?? u['username'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)), subtitle: Text(timeago.format(DateTime.tryParse(u['viewed_at'] ?? '') ?? DateTime.now()), style: const TextStyle(fontSize: 11)), onTap: () => context.push('/profile/${u['id']}'));
  });
}
