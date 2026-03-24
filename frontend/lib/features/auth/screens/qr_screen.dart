import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/socket_service.dart';

class QrScreen extends ConsumerStatefulWidget {
  const QrScreen({super.key});
  @override
  ConsumerState<QrScreen> createState() => _QrScreenState();
}

class _QrScreenState extends ConsumerState<QrScreen>
    with TickerProviderStateMixin {
  // ── Mode: show QR (desktop login) vs scan QR (approve someone else)
  bool _showMode = true;

  // ── Show-QR state
  Uint8List? _qrBytes;
  String? _sessionId;
  DateTime? _expires;
  String _qrStatus = 'loading'; // loading | pending | scanned | confirmed | expired | error
  Timer? _pollTimer;
  Timer? _expireTimer;

  // ── Scan state
  late MobileScannerController _scanCtrl;
  bool _scanProcessing = false;
  bool _scanDone = false;
  String? _scanError;

  // ── Shared animations
  late final AnimationController _pulseCtrl;
  late final AnimationController _glowCtrl;
  late final AnimationController _rotateCtrl;
  late final AnimationController _floatCtrl;
  late final Animation<double> _pulseAnim;
  late final Animation<double> _glowAnim;
  late final Animation<double> _rotateAnim;
  late final Animation<double> _floatAnim;

  @override
  void initState() {
    super.initState();
    _scanCtrl = MobileScannerController(
        detectionSpeed: DetectionSpeed.normal, facing: CameraFacing.back);
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _glowCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);
    _rotateCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 10))
          ..repeat();
    _floatCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 3))
          ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.96, end: 1.04)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _glowAnim = Tween<double>(begin: 0.3, end: 0.9)
        .animate(CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut));
    _rotateAnim = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _rotateCtrl, curve: Curves.linear));
    _floatAnim = Tween<double>(begin: -8.0, end: 8.0)
        .animate(CurvedAnimation(parent: _floatCtrl, curve: Curves.easeInOut));
    _generateQR();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _expireTimer?.cancel();
    _scanCtrl.dispose();
    _pulseCtrl.dispose();
    _glowCtrl.dispose();
    _rotateCtrl.dispose();
    _floatCtrl.dispose();
    _teardownSocket();
    super.dispose();
  }

  void _teardownSocket() {
    if (_sessionId != null) {
      try {
        ref.read(socketServiceProvider).off('qr_confirmed');
      } catch (_) {}
      try {
        ref.read(socketServiceProvider).off('qr_scanned');
      } catch (_) {}
    }
  }

  // ── Generate QR code from backend
  Future<void> _generateQR() async {
    _pollTimer?.cancel();
    _expireTimer?.cancel();
    _teardownSocket();
    setState(() {
      _qrStatus = 'loading';
      _qrBytes = null;
      _sessionId = null;
      _expires = null;
    });

    try {
      final r = await ref.read(authControllerProvider).generateQR();
      if (!mounted) return;

      if (r['success'] != true) {
        setState(() => _qrStatus = 'error');
        return;
      }

      _sessionId = r['session_id'] as String?;
      _expires = r['expires_at'] != null
          ? DateTime.tryParse(r['expires_at'].toString())
          : null;

      // Decode base64 data URL to bytes
      final qrDataUrl = r['qr_code'] as String? ?? '';
      if (qrDataUrl.startsWith('data:image')) {
        final b64 = qrDataUrl.split(',').last;
        try {
          _qrBytes = base64Decode(b64);
        } catch (_) {
          try {
            _qrBytes = base64Decode(base64.normalize(b64));
          } catch (_) {}
        }
      }

      setState(() => _qrStatus = 'pending');

      // Socket events
      if (_sessionId != null) {
        try {
          ref.read(socketServiceProvider).joinQRSession(_sessionId!);
          ref.read(socketServiceProvider).on('qr_scanned', (_) {
            if (mounted) {
              setState(() => _qrStatus = 'scanned');
              HapticFeedback.mediumImpact();
            }
          });
          ref.read(socketServiceProvider).on('qr_confirmed', (d) {
            if (mounted) {
              _pollTimer?.cancel();
              setState(() => _qrStatus = 'confirmed');
              HapticFeedback.heavyImpact();
              Future.delayed(const Duration(milliseconds: 800), () {
                if (mounted) context.go('/');
              });
            }
          });
        } catch (_) {}
      }

      // Polling fallback (every 2 seconds)
      _pollTimer =
          Timer.periodic(const Duration(seconds: 2), (_) => _pollStatus());

      // Expire countdown
      if (_expires != null) {
        final remaining = _expires!.difference(DateTime.now());
        if (remaining.isNegative) {
          setState(() => _qrStatus = 'expired');
        } else {
          _expireTimer = Timer(remaining, () {
            if (mounted) setState(() => _qrStatus = 'expired');
            _pollTimer?.cancel();
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _qrStatus = 'error');
    }
  }

  Future<void> _pollStatus() async {
    if (_sessionId == null || !mounted) return;
    try {
      final r =
          await ref.read(authControllerProvider).checkQRStatus(_sessionId!);
      if (!mounted) return;
      final st = r['status']?.toString() ?? 'pending';
      if (st != _qrStatus) setState(() => _qrStatus = st);
      if (st == 'confirmed') {
        _pollTimer?.cancel();
        context.go('/');
      }
    } catch (_) {}
  }

  // ── Handle scanned QR data (approve login for another device)
  Future<void> _handleScan(String rawData) async {
    if (_scanProcessing || _scanDone) return;
    setState(() {
      _scanProcessing = true;
      _scanError = null;
    });
    HapticFeedback.mediumImpact();

    try {
      Map<String, dynamic> payload = {};
      try {
        payload = Map<String, dynamic>.from(jsonDecode(rawData) as Map);
      } catch (_) {
        payload = {'session_id': rawData};
      }

      final sessionId = payload['session_id'] as String?;
      if (sessionId == null) {
        setState(() {
          _scanProcessing = false;
          _scanError = 'Invalid QR code. Not a RedOrrange code.';
        });
        return;
      }

      final r = await ref
          .read(apiServiceProvider)
          .post('/auth/qr-scan', data: {'session_id': sessionId});
      if (!mounted) return;

      if (r.data['success'] == true) {
        setState(() {
          _scanDone = true;
          _scanProcessing = false;
        });
        await _scanCtrl.stop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(children: [
              Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text('Login approved on the other device!'),
            ]),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        await Future.delayed(const Duration(milliseconds: 1500));
        if (mounted) context.pop();
      } else {
        setState(() {
          _scanProcessing = false;
          _scanError = r.data['message'] ?? 'Failed to approve login.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _scanProcessing = false;
          _scanError = 'Error: ${e.toString()}';
        });
      }
    }
  }

  void _toggleMode(bool isShow) {
    setState(() {
      _showMode = isShow;
      _scanProcessing = false;
      _scanDone = false;
      _scanError = null;
    });
    if (isShow) {
      _scanCtrl.stop();
    } else {
      _scanCtrl.start();
      if (_qrStatus != 'confirmed') _generateQR();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final wide = kIsWeb || MediaQuery.sizeOf(context).width >= 600;

    if (wide) return _buildWide(context, dark);
    return _buildNarrow(context, dark);
  }

  // ─────────────────────────────────────────────────
  // WIDE (2-section) LAYOUT
  // ─────────────────────────────────────────────────
  Widget _buildWide(BuildContext context, bool dark) {
    return Scaffold(
      backgroundColor: dark ? AppTheme.dBg : const Color(0xFFF6F2EE),
      body: Row(children: [
        // ── LEFT: Welcome / Info Panel
        Expanded(
          flex: 48,
          child: _QrLeftPanel(
            dark: dark,
            showMode: _showMode,
            rotateAnim: _rotateAnim,
            floatAnim: _floatAnim,
            onToggle: _toggleMode,
          ),
        ),

        // ── Divider
        Container(
          width: 1,
          color: dark ? AppTheme.dDiv : const Color(0xFFE8E8E8),
        ),

        // ── RIGHT: QR Content
        Expanded(
          flex: 52,
          child: Container(
            color: dark ? AppTheme.dBg : Colors.white,
            child: Column(children: [
              // Header with back button and mode toggle
              SafeArea(
                bottom: false,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back_rounded,
                          color: dark ? Colors.white : AppTheme.lText),
                      onPressed: () => context.pop(),
                    ),
                    const Spacer(),
                    _ModeToggle(showMode: _showMode, onToggle: _toggleMode),
                    const SizedBox(width: 4),
                  ]),
                ),
              ),

              // Body content
              Expanded(
                child: _showMode
                    ? _ShowQRBody(
                        dark: dark,
                        wide: true,
                        qrStatus: _qrStatus,
                        qrBytes: _qrBytes,
                        expires: _expires,
                        pulseAnim: _pulseAnim,
                        glowAnim: _glowAnim,
                        onRefresh: _generateQR,
                      )
                    : _ScanQRBody(
                        dark: dark,
                        ctrl: _scanCtrl,
                        processing: _scanProcessing,
                        done: _scanDone,
                        error: _scanError,
                        onDetected: (barcodes) {
                          final raw = barcodes.barcodes.firstOrNull?.rawValue;
                          if (raw != null) _handleScan(raw);
                        },
                      ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  // ─────────────────────────────────────────────────
  // NARROW (mobile) LAYOUT
  // ─────────────────────────────────────────────────
  Widget _buildNarrow(BuildContext context, bool dark) {
    return Scaffold(
      backgroundColor: dark ? AppTheme.dBg : const Color(0xFFF6F2EE),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded,
              color: dark ? Colors.white : AppTheme.lText),
          onPressed: () => context.pop(),
        ),
        title: Text('QR Code Login',
            style: TextStyle(
                fontWeight: FontWeight.w700,
                color: dark ? Colors.white : AppTheme.lText,
                fontSize: 17)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _ModeToggle(showMode: _showMode, onToggle: _toggleMode),
          ),
        ],
      ),
      body: _showMode
          ? _ShowQRBody(
              dark: dark,
              wide: false,
              qrStatus: _qrStatus,
              qrBytes: _qrBytes,
              expires: _expires,
              pulseAnim: _pulseAnim,
              glowAnim: _glowAnim,
              onRefresh: _generateQR,
            )
          : _ScanQRBody(
              dark: dark,
              ctrl: _scanCtrl,
              processing: _scanProcessing,
              done: _scanDone,
              error: _scanError,
              onDetected: (barcodes) {
                final raw = barcodes.barcodes.firstOrNull?.rawValue;
                if (raw != null) _handleScan(raw);
              },
            ),
    );
  }
}

// ─────────────────────────────────────────────────
// LEFT PANEL — branding + instructions
// ─────────────────────────────────────────────────
class _QrLeftPanel extends StatelessWidget {
  final bool dark, showMode;
  final Animation<double> rotateAnim, floatAnim;
  final ValueChanged<bool> onToggle;

  const _QrLeftPanel({
    required this.dark,
    required this.showMode,
    required this.rotateAnim,
    required this.floatAnim,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A1A2E), Color(0xFF16213E), Color(0xFF0F3460)],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
      child: SafeArea(
        child: Stack(children: [
          // Decorative rotating circles
          Positioned(
            top: -60,
            right: -60,
            child: AnimatedBuilder(
              animation: rotateAnim,
              builder: (_, child) => Transform.rotate(
                  angle: rotateAnim.value * 6.28, child: child),
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  color: AppTheme.orange.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 60,
            left: -40,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            top: 200,
            left: 30,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppTheme.orange.withOpacity(0.06),
                shape: BoxShape.circle,
              ),
            ),
          ),

          // Main content
          Padding(
            padding: const EdgeInsets.all(44),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo
                AnimatedBuilder(
                  animation: floatAnim,
                  builder: (_, child) => Transform.translate(
                      offset: Offset(0, floatAnim.value), child: child),
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppTheme.orange.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                          color: AppTheme.orange.withOpacity(0.4), width: 2),
                      boxShadow: [
                        BoxShadow(
                            color: AppTheme.orange.withOpacity(0.2),
                            blurRadius: 24,
                            offset: const Offset(0, 8)),
                      ],
                    ),
                    child: const Center(
                        child: Icon(Icons.qr_code_2_rounded,
                            color: AppTheme.orange, size: 44)),
                  ),
                ).animate().fadeIn(delay: 100.ms).slideY(begin: -0.3),

                const SizedBox(height: 36),

                const Text(
                  'Log in without\na password',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 36,
                    letterSpacing: -1.2,
                    height: 1.1,
                  ),
                ).animate().fadeIn(delay: 250.ms).slideX(begin: -0.3),

                const SizedBox(height: 16),

                const Text(
                  'Use your phone to instantly authenticate on any device — no passwords, no hassle.',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 15,
                    height: 1.7,
                  ),
                ).animate().fadeIn(delay: 380.ms),

                const SizedBox(height: 40),

                // How it works
                _StepCard(
                  step: '1',
                  icon: Icons.phone_android_rounded,
                  title: 'Open RedOrrange on your phone',
                  subtitle: 'Already logged in on mobile? Perfect.',
                  delay: 500,
                ),
                const SizedBox(height: 14),
                _StepCard(
                  step: '2',
                  icon: Icons.settings_rounded,
                  title: 'Go to Settings → Linked Devices',
                  subtitle: 'Find the QR scanner in your profile.',
                  delay: 620,
                ),
                const SizedBox(height: 14),
                _StepCard(
                  step: '3',
                  icon: Icons.qr_code_scanner_rounded,
                  title: 'Scan this QR code',
                  subtitle: 'Point your camera at the code on the right.',
                  delay: 740,
                ),

                const SizedBox(height: 36),

                // Security note
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: const Row(children: [
                    Icon(Icons.security_rounded,
                        color: Colors.greenAccent, size: 20),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'This QR code is single-use and expires after 5 minutes for your security.',
                        style: TextStyle(color: Colors.white54, fontSize: 12.5, height: 1.5),
                      ),
                    ),
                  ]),
                ).animate().fadeIn(delay: 900.ms),

                const SizedBox(height: 28),

                // Already on phone? toggle to scan mode
                GestureDetector(
                  onTap: () => onToggle(false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.orange.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppTheme.orange.withOpacity(0.3)),
                    ),
                    child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.qr_code_scanner_rounded,
                              color: AppTheme.orange, size: 18),
                          SizedBox(width: 10),
                          Text('I want to approve another device',
                              style: TextStyle(
                                  color: AppTheme.orange,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13)),
                        ]),
                  ),
                ).animate().fadeIn(delay: 1050.ms),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  final String step, title, subtitle;
  final IconData icon;
  final int delay;

  const _StepCard({
    required this.step,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppTheme.orange.withOpacity(0.2),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.orange.withOpacity(0.4)),
        ),
        child: Center(
          child: Text(step,
              style: const TextStyle(
                  color: AppTheme.orange,
                  fontWeight: FontWeight.w900,
                  fontSize: 15)),
        ),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14)),
          const SizedBox(height: 2),
          Text(subtitle,
              style:
                  const TextStyle(color: Colors.white54, fontSize: 12.5, height: 1.4)),
        ]),
      ),
    ]).animate().fadeIn(delay: Duration(milliseconds: delay)).slideX(begin: -0.2);
  }
}

