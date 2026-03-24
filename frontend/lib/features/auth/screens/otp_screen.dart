import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pinput/pinput.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:async';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/auth_provider.dart';

class OtpScreen extends ConsumerStatefulWidget {
  final String phone, cc;
  final bool isNew;
  final String? devCode;

  const OtpScreen({
    super.key,
    required this.phone,
    required this.cc,
    this.isNew = false,
    this.devCode,
  });

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen>
    with SingleTickerProviderStateMixin {
  final _ctrl      = TextEditingController();
  final _focusNode = FocusNode();

  bool    _loading    = false;
  bool    _canResend  = false;
  bool    _success    = false;
  String? _error;
  int     _secs       = 60;
  Timer?  _timer;
  int     _attempts   = 0;

  late final AnimationController _shakeCtrl;
  late final Animation<double>   _shake;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _shake = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeCtrl, curve: Curves.elasticOut));
    _startTimer();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focusNode.dispose();
    _timer?.cancel();
    _shakeCtrl.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() { _secs = 60; _canResend = false; });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _secs--);
      if (_secs <= 0) { t.cancel(); setState(() => _canResend = true); }
    });
  }

  Future<void> _verify(String code) async {
    if (code.length != 6) return;
    _focusNode.unfocus();
    setState(() { _loading = true; _error = null; });
    try {
      final r = await ref.read(authControllerProvider).verifyOtp(widget.phone, widget.cc, code);
      if (!mounted) return;
      if (r['success'] == true) {
        setState(() => _success = true);
        HapticFeedback.heavyImpact();
        await Future.delayed(const Duration(milliseconds: 900));
        if (!mounted) return;
        final needsSetup = r['is_new_user'] == true || r['user']?['needs_setup'] == true;
        if (needsSetup) {
          context.go('/auth/setup');
        } else {
          context.go('/');
        }
      } else {
        _attempts++;
        setState(() => _error = r['message'] ?? 'Incorrect code. Try again.');
        _ctrl.clear();
        _focusNode.requestFocus();
        HapticFeedback.mediumImpact();
        _shakeCtrl.forward(from: 0);
      }
    } catch (_) {
      setState(() => _error = 'Verification failed. Check your connection.');
      _shakeCtrl.forward(from: 0);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    if (!_canResend || _loading) return;
    setState(() { _loading = true; _error = null; _ctrl.clear(); _attempts = 0; });
    try {
      final r = await ref.read(authControllerProvider).sendOtp(widget.phone, widget.cc);
      if (!mounted) return;
      if (r['success'] == true) {
        _startTimer();
        _focusNode.requestFocus();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(children: [
              Icon(Icons.check_circle_outline_rounded, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text('New code sent!'),
            ]),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      } else {
        setState(() => _error = r['message'] ?? 'Failed to resend.');
      }
    } catch (_) {
      setState(() => _error = 'Could not resend. Try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final wide = kIsWeb || MediaQuery.sizeOf(context).width >= 600;

    final basePinTheme = PinTheme(
      width: 54, height: 60,
      textStyle: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w800,
        color: dark ? Colors.white : AppTheme.lText,
      ),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1E1E1E) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: dark ? const Color(0xFF2E2E2E) : Colors.grey.shade200),
      ),
    );

    final focusedTheme = basePinTheme.copyWith(
      decoration: basePinTheme.decoration?.copyWith(
        border: Border.all(color: AppTheme.orange, width: 2),
        color: dark ? const Color(0xFF1E1E1E) : Colors.white,
        boxShadow: [BoxShadow(color: AppTheme.orange.withOpacity(0.15), blurRadius: 8)],
      ),
    );

    final errorTheme = basePinTheme.copyWith(
      decoration: basePinTheme.decoration?.copyWith(
        border: Border.all(color: Colors.red, width: 2),
        color: Colors.red.shade50,
      ),
    );

    final successTheme = basePinTheme.copyWith(
      decoration: basePinTheme.decoration?.copyWith(
        border: Border.all(color: Colors.green.shade400, width: 2),
        color: Colors.green.shade50,
      ),
      textStyle: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.green),
    );

    final formBody = Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: wide ? 440 : double.infinity),
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: wide ? 48 : 28, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),

                // Icon
                Container(
                  width: 72, height: 72,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [AppTheme.orange, Color(0xFFE64A19)]),
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [BoxShadow(color: AppTheme.orange.withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 6))],
                  ),
                  child: const Icon(Icons.sms_rounded, color: Colors.white, size: 34),
                ).animate().fadeIn().scale(begin: const Offset(0.7, 0.7)),

                const SizedBox(height: 28),

                Text('Check your messages',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 28,
                      color: dark ? Colors.white : AppTheme.lText, letterSpacing: -0.5),
                ).animate().fadeIn(delay: 100.ms).slideX(begin: -0.2),

                const SizedBox(height: 12),

                RichText(text: TextSpan(
                  style: TextStyle(fontSize: 15, height: 1.6,
                      color: dark ? AppTheme.dSub : AppTheme.lSub),
                  children: [
                    const TextSpan(text: "We sent a 6-digit code to\n"),
                    TextSpan(
                      text: '${widget.cc} ${_formatPhone(widget.phone)}',
                      style: const TextStyle(color: AppTheme.orange, fontWeight: FontWeight.w700),
                    ),
                  ],
                )).animate().fadeIn(delay: 200.ms),

                // Dev hint (only in debug/dev mode)
                if (widget.devCode != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Row(children: [
                      const Icon(Icons.bug_report_rounded, color: Colors.amber, size: 16),
                      const SizedBox(width: 8),
                      Text('Dev code: ${widget.devCode}',
                        style: TextStyle(color: Colors.amber.shade800, fontSize: 13, fontWeight: FontWeight.w600)),
                    ]),
                  ).animate().fadeIn(delay: 300.ms),
                ],

                const SizedBox(height: 44),

                // PIN input
                Center(
                  child: AnimatedBuilder(
                    animation: _shake,
                    builder: (_, child) => Transform.translate(
                      offset: Offset((_error != null && !_success)
                          ? 12 * (0.5 - (_shake.value % 1).abs()) * 2 : 0, 0),
                      child: child,
                    ),
                    child: Pinput(
                      length: 6,
                      controller: _ctrl,
                      focusNode: _focusNode,
                      autofocus: true,
                      hapticFeedbackType: HapticFeedbackType.lightImpact,
                      animationCurve: Curves.easeInOut,
                      animationDuration: const Duration(milliseconds: 150),
                      defaultPinTheme: basePinTheme,
                      focusedPinTheme: focusedTheme,
                      errorPinTheme: errorTheme,
                      submittedPinTheme: _success ? successTheme : basePinTheme.copyWith(
                        decoration: basePinTheme.decoration?.copyWith(
                          border: Border.all(color: AppTheme.orange.withOpacity(0.5)),
                          color: AppTheme.orange.withOpacity(0.06),
                        ),
                      ),
                      onCompleted: _verify,
                      closeKeyboardWhenCompleted: true,
                    ),
                  ),
                ).animate().fadeIn(delay: 300.ms),

                const SizedBox(height: 28),

                // Status / error
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _success
                    ? _StatusCard(
                        key: const ValueKey('ok'),
                        icon: Icons.check_circle_rounded,
                        color: Colors.green.shade600,
                        bg: Colors.green.shade50,
                        text: 'Verified! Logging you in...',
                      )
                    : _loading
                      ? Center(
                          key: const ValueKey('loading'),
                          child: Column(children: [
                            const CircularProgressIndicator(color: AppTheme.orange, strokeWidth: 2.5),
                            const SizedBox(height: 10),
                            Text('Verifying...', style: TextStyle(color: dark ? AppTheme.dSub : AppTheme.lSub, fontSize: 13)),
                          ]),
                        )
                      : _error != null
                        ? _StatusCard(
                            key: const ValueKey('err'),
                            icon: Icons.error_outline_rounded,
                            color: Colors.red.shade600,
                            bg: Colors.red.shade50,
                            text: _error!,
                            trailing: _attempts >= 3 ? 'Try resending the code' : null,
                          )
                        : const SizedBox.shrink(key: ValueKey('none')),
                ),

                const SizedBox(height: 36),

                // Resend section
                Center(
                  child: _canResend
                    ? Column(children: [
                        Text("Didn't receive the code?",
                          style: TextStyle(color: dark ? AppTheme.dSub : AppTheme.lSub, fontSize: 14)),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: _loading ? null : _resend,
                          child: const Text('Resend Code',
                            style: TextStyle(color: AppTheme.orange, fontWeight: FontWeight.w700, fontSize: 15)),
                        ),
                      ])
                    : Column(children: [
                        Text("Resend code in",
                          style: TextStyle(color: dark ? AppTheme.dSub : AppTheme.lSub, fontSize: 13)),
                        const SizedBox(height: 6),
                        _CountdownRing(secs: _secs, total: 60),
                      ]),
                ).animate().fadeIn(delay: 500.ms),

                const SizedBox(height: 24),

                // Wrong number
                Center(
                  child: TextButton(
                    onPressed: () => context.pop(),
                    child: Text('Wrong number? Go back',
                      style: TextStyle(
                        color: dark ? AppTheme.dSub : Colors.grey.shade500,
                        fontSize: 13,
                        decoration: TextDecoration.underline,
                      )),
                  ),
                ).animate().fadeIn(delay: 600.ms),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
    );

    if (wide) {
      return Scaffold(
        backgroundColor: dark ? AppTheme.dBg : const Color(0xFFF6F2EE),
        body: Row(children: [
          // ── LEFT: OTP info panel
          Expanded(
            flex: 45,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppTheme.orange, Color(0xFFE64A19), Color(0xFFBF360C)],
                  stops: [0.0, 0.5, 1.0],
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(44),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 80, height: 80,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.white.withOpacity(0.3), width: 2),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 24, offset: const Offset(0, 8))],
                        ),
                        child: const Center(child: Icon(Icons.sms_rounded, color: Colors.white, size: 40)),
                      ).animate().fadeIn().scale(begin: const Offset(0.7, 0.7)),

                      const SizedBox(height: 36),

                      const Text('One step away!',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 38,
                            letterSpacing: -1.2, height: 1.1),
                      ).animate().fadeIn(delay: 200.ms).slideX(begin: -0.3),

                      const SizedBox(height: 16),

                      const Text(
                        'We sent a verification code to your phone. Enter it to confirm your identity and get started.',
                        style: TextStyle(color: Colors.white70, fontSize: 16, height: 1.65),
                      ).animate().fadeIn(delay: 350.ms),

                      const SizedBox(height: 40),

                      _OtpInfoRow(icon: Icons.lock_rounded, text: 'Your code expires in 10 minutes')
                        .animate().fadeIn(delay: 500.ms).slideX(begin: -0.2),
                      const SizedBox(height: 16),
                      _OtpInfoRow(icon: Icons.refresh_rounded, text: 'Didn\'t receive it? Request a new code after 60 seconds')
                        .animate().fadeIn(delay: 620.ms).slideX(begin: -0.2),
                      const SizedBox(height: 16),
                      _OtpInfoRow(icon: Icons.verified_user_rounded, text: 'Never share your code with anyone')
                        .animate().fadeIn(delay: 740.ms).slideX(begin: -0.2),

                      const SizedBox(height: 40),

                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withOpacity(0.2)),
                        ),
                        child: Row(children: [
                          const Icon(Icons.info_outline_rounded, color: Colors.white70, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text.rich(TextSpan(
                              style: const TextStyle(color: Colors.white70, fontSize: 13.5, height: 1.5),
                              children: [
                                const TextSpan(text: 'Sending code to '),
                                TextSpan(text: '${widget.cc} ${_formatPhone(widget.phone)}',
                                  style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
                              ],
                            )),
                          ),
                        ]),
                      ).animate().fadeIn(delay: 900.ms),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Divider
          Container(width: 1, color: dark ? AppTheme.dDiv : const Color(0xFFE8E8E8)),

          // ── RIGHT: OTP form
          Expanded(
            flex: 55,
            child: Container(
              color: dark ? AppTheme.dBg : Colors.white,
              child: Column(children: [
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(children: [
                      IconButton(
                        icon: Icon(Icons.arrow_back_rounded,
                            color: dark ? Colors.white : AppTheme.lText),
                        onPressed: () => context.pop(),
                      ),
                      Text('Verify Phone',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16,
                            color: dark ? Colors.white : AppTheme.lText)),
                    ]),
                  ),
                ),
                Expanded(child: formBody),
              ]),
            ),
          ),
        ]),
      );
    }

    return Scaffold(
      backgroundColor: dark ? AppTheme.dBg : const Color(0xFFF6F2EE),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: dark ? Colors.white : AppTheme.lText),
          onPressed: () => context.pop(),
        ),
        title: Text('Verify Phone', style: TextStyle(fontWeight: FontWeight.w700,
            color: dark ? Colors.white : AppTheme.lText, fontSize: 16)),
      ),
      body: formBody,
    );
  }

  String _formatPhone(String p) {
    if (p.length <= 4) return p;
    final visible = p.substring(p.length - 4);
    return '••• ••• $visible';
  }
}

// ─────────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  final IconData icon;
  final Color color, bg;
  final String text;
  final String? trailing;

  const _StatusCard({
    super.key,
    required this.icon, required this.color, required this.bg, required this.text,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: bg, borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13))),
      ]),
      if (trailing != null) Padding(
        padding: const EdgeInsets.only(top: 4, left: 26),
        child: Text(trailing!, style: TextStyle(color: color.withOpacity(0.8), fontSize: 12)),
      ),
    ]),
  );
}

class _CountdownRing extends StatelessWidget {
  final int secs, total;
  const _CountdownRing({required this.secs, required this.total});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 64, height: 64,
    child: Stack(alignment: Alignment.center, children: [
      CircularProgressIndicator(
        value: secs / total,
        strokeWidth: 3,
        backgroundColor: Colors.grey.shade200,
        valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.orange),
      ),
      Text('${secs}s', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.orange)),
    ]),
  );
}

class _OtpInfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _OtpInfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 32, height: 32,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(icon, color: Colors.white, size: 17),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Text(text,
          style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5)),
      ),
    ],
  );
}
