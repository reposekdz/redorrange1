import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/socket_service.dart';
import '../services/api_service.dart';

final notificationProviderInstance = StateNotifierProvider<NotificationController, NotificationState>((ref) => NotificationController(ref));

class NotificationState {
  final Map<String,dynamic>? incomingCall;
  final int unreadNotifications, unreadMessages;
  const NotificationState({this.incomingCall, this.unreadNotifications = 0, this.unreadMessages = 0});
  NotificationState copyWith({Map<String,dynamic>? incomingCall, int? unreadNotifications, int? unreadMessages, bool clearCall = false}) => NotificationState(
    incomingCall: clearCall ? null : (incomingCall ?? this.incomingCall),
    unreadNotifications: unreadNotifications ?? this.unreadNotifications,
    unreadMessages: unreadMessages ?? this.unreadMessages,
  );
}

class NotificationController extends StateNotifier<NotificationState> {
  final Ref _ref;
  NotificationController(this._ref) : super(const NotificationState()) { _init(); }

  Future<void> _init() async {
    await _load();
    _listen();
  }

  Future<void> _load() async {
    try {
      final r = await _ref.read(apiServiceProvider).get('/notifications/unread-count');
      if (mounted) state = state.copyWith(unreadNotifications: r.data['unread_notifications'] as int? ?? 0, unreadMessages: r.data['unread_messages'] as int? ?? 0);
    } catch (_) {}
  }

  void _listen() {
    final s = _ref.read(socketServiceProvider);
    s.on('incoming_call', (d) { if (d is Map && mounted) state = state.copyWith(incomingCall: Map<String,dynamic>.from(d)); });
    s.on('call_cancelled', (_) { if (mounted) state = state.copyWith(clearCall: true); });
    s.on('call_rejected',  (_) { if (mounted) state = state.copyWith(clearCall: true); });
    s.on('new_message', (_) { if (mounted) state = state.copyWith(unreadMessages: state.unreadMessages + 1); });
    s.on('messages_read', (_) { if (mounted && state.unreadMessages > 0) state = state.copyWith(unreadMessages: (state.unreadMessages - 1).clamp(0, 9999)); });
    s.on('notification', (_) { if (mounted) state = state.copyWith(unreadNotifications: state.unreadNotifications + 1); });
    s.on('all_notifications_read', (_) { if (mounted) state = state.copyWith(unreadNotifications: 0); });
    s.on('unread_count', (d) { if (d is Map && mounted) state = state.copyWith(unreadNotifications: d['notifications'] as int? ?? state.unreadNotifications, unreadMessages: d['messages'] as int? ?? state.unreadMessages); });
  }

  void clearIncomingCall() => state = state.copyWith(clearCall: true);
  void zeroMessages() => state = state.copyWith(unreadMessages: 0);
  Future<void> refresh() => _load();
}
