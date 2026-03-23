import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/utils/format_utils.dart';
import 'payment_webview_screen.dart';

/// Payment methods enum with all metadata
enum PayMethod {
  stripe, paypal,
  mtnRw, airtelRw, mpesaKe, mtnUg, airtelUg,
  mtnGh, airtelTz
}

extension PayMethodX on PayMethod {
  String get label => const {
    PayMethod.stripe:   'Credit / Debit Card',
    PayMethod.paypal:   'PayPal',
    PayMethod.mtnRw:    'MTN Mobile Money — Rwanda',
    PayMethod.airtelRw: 'Airtel Money — Rwanda',
    PayMethod.mpesaKe:  'M-Pesa — Kenya',
    PayMethod.mtnUg:    'MTN Mobile Money — Uganda',
    PayMethod.airtelUg: 'Airtel Money — Uganda',
    PayMethod.mtnGh:    'MTN MoMo — Ghana',
    PayMethod.airtelTz: 'Airtel Money — Tanzania',
  }[this]!;

  String get emoji => const {
    PayMethod.stripe:   '💳',
    PayMethod.paypal:   '🅿️',
    PayMethod.mtnRw:    '🇷🇼',
    PayMethod.airtelRw: '🇷🇼',
    PayMethod.mpesaKe:  '🇰🇪',
    PayMethod.mtnUg:    '🇺🇬',
    PayMethod.airtelUg: '🇺🇬',
    PayMethod.mtnGh:    '🇬🇭',
    PayMethod.airtelTz: '🇹🇿',
  }[this]!;

  Color get color => const {
    PayMethod.stripe:   Color(0xFF635BFF),
    PayMethod.paypal:   Color(0xFF003087),
    PayMethod.mtnRw:    Color(0xFFFFCC00),
    PayMethod.airtelRw: Color(0xFFE40000),
    PayMethod.mpesaKe:  Color(0xFF00A651),
    PayMethod.mtnUg:    Color(0xFFFFCC00),
    PayMethod.airtelUg: Color(0xFFE40000),
    PayMethod.mtnGh:    Color(0xFFFFCC00),
    PayMethod.airtelTz: Color(0xFFE40000),
  }[this]!;

  bool get isMobileMoney => ![PayMethod.stripe, PayMethod.paypal].contains(this);
  bool get isStripe => this == PayMethod.stripe;
  bool get isPayPal => this == PayMethod.paypal;

  String get networkCode => const {
    PayMethod.mtnRw:    'MTN_RW',
    PayMethod.airtelRw: 'AIRTEL_RW',
    PayMethod.mpesaKe:  'MPESA_KE',
    PayMethod.mtnUg:    'MTN_UG',
    PayMethod.airtelUg: 'AIRTEL_UG',
    PayMethod.mtnGh:    'MTN_GH',
    PayMethod.airtelTz: 'AIRTEL_TZ',
    PayMethod.stripe:   '',
    PayMethod.paypal:   '',
  }[this]!;

  String get currency => const {
    PayMethod.mtnRw:    'RWF',
    PayMethod.airtelRw: 'RWF',
    PayMethod.mpesaKe:  'KES',
    PayMethod.mtnUg:    'UGX',
    PayMethod.airtelUg: 'UGX',
    PayMethod.mtnGh:    'GHS',
    PayMethod.airtelTz: 'TZS',
    PayMethod.stripe:   'USD',
    PayMethod.paypal:   'USD',
  }[this]!;

