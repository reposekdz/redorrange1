import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/socket_service.dart';
import '../../../shared/widgets/app_avatar.dart';
import '../../../shared/utils/format_utils.dart';

class LiveViewerScreen extends ConsumerStatefulWidget {
  final String streamId;
  final Map<String,dynamic>? data;
  const LiveViewerScreen({super.key, required this.streamId, this.data});
  @override ConsumerState<LiveViewerScreen> createState() => _S();
}

class _S extends ConsumerState<LiveViewerScreen> {
  final _cmtCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<Map<String,dynamic>> _comments = [];
  int _viewers = 0;
  bool _sending = false, _isHost = false;
  Timer? _durationTimer;
  int _seconds = 0;

  @override
  void initState() {
    super.initState();
    _isHost = widget.data?['is_host'] == true;
    _setupSocket();
    if (!_isHost) _join();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) { if (mounted) setState(() => _seconds++); });
  }

  @override
  void dispose() {
    _cmtCtrl.dispose(); _scrollCtrl.dispose();
    _durationTimer?.cancel();
    if (!_isHost) {
      ref.read(socketServiceProvider).leaveLive(widget.streamId);
    } else {
      ref.read(apiServiceProvider).post('/live/${widget.streamId}/end').catchError((_){});
    }
    final s = ref.read(socketServiceProvider);
    s.off('live_comment'); s.off('viewer_count_update'); s.off('live_gift'); s.off('live_ended');
    super.dispose();
  }

  void _setupSocket() {
    final s = ref.read(socketServiceProvider);
    s.on('live_comment', (d) {
      if (d is! Map) return;
      if (mounted) {
        setState(() => _comments.add(Map<String,dynamic>.from(d)));
        Future.delayed(const Duration(milliseconds: 100), () {
          if (_scrollCtrl.hasClients) _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
        });
      }
    });
    s.on('viewer_count_update', (d) {
      if (d is Map && mounted) setState(() => _viewers = d['count'] as int? ?? _viewers);
    });
    s.on('live_gift', (d) {
      if (d is! Map || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('🎁 ${d['sender']?['display_name'] ?? 'Someone'} sent a gift: ${d['gift_type']}!'), backgroundColor: AppTheme.orange, duration: const Duration(seconds: 2)));
    });
    s.on('live_ended', (d) {
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Live stream ended'))); context.pop(); }
    });
  }

  Future<void> _join() async {
    final s = ref.read(socketServiceProvider);
    s.joinLive(widget.streamId);
    try {
      final r = await ref.read(apiServiceProvider).post('/live/${widget.streamId}/join');
      if (mounted) setState(() => _viewers = r.data['stream']?['viewer_count'] as int? ?? 0);
    } catch (_) {}
  }

  Future<void> _sendComment() async {
    final t = _cmtCtrl.text.trim();
    if (t.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ref.read(apiServiceProvider).post('/live/${widget.streamId}/comment', data: {'content': t});
      _cmtCtrl.clear();
    } catch (_) {}
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _endLive() async {
    final confirmed = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('End Live Stream?'),
      content: const Text('This will end your broadcast and notify viewers.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep Going')), TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('End Stream', style: TextStyle(color: Colors.red)))],
    ));
    if (confirmed == true) {
      await ref.read(apiServiceProvider).post('/live/${widget.streamId}/end').catchError((_){});
      if (mounted) context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final me   = ref.watch(currentUserProvider);
    final title    = widget.data?['title'] as String? ?? 'Live Stream';
    final userName = widget.data?['user_name'] as String? ?? 'Host';
    final avatar   = widget.data?['user_avatar'] as String?;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        // Video placeholder (real RTMP/WebRTC would go here)
        Positioned.fill(child: Container(
          decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF0D0D0D), Color(0xFF1A1A1A)])),
          child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.live_tv_rounded, size: 80, color: Colors.white24),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(color: Colors.white38, fontSize: 18, fontWeight: FontWeight.w600)),
          ])),
        )),

        // Gradient overlay bottom
        Positioned.fill(top: null, bottom: 0, child: Container(height: MediaQuery.of(context).size.height * 0.5, decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black.withOpacity(0.95), Colors.transparent])))),

        // Top bar
        SafeArea(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), child: Row(children: [
          AppAvatar(url: avatar, size: 36, username: userName),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(userName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
            Text(title, style: const TextStyle(color: Colors.white70, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
          ])),
          // LIVE badge
          Container(margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(10)), child: Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 7, height: 7, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)), const SizedBox(width: 5), const Text('LIVE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11))])),
          // Viewer count
          Container(margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)), child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.remove_red_eye_rounded, color: Colors.white, size: 13), const SizedBox(width: 4), Text(FormatUtils.count(_viewers), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11))])),
          // Duration
          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)), child: Text(FormatUtils.dur(_seconds), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600))),
          const SizedBox(width: 8),
          if (_isHost) IconButton(onPressed: _endLive, icon: const Icon(Icons.stop_circle_rounded, color: Colors.red, size: 26))
          else IconButton(onPressed: () => context.pop(), icon: const Icon(Icons.close_rounded, color: Colors.white, size: 24)),
        ]))),

        // Comments feed
        Positioned(bottom: 80, left: 14, right: 80, child: SizedBox(height: MediaQuery.of(context).size.height * 0.3,
          child: ListView.builder(
            controller: _scrollCtrl,
            itemCount: _comments.length,
            itemBuilder: (_, i) {
              final c = _comments[i];
              return Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                AppAvatar(url: c['user']?['avatar_url'], size: 28, username: c['user']?['username']),
                const SizedBox(width: 6),
                Flexible(child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)), child: RichText(text: TextSpan(children: [TextSpan(text: '${c['user']?['username'] ?? c['username'] ?? 'User'} ', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)), TextSpan(text: c['content'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 12))])))),
              ]));
            },
          ),
        )),

        // Right: reaction buttons
        Positioned(right: 14, bottom: 90, child: Column(children: [
          _GiftBtn('🎁', 'Gift',  () => ref.read(socketServiceProvider).sendGift(widget.streamId, 'heart')),
          const SizedBox(height: 14),
          _GiftBtn('❤️', 'Like',  () {}),
          const SizedBox(height: 14),
          _GiftBtn('🔥', 'Fire',  () => ref.read(socketServiceProvider).sendGift(widget.streamId, 'fire')),
          const SizedBox(height: 14),
          _GiftBtn('👋', 'Wave',  () => ref.read(socketServiceProvider).sendGift(widget.streamId, 'wave')),
        ])),

        // Comment input
        Positioned(bottom: 0, left: 0, right: 0, child: SafeArea(top: false, child: Container(color: Colors.black87, padding: const EdgeInsets.fromLTRB(12, 8, 12, 10), child: Row(children: [
          AppAvatar(url: me?.avatarUrl, size: 30, username: me?.username),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: _cmtCtrl, style: const TextStyle(color: Colors.white, fontSize: 14), textInputAction: TextInputAction.send, onSubmitted: (_) => _sendComment(), decoration: const InputDecoration(hintText: 'Say something...', hintStyle: TextStyle(color: Colors.white38), border: InputBorder.none, filled: false))),
          const SizedBox(width: 8),
          if (_isHost) TextButton(onPressed: () {}, child: const Text('Share', style: TextStyle(color: AppTheme.orange, fontWeight: FontWeight.w600)))
          else TextButton(onPressed: _sending ? null : _sendComment, child: Text(_sending ? '...' : 'Send', style: const TextStyle(color: AppTheme.orange, fontWeight: FontWeight.w700))),
        ])))),
      ]),
    );
  }
}

class _GiftBtn extends StatelessWidget {
  final String emoji, label; final VoidCallback onTap;
  const _GiftBtn(this.emoji, this.label, this.onTap);
  @override Widget build(BuildContext _) => GestureDetector(onTap: onTap, child: Column(children: [
    Container(width: 46, height: 46, decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle), child: Center(child: Text(emoji, style: const TextStyle(fontSize: 22)))),
    const SizedBox(height: 3), Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10)),
  ]));
}
