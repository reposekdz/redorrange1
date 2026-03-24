import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:country_code_picker/country_code_picker.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/auth_provider.dart';

class PhoneScreen extends ConsumerStatefulWidget {
  const PhoneScreen({super.key});
  @override
  ConsumerState<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends ConsumerState<PhoneScreen>
    with TickerProviderStateMixin {
  final _phoneCtrl = TextEditingController();
  final _phoneFocus = FocusNode();
  String _cc = '+1';
  bool _loading = false;
  String? _error;

  late final AnimationController _pulseCtrl;
  late final AnimationController _floatCtrl;
  late final AnimationController _rotateCtrl;
  late final Animation<double> _pulse;
  late final Animation<double> _float;
  late final Animation<double> _rotate;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _floatCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 3))
      ..repeat(reverse: true);
    _rotateCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 8))
      ..repeat();
    _pulse  = Tween<double>(begin: 0.92, end: 1.08).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _float  = Tween<double>(begin: -10.0, end: 10.0).animate(CurvedAnimation(parent: _floatCtrl, curve: Curves.easeInOut));
    _rotate = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _rotateCtrl, curve: Curves.linear));
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _phoneFocus.dispose();
    _pulseCtrl.dispose();
    _floatCtrl.dispose();
    _rotateCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final raw = _phoneCtrl.text.trim().replaceAll(RegExp(r'\D'), '');
    if (raw.length < 6) {
      setState(() => _error = 'Enter a valid phone number (at least 6 digits)');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final r = await ref.read(authControllerProvider).sendOtp(raw, _cc);
      if (!mounted) return;
      if (r['success'] == true) {
        context.push('/auth/otp', extra: {
          'phone':    raw,
          'cc':       _cc,
          'is_new':   r['is_new_user'] == true,
          'dev_code': r['dev_code'],
        });
      } else {
        setState(() => _error = r['message'] ?? 'Failed to send code. Try again.');
      }
    } catch (_) {
      setState(() => _error = 'Network error. Check your connection.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: dark ? AppTheme.dBg : const Color(0xFFF6F2EE),
        body: wide ? _buildWide(context, dark) : _buildMobile(context, dark),
      ),
    );
  }

  Widget _buildWide(BuildContext context, bool dark) {
    return Row(children: [
      Expanded(flex: 55, child: _LeftPanel(pulse: _pulse, float: _float, rotate: _rotate)),
      Expanded(
        flex: 45,
        child: Container(
          color: dark ? AppTheme.dBg : Colors.white,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 48),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: _FormContent(
                  dark: dark, phoneCtrl: _phoneCtrl, phoneFocus: _phoneFocus,
                  cc: _cc, loading: _loading, error: _error,
                  onCcChanged: (c) => setState(() => _cc = c.dialCode ?? '+1'),
                  onSend: _send, compact: false,
                ),
              ),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _buildMobile(BuildContext context, bool dark) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.35,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFF7043), AppTheme.orange, Color(0xFFE64A19)],
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft:  Radius.circular(40),
                  bottomRight: Radius.circular(40),
                ),
              ),
              child: _MobileHero(pulse: _pulse, float: _float),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
            child: _FormContent(
              dark: dark, phoneCtrl: _phoneCtrl, phoneFocus: _phoneFocus,
              cc: _cc, loading: _loading, error: _error,
              onCcChanged: (c) => setState(() => _cc = c.dialCode ?? '+1'),
              onSend: _send, compact: true,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────
// LEFT PANEL  (desktop)
// ─────────────────────────────────────────────────
class _LeftPanel extends StatelessWidget {
  final Animation<double> pulse, float, rotate;
  const _LeftPanel({required this.pulse, required this.float, required this.rotate});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF7043), AppTheme.orange, Color(0xFFBF360C)],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
      child: SafeArea(
        child: Stack(
          children: [
            // Background decorative blobs
            Positioned(top: -80, right: -80,
              child: AnimatedBuilder(
                animation: rotate,
                builder: (_, child) => Transform.rotate(angle: rotate.value * 6.28, child: child),
                child: Container(width: 260, height: 260,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    shape: BoxShape.circle,
                  )),
              )),
            Positioned(bottom: 40, left: -60,
              child: Container(width: 200, height: 200,
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), shape: BoxShape.circle))),
            Positioned(top: 180, left: 60,
              child: Container(width: 100, height: 100,
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.07), shape: BoxShape.circle))),

            // Main content
            Padding(
              padding: const EdgeInsets.all(52),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Animated logo
                  AnimatedBuilder(
                    animation: pulse,
                    builder: (_, child) => Transform.scale(scale: pulse.value, child: child),
                    child: Container(
                      width: 88, height: 88,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: Colors.white.withOpacity(0.3), width: 2),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 24, offset: const Offset(0, 8)),
                        ],
                      ),
                      child: const Center(child: Text('🔴', style: TextStyle(fontSize: 44))),
                    ),
                  ).animate().fadeIn(delay: 100.ms).slideY(begin: -0.3),

                  const SizedBox(height: 44),

                  const Text('Welcome to', style: TextStyle(color: Colors.white70, fontSize: 18, letterSpacing: 0.4),
                  ).animate().fadeIn(delay: 300.ms).slideX(begin: -0.3),
                  const SizedBox(height: 4),
                  const Text('RedOrrange',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900,
                        fontSize: 52, letterSpacing: -2, height: 1),
                  ).animate().fadeIn(delay: 400.ms).slideX(begin: -0.3),

                  const SizedBox(height: 22),
                  const Text(
                    'Your world — connected.\nChat, share, and discover.',
                    style: TextStyle(color: Colors.white70, fontSize: 17, height: 1.65),
                  ).animate().fadeIn(delay: 500.ms).slideX(begin: -0.3),

                  const SizedBox(height: 52),

                  // Feature list
                  ..._kFeatures.asMap().entries.map((e) =>
                    _FeatureRow(icon: e.value.$1, label: e.value.$2)
                      .animate().fadeIn(delay: Duration(milliseconds: 600 + e.key * 120))
                      .slideX(begin: -0.3)),

                  const SizedBox(height: 52),

                  // Floating feature cards
                  AnimatedBuilder(
                    animation: float,
                    builder: (_, child) => Transform.translate(offset: Offset(0, float.value), child: child),
                    child: Wrap(spacing: 12, runSpacing: 12, children: [
                      _FeatureChip(icon: Icons.chat_bubble_rounded,  label: 'Messaging'),
                      _FeatureChip(icon: Icons.auto_awesome_rounded,  label: 'Stories'),
                      _FeatureChip(icon: Icons.videocam_rounded,      label: 'Reels'),
                      _FeatureChip(icon: Icons.shopping_bag_rounded,  label: 'Market'),
                    ]),
                  ).animate().fadeIn(delay: 1100.ms),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const _kFeatures = [
    (Icons.lock_rounded,              'End-to-end encrypted messages'),
    (Icons.video_camera_back_rounded,  'Stories, Reels & Live video'),
    (Icons.groups_rounded,             'Communities & group events'),
    (Icons.store_rounded,              'Built-in marketplace'),
  ];
}