  /// Local currency amounts (server returns these too)
  String displayAmount(double usd) {
    const rates = {
      'RWF': 1350.0, 'KES': 132.0, 'UGX': 3720.0,
      'GHS': 15.5,   'TZS': 2680.0,'USD': 1.0,
    };
    final rate  = rates[currency] ?? 1.0;
    final local = (usd * rate).ceil();
    const syms = { 'RWF': 'RWF ', 'KES': 'KSh ', 'UGX': 'UGX ', 'GHS': 'GH₵ ', 'TZS': 'TSh ', 'USD': '\$' };
    return '${syms[currency] ?? ''}${local.toString().replaceAllMapped(Reg/// Payment target types
enum PaymentTarget { coins, adTopup, marketplaceItem }

class PaymentScreen extends ConsumerStatefulWidget {
  final PaymentTarget targetType;
  final String targetId;
  final double priceUsd;
  final String title;
  final String? subtitle;
  
  // Specific for coins (optional)
  final int? coins, bonusCoins;

  const PaymentScreen({
    super.key,
    required this.targetType,
    required this.targetId,
    required this.priceUsd,
    required this.title,
    this.subtitle,
    this.coins,
    this.bonusCoins,
  });

  @override ConsumerState<PaymentScreen> createState() => _PS();
}

class _PS extends ConsumerState<PaymentScreen> {
  PayMethod _method = PayMethod.mtnRw;
  bool _busy = false;
  String? _orderId, _paypalOrderId, _flwRef, _netCode, _err, _status;
  bool _needsOtp = false, _waitingReturn = false;
  int _progress = 0;

  final _phoneCtrl = TextEditingController();
  final _otpCtrl   = TextEditingController();
  Timer? _pollTimer;

  @override void dispose() { _phoneCtrl.dispose(); _otpCtrl.dispose(); _pollTimer?.cancel(); super.dispose(); }

  void _setErr(String m)    => setState(() { _err = m; _busy = false; _status = null; });
  void _setStatus(String m, [int p = 0]) => setState(() { _status = m; _progress = p; });

  Future<void> _pay() async {
    if (_method.isMobileMoney && _phoneCtrl.text.trim().isEmpty) { _setErr('Enter your phone number'); return; }
    setState(() { _busy = true; _err = null; _status = null; });
    try {
      if (_method.isStripe)          await _doStripe();
      else if (_method.isPayPal)     await _doPayPal();
      else                           await _doFlutterwave();
    } catch (e) { _setErr(e.toString().replaceFirst('Exception: ', '')); }
  }

  // ════════════════════════════════════════════════════════
  // STRIPE
  // ════════════════════════════════════════════════════════
  Future<void> _doStripe() async {
    _setStatus('Connecting to Stripe...', 10);
    final api = ref.read(apiServiceProvider);

    // 1. Create PaymentIntent on server based on target
    String path = '/payments/stripe/intent';
    Map<String, dynamic> data = { 'currency': 'USD', 'amount_usd': widget.priceUsd };

    if (widget.targetType == PaymentTarget.coins) {
      data['package_id'] = widget.targetId;
    } else if (widget.targetType == PaymentTarget.adTopup) {
      path = '/payments/ads/topup';
      data['ad_account_id'] = widget.targetId;
    } else if (widget.targetType == PaymentTarget.marketplaceItem) {
      path = '/marketplace/${widget.targetId}/buy';
      data['payment_method'] = 'stripe';
    }

    final r = await api.post(path, data: data);
    if (r.data['success'] != true) throw Exception(r.data['message'] ?? 'Failed to create payment');

    _orderId = r.data['order_id'] as String;
    final clientSecret   = r.data['client_secret']    as String;
    final publishableKey = r.data['publishable_key']  as String;
    _setStatus('Opening secure card form...', 30);

    Stripe.publishableKey = publishableKey;
    await Stripe.instance.applySettings();

    await Stripe.instance.initPaymentSheet(
      paymentSheetParameters: SetupPaymentSheetParameters(
        paymentIntentClientSecret: clientSecret,
        merchantDisplayName: 'RedOrrange',
        style: Theme.of(context).brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
        appearance: PaymentSheetAppearance(
          colors: PaymentSheetAppearanceColors(primary: AppTheme.orange),
          shapes: PaymentSheetShape(borderRadius: 12),
        ),
        billingDetails: BillingDetails(name: ref.read(currentUserProvider)?.displayName),
        applePay: const PaymentSheetApplePay(merchantCountryCode: 'US'),
        googlePay: const PaymentSheetGooglePay(merchantCountryCode: 'US', testEnv: false),
        allowsDelayedPaymentMethods: false,
      ),
    );
    _setStatus('Awaiting card details...', 50);

    await Stripe.instance.presentPaymentSheet();

    _setStatus('Confirming payment...', 80);
    // Use unified confirm endpoint
    final confirm = await api.post('/payments/confirm', data: {
      'payment_intent_id': clientSecret.split('_secret_')[0],
      'order_id': _orderId,
    });

    if (confirm.data['success'] == true) {
      _showSuccess(
        txId:        confirm.data['order_id']      as String? ?? _orderId ?? '',
        method:      'Stripe Card',
        details:     confirm.data,
      );
    } else {
      throw Exception(confirm.data['message'] ?? 'Confirmation failed');
    }
  }

  // ════════════════════════════════════════════════════════
  // PAYPAL
  // ════════════════════════════════════════════════════════
  Future<void> _doPayPal() async {
    _setStatus('Creating PayPal order...', 20);
    final api = ref.read(apiServiceProvider);
    
    String path = '/payments/paypal/create';
    Map<String, dynamic> data = { 'currency': 'USD', 'amount_usd': widget.priceUsd };

    if (widget.targetType == PaymentTarget.coins) {
      data['package_id'] = widget.targetId;
    } else if (widget.targetType == PaymentTarget.marketplaceItem) {
      path = '/marketplace/${widget.targetId}/buy';
      data['payment_method'] = 'paypal';
    } else {
      // Ads topup uses generalized PayPal path usually or specialized one
      data['description'] = 'Ads Top-up';
    }

    final r = await api.post(path, data: data);
    if (r.data['success'] != true) throw Exception(r.data['message'] ?? 'PayPal error');

    _orderId       = r.data['order_id']       as String;
    _paypalOrderId = r.data['paypal_order_id'] as String;
    final approveUrl = r.data['approve_url']  as String? ?? '';

    if (approveUrl.isEmpty) throw Exception('PayPal approval URL not received.');

    setState(() { _busy = false; _status = null; });

    final result = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => PaymentWebViewScreen(
      url: approveUrl,
      gateway: 'paypal',
      orderId: _orderId,
      paypalOrderId: _paypalOrderId,
    )));

    if (result == true && mounted) {
      Navigator.pop(context, true);
    } else {
      setState(() { _waitingReturn = true; _status = 'Waiting for PayPal confirmation...\nIf you completed payment, tap below'; });
    }
  }

