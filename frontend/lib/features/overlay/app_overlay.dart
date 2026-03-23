import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';
import '../../core/theme/app_theme.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/notification_provider.dart';
import '../../core/services/api_service.dart';
import '../../core/services/socket_service.dart';
import '../../shared/widgets/app_avatar.dart';

class AppOverlay extends ConsumerStatefulWidget {
  final Widget child;
  const AppOverlay({super.key, required this.child});
  @override ConsumerState<AppOverlay> createState() => _S();
}

class _S extends ConsumerState<AppOverlay> with WidgetsBindingObserver {
  OverlayEntry? _miniChatEntry;
  OverlayEntry? _toastEntry;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _listenSocket();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _miniChatEntry?.remove();
    _toastEntry?.remove();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final s = ref.read(socketServiceProvider);
    if (state == AppLifecycleState.resumed) {
      if (!s.isConnected) s.connect();
      s.setPresence('active');
    } else if (state == AppLifecycleState.paused) {
      s.setPresence('away');
    }
  }

  void _listenSocket() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final s = ref.read(socketServiceProvider);

      // New message → mini chat popup
      s.on('new_message', (d) {
        if (d is! Map) return;
        final msg = d['message'] as Map?;
        if (msg == null) return;
        final convId  = msg['conversation_id'] as String? ?? '';
        final sender  = msg['display_name'] as String? ?? msg['username'] as String? ?? 'Someone';
        final avatar  = msg['avatar_url'] as String?;
        final content = msg['content'] as String? ?? _mediaLabel(msg['type'] as String? ?? '');
        final me = ref.read(currentUserProvider);
        if (msg['sender_id'] == me?.id) return;

        // Don't show if already in that chat
        final nav = GoRouter.of(context);
        final currentLoc = nav.routerDelegate.currentConfiguration.uri.toString();
        if (currentLoc.contains('/chat/$convId')) return;

        _showMiniChat(convId: convId, sender: sender, avatar: avatar, content: content);
      });

      // Notification toast
      s.on('notification', (d) {
        if (d is! Map) return;
        final n = d['notification'] as Map? ?? d;
        _showNotifToast(
          message: n['message'] as String? ?? 'New notification',
          avatar:  n['actor_avatar'] as String?,
          name:    n['actor_name'] as String? ?? n['actor_username'] as String? ?? '',
          targetType: n['target_type'] as String?,
          targetId:   n['target_id'] as String?,
        );
      });
    });
  }

  String _mediaLabel(String type) {
    switch (type) {
      case 'image':      return '📷 Photo';
      case 'video':      return '🎥 Video';
      case 'voice_note': return '🎤 Voice message';
      case 'file':       return '📎 File';
      default:           return 'Message';
    }
  }

  void _showMiniChat({required String convId, required String sender, String? avatar, required String content}) {
    _miniChatEntry?.remove();
    _miniChatEntry = null;

    final replyCtrl = TextEditingController();

    _miniChatEntry = OverlayEntry(builder: (_) => _MiniChatBubble(
      sender: sender, avatar: avatar, content: content, convId: convId,
      replyCtrl: replyCtrl,
      onOpen: () {
        _miniChatEntry?.remove(); _miniChatEntry = null;
        context.push('/chat/$convId');
      },
      onDismiss: () { _miniChatEntry?.remove(); _miniChatEntry = null; },
      onReply: (text) async {
        if (text.trim().isEmpty) return;
        try {
          await ref.read(apiServiceProvider).post('/messages/conversations/$convId/messages', data: {'content': text.trim()});
        } catch (_) {}
        _miniChatEntry?.remove(); _miniChatEntry = null;
      },
    ));

    Overlay.of(context).insert(_miniChatEntry!);

    // Auto-dismiss after 7 seconds
    Timer(const Duration(seconds: 7), () {
      if (_miniChatEntry != null) { _miniChatEntry?.remove(); _miniChatEntry = null; }
    });
  }

  void _showNotifToast({required String message, String? avatar, required String name, String? targetType, String? targetId}) {
    _toastEntry?.remove(); _toastEntry = null;

    _toastEntry = OverlayEntry(builder: (_) => _NotifToast(
      message: message, avatar: avatar, name: name,
      onTap: () {
        _toastEntry?.remove(); _toastEntry = null;
        if (targetType == 'post' && targetId != null) context.push('/post/$targetId');
        else if (targetType == 'escrow' && targetId != null) context.push('/escrow/$targetId');
      },
      onDismiss: () { _toastEntry?.remove(); _toastEntry = null; },
    ));

    Overlay.of(context).insert(_toastEntry!);
    Timer(const Duration(seconds: 5), () { _toastEntry?.remove(); _toastEntry = null; });
  }

  @override
  Widget build(BuildContext context) {
    final callState = ref.watch(notificationProviderInstance.select((s) => s.incomingCall));
    return Stack(children: [
      widget.child,
      if (callState != null) _IncomingCallOverlay(callData: callState),
    ]);
  }
}

