import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/models/models.dart';
import '../../../shared/widgets/app_avatar.dart';

final _notifProvider = StateNotifierProvider.autoDispose<_NotifsNotifier, _NotifsState>((ref) => _NotifsNotifier(ref));

class _NotifsState {
  final List<NotificationModel> all;
  final int unread;
  final bool loading;
  const _NotifsState({this.all = const [], this.unread = 0, this.loading = true});
  _NotifsState copyWith({List<NotificationModel>? all, int? unread, bool? loading}) =>
    _NotifsState(all: all ?? this.all, unread: unread ?? this.unread, loading: loading ?? this.loading);
}

class _NotifsNotifier extends StateNotifier<_NotifsState> {
  final Ref _ref;
  _NotifsNotifier(this._ref) : super(const _NotifsState()) {
    load();
    _listenSocket();
  }

  void _listenSocket() {
    final s = _ref.read(socketServiceProvider);
    s.on('notification', (d) {
      if (d is! Map) return;
      final n = NotificationModel.fromJson(Map<String,dynamic>.from(d['notification'] as Map? ?? d));
      if (mounted) state = state.copyWith(all: [n, ...state.all], unread: state.unread + 1);
    });
    s.on('notification_updated', (d) {
      if (d is! Map) return;
      final id = d['notification_id'] as String?;
      if (id == null) return;
      state = state.copyWith(
        all: state.all.map((n) => n.id == id ? NotificationModel(id: n.id, type: n.type, createdAt: n.createdAt, actorId: n.actorId, actorUsername: n.actorUsername, actorName: n.actorName, actorAvatar: n.actorAvatar, targetType: n.targetType, targetId: n.targetId, message: n.message, isRead: true) : n).toList(),
        unread: (state.unread - 1).clamp(0, 9999),
      );
    });
    s.on('all_notifications_read', (_) {
      state = state.copyWith(
        all: state.all.map((n) => NotificationModel(id: n.id, type: n.type, createdAt: n.createdAt, actorId: n.actorId, actorUsername: n.actorUsername, actorName: n.actorName, actorAvatar: n.actorAvatar, targetType: n.targetType, targetId: n.targetId, message: n.message, isRead: true)).toList(),
        unread: 0,
      );
    });
  }

  Future<void> load() async {
    try {
      final r = await _ref.read(apiServiceProvider).get('/notifications', q: {'limit': '60'});
      final list = (r.data['notifications'] as List? ?? []).map((n) => NotificationModel.fromJson(Map<String,dynamic>.from(n))).toList();
      final unread = list.where((n) => !n.isRead).length;
      if (mounted) state = state.copyWith(all: list, unread: unread, loading: false);
    } catch (_) { if (mounted) state = state.copyWith(loading: false); }
  }

  void markRead(String id) {
    _ref.read(socketServiceProvider).readNotification(id);
  }

  void markAllRead() {
    _ref.read(socketServiceProvider).readAllNotifications();
  }
}

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});
  @override ConsumerState<NotificationsScreen> createState() => _S();
}
class _S extends ConsumerState<NotificationsScreen> with SingleTickerProviderStateMixin {
  late TabController _tc;
  static const _tabs = ['All', 'Mentions', 'Likes', 'Comments', 'Follows', 'Gifts', 'Calls'];
  @override void initState() { super.initState(); _tc = TabController(length: _tabs.length, vsync: this); }
  @override void dispose() { _tc.dispose(); super.dispose(); }