// ─────────────────────────────────────────────────
// MODE TOGGLE
// ─────────────────────────────────────────────────
class _ModeToggle extends StatelessWidget {
  final bool showMode;
  final ValueChanged<bool> onToggle;
  const _ModeToggle({required this.showMode, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _Tab(
            label: 'Show QR',
            icon: Icons.qr_code_rounded,
            active: showMode,
            onTap: () => onToggle(true)),
        _Tab(
            label: 'Scan QR',
            icon: Icons.qr_code_scanner_rounded,
            active: !showMode,
            onTap: () => onToggle(false)),
      ]),
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _Tab(
      {required this.label,
      required this.icon,
      required this.active,
      required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: active ? AppTheme.orange : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 15, color: active ? Colors.white : Colors.grey),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: active ? Colors.white : Colors.grey)),
          ]),
        ),
      );
}

// ─────────────────────────────────────────────────
// SHOW QR BODY
// ─────────────────────────────────────────────────
class _ShowQRBody extends StatelessWidget {
  final bool dark, wide;
  final String qrStatus;
  final Uint8List? qrBytes;
  final DateTime? expires;
  final Animation<double> pulseAnim, glowAnim;
  final VoidCallback onRefresh;

  const _ShowQRBody({
    required this.dark,
    required this.wide,
    required this.qrStatus,
    required this.qrBytes,
    required this.expires,
    required this.pulseAnim,
    required this.glowAnim,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
            horizontal: wide ? 56 : 28, vertical: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Status header
            _QrStatusHeader(status: qrStatus, dark: dark)
                .animate()
                .fadeIn(delay: 100.ms)
                .slideY(begin: -0.2),

            const SizedBox(height: 32),

            // QR code / status display
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              switchInCurve: Curves.easeOut,
              child: _buildQrContent(context),
            ),

            const SizedBox(height: 32),

            // Instructions (only when pending)
            if (qrStatus == 'pending' || qrStatus == 'loading') ...[
              _InstructionStep(
                      step: '1',
                      text: 'Open RedOrrange on your phone',
                      dark: dark)
                  .animate()
                  .fadeIn(delay: 400.ms)
                  .slideX(begin: -0.2),
              const SizedBox(height: 12),
              _InstructionStep(
                      step: '2',
                      text: 'Go to Settings → Linked Devices',
                      dark: dark)
                  .animate()
                  .fadeIn(delay: 500.ms)
                  .slideX(begin: -0.2),
              const SizedBox(height: 12),
              _InstructionStep(
                      step: '3',
                      text:
                          'Tap "Scan QR Code" and point at this screen',
                      dark: dark)
                  .animate()
                  .fadeIn(delay: 600.ms)
                  .slideX(begin: -0.2),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQrContent(BuildContext context) {
    switch (qrStatus) {
      case 'loading':
        return const SizedBox(
          key: ValueKey('loading'),
          height: 280,
          child: Center(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                CircularProgressIndicator(
                    color: AppTheme.orange, strokeWidth: 2.5),
                SizedBox(height: 16),
                Text('Generating QR code...',
                    style: TextStyle(
                        color: AppTheme.orange,
                        fontWeight: FontWeight.w600)),
              ])),
        );

      case 'confirmed':
        return SizedBox(
          key: const ValueKey('confirmed'),
          height: 280,
          child: Center(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                const Icon(Icons.check_circle_rounded,
                        color: Colors.green, size: 96)
                    .animate()
                    .scale(
                        begin: const Offset(0.5, 0.5),
                        curve: Curves.elasticOut),
                const SizedBox(height: 16),
                const Text('Logged in successfully!',
                    style: TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.w700,
                        fontSize: 18)),
              ])),
        );

      case 'expired':
        return SizedBox(
          key: const ValueKey('expired'),
          height: 280,
          child: Center(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                Icon(Icons.timer_off_rounded,
                    color: Colors.grey.shade400, size: 72),
                const SizedBox(height: 16),
                Text('QR code expired',
                    style: TextStyle(
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w600,
                        fontSize: 16)),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh_rounded,
                      color: Colors.white),
                  label: const Text('Generate New QR',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.orange,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                ),
              ])),
        );

      case 'scanned':
        return SizedBox(
          key: const ValueKey('scanned'),
          height: 280,
          child: Center(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                const CircularProgressIndicator(
                    color: AppTheme.orange, strokeWidth: 3),
                const SizedBox(height: 20),
                const Text('Scan detected!',
                    style: TextStyle(
                        color: AppTheme.orange,
                        fontWeight: FontWeight.w700,
                        fontSize: 17)),
                const SizedBox(height: 6),
                Text('Confirm on your phone to complete login',
                    style: TextStyle(
                        color: Colors.grey.shade500, fontSize: 13)),
              ])),
        );

      case 'error':
        return SizedBox(
          key: const ValueKey('error'),
          height: 280,
          child: Center(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                Icon(Icons.error_outline_rounded,
                    color: Colors.red.shade400, size: 72),
                const SizedBox(height: 16),
                Text('Failed to generate QR',
                    style: TextStyle(
                        color: Colors.red.shade600,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Try Again'),
                ),
              ])),
        );

      default:
        // pending — show QR code
        if (qrBytes == null) {
          return const SizedBox(
              key: ValueKey('no-qr'),
              height: 280,
              child: Center(
                  child: CircularProgressIndicator(color: AppTheme.orange)));
        }
        return AnimatedBuilder(
          key: const ValueKey('qr'),
          animation: pulseAnim,
          builder: (_, child) =>
              Transform.scale(scale: pulseAnim.value, child: child),
          child: Column(children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color:
                        AppTheme.orange.withOpacity(glowAnim.value * 0.25),
                    blurRadius: 32,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: AnimatedBuilder(
                animation: glowAnim,
                builder: (_, child) => child!,
                child: Image.memory(qrBytes!,
                    width: 220, height: 220, fit: BoxFit.cover),
              ),
            ),
            if (expires != null) ...[
              const SizedBox(height: 14),
              _ExpiryBar(expires: expires!),
            ],
          ]),
        ).animate().fadeIn(delay: 200.ms).scale(begin: const Offset(0.9, 0.9));
    }
  }
}