// ─────────────────────────────────────────────────
// MOBILE HERO (top panel on small screens)
// ─────────────────────────────────────────────────
class _MobileHero extends StatelessWidget {
  final Animation<double> pulse, float;
  const _MobileHero({required this.pulse, required this.float});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 20, 28, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(children: [
              AnimatedBuilder(
                animation: pulse,
                builder: (_, child) => Transform.scale(scale: pulse.value, child: child),
                child: Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white.withOpacity(0.3)),
                  ),
                  child: const Center(child: Text('🔴', style: TextStyle(fontSize: 28))),
                ),
              ),
              const SizedBox(width: 16),
              const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Welcome to', style: TextStyle(color: Colors.white70, fontSize: 14)),
                Text('RedOrrange', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 26, letterSpacing: -0.5)),
              ]),
            ]).animate().fadeIn(delay: 100.ms).slideY(begin: -0.2),

            const SizedBox(height: 18),

            AnimatedBuilder(
              animation: float,
              builder: (_, child) => Transform.translate(offset: Offset(0, float.value * 0.5), child: child),
              child: const Text('Connect, share, and discover\nwith people around the world.',
                style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.55)),
            ).animate().fadeIn(delay: 300.ms),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────
// FORM CONTENT  (shared between wide & mobile)
// ─────────────────────────────────────────────────
class _FormContent extends StatelessWidget {
  final bool dark, compact;
  final TextEditingController phoneCtrl;
  final FocusNode phoneFocus;
  final String cc;
  final bool loading;
  final String? error;
  final ValueChanged<CountryCode> onCcChanged;
  final VoidCallback onSend;

