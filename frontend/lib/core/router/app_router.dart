import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/screens/phone_screen.dart';
import '../../features/auth/screens/otp_screen.dart';
import '../../features/auth/screens/qr_screen.dart';
import '../../features/auth/screens/setup_screen.dart';
import '../../features/shell/main_shell.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/messages/screens/messages_screen.dart';
import '../../features/discover/screens/discover_screen.dart';
import '../../features/reels/screens/reels_screen.dart';
import '../../features/create/screens/create_screen.dart';
import '../../features/messages/screens/chat_screen.dart';
import '../../features/messages/screens/new_chat_screen.dart';
import '../../features/messages/screens/chat_info_screen.dart';
import '../../features/messages/screens/chat_media_screen.dart';
import '../../features/messages/screens/starred_messages_screen.dart';
import '../../features/feed/screens/post_detail_screen.dart';
import '../../features/feed/screens/post_likes_screen.dart';
import '../../features/feed/screens/report_screen.dart';
import '../../features/reels/screens/reel_detail_screen.dart';
import '../../features/stories/screens/story_viewer_screen.dart';
import '../../features/stories/screens/create_story_screen.dart';
import '../../features/stories/screens/highlights_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/profile/screens/edit_profile_screen.dart';
import '../../features/profile/screens/followers_screen.dart';
import '../../features/profile/screens/follow_requests_screen.dart';
import '../../features/profile/screens/close_friends_screen.dart';
import '../../features/profile/screens/mutual_followers_screen.dart';
import '../../features/profile/screens/activity_log_screen.dart';
import '../../features/wallet/screens/payment_webview_screen.dart';
import '../../features/wallet/screens/payouts_screen.dart';
import '../../features/ads/screens/ads_manager_screen.dart';
import '../../features/ads/screens/ads_topup_screen.dart';
import '../../features/ads/screens/create_campaign_screen.dart';
import '../../features/ads/screens/campaign_detail_screen.dart';
import '../../features/events/screens/events_screen.dart';
import '../../features/events/screens/event_detail_screen.dart';
import '../../features/events/screens/create_event_screen.dart';
import '../../features/events/screens/event_attendees_screen.dart';
import '../../features/calls/screens/call_screen.dart';
import '../../features/calls/screens/call_history_screen.dart';
import '../../features/search/screens/search_screen.dart';
import '../../features/search/screens/hashtag_screen.dart';
import '../../features/notifications/screens/notifications_screen.dart';
import '../../features/notifications/screens/mentions_screen.dart';
import '../../features/contacts/screens/contacts_screen.dart';
import '../../features/contacts/screens/add_contact_screen.dart';
import '../../features/media/screens/media_viewer_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../../features/settings/screens/security_screen.dart';
import '../../features/settings/screens/privacy_settings_screen.dart';
import '../../features/settings/screens/notification_settings_screen.dart';
import '../../features/settings/screens/blocked_users_screen.dart';
import '../../features/settings/screens/about_screen.dart';
import '../../features/settings/screens/storage_screen.dart';
import '../../features/settings/screens/app_language_screen.dart';
import '../../features/settings/screens/appearance_screen.dart';
import '../../features/marketplace/screens/marketplace_screen.dart';
import '../../features/marketplace/screens/marketplace_detail_screen.dart';
import '../../features/marketplace/screens/marketplace_orders_screen.dart';
import '../../features/marketplace/screens/marketplace_create_screen.dart';
import '../../features/channels/screens/channels_screen.dart';
import '../../features/channels/screens/channel_detail_screen.dart';
import '../../features/live/screens/live_screen.dart';
import '../../features/live/screens/live_viewer_screen.dart';
import '../../features/analytics/screens/analytics_screen.dart';
import '../../features/saved/screens/saved_screen.dart';
import '../../features/groups/screens/group_screen.dart';
import '../../features/groups/screens/group_create_screen.dart';
import '../../features/groups/screens/group_settings_screen.dart';
import '../../core/models/models.dart';
import '../providers/auth_provider.dart';