  Future<void> _capturePayPal() async {
    setState(() { _busy = true; _status = 'Capturing PayPal payment...'; _waitingReturn = false; });
    final r = await ref.read(apiServiceProvider).post('/payments/confirm', data: {
      'paypal_order_id': _paypalOrderId,
      'order_id': _orderId,
    });
    if (r.data['success'] == true) {
      _showSuccess(
        txId:       r.data['order_id']     as String? ?? _orderId ?? '',
        method:     'PayPal',
        details:    r.data,
      );
    } else {
      _setErr(r.data['message'] as String? ?? 'PayPal payment not completed yet. Try again.');
    }
  }

  // ════════════════════════════════════════════════════════
  // FLUTTERWAVE
  // ════════════════════════════════════════════════════════
  Future<void> _doFlutterwave() async {
    final phone = _phoneCtrl.text.trim().replaceAll(RegExp(r'[\s\-()]'), '');
    _netCode = _method.networkCode;
    _setStatus('Initiating ${_method.label}...', 20);
    final api = ref.read(apiServiceProvider);

    String path = '/payments/flutterwave/initiate';
    Map<String, dynamic> data = {
      'currency':     _method.currency,
      'amount_usd':   widget.priceUsd,
      'phone':        phone,
      'network_code': _netCode,
    };

    if (widget.targetType == PaymentTarget.coins) {
      data['package_id'] = widget.targetId;
    } else if (widget.targetType == PaymentTarget.marketplaceItem) {
      path = '/marketplace/${widget.targetId}/buy';
      data['payment_method'] = 'flutterwave';
    }

    final r = await api.post(path, data: data);
    if (r.data['success'] != true) throw Exception(r.data['message'] ?? 'Mobile money initiation failed');

    _orderId = r.data['order_id'] as String;
    _flwRef  = r.data['flw_ref']  as String?;

    if (r.data['requires_otp'] == true || r.data['auth_mode'] == 'otp') {
      setState(() { _needsOtp = true; _busy = false; _status = 'Enter the OTP sent to $phone'; });
    } else if (r.data['payment_link'] != null) {
      final link = r.data['payment_link'] as String;
      setState(() { _busy = false; });
      final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => PaymentWebViewScreen(
        url: link, gateway: 'flutterwave',
        orderId: _orderId, txRef: _orderId,
      )));
      if (ok == true && mounted) Navigator.pop(context, true);
      else setState(() { _waitingReturn = true; _status = 'Return here after completing payment in browser'; });
    } else {
      _setStatus('📱 Approve the prompt on $phone...', 50);
      await _pollFlutterwave();
    }
  }

  Future<void> _validateOtp() async {
    final otp = _otpCtrl.text.trim();
    if (otp.isEmpty) { setState(() => _err = 'Enter the OTP'); return; }
    setState(() { _busy = true; _err = null; _status = 'Validating...'; _needsOtp = false; });
    final r = await ref.read(apiServiceProvider).post('/payments/validate', data: {
      'flw_ref':      _flwRef || _orderId,
      'otp':          otp,
      'order_id':     _orderId,
      'network_code': _netCode,
    });
    if (r.data['success'] == true) {
      _showSuccess(
        txId:       r.data['order_id']     as String? ?? _orderId ?? '',
        method:     _method.label,
        details:    r.data,
      );
    } else {
      _setErr(r.data['message'] as String? ?? 'OTP invalid — check and retry');
      setState(() => _needsOtp = true);
    }
  }

  Future<void> _pollFlutterwave() async {
    for (int i = 0; i < 8; i++) {
      await Future.delayed(const Duration(seconds: 5));
      try {
        final r = await ref.read(apiServiceProvider).get('/payments/flutterwave/status', q: {'order_id': _orderId});
        if (r.data['status'] == 'completed') {
          _showSuccess(txId: _orderId ?? '', method: _method.label, details: r.data);
          return;
        }
        if (r.data['status'] == 'failed') { _setErr('Payment failed.'); return; }
        if (mounted) setState(() => _status = 'Waiting for approval... (${(i+1)*5}s)');
      } catch (_) {}
    }
    if (mounted) setState(() { _busy = false; _waitingReturn = true; _status = 'If you approved on your phone, tap "I\'ve Paid" below'; });
  }

  Future<void> _verifyManually() async {
    setState(() { _busy = true; _err = null; _status = 'Verifying payment...'; _waitingReturn = false; });
    try {
      final r = await ref.read(apiServiceProvider).get('/payments/flutterwave/status', q: {'order_id': _orderId});
      if (r.data['status'] == 'completed') {
        _showSuccess(txId: _orderId ?? '', method: _method.label, details: r.data);
      } else {
        _setErr('Payment not confirmed yet.');
      }
    } catch (e) { _setErr('$e'); }
  }

  void _showSuccess({required String txId, required String method, Map? details}) {
    setState(() { _busy = false; _status = null; _needsOtp = false; });
    HapticFeedback.heavyImpact();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 80, height: 80, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle), child: const Icon(Icons.check_rounded, color: Colors.white, size: 40)),
          const SizedBox(height: 20),
          const Text('Payment Successful! 🎉', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
          const SizedBox(height: 12),
          Text(widget.title, style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () { Navigator.pop(context); Navigator.pop(context, true); },
            child: const Text('Continue'),
          )),
        ])),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark  = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: dark ? AppTheme.dBg : const Color(0xFFF4F6F9),
      appBar: AppBar(title: const Text('Secure Payment', style: TextStyle(fontWeight: FontWeight.w800))),
      body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Order Summary
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(gradient: LinearGradient(colors: [AppTheme.orange, AppTheme.orangeDark]), borderRadius: BorderRadius.circular(18)),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
              if (widget.subtitle != null) Text(widget.subtitle!, style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ])),
            Text('\$${widget.priceUsd.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 24)),
          ]),
        ),
        const SizedBox(height: 20),
        const Text('Choose Payment Method', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 12),
        _MethodCard(method: PayMethod.stripe, selected: _method == PayMethod.stripe, onTap: () => setState(() { _method = PayMethod.stripe; _reset(); }), subtitle: 'Card, Apple/Google Pay', dark: dark),
        const SizedBox(height: 8),
        _MethodCard(method: PayMethod.paypal, selected: _method == PayMethod.paypal, onTap: () => setState(() { _method = PayMethod.paypal; _reset(); }), subtitle: 'PayPal Balance or Card', dark: dark),
        const SizedBox(height: 16),
        const Text('Mobile Money (Africa)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Colors.grey)),
        const SizedBox(height: 8),
        ...([PayMethod.mtnRw, PayMethod.airtelRw, PayMethod.mpesaKe].map((m) => Padding(padding: const EdgeInsets.only(bottom: 8), child: _MethodCard(method: m, selected: _method == m, onTap: () => setState(() { _method = m; _reset(); }), subtitle: m.label, dark: dark)))),
        
        if (_method.isMobileMoney) ...[
          const SizedBox(height: 12),
          TextField(controller: _phoneCtrl, keyboardType: TextInputType.phone, decoration: InputDecoration(hintText: 'Phone Number', prefixIcon: Icon(Icons.phone_rounded, color: AppTheme.orange))),
        ],

        if (_needsOtp) ...[
          const SizedBox(height: 12),
          TextField(controller: _otpCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'OTP / PIN')),
          const SizedBox(height: 8),
          ElevatedButton(onPressed: _validateOtp, child: const Text('Verify OTP')),
        ],

        if (_err != null) ...[
           const SizedBox(height: 12),
           Text(_err!, style: const TextStyle(color: Colors.red)),
        ],

        const SizedBox(height: 20),
        if (!_needsOtp && !_waitingReturn) SizedBox(width: double.infinity, child: ElevatedButton(
          onPressed: _busy ? null : _pay,
          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
          child: _busy ? const CircularProgressIndicator(color: Colors.white) : Text('Pay \$${widget.priceUsd.toStringAsFixed(2)}'),
        )),
        
        if (_waitingReturn) ...[
          const SizedBox(height: 12),
          ElevatedButton(onPressed: _method.isPayPal ? _capturePayPal : _verifyManually, child: const Text("I've Paid")),
        ],

        const SizedBox(height: 30),
        const Center(child: Text('Secure encrypted payments', style: TextStyle(fontSize: 11, color: Colors.grey))),
      ])),
    );
  }

  void _reset() { setState(() { _err = null; _status = null; _needsOtp = false; _waitingReturn = false; _orderId = null; _paypalOrderId = null; _flwRef = null; _otpCtrl.clear(); }); }
}

