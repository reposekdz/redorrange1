import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'socket_service.dart';
import 'api_service.dart';

/// Pure WebSocket-based push service — no Firebase.
/// Uses flutter_local_notifications to show system notifications when a
/// socket event arrives while the app is in background.
class PushService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (kIsWeb) return; // Web uses browser Notification API
    if (_initialized) return;

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios     = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const linux   = LinuxInitializationSettings(defaultActionName: 'Open RedOrrange');

    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios, macOS: ios, linux: linux),
      onDidReceiveNotificationResponse: (details) {
        // payload = route to navigate, handled by app_overlay
        _pendingRoute = details.payload;
      },
    );

    // Request permissions
    if (!kIsWeb) {
      await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
      await _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()?.requestPermissions(alert: true, badge: true, sound: true);
    }

    _initialized = true;
  }

  static String? _pendingRoute;
  static String? get pendingRoute { final r = _pendingRoute; _pendingRoute = null; return r; }

  static Future<void> showMessageNotification({
    required String id,
    required String conversationId,
    required String senderName,
    required String? senderAvatar,
    required String content,
    String? convName,
  }) async {
    if (kIsWeb) { _showWebNotification('$senderName', content, '/chat/$conversationId'); return; }
    if (!_initialized) return;

    const android = AndroidNotificationDetails(
      'messages', 'Messages',
      channelDescription: 'Chat message notifications',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.message,
      color: Color(0xFFFF6B35),
      enableVibration: true,
      playSound: true,
      styleInformation: BigTextStyleInformation(''),
    );
    const ios = DarwinNotificationDetails(
      presentAlert: true, presentBadge: true, presentSound: true,
      threadIdentifier: 'messages',
    );

    await _plugin.show(
      conversationId.hashCode,
      senderName,
      content,
      const NotificationDetails(android: android, iOS: ios, macOS: ios),
      payload: '/chat/$conversationId',
    );
  }

  static Future<void> showCallNotification({
    required String callId,
    required String callerName,
    required String callType,
  }) async {
    if (kIsWeb) { _showWebNotification('Incoming call', '$callerName is calling', '/call/$callType'); return; }
    if (!_initialized) return;

    const android = AndroidNotificationDetails(
      'calls', 'Calls',
      channelDescription: 'Incoming call notifications',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.call,
      color: Color(0xFF4CAF50),
      fullScreenIntent: true,
      ongoing: true,
    );

    await _plugin.show(
      callId.hashCode,
      'Incoming ${callType == 'video' ? 'Video' : 'Audio'} Call',
      '$callerName is calling...',
      const NotificationDetails(android: android),
      payload: '/call/$callType',
    );
  }

  static Future<void> showGenericNotification({
    required String id,
    required String title,
    required String body,
    String? route,
  }) async {
    if (kIsWeb) { _showWebNotification(title, body, route); return; }
    if (!_initialized) return;

    const android = AndroidNotificationDetails(
      'general', 'General',
      channelDescription: 'General notifications',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      color: Color(0xFFFF6B35),
    );

    await _plugin.show(
      id.hashCode,
      title,
      body,
      const NotificationDetails(android: android, iOS: const DarwinNotificationDetails()),
      payload: route,
    );
  }

  static Future<void> cancel(int id) => _plugin.cancel(id);
  static Future<void> cancelAll() => _plugin.cancelAll();

  static void _showWebNotification(String title, String body, String? route) {
    // Web Notification API — shows browser notification
    // Handled via JS interop in web/index.html
  }

  /// Register socket listeners to show local notifications when app is backgrounded
  static void attachToSocket(SocketService socket) {
    socket.on('new_message', (d) {
      if (d is! Map) return;
      final msg    = d['message'] as Map?;
      if (msg == null) return;
      final convId = msg['conversation_id'] as String? ?? '';
      final sender = msg['display_name'] as String? ?? msg['username'] as String? ?? 'Someone';
      final content = msg['content'] as String? ?? '📷 Media';
      showMessageNotification(id: msg['id'] ?? '', conversationId: convId, senderName: sender, senderAvatar: msg['avatar_url'], content: content);
    });

    socket.on('incoming_call', (d) {
      if (d is! Map) return;
      final caller = d['caller'] as Map? ?? {};
      showCallNotification(callId: d['call_id'] as String? ?? '', callerName: caller['display_name'] as String? ?? 'Someone', callType: d['call_type'] as String? ?? 'audio');
    });

    socket.on('notification', (d) {
      if (d is! Map) return;
      final n = d['notification'] as Map? ?? d;
      final type = n['type'] as String? ?? '';
      if (['message', 'call'].contains(type)) return; // handled separately
      final title  = _notifTitle(type, n['actor_name'] as String?);
      final body   = n['message'] as String? ?? '';
      final target = n['target_type'] as String?;
      final tid    = n['target_id'] as String?;
      showGenericNotification(id: n['id'] as String? ?? '', title: title, body: body, route: target != null && tid != null ? '/$target/$tid' : null);
    });
  }

  static String _notifTitle(String type, String? actorName) {
    final name = actorName ?? 'Someone';
    switch (type) {
      case 'like':               return '$name liked your post';
      case 'comment':            return '$name commented';
      case 'follow':             return '$name followed you';
      case 'follow_request':     return '$name wants to follow you';
      case 'mention':            return '$name mentioned you';
      case 'gift':               return '$name sent you a gift! 🎁';
      case 'escrow_created':     return 'New purchase request';
      case 'escrow_funded':      return 'Payment received — ship now';
      case 'escrow_completed':   return 'Sale completed — payment released';
      case 'escrow_disputed':    return 'Dispute opened';
      case 'subscription_activated': return '⭐ Subscription activated!';
      case 'live':               return '$name is live';
      default:                   return 'New notification';
    }
  }
}