  const _FormContent({
    required this.dark, required this.compact,
    required this.phoneCtrl, required this.phoneFocus,
    required this.cc, required this.loading, required this.error,
    required this.onCcChanged, required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!compact) ...[
          Text('Get Started',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 34,
                color: dark ? Colors.white : AppTheme.lText, letterSpacing: -1),
          ).animate().fadeIn(delay: 200.ms).slideY(begin: -0.2),
          const SizedBox(height: 8),
          Text('Enter your phone number to continue',
            style: TextStyle(fontSize: 15, color: dark ? AppTheme.dSub : AppTheme.lSub),
          ).animate().fadeIn(delay: 350.ms),
          const SizedBox(height: 40),
        ] else
          const SizedBox(height: 4),

        Text('Phone Number',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13,
              color: dark ? AppTheme.dText : AppTheme.lText),
        ).animate().fadeIn(delay: compact ? 100.ms : 450.ms),
        const SizedBox(height: 8),

        _PhoneRow(
          dark: dark, phoneCtrl: phoneCtrl, phoneFocus: phoneFocus,
          cc: cc, hasError: error != null,
          onCcChanged: onCcChanged, onSubmit: onSend,
        ).animate().fadeIn(delay: compact ? 150.ms : 500.ms).slideY(begin: 0.1),

        // Error message
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: error != null
            ? Container(
                key: const ValueKey('err'),
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(children: [
                  Icon(Icons.error_outline_rounded, color: Colors.red.shade600, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(error!,
                    style: TextStyle(color: Colors.red.shade700, fontSize: 13))),
                ]),
              )
            : const SizedBox.shrink(key: ValueKey('no-err')),
        ),

        const SizedBox(height: 20),

        // Continue button
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: loading ? null : onSend,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.orange,
              disabledBackgroundColor: AppTheme.orange.withOpacity(0.6),
              elevation: loading ? 0 : 4,
              shadowColor: AppTheme.orange.withOpacity(0.35),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: loading
              ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)),
                  SizedBox(width: 14),
                  Text('Sending code...', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                ])
              : const Text('Continue →', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16, letterSpacing: 0.3)),
          ),
        ).animate().fadeIn(delay: compact ? 200.ms : 600.ms),

        const SizedBox(height: 22),

        Row(children: [
          Expanded(child: Divider(color: dark ? AppTheme.dDiv : Colors.grey.shade200)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('or sign in with', style: TextStyle(color: dark ? AppTheme.dSub : Colors.grey.shade500, fontSize: 12)),
          ),
          Expanded(child: Divider(color: dark ? AppTheme.dDiv : Colors.grey.shade200)),
        ]),

        const SizedBox(height: 18),

        // QR code login button
        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton(
            onPressed: () => context.push('/auth/qr'),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: dark ? AppTheme.dDiv : Colors.grey.shade300, width: 1.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: 30, height: 30,
                decoration: BoxDecoration(
                  color: AppTheme.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.qr_code_scanner_rounded, color: AppTheme.orange, size: 18),
              ),
              const SizedBox(width: 12),
              Text('Log in with QR Code',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14,
                    color: dark ? AppTheme.dText : AppTheme.lText)),
            ]),
          ),
        ).animate().fadeIn(delay: compact ? 300.ms : 700.ms),

        const SizedBox(height: 28),

        Center(
          child: Text(
            'By continuing, you agree to our Terms of Service\nand Privacy Policy.',
            textAlign: TextAlign.center,
            style: TextStyle(color: dark ? AppTheme.dSub : Colors.grey.shade500,
                fontSize: 12, height: 1.6),
          ),
        ).animate().fadeIn(delay: compact ? 400.ms : 800.ms),
      ],
    );
  }
}

// ─────────────────────────────────────────────────
// PHONE ROW — always dark-themed country picker
// ─────────────────────────────────────────────────
class _PhoneRow extends StatelessWidget {
  final bool dark, hasError;
  final TextEditingController phoneCtrl;
  final FocusNode phoneFocus;
  final String cc;
  final ValueChanged<CountryCode> onCcChanged;
  final VoidCallback onSubmit;