class _TrustBadge extends StatelessWidget {
  final IconData icon; final String label;
  const _TrustBadge(this.icon, this.label);
  @override Widget build(BuildContext _) => Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 13, color: Colors.grey), const SizedBox(width: 4), Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w500))]);
}

class _MethodCard extends StatelessWidget {
  final PayMethod method; final bool selected, dark;
  final VoidCallback onTap;
  final String subtitle;
  const _MethodCard({required this.method, required this.selected, required this.dark, required this.onTap, required this.subtitle});

  @override Widget build(BuildContext _) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: selected ? method.color.withOpacity(0.08) : (dark ? AppTheme.dCard : Colors.white),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: selected ? method.color : Colors.transparent, width: 2),
      ),
      child: Row(children: [
        Container(width: 40, height: 40, decoration: BoxDecoration(color: method.color.withOpacity(0.1), shape: BoxShape.circle), child: Center(child: Text(method.emoji, style: const TextStyle(fontSize: 18)))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(method.label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: selected ? method.color : null)),
          Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ])),
        if (selected) Icon(Icons.check_circle_rounded, color: method.color, size: 20),
      ]),
    ),
  );
}

        // ── Trust badges
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _TrustBadge(Icons.security_rounded, 'PCI DSS'),
          const SizedBox(width: 16),
          _TrustBadge(Icons.verified_rounded, 'Stripe'),
          const SizedBox(width: 16),
          _TrustBadge(Icons.shield_rounded, 'Encrypted'),
        ]),

        const SizedBox(height: 8),
        const Center(child: Text('Payments processed by Stripe, PayPal & Flutterwave.\nNo card data is stored on our servers.', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.5))),
        const SizedBox(height: 20),
      ])),
    );
  }

  void _reset() { setState(() { _err = null; _status = null; _needsOtp = false; _waitingReturn = false; _orderId = null; _paypalOrderId = null; _flwRef = null; _otpCtrl.clear(); }); }
}

