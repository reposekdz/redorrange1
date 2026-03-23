import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'dart:async';
import 'api_service.dart';
import 'push_service.dart';

const _wsBase = String.fromEnvironment('WS_URL', defaultValue: 'http://10.0.2.2:3000');

final socketServiceProvider = Provider<SocketService>((ref) => SocketService(ref.read(apiServiceProvider)));

class SocketService {
  io.Socket? _socket;
  final ApiService _api;
  final Map<String, List<void Function(dynamic)>> _handlers = {};
  bool _connected = false;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;

  SocketService(this._api);

  bool get isConnected => _connected;

  /// Connect with JWT auth. Safe to call multiple times.
  Future<void> connect() async {
    if (_socket?.connected == true) return;
    final token = await _api.getToken();
    if (token == null) return;

    _socket?.dispose();
    _socket = io.io(_wsBase, io.OptionBuilder()
      .setTransports(['websocket'])
      .setAuth({'token': token})
      .setReconnectionDelay(2000)
      .setReconnectionDelayMax(10000)
      .setReconnectionAttempts(20)
      .enableReconnection()
      .disableAutoConnect()
      .setTimeout(20000)
      .build());

    // Attach push notifications to socket events
    PushService.attachToSocket(this);
    _socket!.onConnect((_) {
      _connected = true;
      _reconnectAttempts = 0;
      _rebindAll();
      _startPing();
      emit('ping_server');
    });

    _socket!.onDisconnect((_) {
      _connected = false;
      _pingTimer?.cancel();
    });

    _socket!.onReconnect((_) {
      _connected = true;
      _rebindAll();
      _startPing();
    });

    _socket!.onReconnectAttempt((_) => _reconnectAttempts++);

    _socket!.on('pong_server', (_) {}); // heartbeat ack

    _socket!.onError((e) {});
    _socket!.onConnectError((e) {});

    _rebindAll();
    _socket!.connect();
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (_connected) emit('ping_server');
    });
  }

  void _rebindAll() {
    for (final entry in _handlers.entries) {
      _socket?.off(entry.key);
      for (final cb in entry.value) _socket?.on(entry.key, cb);
    }
  }

  /// Register event listener. Survives reconnects.
  void on(String event, void Function(dynamic) cb) {
    _handlers.putIfAbsent(event, () => []);
    if (!_handlers[event]!.contains(cb)) {
      _handlers[event]!.add(cb);
    }
    _socket?.on(event, cb);
  }

  /// Remove event listener.
  void off(String event, [void Function(dynamic)? cb]) {
    if (cb != null) {
      _handlers[event]?.remove(cb);
      _socket?.off(event, cb);
    } else {
      _handlers.remove(event);
      _socket?.off(event);
    }
  }

  void emit(String event, [dynamic data]) => _socket?.emit(event, data ?? {});

  // ════════════════════════════════════════════════════════
  // MESSAGING
  // ════════════════════════════════════════════════════════
  void joinConversation(String id)  => emit('join_conversation',  {'conversation_id': id});
  void leaveConversation(String id) => emit('leave_conversation', {'conversation_id': id});
  void startTyping(String id)       => emit('typing_start', {'conversation_id': id});
  void stopTyping(String id)        => emit('typing_stop',  {'conversation_id': id});
  void markRead(String id)          => emit('mark_read', {'conversation_id': id});

  void messageDelivered(String msgId, String senderId, String convId) =>
    emit('message_delivered', {'message_id': msgId, 'sender_id': senderId, 'conversation_id': convId});

  void reactToMessage(String msgId, String emoji, String convId) =>
    emit('message_reaction', {'message_id': msgId, 'emoji': emoji, 'conversation_id': convId});

  void starMessage(String msgId) => emit('star_message', {'message_id': msgId});

  void pinMessage(String msgId, String convId) =>
    emit('pin_message', {'message_id': msgId, 'conversation_id': convId});

  // ════════════════════════════════════════════════════════
  // WEBRTC CALLS
  // ════════════════════════════════════════════════════════
  void initiateCall({
    required String calleeId, required String callType, required dynamic offer,
  }) => emit('call_initiate', {'callee_id': calleeId, 'call_type': callType, 'offer': offer});

  void answerCall({required String callId, required String callerId, required dynamic answer}) =>
    emit('call_answer', {'call_id': callId, 'caller_id': callerId, 'answer': answer});

  void rejectCall({required String callId, required String callerId, String? reason}) =>
    emit('call_reject', {'call_id': callId, 'caller_id': callerId, 'reason': reason ?? 'declined'});

  void endCall({required String callId, required String otherUserId, int? duration}) =>
    emit('call_end', {'call_id': callId, 'other_user_id': otherUserId, 'duration': duration ?? 0});

  void busyCall({required String callerId, required String callId}) =>
    emit('call_busy', {'caller_id': callerId, 'call_id': callId});

  void sendIceCandidate({required String targetUserId, required dynamic candidate, required String callId}) =>
    emit('ice_candidate', {'target_user_id': targetUserId, 'candidate': candidate, 'call_id': callId});

  void toggleVideo(String callId, bool enabled, String otherUserId) =>
    emit('call_toggle_video', {'call_id': callId, 'enabled': enabled, 'other_user_id': otherUserId});

  void toggleAudio(String callId, bool enabled, String otherUserId) =>
    emit('call_toggle_audio', {'call_id': callId, 'enabled': enabled, 'other_user_id': otherUserId});

  void toggleScreenShare(String callId, bool enabled, String otherUserId) =>
    emit('call_screen_share', {'call_id': callId, 'enabled': enabled, 'other_user_id': otherUserId});

  // ════════════════════════════════════════════════════════
  // STORIES
  // ════════════════════════════════════════════════════════
  void viewStory(String storyId, String ownerId) =>
    emit('story_viewed', {'story_id': storyId, 'story_owner_id': ownerId});

  void reactToStory(String storyId, String ownerId, String emoji) =>
    emit('story_react', {'story_id': storyId, 'story_owner_id': ownerId, 'emoji': emoji});

  // ════════════════════════════════════════════════════════
  // LIVE
  // ════════════════════════════════════════════════════════
  void joinLive(String id)  => emit('join_live',  {'stream_id': id});
  void leaveLive(String id) => emit('leave_live', {'stream_id': id});

  void sendGift(String streamId, String giftType, {String? giftId}) =>
    emit('live_gift', {'stream_id': streamId, 'gift_type': giftType, if (giftId != null) 'gift_id': giftId});

  void sendLiveComment(String streamId, String content) =>
    emit('live_comment', {'stream_id': streamId, 'content': content});

  // ════════════════════════════════════════════════════════
  // POSTS / REELS
  // ════════════════════════════════════════════════════════
  void joinPost(String id)  => emit('join_post',  {'post_id': id});
  void leavePost(String id) => emit('leave_post', {'post_id': id});
  void joinReel(String id)  => emit('join_reel',  {'reel_id': id});
  void leaveReel(String id) => emit('leave_reel', {'reel_id': id});

  // ════════════════════════════════════════════════════════
  // QR
  // ════════════════════════════════════════════════════════
  void joinQRSession(String id) => emit('join_qr_session', {'session_id': id});

  // ════════════════════════════════════════════════════════
  // NOTIFICATIONS
  // ════════════════════════════════════════════════════════
  void readNotification(String id)  => emit('notification_read',     {'notification_id': id});
  void readAllNotifications()       => emit('notifications_read_all', {});

  // ════════════════════════════════════════════════════════
  // PRESENCE
  // ════════════════════════════════════════════════════════
  void updateStatus(String? text)   => emit('update_status', {'status_text': text});
  void setPresence(String presence) => emit('set_presence',  {'presence': presence});

  /// Check if a batch of users are online
  void requestOnlineStatus(List<String> userIds) =>
    emit('request_online_status', {'user_ids': userIds});

  // ════════════════════════════════════════════════════════
  // LIFECYCLE
  // ════════════════════════════════════════════════════════
  void disconnect() {
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _socket?.disconnect();
    _connected = false;
  }

  void dispose() {
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _handlers.clear();
    _socket?.dispose();
    _connected = false;
  }
}
