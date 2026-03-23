import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'dart:async';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/socket_service.dart';

class QrScreen extends ConsumerStatefulWidget {
  const QrScreen({super.key});
  @override ConsumerState<QrScreen> createState() => _S();
}
class _S extends ConsumerState<QrScreen> with SingleTickerProviderStateMixin {
  // Mode: 'show' = show QR to scan (desktop login), 'scan' = scan QR (mobile login)
  String _mode = 'show';
  String? _qrDataUrl, _sessionId; DateTime? _expires;
  String _status = 'pending'; // pending | scanned | confirmed | expired
  Timer? _poll;
  bool _l = true;
  MobileScannerController? _scanCtrl;

  @override void initState() { super.initState(); _genQR(); }
  @override void dispose() { _poll?.cancel(); _scanCtrl?.dispose(); super.dispose(); }

  Future<void> _genQR() async {
    setState(() { _l = true; _status = 'pending'; });
    try {
      final r = await ref.read(authControllerProvider).generateQR();
      if (r['success'] == true && mounted) {
        setState(() { _qrDataUrl = r['qr_code']; _sessionId = r['session_id']; _expires = DateTime.tryParse(r['expires_at'] ?? ''); _l = false; });
        _startPolling();
        // Also listen via socket
        if (_sessionId != null) {
          ref.read(socketServiceProvider).joinQRSession(_sessionId!);
          ref.read(socketServiceProvider).on('qr_confirmed', (d) {
            if (mounted) { _poll?.cancel(); setState(() => _status = 'confirmed'); Future.delayed(const Duration(milliseconds: 500), () { if (mounted) context.go('/'); }); }
          });
          ref.read(socketServiceProvider).on('qr_scanned', (d) {
            if (mounted) setState(() => _status = 'scanned');
          });
        }
      }
    } catch (_) { if (mounted) setState(() => _l = false); }
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_sessionId == null) return;
      if (_expires != null && DateTime.now().isAfter(_expires!)) { _poll?.cancel(); setState(() => _status = 'expired'); return; }
      try {
        final r = await ref.read(authControllerProvider).checkQRStatus(_sessionId!);
        if (!mounted) { _poll?.cancel(); return; }
        final st = r['status'] as String? ?? 'pending';
        setState(() => _status = st);
        if (st == 'confirmed') { _poll?.cancel(); context.go('/'); }
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Login with QR', style: TextStyle(fontWeight: FontWeight.w800)),
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => context.pop()),
        actions: [
          TextButton.icon(onPressed: () { setState(() => _mode = _mode == 'show' ? 'scan' : 'show'); if (_mode == 'scan') { _scanCtrl = MobileScannerController(); } else { _scanCtrl?.dispose(); _scanCtrl = null; } },
            icon: Icon(_mode == 'show' ? Icons.qr_code_scanner_rounded : Icons.qr_code_rounded, size: 18),
            label: Text(_mode == 'show' ? 'Scan QR' : 'Show QR')),
        ],
      ),
      body: _mode == 'scan' ? _ScanMode(ctrl: _scanCtrl ??= MobileScannerController(), onScanned: _handleScan) : _ShowMode(
        loading: _l, status: _status, qrDataUrl: _qrDataUrl, onRefresh: _genQR,
        expires: _expires, sessionId: _sessionId,
      ),
    );
  }

  Future<void> _handleScan(String data) async {
    // When scanning another user's QR code to approve login
    try {
      final r = await ref.read(apiServiceProvider).post('/auth/qr-scan', data: {'session_id': data});
      if (r.data['success'] == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Login approved!')));
        context.pop();
      }
    } catch (_) {}
  }
}

