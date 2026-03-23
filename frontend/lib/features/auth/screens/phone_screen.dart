// phone_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:country_code_picker/country_code_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/auth_provider.dart';

class PhoneScreen extends ConsumerStatefulWidget {
  const PhoneScreen({super.key});
  @override ConsumerState<PhoneScreen> createState() => _S();
}
class _S extends ConsumerState<PhoneScreen> {
  final _ctrl = TextEditingController(); String _cc = '+1'; bool _l = false; String? _e;
  @override void dispose() { _ctrl.dispose(); super.dispose(); }
  Future<void> _send() async {
    final p = _ctrl.text.trim().replaceAll(RegExp(r'\D'), '');
    if (p.length < 7) { setState(() => _e = 'Enter a valid phone number'); return; }
    setState(() { _l = true; _e = null; });
    try {
      final r = await ref.read(authControllerProvider).sendOtp(p, _cc);
      if (!mounted) return;
      if (r['success'] == true) {
        context.push('/auth/otp', extra: {'phone': p, 'cc': _cc, 'is_new': r['is_new_user'] == true});
      } else {
        setState(() => _e = r['message'] ?? 'Failed to send code');
      }
    } catch (e) { setState(() => _e = 'Network error. Check connection.'); }
    finally { if (mounted) setState(() => _l = false); }
  }
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(28), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 40),
      Container(width: 76, height: 76, decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppTheme.orange, AppTheme.orangeDark]), borderRadius: BorderRadius.circular(22)), child: const Icon(Icons.circle, color: Colors.white, size: 40)),
      const SizedBox(height: 28),
      Text('Welcome to', style: TextStyle(color: dark ? AppTheme.dSub : AppTheme.lSub, fontSize: 16)),
      const Text('RedOrrange', style: TextStyle(color: AppTheme.orange, fontWeight: FontWeight.w900, fontSize: 34, letterSpacing: -1)),
      const SizedBox(height: 8),
      Text('Connect with the world. Enter your\nphone number to get started.', style: TextStyle(color: dark ? AppTheme.dSub : AppTheme.lSub, fontSize: 14, height: 1.5)),
      const SizedBox(height: 36),
      Text('Phone Number', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: dark ? AppTheme.dText : AppTheme.lText)),
      const SizedBox(height: 8),
      Container(decoration: BoxDecoration(color: dark ? AppTheme.dInput : AppTheme.lInput, borderRadius: BorderRadius.circular(14), border: _e != null ? Border.all(color: Colors.red, width: 1) : null), child: Row(children: [
        CountryCodePicker(onChanged: (c) => setState(() => _cc = c.dialCode ?? '+1'), initialSelection: 'US', favorite: const ['+250', '+254', '+255', '+1', '+44', '+33'], showFlag: true, showCountryOnly: false, alignLeft: false, textStyle: TextStyle(color: dark ? AppTheme.dText : AppTheme.lText, fontWeight: FontWeight.w700, fontSize: 15)),
        Container(width: 1, height: 30, color: dark ? AppTheme.dDiv : AppTheme.lDiv),
        Expanded(child: TextField(controller: _ctrl, keyboardType: TextInputType.phone, style: TextStyle(color: dark ? AppTheme.dText : AppTheme.lText, fontSize: 16, fontWeight: FontWeight.w500),
          decoration: const InputDecoration(hintText: '700 000 000', border: InputBorder.none, filled: false, contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16)),
          onSubmitted: (_) => _send())),
      ])),
      if (_e != null) Padding(padding: const EdgeInsets.only(top: 8), child: Row(children: [const Icon(Icons.error_outline_rounded, color: Colors.red, size: 14), const SizedBox(width: 4), Text(_e!, style: const TextStyle(color: Colors.red, fontSize: 13))])),
      const SizedBox(height: 20),
      SizedBox(width: double.infinity, child: ElevatedButton(
        onPressed: _l ? null : _send,
        style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
        child: _l ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)), SizedBox(width: 10), Text('Sending code...', style: TextStyle(fontWeight: FontWeight.w600))])
          : const Text('Send Verification Code', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      )),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: Divider(color: dark ? AppTheme.dDiv : AppTheme.lDiv)),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: Text('or', style: TextStyle(color: dark ? AppTheme.dSub : AppTheme.lSub))),
        Expanded(child: Divider(color: dark ? AppTheme.dDiv : AppTheme.lDiv)),
      ]),
      const SizedBox(height: 16),
      SizedBox(width: double.infinity, child: OutlinedButton.icon(
        onPressed: () => context.push('/auth/qr'),
        icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
        label: const Text('Log in with QR Code', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
      )),
      const SizedBox(height: 32),
      Center(child: Text('By continuing, you agree to our Terms & Privacy Policy', textAlign: TextAlign.center, style: TextStyle(color: dark ? AppTheme.dSub : AppTheme.lSub, fontSize: 12))),
    ]))));
  }
}