class _QrStatusHeader extends StatelessWidget {
  final String status;
  final bool dark;
  const _QrStatusHeader({required this.status, required this.dark});

  @override
  Widget build(BuildContext context) {
    final (title, subtitle, color) = switch (status) {
      'scanned' => (
          'Scan detected!',
          'Confirm on your phone to log in',
          AppTheme.orange
        ),
      'confirmed' => (
          'Logged in!',
          'Redirecting to your feed...',
          Colors.green
        ),
      'expired' => (
          'QR Code Expired',
          'Generate a new code to continue',
          Colors.red
        ),
      'error' => (
          'Something went wrong',
          'Could not generate QR code',
          Colors.red
        ),
      _ => (
          'Scan with your phone',
          'Point your phone camera at the QR code',
          AppTheme.orange
        ),
    };

    return Column(children: [
      Text(title,
          style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 24,
              color: color,
              letterSpacing: -0.5)),
      const SizedBox(height: 6),
      Text(subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(
              color: dark ? AppTheme.dSub : AppTheme.lSub, fontSize: 14)),
    ]);
  }
}

class _InstructionStep extends StatelessWidget {
  final String step, text;
  final bool dark;
  const _InstructionStep(
      {required this.step, required this.text, required this.dark});

  @override
  Widget build(BuildContext context) => Row(children: [
        Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(
              color: AppTheme.orange, shape: BoxShape.circle),
          child: Center(
              child: Text(step,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13))),
        ),
        const SizedBox(width: 12),
        Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 14,
                    color: dark ? AppTheme.dText : AppTheme.lText))),
      ]);
}