  List<NotificationModel> _filter(List<NotificationModel> all, String tab) {
    switch (tab) {
      case 'Mentions':  return all.where((n) => n.type == 'mention').toList();
      case 'Likes':     return all.where((n) => ['like','reaction'].contains(n.type)).toList();
      case 'Comments':  return all.where((n) => ['comment','comment_reply'].contains(n.type)).toList();
      case 'Follows':   return all.where((n) => ['follow','follow_request','follow_accepted'].contains(n.type)).toList();
      case 'Gifts':     return all.where((n) => n.type == 'gift').toList();
      case 'Calls':     return all.where((n) => n.type == 'call').toList();
      default:          return all;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(_notifProvider);
    final dark  = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          const Text('Notifications', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
          if (state.unread > 0) Container(margin: const EdgeInsets.only(left: 8), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: AppTheme.orange, borderRadius: BorderRadius.circular(10)), child: Text('${state.unread}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700))),
        ]),
        actions: [
          if (state.unread > 0) TextButton(onPressed: () => ref.read(_notifProvider.notifier).markAllRead(), child: const Text('Mark all read', style: TextStyle(color: AppTheme.orange, fontSize: 12, fontWeight: FontWeight.w600))),
          IconButton(icon: const Icon(Icons.settings_rounded), onPressed: () => context.push('/notification-settings'), tooltip: 'Settings'),
        ],
        bottom: TabBar(
          controller: _tc, isScrollable: true, tabAlignment: TabAlignment.start,
          indicatorColor: AppTheme.orange, labelColor: AppTheme.orange, unselectedLabelColor: Colors.grey,
          labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          tabs: _tabs.map((t) {
            final count = t == 'All' ? state.unread : _filter(state.all, t).where((n) => !n.isRead).length;
            return Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(t),
              if (count > 0) Container(margin: const EdgeInsets.only(left: 4), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1), decoration: BoxDecoration(color: AppTheme.orange, borderRadius: BorderRadius.circular(8)), child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700))),
            ]));
          }).toList(),
        ),
      ),
      body: state.loading
        ? const Center(child: CircularProgressIndicator(color: AppTheme.orange))
        : TabBarView(controller: _tc, children: _tabs.map((tab) {
            final list = _filter(state.all, tab);
            if (list.isEmpty) return _Empty(tab: tab);
            return RefreshIndicator(
              color: AppTheme.orange,
              onRefresh: () async => ref.read(_notifProvider.notifier).load(),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final n = list[i];
                  return _NotifTile(
                    notif: n, dark: dark,
                    onTap: () {
                      if (!n.isRead) ref.read(_notifProvider.notifier).markRead(n.id);
                      _navigate(context, n);
                    },
                    onDismiss: () => ref.read(_notifProvider.notifier).markRead(n.id),
                  );
                },
              ),
            );
          }).toList()),
    );
  }

  void _navigate(BuildContext ctx, NotificationModel n) {
    if (n.targetType == 'post' && n.targetId != null)    ctx.push('/post/${n.targetId}');
    else if (n.targetType == 'reel' && n.targetId != null) ctx.push('/reel/${n.targetId}');
    else if (n.targetType == 'user' && n.actorId != null)  ctx.push('/profile/${n.actorId}');
    else if (n.targetType == 'escrow' && n.targetId != null) ctx.push('/escrow/${n.targetId}');
    else if (n.actorId != null) ctx.push('/profile/${n.actorId}');
  }
}

class _NotifTile extends StatelessWidget {
  final NotificationModel notif; final bool dark;
  final VoidCallback onTap, onDismiss;
  const _NotifTile({required this.notif, required this.dark, required this.onTap, required this.onDismiss});

  Color get _accentColor {
    switch (notif.type) {
      case 'like': case 'reaction':       return Colors.red;
      case 'comment': case 'comment_reply': return const Color(0xFF9C27B0);
      case 'follow': case 'follow_request': case 'follow_accepted': return const Color(0xFF2196F3);
      case 'mention':                      return const Color(0xFFFF9800);
      case 'gift':                         return AppTheme.orange;
      case 'call':                         return const Color(0xFF4CAF50);
      case 'story_view': case 'story_reply': return const Color(0xFFE91E63);
      case 'escrow_created': case 'escrow_funded': case 'escrow_completed': return const Color(0xFF4CAF50);
      case 'escrow_disputed':              return Colors.red;
      case 'subscription_activated':       return const Color(0xFF9C27B0);
      case 'live':                         return Colors.red;
      default:                             return AppTheme.orange;
    }
  }