// ── Payment method card
class _MethodCard extends StatelessWidget {
  final PayMethod method; final bool selected, dark;
  final VoidCallback onTap;
  final String subtitle;
  final List<String> badges;
  const _MethodCard({required this.method, required this.selected, required this.dark, required this.onTap, required this.subtitle, this.badges = const []});

  @override Widget build(BuildContext _) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: selected ? method.color.withOpacity(0.06) : (dark ? AppTheme.dCard : Colors.white),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: selected ? method.color : Colors.transparent, width: 2),
        boxShadow: selected ? [BoxShadow(color: method.color.withOpacity(0.2), blurRadius: 8)] : [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 4)],
      ),
      child: Row(children: [
        // Icon
        Container(width: 46, height: 46, decoration: BoxDecoration(color: selected ? method.color.withOpacity(0.12) : (dark ? AppTheme.dBg : const Color(0xFFF5F5F5)), borderRadius: BorderRadius.circular(12)), child: Center(child: Text(method.emoji, style: const TextStyle(fontSize: 22)))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(method.label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: selected ? method.color : null)),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          if (badges.isNotEmpty) const SizedBox(height: 4),
          if (badges.isNotEmpty) Row(children: badges.map((b) => Container(margin: const EdgeInsets.only(right: 6), padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2), decoration: BoxDecoration(color: const Color(0xFF4CAF50).withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Text(b, style: const TextStyle(color: Color(0xFF4CAF50), fontSize: 9, fontWeight: FontWeight.w700)))).toList()),
        ])),
        // Radio
        Container(width: 20, height: 20, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: selected ? method.color : Colors.grey.shade400, width: 2)), child: selected ? Center(child: Container(width: 10, height: 10, decoration: BoxDecoration(color: method.color, shape: BoxShape.circle))) : null),
      ]),
    ),
  );
}

class _TrustBadge extends StatelessWidget {
  final IconData icon; final String label;
  const _TrustBadge(this.icon, this.label);
  @override Widget build(BuildContext _) => Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 13, color: Colors.grey), const SizedBox(width: 4), Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w500))]);
}