class _ExpiryBar extends StatefulWidget {
  final DateTime expires;
  const _ExpiryBar({required this.expires});
  @override
  State<_ExpiryBar> createState() => _ExpiryBarState();
}

class _ExpiryBarState extends State<_ExpiryBar> {
  Timer? _t;
  int _secs = 0;

  @override
  void initState() {
    super.initState();
    _tick();
    _t = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  void _tick() {
    if (mounted) {
      setState(() => _secs =
          widget.expires.difference(DateTime.now()).inSeconds.clamp(0, 9999));
    }
  }

  @override
  Widget build(BuildContext context) {
    final mins = _secs ~/ 60;
    final secs = _secs % 60;
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.timer_outlined, size: 14, color: Colors.grey),
      const SizedBox(width: 4),
      Text(
          'Expires in ${mins}m ${secs.toString().padLeft(2, '0')}s',
          style: const TextStyle(
              color: Colors.grey,
              fontSize: 12,
              fontWeight: FontWeight.w500)),
    ]);
  }
}

// ─────────────────────────────────────────────────
// SCAN QR BODY (full-screen camera)
// ─────────────────────────────────────────────────
class _ScanQRBody extends StatelessWidget {
  final bool dark;
  final MobileScannerController ctrl;
  final bool processing, done;
  final String? error;
  final ValueChanged<BarcodeCapture> onDetected;

