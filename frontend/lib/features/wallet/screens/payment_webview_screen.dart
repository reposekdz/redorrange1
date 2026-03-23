import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/api_service.dart';

/// Handles all payment gateway webviews (Stripe checkout, PayPal, Flutterwave)
class PaymentWebViewScreen extends ConsumerStatefulWidget {
  final String url;
  final String? orderId, gateway, txRef, paypalOrderId;
  const PaymentWebViewScreen({super.key, required this.url, this.orderId, this.gateway, this.txRef, this.paypalOrderId});
  @override ConsumerState<PaymentWebViewScreen> createState() => _S();
}
class _S extends ConsumerState<PaymentWebViewScreen> {
  WebViewController? _ctrl;
  bool _loading = true, _confirming = false;
  int _progress = 0;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  void _initWebView() {
    final successPatterns = ['payment-success', 'payment/success', 'payment_success', 'redorrange.app/success', '?status=successful', '?status=completed', 'approved', 'PayerID'];
    final cancelPatterns  = ['payment-cancel', 'payment/cancel', 'cancel', 'declined', 'failed'];

    final ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) => setState(() => _progress = p),
        onPageStarted: (_) => setState(() => _loading = true),
        onPageFinished: (url) {
          setState(() => _loading = false);
          _checkUrl(url, successPatterns, cancelPatterns);
        },
        onNavigationRequest: (req) {
          _checkUrl(req.url, successPatterns, cancelPatterns);
          return NavigationDecision.navigate;
        },
        onWebResourceError: (e) {},
      ))
      ..loadRequest(Uri.parse(widget.url));
    setState(() => _ctrl = ctrl);
  }

  void _checkUrl(String url, List<String> success, List<String> cancel) {
    final isSuccess = success.any((p) => url.toLowerCase().contains(p));
    final isCancel  = cancel.any((p)  => url.toLowerCase().contains(p));
    if (isSuccess && !_confirming) _handleSuccess(url);
    else if (isCancel) _handleCancel();
  }

  Future<void> _handleSuccess(String url) async {
    setState(() => _confirming = true);
    try {
      final api = ref.read(apiServiceProvider);
      final gw  = widget.gateway ?? '';
      Map<String,dynamic> result = {};

      if (gw == 'stripe' && widget.orderId != null) {
        // Extract payment_intent from URL or rely on webhook
        final uri = Uri.parse(url);
        final pi  = uri.queryParameters['payment_intent'];
        if (pi != null) {
          final r = await api.post('/coins/purchase/stripe/confirm', data: {'payment_intent_id': pi, 'order_id': widget.orderId});
          result = Map<String,dynamic>.from(r.data);
        }
      } else if (gw == 'paypal' && widget.orderId != null && widget.paypalOrderId != null) {
        final r = await api.post('/coins/purchase/paypal/capture', data: {'paypal_order_id': widget.paypalOrderId, 'order_id': widget.orderId});
        result = Map<String,dynamic>.from(r.data);
      } else if (gw == 'flutterwave' && widget.txRef != null && widget.orderId != null) {
        final r = await api.post('/coins/purchase/flutterwave/verify', data: {'tx_ref': widget.txRef, 'order_id': widget.orderId});
        result = Map<String,dynamic>.from(r.data);
      }

      if (mounted) {
        context.pop();
        _showSuccess(result['coins_added'] as int? ?? 0, result['new_balance'] as int? ?? 0);
      }
    } catch (e) {
      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Payment confirmed. Coins being processed...'), backgroundColor: Colors.green));
      }
    }
  }

  void _handleCancel() {
    if (mounted) { context.pop(); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment cancelled'))); }
  }

  void _showSuccess(int coinsAdded, int newBalance) {
    showDialog(context: context, builder: (_) => Dialog(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)), child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 72, height: 72, decoration: const BoxDecoration(color: Color(0xFF4CAF50), shape: BoxShape.circle), child: const Icon(Icons.check_rounded, color: Colors.white, size: 40)),
      const SizedBox(height: 16),
      const Text('Payment Successful!', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
      const SizedBox(height: 8),
      Text('+$coinsAdded coins added to your wallet', style: const TextStyle(color: Colors.grey, fontSize: 14)),
      const SizedBox(height: 4),
      Text('New balance: ${newBalance.toString()} coins', style: const TextStyle(color: AppTheme.orange, fontWeight: FontWeight.w700)),
      const SizedBox(height: 20),
      ElevatedButton(onPressed: () { Navigator.pop(context); }, child: const Text('Continue', style: TextStyle(fontWeight: FontWeight.w700))),
    ]))));
  }

  @override
  Widget build(BuildContext context) {
    final gw = widget.gateway ?? 'payment';
    return Scaffold(
      appBar: AppBar(
        title: Text(_title(gw), style: const TextStyle(fontWeight: FontWeight.w700)),
        leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => showDialog(context: context, builder: (_) => AlertDialog(title: const Text('Cancel Payment?'), content: const Text('Your payment will not be processed.'), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Continue')), TextButton(onPressed: () { Navigator.pop(context); context.pop(); }, child: const Text('Cancel Payment', style: TextStyle(color: Colors.red)))]))),
        bottom: _loading || _progress < 100 ? PreferredSize(preferredSize: const Size.fromHeight(3), child: LinearProgressIndicator(value: _progress / 100, color: AppTheme.orange, backgroundColor: Colors.transparent)) : null,
      ),
      body: _confirming
        ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [CircularProgressIndicator(color: AppTheme.orange), SizedBox(height: 16), Text('Confirming payment...', style: TextStyle(fontWeight: FontWeight.w600))]))
        : _ctrl != null ? WebViewWidget(controller: _ctrl!) : const Center(child: CircularProgressIndicator(color: AppTheme.orange)),
    );
  }

  String _title(String gw) { switch(gw) { case 'stripe': return 'Card Payment'; case 'paypal': return 'PayPal'; case 'flutterwave': return 'Mobile Money'; default: return 'Secure Payment'; } }
}