// ═══════════════════════════════════════════════════════
// INCOMING CALL OVERLAY
// ═══════════════════════════════════════════════════════
class _IncomingCallOverlay extends ConsumerWidget {
  final Map<String,dynamic> callData;
  const _IncomingCallOverlay({required this.callData});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caller    = callData['caller'] as Map? ?? {};
    final callId    = callData['call_id'] as String? ?? '';
    final callType  = callData['call_type'] as String? ?? 'audio';
    final callerName = caller['display_name'] as String? ?? caller['username'] as String? ?? 'Unknown';
    final callerAvatar = caller['avatar_url'] as String?;
    final callerId   = caller['id'] as String? ?? '';
    final isVideo    = callType == 'video';
    final dark       = Theme.of(context).brightness == Brightness.dark;

    return Positioned.fill(child: Material(color: Colors.transparent, child: Container(
      decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF0A0A0A), Color(0xFF1A1A1A)], stops: [0.0, 1.0])),
      child: SafeArea(child: Column(children: [
        const SizedBox(height: 40),
        Text(isVideo ? 'Incoming Video Call' : 'Incoming Call', style: const TextStyle(color: Colors.white54, fontSize: 16, letterSpacing: 0.5)),
        const SizedBox(height: 30),

        // Pulsing avatar
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.95, end: 1.05),
          duration: const Duration(seconds: 1),
          curve: Curves.easeInOut,
          builder: (_, v, child) => Transform.scale(scale: v, child: child),
          child: Container(
            width: 120, height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(colors: [AppTheme.orange, AppTheme.orangeDark]),
              boxShadow: [BoxShadow(color: AppTheme.orange.withOpacity(0.4), blurRadius: 40, spreadRadius: 10)],
            ),
            child: Padding(padding: const EdgeInsets.all(4), child: ClipOval(child: callerAvatar != null
              ? Image.network(callerAvatar, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _AvatarFallback(callerName))
              : _AvatarFallback(callerName))),
          ),
        ),

        const SizedBox(height: 24),
        Text(callerName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 28)),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (isVideo) const Icon(Icons.videocam_rounded, color: Colors.white54, size: 18),
          if (!isVideo) const Icon(Icons.call_rounded, color: Colors.white54, size: 18),
          const SizedBox(width: 6),
          Text(isVideo ? 'Video Call' : 'Audio Call', style: const TextStyle(color: Colors.white54, fontSize: 15)),
        ]),

        const Spacer(),

        // Action buttons
        Padding(padding: const EdgeInsets.only(bottom: 60), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          // Decline
          _CallBtn(Icons.call_end_rounded, Colors.red, 'Decline', () {
            HapticFeedback.heavyImpact();
            ref.read(socketServiceProvider).rejectCall(callId: callId, callerId: callerId, reason: 'declined');
            ref.read(notificationProviderInstance.notifier).clearIncomingCall();
          }),

          // Message
          _CallBtn(Icons.message_rounded, Colors.blueGrey, 'Message', () {
            ref.read(notificationProviderInstance.notifier).clearIncomingCall();
            context.push('/new-chat');
          }),

          // Accept
          _CallBtn(Icons.call_rounded, Colors.green, 'Accept', () {
            HapticFeedback.heavyImpact();
            ref.read(notificationProviderInstance.notifier).clearIncomingCall();
            context.push('/call/$callType', extra: {
              'call_id':    callId,
              'user_id':    callerId,
              'user_name':  callerName,
              'avatar':     callerAvatar,
              'is_incoming': true,
              'offer':      callData['offer'],
            });
          }),
        ])),
      ])),
    )));
  }
}

class _AvatarFallback extends StatelessWidget {
  final String name;
  const _AvatarFallback(this.name);
  @override Widget build(BuildContext _) => Container(color: AppTheme.orange, child: Center(child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white, fontSize: 46, fontWeight: FontWeight.w900))));
}

class _CallBtn extends StatelessWidget {
  final IconData icon; final Color color; final String label; final VoidCallback onTap;
  const _CallBtn(this.icon, this.color, this.label, this.onTap);
  @override Widget build(BuildContext _) => GestureDetector(onTap: onTap, child: Column(children: [
    Container(width: 68, height: 68, decoration: BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 16, spreadRadius: 2)]), child: Icon(icon, color: Colors.white, size: 30)),
    const SizedBox(height: 10),
    Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
  ]));
}