  const _ScanQRBody({
    required this.dark,
    required this.ctrl,
    required this.processing,
    required this.done,
    required this.error,
    required this.onDetected,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      // Camera view
      MobileScanner(
        controller: ctrl,
        onDetect: onDetected,
      ),

      // Dark overlay with cutout
      Positioned.fill(
        child: CustomPaint(painter: _ScannerOverlayPainter()),
      ),

      // Targeting frame
      Positioned.fill(
        child: Center(
          child: _ScannerFrame(processing: processing, done: done),
        ),
      ),

      // Top controls
      Positioned(
        top: 16,
        right: 16,
        child: Row(children: [
          _CameraBtn(
            icon: Icons.flash_on_rounded,
            onTap: () => ctrl.toggleTorch(),
          ),
          const SizedBox(width: 10),
          _CameraBtn(
            icon: Icons.flip_camera_ios_rounded,
            onTap: () => ctrl.switchCamera(),
          ),
        ]),
      ),

      // Bottom info
      Positioned(
        bottom: 0,
        left: 0,
        right: 0,
        child: Container(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 48),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Colors.black87, Colors.transparent],
            ),
          ),
          child: Column(children: [
            if (error != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.red.shade900.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(children: [
                  const Icon(Icons.error_outline_rounded,
                      color: Colors.white, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(error!,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13))),
                ]),
              ),
            const Text(
              'Point the camera at a RedOrrange QR code',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  shadows: [Shadow(blurRadius: 8, color: Colors.black)]),
            ),
            const SizedBox(height: 6),
            const Text(
              'Scan the QR code from another device to approve its login',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ]),
        ),
      ),

      // Processing overlay
      if (processing && !done)
        const Positioned.fill(child: _ProcessingOverlay()),

      // Done overlay
      if (done) const Positioned.fill(child: _DoneOverlay()),
    ]);
  }
}