  IconData get _icon {
    switch (notif.type) {
      case 'like':                         return Icons.favorite_rounded;
      case 'reaction':                     return Icons.emoji_emotions_rounded;
      case 'comment':                      return Icons.chat_bubble_rounded;
      case 'comment_reply':                return Icons.reply_rounded;
      case 'follow':                       return Icons.person_add_rounded;
      case 'follow_request':               return Icons.person_add_outlined;
      case 'follow_accepted':              return Icons.how_to_reg_rounded;
      case 'mention':                      return Icons.alternate_email_rounded;
      case 'gift':                         return Icons.card_giftcard_rounded;
      case 'call':                         return Icons.call_rounded;
      case 'story_view':                   return Icons.auto_stories_rounded;
      case 'story_reply':                  return Icons.reply_rounded;
      case 'message_reaction':             return Icons.emoji_emotions_rounded;
      case 'escrow_created':               return Icons.security_rounded;
      case 'escrow_funded':                return Icons.paid_rounded;
      case 'escrow_shipped':               return Icons.local_shipping_rounded;
      case 'escrow_completed':             return Icons.verified_rounded;
      case 'escrow_disputed':              return Icons.gavel_rounded;
      case 'subscription_activated':       return Icons.workspace_premium_rounded;
      case 'live':                         return Icons.live_tv_rounded;
      case 'contact_joined':               return Icons.person_rounded;
      default:                             return Icons.notifications_rounded;
    }
  }

  @override
  Widget build(BuildContext context) => Dismissible(
    key: Key(notif.id),
    direction: DismissDirection.endToStart,
    background: Container(color: AppTheme.orange, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.done_all_rounded, color: Colors.white)),
    onDismissed: (_) => onDismiss(),
    child: InkWell(
      onTap: onTap,
      child: Container(
        color: notif.isRead ? null : (dark ? AppTheme.orange.withOpacity(0.05) : AppTheme.orange.withOpacity(0.04)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Actor avatar with icon badge
          Stack(children: [
            AppAvatar(url: notif.actorAvatar, size: 46, username: notif.actorName ?? notif.actorUsername),
            Positioned(bottom: 0, right: 0, child: Container(width: 18, height: 18, decoration: BoxDecoration(color: _accentColor, shape: BoxShape.circle, border: Border.all(color: dark ? AppTheme.dBg : Colors.white, width: 1.5)), child: Icon(_icon, color: Colors.white, size: 10))),
          ]),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(notif.message ?? '', style: const TextStyle(fontSize: 14, height: 1.4), maxLines: 3, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(timeago.format(DateTime.tryParse(notif.createdAt) ?? DateTime.now()), style: TextStyle(fontSize: 11, color: dark ? AppTheme.dSub : AppTheme.lSub)),
          ])),
          if (!notif.isRead) Container(width: 8, height: 8, margin: const EdgeInsets.only(top: 4, left: 6), decoration: const BoxDecoration(color: AppTheme.orange, shape: BoxShape.circle)),
        ]),
      ),
    ),
  );
}

class _Empty extends StatelessWidget {
  final String tab;
  const _Empty({required this.tab});
  @override Widget build(BuildContext _) => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    const Icon(Icons.notifications_none_rounded, size: 72, color: Colors.grey),
    const SizedBox(height: 16),
    Text('No ${tab.toLowerCase()} notifications', style: const TextStyle(fontSize: 16, color: Colors.grey, fontWeight: FontWeight.w600)),
    const SizedBox(height: 8),
    const Text('Engage with others to start getting notified', style: TextStyle(color: Colors.grey, fontSize: 13), textAlign: TextAlign.center),
  ]));
}