  const _PhoneRow({
    required this.dark, required this.hasError,
    required this.phoneCtrl, required this.phoneFocus,
    required this.cc, required this.onCcChanged, required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasError ? Colors.red : (dark ? const Color(0xFF2E2E2E) : Colors.grey.shade200),
          width: hasError ? 1.5 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: hasError
                ? Colors.red.withOpacity(0.08)
                : (dark ? Colors.black.withOpacity(0.3) : Colors.black.withOpacity(0.05)),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          // ── Country code picker (ALWAYS uses dark theme to avoid white washout)
          Theme(
            data: ThemeData.dark().copyWith(
              primaryColor: AppTheme.orange,
              colorScheme: const ColorScheme.dark(primary: AppTheme.orange, secondary: AppTheme.orange),
              scaffoldBackgroundColor: const Color(0xFF141414),
              cardColor: const Color(0xFF1E1E1E),
              dialogBackgroundColor: const Color(0xFF141414),
              appBarTheme: const AppBarTheme(
                backgroundColor: Color(0xFF1A1A1A),
                foregroundColor: Colors.white,
                elevation: 0,
              ),
              listTileTheme: const ListTileThemeData(textColor: Colors.white, iconColor: Colors.white70),
              inputDecorationTheme: const InputDecorationTheme(
                filled: true,
                fillColor: Color(0xFF242424),
                hintStyle: TextStyle(color: Colors.white38),
                prefixIconColor: Colors.white54,
                border: OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.all(Radius.circular(12))),
              ),
            ),
            child: CountryCodePicker(
              onChanged: onCcChanged,
              initialSelection: 'US',
              favorite: const ['RW', 'KE', 'TZ', 'UG', 'US', 'GB', 'NG', 'ZA', 'FR', 'IN'],
              showFlag: true,
              showCountryOnly: false,
              showOnlyCountryWhenClosed: false,
              alignLeft: false,
              textStyle: TextStyle(
                color: dark ? Colors.white : AppTheme.lText,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
              dialogBackgroundColor: const Color(0xFF141414),
              searchStyle: const TextStyle(color: Colors.white),
              dialogTextStyle: const TextStyle(color: Colors.white),
              flagDecoration: BoxDecoration(borderRadius: BorderRadius.circular(4)),
              searchDecoration: const InputDecoration(
                labelText: 'Search country...',
                labelStyle: TextStyle(color: Colors.white54),
                prefixIcon: Icon(Icons.search_rounded, color: Colors.white38, size: 20),
                filled: true,
                fillColor: Color(0xFF242424),
                border: OutlineInputBorder(borderSide: BorderSide.none),
              ),
            ),
          ),

          Container(width: 1, height: 34, color: dark ? const Color(0xFF2E2E2E) : Colors.grey.shade200),

          // ── Phone number input
          Expanded(
            child: TextField(
              controller: phoneCtrl,
              focusNode: phoneFocus,
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d\s\-\(\)\+]'))],
              style: TextStyle(
                color: dark ? Colors.white : AppTheme.lText,
                fontSize: 17,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.8,
              ),
              decoration: InputDecoration(
                hintText: '700 000 000',
                hintStyle: TextStyle(
                  color: dark ? Colors.white24 : Colors.grey.shade400,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0,
                ),
                border: InputBorder.none,
                filled: false,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => onSubmit(),
            ),
          ),

          // Clear icon
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: phoneCtrl,
            builder: (_, v, __) => v.text.isEmpty
              ? const SizedBox.shrink()
              : GestureDetector(
                  onTap: () { phoneCtrl.clear(); phoneFocus.requestFocus(); },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Icon(Icons.close_rounded, size: 18,
                      color: dark ? Colors.white30 : Colors.grey.shade400),
                  ),
                ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────
// SMALL HELPERS
// ─────────────────────────────────────────────────
class _FeatureRow extends StatelessWidget {
  final IconData icon; final String label;
  const _FeatureRow({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(children: [
      Container(
        width: 38, height: 38,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(icon, color: Colors.white, size: 19),
      ),
      const SizedBox(width: 14),
      Text(label, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
    ]),
  );
}

class _FeatureChip extends StatelessWidget {
  final IconData icon; final String label;
  const _FeatureChip({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.12),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white.withOpacity(0.18)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: Colors.white, size: 16),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
    ]),
  );
}