class _ScannerFrame extends StatefulWidget {
  final bool processing, done;
  const _ScannerFrame({required this.processing, required this.done});
  @override
  State<_ScannerFrame> createState() => _ScannerFrameState();
}

class _ScannerFrameState extends State<_ScannerFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scan;
  late final Animation<double> _line;

  @override
  void initState() {
    super.initState();
    _scan = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _line = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _scan, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _scan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.done
        ? Colors.green
        : widget.processing
            ? AppTheme.orange
            : Colors.white;
    const size = 240.0;
    return SizedBox(
        width: size,
        height: size,
        child: Stack(children: [
          // Corner marks
          ..._corners(color),

          // Scanning line
          if (!widget.processing && !widget.done)
            AnimatedBuilder(
              animation: _line,
              builder: (_, __) => Positioned(
                top: _line.value * (size - 4),
                left: 16,
                right: 16,
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [
                      Colors.transparent,
                      AppTheme.orange,
                      Colors.transparent,
                    ]),
                    boxShadow: [
                      BoxShadow(
                          color: AppTheme.orange.withOpacity(0.6),
                          blurRadius: 6)
                    ],
                  ),
                ),
              ),
            ),

          if (widget.done)
            const Center(
                    child: Icon(Icons.check_circle_rounded,
                        color: Colors.green, size: 60))
                .animate()
                .scale(
                    begin: const Offset(0.5, 0.5),
                    curve: Curves.elasticOut),
        ]));
  }

  List<Widget> _corners(Color c) {
    const w = 28.0;
    const t = 4.0;
    const r = 12.0;
    return [
      _Corner(top: 0, left: 0, tlH: true, tlV: true, r: r, w: w, t: t, c: c),
      _Corner(
          top: 0, right: 0, trH: true, trV: true, r: r, w: w, t: t, c: c),
      _Corner(
          bottom: 0, left: 0, blH: true, blV: true, r: r, w: w, t: t, c: c),
      _Corner(
          bottom: 0,
          right: 0,
          brH: true,
          brV: true,
          r: r,
          w: w,
          t: t,
          c: c),
    ];
  }
}

