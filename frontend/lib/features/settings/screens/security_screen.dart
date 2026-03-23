import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/api_service.dart';
import '../../../core/providers/auth_provider.dart';

final _secProv = FutureProvider.autoDispose<Map<String,dynamic>>((ref) async {
  final r = await ref.read(apiServiceProvider).get('/settings');
  return Map<String,dynamic>.from(r.data);
});

class SecurityScreen extends ConsumerStatefulWidget {
  const SecurityScreen({super.key});
  @override ConsumerState<SecurityScreen> createState() => _S();
}
class _S extends ConsumerState<SecurityScreen> {
  bool _twoFA = false, _biometric = false, _loginAlerts = true;
  bool _saving = false;
  List<dynamic> _devices = [];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final r = await ref.read(apiServiceProvider).get('/settings');
      final s = r.data['settings'] ?? {};
      final devR = await ref.read(apiServiceProvider).get('/auth/devices').catchError((_) => Future.value(null));
      if (mounted) setState(() {
        _twoFA      = s['two_factor_enabled'] == 1 || s['two_factor_enabled'] == true;
        _biometric  = s['biometric_enabled']  == 1 || s['biometric_enabled'] == true;
        _loginAlerts = s['login_alerts'] != 0;
        if (devR != null) _devices = devR.data['devices'] ?? [];
      });
    } catch (_) {}
  }

  Future<void> _save(String key, dynamic val) async {
    setState(() => _saving = true);
    try {
      await ref.read(apiServiceProvider).put('/settings', data: {key: val});
    } catch (_) {} finally { if (mounted) setState(() => _saving = false); }
  }

  Future<void> _changePassword() async {
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confCtrl = TextEditingController();
    bool obscOld = true, obscNew = true;
    await showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (_) => StatefulBuilder(builder: (ctx, setSt) => Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom + 16, left: 20, right: 20, top: 20),
      decoration: BoxDecoration(color: Theme.of(ctx).brightness == Brightness.dark ? AppTheme.dCard : Colors.white, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Change Password', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        const SizedBox(height: 16),
        TextField(controller: oldCtrl, obscureText: obscOld, decoration: InputDecoration(labelText: 'Current Password', suffixIcon: IconButton(icon: Icon(obscOld ? Icons.visibility_rounded : Icons.visibility_off_rounded), onPressed: () => setSt(() => obscOld = !obscOld)))),
        const SizedBox(height: 10),
        TextField(controller: newCtrl, obscureText: obscNew, decoration: InputDecoration(labelText: 'New Password', helperText: 'Min 8 chars, include a number', suffixIcon: IconButton(icon: Icon(obscNew ? Icons.visibility_rounded : Icons.visibility_off_rounded), onPressed: () => setSt(() => obscNew = !obscNew)))),
        const SizedBox(height: 10),
        TextField(controller: confCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Confirm New Password')),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () async {
          if (newCtrl.text != confCtrl.text) { ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Passwords do not match'))); return; }
          if (newCtrl.text.length < 8) { ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Password too short'))); return; }
          try {
            await ref.read(apiServiceProvider).put('/auth/change-password', data: {'old_password': oldCtrl.text, 'new_password': newCtrl.text});
            if (ctx.mounted) { Navigator.pop(ctx); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Password changed!'))); }
          } catch (e) { if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Error: $e'))); }
        }, child: const Text('Update Password'))),
      ]),
    )));
  }

  Future<void> _revokeDevice(dynamic device) async {
    final confirmed = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Remove Device'),
      content: Text('Remove "${device['device_info'] ?? 'Unknown device'}" from your account?'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove', style: TextStyle(color: Colors.red)))],
    ));
    if (confirmed != true) return;
    try {
      await ref.read(apiServiceProvider).delete('/auth/devices/${device['id']}');
      setState(() => _devices.remove(device));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('Security', style: TextStyle(fontWeight: FontWeight.w800))),
      body: ListView(children: [
        _Group('Authentication', dark),

        _SwitchTile(Icons.verified_user_rounded, 'Two-Factor Authentication', 'Add extra security to your account', _twoFA, (v) { setState(() => _twoFA = v); _save('two_factor_enabled', v); }),
        if (_twoFA) Container(margin: const EdgeInsets.fromLTRB(16, 0, 16, 8), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: AppTheme.orangeSurf, borderRadius: BorderRadius.circular(10)), child: const Row(children: [Icon(Icons.info_rounded, color: AppTheme.orange, size: 16), SizedBox(width: 8), Expanded(child: Text('2FA is enabled. A code will be required each time you log in.', style: TextStyle(fontSize: 12, color: AppTheme.orangeDark)))])),

        _SwitchTile(Icons.fingerprint_rounded, 'Biometric Login', 'Use fingerprint or face to log in', _biometric, (v) { setState(() => _biometric = v); _save('biometric_enabled', v); }),
        _SwitchTile(Icons.notifications_active_rounded, 'Login Alerts', 'Get notified of new sign-ins', _loginAlerts, (v) { setState(() => _loginAlerts = v); _save('login_alerts', v); }),

        _Group('Password', dark),
        _NavTile(Icons.lock_rounded, 'Change Password', 'Update your account password', _changePassword),
        _NavTile(Icons.link_rounded, 'Linked Accounts', 'Manage connected services', () {}),

        _Group('Active Sessions', dark),

        if (_devices.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(12)), child: Row(children: [const Icon(Icons.devices_rounded, color: Colors.grey, size: 20), const SizedBox(width: 10), Text('Loading active sessions...', style: TextStyle(color: dark ? AppTheme.dSub : AppTheme.lSub, fontSize: 13))])))
        else
          ...(_devices.take(5).map((d) => _DeviceTile(device: d, dark: dark, onRevoke: () => _revokeDevice(d)))),

        _Group('Account Security', dark),
        _NavTile(Icons.shield_rounded, 'Security Checkup', 'Review your account security', () {}),
        _NavTile(Icons.history_rounded, 'Login History', 'View recent login activity', () => context.push('/activity-log')),
        _NavTile(Icons.download_rounded, 'Download My Data', 'Export all your data', () async {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Data export requested. You\'ll receive an email.')));
          await ref.read(apiServiceProvider).post('/users/export-data').catchError((_){});
        }),
        _NavTile(Icons.delete_forever_rounded, 'Delete Account', 'Permanently delete your account', () => _showDeleteConfirm(), color: Colors.red),
        const SizedBox(height: 30),
      ]),
    );
  }

  void _showDeleteConfirm() {
    final confirm = TextEditingController();
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('Delete Account', style: TextStyle(color: Colors.red)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('This action is permanent and cannot be undone.\nAll your data will be deleted.\n\nType "DELETE" to confirm:'),
        const SizedBox(height: 12),
        TextField(controller: confirm, decoration: const InputDecoration(hintText: 'Type DELETE here')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: () async {
          if (confirm.text != 'DELETE') return;
          Navigator.pop(context);
          await ref.read(apiServiceProvider).delete('/users/account');
          await ref.read(authControllerProvider).logout();
          if (mounted) context.go('/auth/phone');
        }, child: const Text('Delete', style: TextStyle(color: Colors.red))),
      ],
    ));
  }

  Widget _Group(String t, bool dark) => Padding(padding: const EdgeInsets.fromLTRB(16, 20, 16, 8), child: Text(t, style: const TextStyle(color: AppTheme.orange, fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 0.8)));

  Widget _SwitchTile(IconData icon, String title, String sub, bool val, void Function(bool) onChange) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3), decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Container(width: 38, height: 38, decoration: BoxDecoration(color: AppTheme.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(9)), child: Icon(icon, color: AppTheme.orange, size: 20)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(sub, style: const TextStyle(fontSize: 12)),
        trailing: Switch.adaptive(value: val, onChanged: onChange, activeColor: AppTheme.orange),
      ));
  }

  Widget _NavTile(IconData icon, String title, String sub, VoidCallback onTap, {Color? color}) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3), decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Container(width: 38, height: 38, decoration: BoxDecoration(color: (color ?? AppTheme.orange).withOpacity(0.1), borderRadius: BorderRadius.circular(9)), child: Icon(icon, color: color ?? AppTheme.orange, size: 20)),
        title: Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: color)),
        subtitle: Text(sub, style: const TextStyle(fontSize: 12)),
        trailing: Icon(Icons.chevron_right_rounded, color: color ?? Colors.grey, size: 20),
        onTap: onTap,
      ));
  }
}