// ═══════════════════════════════════════════════════════
// MINI CHAT BUBBLE
// ═══════════════════════════════════════════════════════
class _MiniChatBubble extends StatefulWidget {
  final String sender, content, convId;
  final String? avatar;
  final TextEditingController replyCtrl;
  final VoidCallback onOpen, onDismiss;
  final Future<void> Function(String) onReply;
  const _MiniChatBubble({required this.sender, required this.content, required this.convId, this.avatar, required this.replyCtrl, required this.onOpen, required this.onDismiss, required this.onReply});
  @override State<_MiniChatBubble> createState() => _MCBS();
}
class _MCBS extends State<_MiniChatBubble> with SingleTickerProviderStateMixin {
  late AnimationController _ac;
  late Animation<Offset> _slide;
  late Animation<double> _fade;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
    _slide = Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero).animate(CurvedAnimation(parent: _ac, curve: Curves.elasticOut));
    _fade  = CurvedAnimation(parent: _ac, curve: Curves.easeOut);
    _ac.forward();
    HapticFeedback.lightImpact();
  }

  @override
  void dispose() { _ac.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Positioned(top: MediaQuery.of(context).viewPadding.top + 8, left: 12, right: 12, child: SlideTransition(position: _slide, child: FadeTransition(opacity: _fade, child: Material(elevation: 8, borderRadius: BorderRadius.circular(16), color: Colors.transparent, child: Container(
      decoration: BoxDecoration(color: dark ? const Color(0xFF1E1E1E) : Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.orange.withOpacity(0.3))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Header
        InkWell(onTap: widget.onOpen, borderRadius: const BorderRadius.vertical(top: Radius.circular(16)), child: Padding(padding: const EdgeInsets.fromLTRB(12, 10, 10, 8), child: Row(children: [
          AppAvatar(url: widget.avatar, size: 36, username: widget.sender),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.sender, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            Text(widget.content, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ])),
          GestureDetector(onTap: () => setState(() => _expanded = !_expanded), child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: AppTheme.orangeSurf, borderRadius: BorderRadius.circular(10)), child: Text(_expanded ? 'Hide' : 'Reply', style: const TextStyle(color: AppTheme.orange, fontSize: 11, fontWeight: FontWeight.w600)))),
          const SizedBox(width: 6),
          GestureDetector(onTap: widget.onDismiss, child: const Icon(Icons.close_rounded, size: 16, color: Colors.grey)),
        ]))),

        // Reply field
        if (_expanded) Padding(padding: const EdgeInsets.fromLTRB(10, 0, 10, 10), child: Row(children: [
          Expanded(child: TextField(controller: widget.replyCtrl, autofocus: true, textInputAction: TextInputAction.send, onSubmitted: widget.onReply, decoration: InputDecoration(hintText: 'Reply to ${widget.sender}...', isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none), filled: true, fillColor: dark ? AppTheme.dCard : const Color(0xFFF0F0F0)))),
          const SizedBox(width: 6),
          GestureDetector(onTap: () => widget.onReply(widget.replyCtrl.text), child: Container(width: 36, height: 36, decoration: const BoxDecoration(color: AppTheme.orange, shape: BoxShape.circle), child: const Icon(Icons.send_rounded, color: Colors.white, size: 18))),
        ])),
      ]),
    )))));
  }
}

// ═══════════════════════════════════════════════════════
// NOTIFICATION TOAST
// ═══════════════════════════════════════════════════════
class _NotifToast extends StatefulWidget {
  final String message, name; final String? avatar, targetType, targetId;
  final VoidCallback onTap, onDismiss;
  const _NotifToast({required this.message, required this.name, this.avatar, this.targetType, this.targetId, required this.onTap, required this.onDismiss});
  @override State<_NotifToast> createState() => _NTS();
}
class _NTS extends State<_NotifToast> with SingleTickerProviderStateMixin {
  late AnimationController _ac;
  late Animation<Offset> _slide;
  @override void initState() { super.initState(); _ac = AnimationController(vsync: this, duration: const Duration(milliseconds: 300)); _slide = Tween<Offset>(begin: const Offset(0, -1.5), end: Offset.zero).animate(CurvedAnimation(parent: _ac, curve: Curves.easeOutBack)); _ac.forward(); }
  @override void dispose() { _ac.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Positioned(top: MediaQuery.of(context).viewPadding.top + 8, left: 12, right: 12, child: SlideTransition(position: _slide, child: Material(elevation: 6, borderRadius: BorderRadius.circular(14), color: Colors.transparent, child: InkWell(onTap: widget.onTap, borderRadius: BorderRadius.circular(14), child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: dark ? const Color(0xFF2A2A2A) : Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.orange.withOpacity(0.2))),
      child: Row(children: [
        AppAvatar(url: widget.avatar, size: 38, username: widget.name),
        const SizedBox(width: 10),
        Expanded(child: Text(widget.message, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, height: 1.3))),
        const SizedBox(width: 6),
        GestureDetector(onTap: widget.onDismiss, child: const Icon(Icons.close_rounded, size: 16, color: Colors.grey)),
      ]),
    )))));
  }
}
