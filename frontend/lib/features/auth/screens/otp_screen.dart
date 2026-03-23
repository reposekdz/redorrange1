import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pinput/pinput.dart';
import 'dart:async';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/auth_provider.dart';

class OtpScreen extends ConsumerStatefulWidget {
  final String phone, cc;
  const OtpScreen({super.key, required this.phone, required this.cc});
  @override ConsumerState<OtpScreen> createState() => _S();
}
class _S extends ConsumerState<OtpScreen> {
  final _ctrl = TextEditingController();
  bool _l = false; String? _e; int _sec = 60; Timer? _t;
  bool _canResend = false;
  @override void initState() { super.initState(); _startTimer(); }
  @override void dispose() { _ctrl.dispose(); _t?.cancel(); super.dispose(); }
  void _startTimer() { _t?.cancel(); setState(() { _sec = 60; _canResend = false; }); _t = Timer.periodic(const Duration(seconds: 1), (t) { if (!mounted) { t.cancel(); return; } setState(() => _sec--); if (_sec == 0) { t.cancel(); setState(() => _canResend = true); } }); }
  Future<void> _verify(String code) async {
    if (code.length != 6) return;
    setState(() { _l = true; _e = null; });
    try {
      final r = await ref.read(authControllerProvider).verifyOtp(widget.phone, widget.cc, code);
      if (!mounted) return;
      if (r['success'] == true) {
        if (r['is_new_user'] == true || r['user']?['needs_setup'] == true) context.go('/auth/setup');
        else context.go('/');
      } else { setState(() { _e = r['message'] ?? 'Incorrect code. Try again.'; }); _ctrl.clear(); }
    } catch (e) { setState(() => _e = 'Verification failed. Check your connection.'); }
    finally { if (mounted) setState(() => _l = false); }
  }
  Future<void> _resend() async {
    if (!_canResend) return;
    try {
      await ref.read(authControllerProvider).sendOtp(widget.phone, widget.cc);
      _startTimer();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('New code sent!')));
    } catch (_) {}
  }
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final pinTheme = PinTheme(width: 56, height: 62,
      textStyle: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: dark ? AppTheme.dText : AppTheme.lText),
      decoration: BoxDecoration(color: dark ? AppTheme.dInput : AppTheme.lInput, borderRadius: BorderRadius.circular(14)));
    return Scaffold(
      appBar: AppBar(leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => context.pop())),
      body: SafeArea(child: Padding(padding: const EdgeInsets.all(28), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 16),
        const Text('Verify your number', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 28, letterSpacing: -0.5)),
        const SizedBox(height: 10),
        RichText(text: TextSpan(style: TextStyle(color: dark ? AppTheme.dSub : AppTheme.lSub, fontSize: 15, height: 1.5), children: [
          const TextSpan(text: "We sent a 6-digit code to\n"),
          TextSpan(text: '${widget.cc} ${widget.phone}', style: const TextStyle(color: AppTheme.orange, fontWeight: FontWeight.w700)),
        ])),
        const SizedBox(height: 36),
        Center(child: Pinput(length: 6, controller: _ctrl, autofocus: true,
          defaultPinTheme: pinTheme,
          focusedPinTheme: pinTheme.copyWith(decoration: pinTheme.decoration?.copyWith(border: Border.all(color: AppTheme.orange, width: 2))),
          errorPinTheme: pinTheme.copyWith(decoration: pinTheme.decoration?.copyWith(border: Border.all(color: Colors.red, width: 2))),
          onCompleted: _verify)),
        if (_e != null) Padding(padding: const EdgeInsets.only(top: 16), child: Center(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.error_outline_rounded, color: Colors.red, size: 16), const SizedBox(width: 6), Flexible(child: Text(_e!, style: const TextStyle(color: Colors.red, fontSize: 14), textAlign: TextAlign.center))]))),
        if (_l) const Padding(padding: EdgeInsets.only(top: 24), child: Center(child: CircularProgressIndicator(color: AppTheme.orange))),
        const SizedBox(height: 28),
        Center(child: _canResend
          ? GestureDetector(onTap: _resend, child: const Text('Resend Code', style: TextStyle(color: AppTheme.orange, fontWeight: FontWeight.w700, fontSize: 15)))
          : RichText(text: TextSpan(style: TextStyle(color: dark ? AppTheme.dSub : AppTheme.lSub, fontSize: 14), children: [
              const TextSpan(text: 'Resend code in '),
              TextSpan(text: '${_sec}s', style: const TextStyle(color: AppTheme.orange, fontWeight: FontWeight.w700)),
            ]))),
        const SizedBox(height: 16),
        Center(child: GestureDetector(onTap: () => context.pop(), child: Text('Wrong number? Change it', style: TextStyle(color: dark ? AppTheme.dSub : AppTheme.lSub, fontSize: 13)))),
      ]))),
    );
  }
}
