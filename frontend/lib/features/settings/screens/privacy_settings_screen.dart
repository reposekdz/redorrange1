
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/api_service.dart';

class PrivacySettingsScreen extends ConsumerStatefulWidget {
  const PrivacySettingsScreen({super.key});
  @override ConsumerState<PrivacySettingsScreen> createState() => _S();
}
class _S extends ConsumerState<PrivacySettingsScreen> {
  bool _privateAccount = false, _readReceipts = true, _onlineStatus = true, _lastSeen = true;
  String _whoCanMessage = 'everyone', _whoCanCallMe = 'everyone', _whoCanSeeStories = 'everyone';
  bool _saving = false;

  @override void initState() { super.initState(); final u = ref.read(currentUserProvider); _privateAccount = u?.isPrivate ?? false; }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(apiServiceProvider).put('/users/privacy', data: {
        'is_private': _privateAccount, 'read_receipts': _readReceipts,
        'online_status': _onlineStatus, 'last_seen': _lastSeen,
        'who_can_message': _whoCanMessage, 'who_can_call': _whoCanCallMe,
        'who_can_see_stories': _whoCanSeeStories,
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Privacy settings saved')));
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'))); }
    finally { if (mounted) setState(() => _saving = false); }
  }

  @override
  Widget build(BuildContext ctx) {
    final dark = Theme.of(ctx).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [TextButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving...' : 'Save', style: const TextStyle(color: AppTheme.orange, fontWeight: FontWeight.w700, fontSize: 15)))]),
      body: ListView(children: [
        _Section('Account'),
        _SwitchCard(Icons.lock_outline_rounded, 'Private Account', 'Only approved followers see your posts and stories', _privateAccount, (v) => setState(() => _privateAccount = v)),

        _Section('Messages & Calls'),
        _DropCard(Icons.message_rounded,  'Who can message me', _whoCanMessage, (v) => setState(() => _whoCanMessage = v!)),
        _DropCard(Icons.call_rounded,     'Who can call me',    _whoCanCallMe,  (v) => setState(() => _whoCanCallMe = v!)),

        _Section('Stories'),
        _DropCard(Icons.auto_stories_rounded, 'Who can see my stories', _whoCanSeeStories, (v) => setState(() => _whoCanSeeStories = v!)),
        _NavCard(Icons.group_rounded, 'Close Friends', 'Choose who sees close friends content', () => ctx.push('/close-friends')),

        _Section('Activity'),
        _SwitchCard(Icons.done_all_rounded, 'Read Receipts', 'Show when you have read messages', _readReceipts, (v) => setState(() => _readReceipts = v)),
        _SwitchCard(Icons.circle_outlined, 'Online Status', 'Show when you are online', _onlineStatus, (v) => setState(() => _onlineStatus = v)),
        _SwitchCard(Icons.access_time_rounded, 'Last Seen', 'Show when you were last active', _lastSeen, (v) => setState(() => _lastSeen = v)),

        _Section('Connections'),
        _NavCard(Icons.person_add_outlined, 'Follow Requests', 'Manage who wants to follow you', () => ctx.push('/follow-requests')),
        _NavCard(Icons.block_rounded, 'Blocked Accounts', 'Manage blocked users', () => ctx.push('/blocked-users')),

        const SizedBox(height: 30),
      ]),
    );
  }

  Widget _Section(String t) => Padding(padding: const EdgeInsets.fromLTRB(16,20,16,8), child: Text(t, style: const TextStyle(color: AppTheme.orange, fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 0.8)));

  Widget _SwitchCard(IconData icon, String title, String sub, bool val, void Function(bool) onChange) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3), decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(12)),
      child: ListTile(leading: Container(width: 36, height: 36, decoration: BoxDecoration(color: AppTheme.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: AppTheme.orange, size: 18)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)), subtitle: Text(sub, style: const TextStyle(fontSize: 12)),
        trailing: Switch.adaptive(value: val, onChanged: onChange, activeColor: AppTheme.orange)));
  }

  Widget _DropCard(IconData icon, String title, String val, void Function(String?) onChange) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3), decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(12)),
      child: ListTile(leading: Container(width: 36, height: 36, decoration: BoxDecoration(color: AppTheme.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: AppTheme.orange, size: 18)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
        trailing: DropdownButton<String>(value: val, onChanged: onChange, underline: const SizedBox(),
          items: ['everyone','followers','close_friends','nobody'].map((v) => DropdownMenuItem(value: v, child: Text(v == 'close_friends' ? 'Close Friends' : v[0].toUpperCase() + v.substring(1), style: const TextStyle(fontSize: 13)))).toList())));
  }

  Widget _NavCard(IconData icon, String title, String sub, VoidCallback onTap) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3), decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(12)),
      child: ListTile(leading: Container(width: 36, height: 36, decoration: BoxDecoration(color: AppTheme.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: AppTheme.orange, size: 18)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)), subtitle: Text(sub, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey), onTap: onTap));
  }
}
