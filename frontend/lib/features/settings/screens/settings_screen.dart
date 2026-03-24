import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/widgets/app_avatar.dart';

// Settings state loaded from API
final _settingsProv = FutureProvider.autoDispose<Map<String,dynamic>>((ref) async {
  final r = await ref.read(apiServiceProvider).get('/settings');
  return Map<String,dynamic>.from(r.data);
});

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user  = ref.watch(currentUserProvider);
    final theme = ref.watch(themeModeProvider);
    final dark  = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.w800))),
      body: ListView(children: [
        // ── Profile Card
        GestureDetector(
          onTap: () => context.push('/profile/${user?.id}'),
          child: Container(margin: const EdgeInsets.all(14), padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(gradient: LinearGradient(colors: [AppTheme.orange.withOpacity(0.9), AppTheme.orangeDark], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(18)),
            child: Row(children: [
              AppAvatar(url: user?.avatarUrl, size: 58, username: user?.username),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(user?.displayName ?? user?.username ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17, letterSpacing: -0.3), overflow: TextOverflow.ellipsis),
                Text('@${user?.username ?? ''}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                if (user?.statusText != null) Text(user!.statusText!, style: const TextStyle(color: Colors.white60, fontSize: 12), overflow: TextOverflow.ellipsis),
              ])),
              const Column(children: [Icon(Iconsax.arrow_right_3, color: Colors.white70, size: 20)]),
            ])),
        ),

        // ── Account
        _Section('ACCOUNT', [
          _Tile(Iconsax.user_edit, 'Edit Profile',        AppTheme.orange,            () => context.push('/edit-profile')),
          _Tile(Iconsax.chart_2,      'Analytics',           const Color(0xFF2196F3),    () => context.push('/analytics')),
          _Tile(Iconsax.bookmark,     'Saved Posts',         const Color(0xFF9C27B0),    () => context.push('/saved')),
          _Tile(Iconsax.clock,        'Activity Log',        const Color(0xFF607D8B),    () => context.push('/activity-log')),
          _Tile(Iconsax.star,         'Boosts',              const Color(0xFFFF9800),    () => context.push('/boosts')),
        ]),

        // ── Privacy & Security
        _Section('PRIVACY & SECURITY', [
          _Tile(Iconsax.lock,         'Privacy',             AppTheme.orange,            () => context.push('/privacy-settings')),
          _Tile(Iconsax.shield_tick,  'Security',            const Color(0xFF4CAF50),    () => context.push('/security')),
          _Tile(Iconsax.slash,        'Blocked Accounts',    const Color(0xFFE53935),    () => context.push('/blocked-users')),
          _Tile(Iconsax.people,       'Close Friends',       const Color(0xFF4CAF50),    () => context.push('/close-friends')),
          _Tile(Iconsax.user_add,     'Follow Requests',     const Color(0xFF2196F3),    () => context.push('/follow-requests')),
          _Tile(Iconsax.mobile,       'Linked Devices',      const Color(0xFF607D8B),    () => _showDevices(context, ref)),
        ]),

        // ── Notifications
        _Section('NOTIFICATIONS', [
          _Tile(Iconsax.notification, 'Push Notifications',  AppTheme.orange,            () => context.push('/notification-settings')),
          _Tile(Iconsax.tag_user,     'Mentions',            const Color(0xFF2196F3),    () => context.push('/mentions')),
        ]),

        // ── Appearance
        _Section('APPEARANCE', [
          ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            leading: Container(width: 40, height: 40, decoration: BoxDecoration(color: AppTheme.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: const Icon(Iconsax.brush, color: AppTheme.orange, size: 20)),
            title: const Text('Theme', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            trailing: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.light,  icon: Icon(Iconsax.sun_1, size: 15)),
                ButtonSegment(value: ThemeMode.system, icon: Icon(Iconsax.mobile, size: 15)),
                ButtonSegment(value: ThemeMode.dark,   icon: Icon(Iconsax.moon, size: 15)),
              ],
              selected: {theme}, onSelectionChanged: (s) => ref.read(themeModeProvider.notifier).set(s.first),
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
            )),
          _Tile(Iconsax.text,         'Appearance',          const Color(0xFF9C27B0),    () => context.push('/appearance')),
          _Tile(Iconsax.global,       'Language',            const Color(0xFF2196F3),    () => context.push('/app-language')),
        ]),

        // ── Messaging
        _Section('MESSAGING', [
          _Tile(Iconsax.star,         'Starred Messages',    AppTheme.orange,            () => context.push('/starred-messages')),
          _Tile(Iconsax.cpu_charge,   'Chat Backup',         const Color(0xFF4CAF50),    () {}),
          _Tile(Iconsax.refresh,      'Chat History',        const Color(0xFF607D8B),    () {}),
        ]),

        // ── Storage & Data
        _Section('STORAGE & DATA', [
          _Tile(Iconsax.archive,      'Storage Usage',       const Color(0xFF2196F3),    () => context.push('/storage')),
          _Tile(Iconsax.wifi,         'Auto-Download (Wi-Fi)', const Color(0xFF4CAF50), () {}),
          _Tile(Iconsax.chart,        'Data Usage',          const Color(0xFF607D8B),    () {}),
        ]),

        // ── Help & About
        _Section('SUPPORT', [
          _Tile(Iconsax.message_question, 'Help Center',     AppTheme.orange,            () {}),
          _Tile(Iconsax.message_text_1,   'Send Feedback',   const Color(0xFF2196F3),    () {}),
          _Tile(Iconsax.info_circle,      'About RedOrrange', const Color(0xFF607D8B),  () => context.push('/about')),
        ]),

        const SizedBox(height: 24),

        // Logout
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: SizedBox(width: double.infinity, child: OutlinedButton.icon(
          onPressed: () => _confirmLogout(context, ref),
          style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red), padding: const EdgeInsets.symmetric(vertical: 14)),
          icon: const Icon(Iconsax.logout, size: 18), label: const Text('Log Out', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        ))),

        const SizedBox(height: 16),
        Center(child: Text('RedOrrange v2.0.0 · Build 200', style: TextStyle(fontSize: 11, color: dark ? AppTheme.dSub : AppTheme.lSub))),
        const SizedBox(height: 32),
      ]),
    );
  }

  void _confirmLogout(BuildContext context, WidgetRef ref) {
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('Log Out'),
      content: const Text('Are you sure you want to log out of your account?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: () async { Navigator.pop(context); await ref.read(authControllerProvider).logout(); if (context.mounted) context.go('/auth/phone'); }, child: const Text('Log Out', style: TextStyle(color: Colors.red))),
      ],
    ));
  }

  void _showDevices(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (_) => _DevicesSheet(ref: ref));
  }
}