class _Corner extends StatelessWidget {
  final double? top, bottom, left, right;
  final double r, w, t;
  final bool tlH, tlV, trH, trV, blH, blV, brH, brV;
  final Color c;
  const _Corner({
    this.top,
    this.bottom,
    this.left,
    this.right,
    this.tlH = false,
    this.tlV = false,
    this.trH = false,
    this.trV = false,
    this.blH = false,
    this.blV = false,
    this.brH = false,
    this.brV = false,
    required this.r,
    required this.w,
    required this.t,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    final borders = Border(
      top: (tlH || trH) ? BorderSide(color: c, width: t) : BorderSide.none,
      bottom:
          (blH || brH) ? BorderSide(color: c, width: t) : BorderSide.none,
      left: (tlV || blV) ? BorderSide(color: c, width: t) : BorderSide.none,
      right:
          (trV || brV) ? BorderSide(color: c, width: t) : BorderSide.none,
    );
    final radius = BorderRadius.only(
      topLeft: tlH && tlV ? Radius.circular(r) : Radius.zero,
      topRight: trH && trV ? Radius.circular(r) : Radius.zero,
      bottomLeft: blH && blV ? Radius.circular(r) : Radius.zero,
      bottomRight: brH && brV ? Radius.circular(r) : Radius.zero,
    );
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: Container(
        width: w,
        height: w,
        decoration: BoxDecoration(border: borders, borderRadius: radius),
      ),
    );
  }
}

class _CameraBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CameraBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      );
}

class _ProcessingOverlay extends StatelessWidget {
  const _ProcessingOverlay();

  @override
  Widget build(BuildContext context) => Container(
        color: Colors.black54,
        child: const Center(
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
              CircularProgressIndicator(
                  color: AppTheme.orange, strokeWidth: 3),
              SizedBox(height: 16),
              Text('Verifying QR code...',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 16)),
            ])),
      );
}

class _DoneOverlay extends StatelessWidget {
  const _DoneOverlay();

  @override
  Widget build(BuildContext context) => Container(
        color: Colors.black54,
        child: Center(
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
              const Icon(Icons.check_circle_rounded,
                      color: Colors.green, size: 80)
                  .animate()
                  .scale(
                      begin: const Offset(0.5, 0.5),
                      curve: Curves.elasticOut),
              const SizedBox(height: 16),
              const Text('Login approved!',
                  style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.w700,
                      fontSize: 20)),
            ])),
      );
}

class _ScannerOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const holeSize = 240.0;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final rect = Rect.fromCenter(
        center: Offset(cx, cy), width: holeSize, height: holeSize);
    final paint = Paint()..color = Colors.black.withOpacity(0.55);
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(16)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_) => false;
}
