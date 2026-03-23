
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_theme.dart';

class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});
  @override ConsumerState<NotificationSettingsScreen> createState() => _S();
}
class _S extends ConsumerState<NotificationSettingsScreen> {
  Map<String, bool> _prefs = {
    'messages': true, 'likes': true, 'comments': true, 'follows': true,
    'story_views': true, 'mentions': true, 'calls': true, 'events': true,
    'live': true, 'marketplace': false, 'channel_posts': true,
    'email_digest': false, 'push_enabled': true,
  };

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      for (final k in _prefs.keys) _prefs[k] = p.getBool('notif_$k') ?? _prefs[k]!;
    });
  }

  Future<void> _set(String key, bool val) async {
    setState(() => _prefs[key] = val);
    final p = await SharedPreferences.getInstance();
    await p.setBool('notif_$key', val);
  }

  @override
  Widget build(BuildContext ctx) {
    final dark = Theme.of(ctx).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications', style: TextStyle(fontWeight: FontWeight.w800))),
      body: ListView(children: [
        if (!(_prefs['push_enabled'] ?? true))
          Container(margin: const EdgeInsets.all(12), padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orange.withOpacity(0.3))),
            child: Row(children: [const Icon(Icons.notifications_off_rounded, color: Colors.orange), const SizedBox(width: 10), const Expanded(child: Text('Push notifications are disabled. Enable them to get alerts.', style: TextStyle(fontSize: 13)))])),

        _SwitchGroup('Push Notifications', [
          _Pref('push_enabled', Icons.notifications_rounded, 'Enable all notifications', 'Allow push notifications from RedOrrange'),
        ], _prefs, _set),

        _SwitchGroup('Messages & Calls', [
          _Pref('messages',  Icons.chat_bubble_rounded,   'New messages',       'When you receive a new message'),
          _Pref('calls',     Icons.call_rounded,           'Incoming calls',     'Audio and video calls'),
        ], _prefs, _set),

        _SwitchGroup('Activity', [
          _Pref('likes',       Icons.favorite_rounded,        'Likes',              'When someone likes your post or reel'),
          _Pref('comments',    Icons.chat_rounded,            'Comments',           'When someone comments on your content'),
          _Pref('mentions',    Icons.alternate_email_rounded, 'Mentions',           'When someone tags you'),
          _Pref('follows',     Icons.person_add_rounded,      'New followers',      'When someone follows you'),
          _Pref('story_views', Icons.auto_stories_rounded,    'Story views',        'When someone views your story'),
        ], _prefs, _set),

        _SwitchGroup('Events & Live', [
          _Pref('events', Icons.event_rounded,   'Events',      'Event reminders and invites'),
          _Pref('live',   Icons.live_tv_rounded, 'Live streams','When someone you follow goes live'),
        ], _prefs, _set),

        _SwitchGroup('Other', [
          _Pref('marketplace',   Icons.store_rounded,    'Marketplace',     'Messages from buyers/sellers'),
          _Pref('channel_posts', Icons.podcasts_rounded, 'Channel posts',   'New posts from channels you follow'),
          _Pref('email_digest',  Icons.email_rounded,    'Email digest',    'Weekly summary via email'),
        ], _prefs, _set),
      ]),
    );
  }
}

class _Pref { final String key, label, subtitle; final IconData icon; const _Pref(this.key, this.icon, this.label, this.subtitle); }

class _SwitchGroup extends StatelessWidget {
  final String title; final List<_Pref> items; final Map<String,bool> prefs; final Future<void> Function(String, bool) onSet;
  const _SwitchGroup(this.title, this.items, this.prefs, this.onSet);
  @override
  Widget build(BuildContext ctx) {
    final dark = Theme.of(ctx).brightness == Brightness.dark;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.fromLTRB(16,18,16,6), child: Text(title, style: const TextStyle(color: AppTheme.orange, fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 0.8))),
      Container(margin: const EdgeInsets.symmetric(horizontal: 12), decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(12)), child: Column(children: [
        for (int i = 0; i < items.length; i++) ...[
          ListTile(
            leading: Container(width: 36, height: 36, decoration: BoxDecoration(color: AppTheme.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Icon(items[i].icon, color: AppTheme.orange, size: 18)),
            title: Text(items[i].label, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
            subtitle: Text(items[i].subtitle, style: const TextStyle(fontSize: 12)),
            trailing: Switch.adaptive(value: prefs[items[i].key] ?? true, onChanged: (v) => onSet(items[i].key, v), activeColor: AppTheme.orange),
          ),
          if (i < items.length - 1) const Divider(height: 0.5, indent: 62),
        ],
      ])),
    ]);
  }
}