// Devices sheet
class _DevicesSheet extends StatefulWidget {
  final WidgetRef ref;
  const _DevicesSheet({required this.ref});
  @override State<_DevicesSheet> createState() => _DS();
}
class _DS extends State<_DevicesSheet> {
  List<dynamic> _devices = []; bool _l = true;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try { final r = await widget.ref.read(apiServiceProvider).get('/settings/devices'); setState(() { _devices = r.data['devices'] ?? []; _l = false; }); } catch (_) { setState(() => _l = false); }
  }
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(margin: const EdgeInsets.all(12), decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(20)), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 40, height: 4, margin: const EdgeInsets.only(top: 12, bottom: 8), decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
      const Padding(padding: EdgeInsets.all(14), child: Text('Linked Devices', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
      if (_l) const Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(color: AppTheme.orange))
      else if (_devices.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('No linked devices', style: TextStyle(color: Colors.grey)))
      else ..._devices.map((d) => ListTile(leading: Icon(d['platform'] == 'ios' ? Iconsax.mobile : d['platform'] == 'web' ? Iconsax.global : Iconsax.android, color: AppTheme.orange, size: 22), title: Text(d['device_name'] ?? 'Unknown Device', style: const TextStyle(fontWeight: FontWeight.w600)), subtitle: Text(d['ip_address'] ?? '', style: const TextStyle(fontSize: 12)), trailing: IconButton(icon: const Icon(Iconsax.logout, color: Colors.red, size: 20), onPressed: () async { await widget.ref.read(apiServiceProvider).delete('/settings/devices/${d['id']}'); _load(); }))),
      if (_devices.length > 1) Padding(padding: const EdgeInsets.all(14), child: OutlinedButton.icon(onPressed: () async { await widget.ref.read(apiServiceProvider).delete('/settings/devices'); _load(); }, style: OutlinedButton.styleFrom(foregroundColor: Colors.red), icon: const Icon(Iconsax.logout, size: 16), label: const Text('Log out all devices'))),
      const SizedBox(height: 16),
    ]));
  }
}

// Helpers
class _Section extends StatelessWidget {
  final String title; final List<Widget> tiles;
  const _Section(this.title, this.tiles);
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 20, 16, 8), child: Text(title, style: TextStyle(color: AppTheme.orange.withOpacity(0.85), fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 1.0))),
      Container(margin: const EdgeInsets.symmetric(horizontal: 12), decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: dark ? AppTheme.dDiv : AppTheme.lDiv, width: 0.5)), child: Column(children: [
        for (int i = 0; i < tiles.length; i++) ...[
          tiles[i],
          if (i < tiles.length - 1) Divider(height: 0.5, indent: 62, color: dark ? AppTheme.dDiv : AppTheme.lDiv),
        ],
      ])),
    ]);
  }
}

class _Tile extends StatelessWidget {
  final IconData icon; final String title; final Color iconColor; final VoidCallback onTap;
  const _Tile(this.icon, this.title, this.iconColor, this.onTap);
  @override
  Widget build(BuildContext _) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    leading: Container(width: 38, height: 38, decoration: BoxDecoration(color: iconColor.withOpacity(0.12), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: iconColor, size: 19)),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
    trailing: const Icon(Iconsax.arrow_right_3, size: 16, color: Colors.grey),
    onTap: onTap,
    dense: true,
  );
}