class _DeviceTile extends StatelessWidget {
  final dynamic device; final bool dark; final VoidCallback onRevoke;
  const _DeviceTile({required this.device, required this.dark, required this.onRevoke});

  IconData get _icon {
    final info = (device['device_info'] ?? '').toLowerCase();
    if (info.contains('iphone') || info.contains('ios')) return Icons.phone_iphone_rounded;
    if (info.contains('android')) return Icons.phone_android_rounded;
    if (info.contains('mac') || info.contains('ipad')) return Icons.laptop_mac_rounded;
    if (info.contains('windows') || info.contains('linux')) return Icons.computer_rounded;
    return Icons.devices_rounded;
  }

  @override
  Widget build(BuildContext _) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
    decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(12)),
    child: ListTile(
      leading: Container(width: 38, height: 38, decoration: BoxDecoration(color: AppTheme.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(9)), child: Icon(_icon, color: AppTheme.orange, size: 20)),
      title: Text(device['device_info'] ?? 'Unknown Device', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (device['ip_address'] != null) Text(device['ip_address'], style: const TextStyle(fontSize: 11)),
        if (device['last_used'] != null) Text('Last active ${_ago(device['last_used'])}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
        if (device['is_current'] == true) const Text('Current device', style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.w600)),
      ]),
      trailing: device['is_current'] != true ? TextButton(onPressed: onRevoke, child: const Text('Remove', style: TextStyle(color: Colors.red, fontSize: 12))) : const Icon(Icons.check_circle_rounded, color: Colors.green, size: 20),
    ),
  );

  static String _ago(String ts) {
    try { return _fmt(DateTime.now().difference(DateTime.parse(ts))); } catch (_) { return ts; }
  }
  static String _fmt(Duration d) {
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes}m ago';
    if (d.inDays < 1) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}