// Show QR to be scanned
class _ShowMode extends StatelessWidget {
  final bool loading; final String status; final String? qrDataUrl; final VoidCallback onRefresh;
  final DateTime? expires; final String? sessionId;
  const _ShowMode({required this.loading, required this.status, this.qrDataUrl, required this.onRefresh, this.expires, this.sessionId});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text(
        status == 'scanned' ? 'Scan detected — confirming...'
          : status == 'confirmed' ? '✅ Confirmed! Logging you in...'
          : status == 'expired' ? 'QR code expired'
          : 'Scan this QR code with your phone',
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: status == 'confirmed' ? Colors.green : status == 'expired' ? Colors.red : null),
        textAlign: TextAlign.center,
      ),
      if (status != 'confirmed' && status != 'expired') ...[
        const SizedBox(height: 4),
        Text('Open RedOrrange on your phone → Settings → Linked Devices → Scan QR', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: dark ? AppTheme.dSub : AppTheme.lSub)),
      ],
      const SizedBox(height: 32),
      if (loading) const CircularProgressIndicator(color: AppTheme.orange)
      else if (status == 'expired') Column(children: [
        const Icon(Icons.refresh_rounded, size: 72, color: AppTheme.orange),
        const SizedBox(height: 16),
        ElevatedButton.icon(onPressed: onRefresh, icon: const Icon(Icons.refresh_rounded), label: const Text('Generate New QR Code')),
      ])
      else if (status == 'confirmed') const Icon(Icons.check_circle_rounded, size: 96, color: Colors.green)
      else if (status == 'scanned') Column(children: [
        const SizedBox(width: 60, height: 60, child: CircularProgressIndicator(strokeWidth: 3, color: AppTheme.orange)),
        const SizedBox(height: 16), const Text('Confirming on your phone...', style: TextStyle(color: AppTheme.orange, fontWeight: FontWeight.w600)),
      ])
      else if (qrDataUrl != null) Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: AppTheme.orange.withOpacity(0.2), blurRadius: 24, spreadRadius: 4)]),
        child: Column(children: [
          // Real QR code from backend (data URL or URL)
          qrDataUrl!.startsWith('data:image')
            ? Image.memory(Uri.parse(qrDataUrl!).data!.contentAsBytes(), width: 220, height: 220)
            : Image.network(qrDataUrl!, width: 220, height: 220, errorBuilder: (_, __, ___) => Container(width: 220, height: 220, color: Colors.grey.shade100, child: const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.qr_code_rounded, size: 60, color: Colors.grey), Text('QR Code', style: TextStyle(color: Colors.grey))])))),
          if (expires != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text('Expires in ${expires!.difference(DateTime.now()).inMinutes}m', style: const TextStyle(fontSize: 12, color: Colors.grey))),
        ]),
      ),
      if (!loading && status != 'expired') ...[
        const SizedBox(height: 24),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: status == 'pending' ? Colors.grey : AppTheme.orange, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(status == 'pending' ? 'Waiting for scan...' : status, style: TextStyle(fontSize: 13, color: dark ? AppTheme.dSub : AppTheme.lSub)),
        ]),
      ],
    ])));
  }
}

// Scan a QR code (to approve someone else's login)
class _ScanMode extends StatefulWidget {
  final MobileScannerController ctrl;
  final Future<void> Function(String) onScanned;
  const _ScanMode({required this.ctrl, required this.onScanned});
  @override State<_ScanMode> createState() => _SMS();
}
class _SMS extends State<_ScanMode> {
  bool _scanned = false;
  @override
  Widget build(BuildContext context) => Stack(children: [
    MobileScanner(controller: widget.ctrl, onDetect: (capture) {
      if (_scanned) return;
      final code = capture.barcodes.firstOrNull?.rawValue;
      if (code != null) { setState(() => _scanned = true); widget.onScanned(code); }
    }),
    // Scanning overlay
    Positioned.fill(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(width: 240, height: 240, decoration: BoxDecoration(border: Border.all(color: AppTheme.orange, width: 2.5), borderRadius: BorderRadius.circular(16)),
        child: Stack(children: [
          Positioned(top: 0, left: 0, child: Container(width: 30, height: 30, decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppTheme.orange, width: 4), left: BorderSide(color: AppTheme.orange, width: 4)), borderRadius: BorderRadius.only(topLeft: Radius.circular(12))))),
          Positioned(top: 0, right: 0, child: Container(width: 30, height: 30, decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppTheme.orange, width: 4), right: BorderSide(color: AppTheme.orange, width: 4)), borderRadius: BorderRadius.only(topRight: Radius.circular(12))))),
          Positioned(bottom: 0, left: 0, child: Container(width: 30, height: 30, decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.orange, width: 4), left: BorderSide(color: AppTheme.orange, width: 4)), borderRadius: BorderRadius.only(bottomLeft: Radius.circular(12))))),
          Positioned(bottom: 0, right: 0, child: Container(width: 30, height: 30, decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.orange, width: 4), right: BorderSide(color: AppTheme.orange, width: 4)), borderRadius: BorderRadius.only(bottomRight: Radius.circular(12))))),
        ])),
      const SizedBox(height: 20),
      const Text('Point at a RedOrrange QR code', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15, shadows: [Shadow(blurRadius: 8)])),
    ])),
    Positioned(top: 16, right: 16, child: Row(children: [
      IconButton(icon: const Icon(Icons.flash_on_rounded, color: Colors.white), onPressed: () => widget.ctrl.toggleTorch()),
      IconButton(icon: const Icon(Icons.flip_camera_ios_rounded, color: Colors.white), onPressed: () => widget.ctrl.switchCamera()),
    ])),
    if (_scanned) Positioned.fill(child: Container(color: Colors.black54, child: const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [CircularIndicator(), SizedBox(height: 16), Text('Processing...', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16))])))),
  ]);
}

class CircularIndicator extends StatelessWidget {
  const CircularIndicator();
  @override Widget build(BuildContext _) => const CircularProgressIndicator(color: AppTheme.orange);
}