import '../../features/wallet/screens/wallet_screen.dart';
import '../../features/wallet/screens/payment_screen.dart';
import '../../features/wallet/screens/subscription_screen.dart';
import '../../features/wallet/screens/gift_screen.dart';
import '../../features/wallet/screens/escrow_screen.dart';
import '../../features/wallet/screens/subscription_screen.dart';
import '../../features/feed/screens/boost_post_screen.dart';
import '../../features/feed/screens/reactions_screen.dart';
import '../../features/analytics/screens/post_insights_screen.dart';
import '../../features/messages/screens/disappearing_messages_screen.dart';
import '../../features/messages/screens/schedule_message_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/auth/phone',
    redirect: (ctx, state) {
      final auth = ref.read(authStateProvider);
      final loggedIn = auth.when(data: (u) => u != null, loading: () => null, error: (_, __) => false);
      if (loggedIn == null) return null;
      final authPaths = ['/auth/phone', '/auth/otp', '/auth/qr', '/auth/setup'];
      final onAuth = authPaths.any((r) => state.matchedLocation.startsWith(r));
      if (!loggedIn && !onAuth) return '/auth/phone';
      if (loggedIn && onAuth) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/auth/phone', builder: (_, __) => const PhoneScreen()),
      GoRoute(path: '/auth/otp', builder: (_, s) {
        final e = s.extra as Map<String,dynamic>? ?? {};
        return OtpScreen(phone: e['phone'] as String? ?? '', cc: e['cc'] as String? ?? '+1');
      }),
      GoRoute(path: '/auth/qr',    builder: (_, __) => const QrScreen()),
      GoRoute(path: '/auth/setup', builder: (_, __) => const SetupScreen()),

      ShellRoute(
        builder: (_, __, child) => MainShell(child: child),
        routes: [
          GoRoute(path: '/',         builder: (_, __) => const HomeScreen()),
          GoRoute(path: '/messages', builder: (_, __) => const MessagesScreen()),
          GoRoute(path: '/discover', builder: (_, __) => const DiscoverScreen()),
          GoRoute(path: '/reels',    builder: (_, __) => const ReelsScreen()),
          GoRoute(path: '/create',   builder: (_, __) => const CreateScreen()),
        ],
      ),

      GoRoute(path: '/chat/:id',       builder: (_, s) => ChatScreen(convId: s.pathParameters['id']!, extra: s.extra as Map<String,dynamic>?)),
      GoRoute(path: '/new-chat',       builder: (_, __) => const NewChatScreen()),
      GoRoute(path: '/new-group',      builder: (_, __) => const GroupCreateScreen()),
      GoRoute(path: '/chat-info/:id',  builder: (_, s) => ChatInfoScreen(convId: s.pathParameters['id']!)),
      GoRoute(path: '/chat-media/:id', builder: (_, s) => ChatMediaScreen(convId: s.pathParameters['id']!, displayName: (s.extra as Map?)?.['name'] as String? ?? 'Chat')),
      GoRoute(path: '/starred-messages', builder: (_, __) => const StarredMessagesScreen()),

      GoRoute(path: '/post/:id',         builder: (_, s) => PostDetailScreen(postId: s.pathParameters['id']!)),
      GoRoute(path: '/post/:id/likes',   builder: (_, s) => PostLikesScreen(postId: s.pathParameters['id']!)),
      GoRoute(path: '/report/:type/:id', builder: (_, s) => ReportScreen(targetType: s.pathParameters['type']!, targetId: s.pathParameters['id']!)),

      GoRoute(path: '/reel/:id', builder: (_, s) => ReelDetailScreen(reelId: s.pathParameters['id']!)),

      GoRoute(path: '/story/:uid',       builder: (_, s) => StoryViewerScreen(userId: s.pathParameters['uid']!)),
      GoRoute(path: '/create-story',     builder: (_, __) => const CreateStoryScreen()),
      GoRoute(path: '/highlight/:id',    builder: (_, s) => HighlightViewerScreen(highlightId: s.pathParameters['id']!)),
      GoRoute(path: '/create-highlight', builder: (_, __) => const CreateHighlightScreen()),

      GoRoute(path: '/profile/:id',     builder: (_, s) => ProfileScreen(userId: s.pathParameters['id']!)),
      GoRoute(path: '/edit-profile',    builder: (_, __) => const EditProfileScreen()),
      GoRoute(path: '/followers/:id',   builder: (_, s) => FollowersScreen(userId: s.pathParameters['id']!, type: (s.extra as Map?)?.['type'] as String? ?? 'followers')),
      GoRoute(path: '/follow-requests', builder: (_, __) => const FollowRequestsScreen()),
      GoRoute(path: '/close-friends',   builder: (_, __) => const CloseFriendsScreen()),
      GoRoute(path: '/mutual/:id',      builder: (_, s) => MutualFollowersScreen(userId: s.pathParameters['id']!)),
      GoRoute(path: '/activity-log',    builder: (_, __) => const ActivityLogScreen()),

      GoRoute(path: '/events',              builder: (_, __) => const EventsScreen()),
      GoRoute(path: '/event/:id',           builder: (_, s) => EventDetailScreen(eventId: s.pathParameters['id']!)),
      GoRoute(path: '/event/:id/attendees', builder: (_, s) => EventAttendeesScreen(eventId: s.pathParameters['id']!)),
      GoRoute(path: '/create-event',        builder: (_, __) => const CreateEventScreen()),

      GoRoute(path: '/call/:type',    builder: (_, s) => CallScreen(callType: s.pathParameters['type']!, extra: (s.extra as Map<String,dynamic>?) ?? {})),
      GoRoute(path: '/calls-history', builder: (_, __) => const CallHistoryScreen()),

      GoRoute(path: '/search',       builder: (_, __) => const SearchScreen()),
      GoRoute(path: '/hashtag/:tag', builder: (_, s) => HashtagScreen(tag: s.pathParameters['tag']!)),
      GoRoute(path: '/ads',          builder: (_, __) => const AdsManagerScreen()),
      GoRoute(path: '/ads/topup',    builder: (_, __) => const AdsTopupScreen()),
      GoRoute(path: '/ads/campaign/:id', builder: (_, s) => CampaignDetailScreen(id: s.pathParameters['id']!)),
      GoRoute(path: '/notifications', builder: (_, __) => const NotificationsScreen()),
      GoRoute(path: '/mentions',      builder: (_, __) => const MentionsScreen()),

      GoRoute(path: '/contacts',    builder: (_, __) => const ContactsScreen()),
      GoRoute(path: '/add-contact', builder: (_, __) => const AddContactScreen()),

      GoRoute(path: '/media-viewer', builder: (_, s) {
        final e = s.extra as Map<String,dynamic>? ?? {};
        final rawMedia = e['media'] as List? ?? [];
        final idx = e['index'] as int? ?? 0;
        return MediaViewerScreen(
          media: rawMedia.map((m) => MediaItem.fromJson(Map<String,dynamic>.from(m as Map))).toList(),
          initialIndex: idx,
        );
      }),

      GoRoute(path: '/settings',              builder: (_, __) => const SettingsScreen()),
      GoRoute(path: '/security',              builder: (_, __) => const SecurityScreen()),
      GoRoute(path: '/privacy-settings',      builder: (_, __) => const PrivacySettingsScreen()),
      GoRoute(path: '/notification-settings', builder: (_, __) => const NotificationSettingsScreen()),
      GoRoute(path: '/blocked-users',         builder: (_, __) => const BlockedUsersScreen()),
      GoRoute(path: '/about',                 builder: (_, __) => const AboutScreen()),
      GoRoute(path: '/storage',               builder: (_, __) => const StorageScreen()),
      GoRoute(path: '/app-language',          builder: (_, __) => const AppLanguageScreen()),
      GoRoute(path: '/appearance',            builder: (_, __) => const AppearanceScreen()),

      GoRoute(path: '/marketplace',             builder: (_, __) => const MarketplaceScreen()),
      GoRoute(path: '/marketplace/create',      builder: (_, __) => const MarketplaceCreateScreen()),
      GoRoute(path: '/marketplace/my-listings', builder: (_, __) => const MyListingsScreen()),
      GoRoute(path: '/marketplace/:id',         builder: (_, s) => MarketplaceDetailScreen(itemId: s.pathParameters['id']!)),

      GoRoute(path: '/channels',        builder: (_, __) => const ChannelsScreen()),
      GoRoute(path: '/channels/create', builder: (_, __) => const ChannelCreateScreen()),
      GoRoute(path: '/channels/:id',    builder: (_, s) => ChannelDetailScreen(channelId: s.pathParameters['id']!)),

      GoRoute(path: '/live',     builder: (_, __) => const LiveScreen()),
      GoRoute(path: '/live/:id', builder: (_, s) => LiveViewerScreen(streamId: s.pathParameters['id']!, data: s.extra as Map<String,dynamic>?)),

      GoRoute(path: '/analytics', builder: (_, __) => const AnalyticsScreen()),
      GoRoute(path: '/saved',     builder: (_, __) => const SavedScreen()),

      GoRoute(path: '/group/:id',          builder: (_, s) => GroupScreen(groupId: s.pathParameters['id']!)),
      GoRoute(path: '/group/:id/settings', builder: (_, s) => GroupSettingsScreen(groupId: s.pathParameters['id']!)),
    ],


      GoRoute(path: '/wallet',       builder: (_, __) => const WalletScreen()),
      GoRoute(path: '/marketplace/orders', builder: (_, __) => const MarketplaceOrdersScreen()),
      GoRoute(path: '/payment',      builder: (_, s) {
        final e = s.extra as Map<String,dynamic>;
        return PaymentScreen(
          targetType: e['targetType'] as PaymentTarget,
          targetId:   e['targetId']   as String,
          priceUsd:   e['priceUsd']   as double,
          title:      e['title']      as String,
          subtitle:   e['subtitle']   as String?,
          coins:      e['coins']      as int?,
          bonusCoins: e['bonusCoins'] as int?,
        );
      }),
      GoRoute(path: '/gifts',        builder: (_, __) => const Scaffold(body: Center(child: Text('Gift Shop')))),
      GoRoute(path: '/escrow',       builder: (_, __) => const EscrowScreen()),
      GoRoute(path: '/escrow/:id',   builder: (_, s) => EscrowScreen()),
      GoRoute(path: '/subscription', builder: (_, __) => const SubscriptionScreen()),
      GoRoute(path: '/payouts',      builder: (_, __) => const Scaffold(body: Center(child: Text('Payouts')))),
      GoRoute(path: '/post/:id/boost',    builder: (_, s) => BoostPostScreen(postId: s.pathParameters['id']!, postCaption: (s.extra as Map?)?.['caption'] as String? ?? '')),
      GoRoute(path: '/post/:id/insights', builder: (_, s) => PostInsightsScreen(postId: s.pathParameters['id']!)),
      GoRoute(path: '/post/:id/reactions',builder: (_, s) => ReactionsScreen(postId: s.pathParameters['id']!)),
      GoRoute(path: '/chat/:id/disappearing', builder: (_, s) => DisappearingMessagesScreen(convId: s.pathParameters['id']!)),
      GoRoute(path: '/chat/:id/schedule', builder: (_, s) => ScheduleMessageScreen(convId: s.pathParameters['id']!)),

    errorBuilder: (_, state) => Scaffold(
      appBar: AppBar(),
      body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.error_outline_rounded, size: 56, color: Colors.grey),
        const SizedBox(height: 12),
        Text('Page not found\n${state.uri}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
      ])),
    ),
  );
});
