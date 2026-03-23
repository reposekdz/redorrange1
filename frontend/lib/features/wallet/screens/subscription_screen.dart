import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/api_service.dart';

final _subsProv = FutureProvider.autoDispose<Map<String,dynamic>>((ref) async {
  final r = await ref.read(apiServiceProvider).get('/payments/subscription/plans');
  return Map<String,dynamic>.from(r.data);
});

class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});
  @override ConsumerState<SubscriptionScreen> createState() => _S();
}
class _S extends ConsumerState<SubscriptionScreen> {
  String? _activating; bool _cancelling = false;

  static const _planGradients = {
    'RedOrrange Plus':  [Color(0xFF7B1FA2), Color(0xFF9C27B0)],
    'RedOrrange Pro':   [Color(0xFFE65100), Color(0xFFFF6B35)],
    'RedOrrange Elite': [Color(0xFFB8860B), Color(0xFFFFD700)],
  };
  static const _planIcons = {
    'RedOrrange Plus':  Icons.workspace_premium_rounded,
    'RedOrrange Pro':   Icons.rocket_launch_rounded,
    'RedOrrange Elite': Icons.diamond_rounded,
  };

  Future<void> _subscribe(BuildContext context, Map plan, String method) async {
    setState(() => _activating = plan['id']);
    try {
      if (method == 'stripe') {
        if (plan['stripe_price_id'] != null) {
          // Real Stripe subscription
          final r = await ref.read(apiServiceProvider).post('/payments/stripe/subscription', data: {
            'plan_id': plan['id'],
            'stripe_price_id': plan['stripe_price_id'],
          });
          if (r.data['success'] == true) {
            // In production: use flutter stripe SDK with client_secret
            // For now show success
            await _activatePlan(context, plan['id'], 'stripe', r.data['subscription_id']);
          }
        } else {
          // Fall back to one-time stripe payment
          await _stripeOneTime(context, plan);
        }
      } else if (method == 'paypal') {
        await _paypalPlan(context, plan);
      } else {
        // Flutterwave — mobile money
        await _fwPlan(context, plan, method);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
    if (mounted) setState(() => _activating = null);
  }

  Future<void> _stripeOneTime(BuildContext context, Map plan) async {
    final r = await ref.read(apiServiceProvider).post('/payments/stripe/intent', data: {
      'amount_usd': plan['price_usd'],
      'description': '${plan['name']} subscription',
    });
    if (r.data['success'] != true) throw Exception(r.data['message']);
    // Confirm and activate
    final conf = await ref.read(apiServiceProvider).post('/payments/stripe/confirm', data: {
      'payment_intent_id': r.data['payment_intent_id'],
      'order_id': r.data['order_id'],
    });
    if (conf.data['success'] == true) await _activatePlan(context, plan['id'], 'stripe', null);
  }

  Future<void> _paypalPlan(BuildContext context, Map plan) async {
    final r = await ref.read(apiServiceProvider).post('/payments/paypal/create', data: {
      'amount_usd': plan['price_usd'],
      'description': plan['name'],
      'currency': 'USD',
    });
    if (r.data['success'] != true) throw Exception(r.data['message']);
    final approveUrl = r.data['approve_url'] as String?;
    if (approveUrl != null) {
      await launchUrl(Uri.parse(approveUrl), mode: LaunchMode.externalApplication);
      // Show "I've paid" dialog
      if (context.mounted) {
        final confirmed = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
          title: const Text('PayPal Payment'),
          content: const Text('Did you complete the payment in PayPal?'),
          actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("Yes, I've Paid"))],
        ));
        if (confirmed == true) {
          final cap = await ref.read(apiServiceProvider).post('/payments/paypal/capture', data: {'paypal_order_id': r.data['paypal_order_id'], 'order_id': r.data['order_id']});
          if (cap.data['success'] == true && context.mounted) await _activatePlan(context, plan['id'], 'paypal', null);
        }
      }
    }
  }

  Future<void> _fwPlan(BuildContext context, Map plan, String networkCode) async {
    final phoneCtrl = TextEditingController();
    final phone = await showDialog<String>(context: context, builder: (_) => AlertDialog(
      title: const Text('Mobile Money Payment'),
      content: TextField(controller: phoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Your mobile money number', hintText: '+250 7XX XXX XXX')),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(context, phoneCtrl.text.trim()), child: const Text('Initiate'))],
    ));
    if (phone == null || phone.isEmpty) return;
    // Convert to local currency
    final currencies = {'MTN_RW': 'RWF', 'AIRTEL_RW': 'RWF', 'MPESA_KE': 'KES', 'MTN_UG': 'UGX'};
    final rates      = {'RWF': 1350, 'KES': 132, 'UGX': 3720};
    final cur = currencies[networkCode] ?? 'RWF';
    final localAmt = (plan['price_usd'] * (rates[cur] ?? 1350)).round();
    final r = await ref.read(apiServiceProvider).post('/payments/flutterwave/initiate', data: {
      'amount_usd': plan['price_usd'], 'currency': cur,
      'phone': phone, 'network_code': networkCode, 'use_link': false,
      'description': plan['name'],
    });
    if (r.data['success'] != true) throw Exception(r.data['message']);
    if (r.data['requires_otp'] == true && context.mounted) {
      final otpCtrl = TextEditingController();
      final otp = await showDialog<String>(context: context, builder: (_) => AlertDialog(
        title: Text('OTP for $networkCode'),
        content: TextField(controller: otpCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Enter OTP')),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(context, otpCtrl.text.trim()), child: const Text('Confirm'))],
      ));
      if (otp != null && otp.isNotEmpty) {
        final val = await ref.read(apiServiceProvider).post('/payments/flutterwave/validate', data: {'flw_ref': r.data['flw_ref'], 'otp': otp, 'order_id': r.data['order_id'], 'network_code': networkCode});
        if (val.data['success'] == true && context.mounted) await _activatePlan(context, plan['id'], networkCode, null);
      }
    } else if (r.data['payment_link'] != null) {
      await launchUrl(Uri.parse(r.data['payment_link'] as String), mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _activatePlan(BuildContext context, String planId, String method, String? ref_) async {
    final r = await this.ref.read(apiServiceProvider).post('/payments/subscription/activate', data: {'plan_id': planId, 'payment_method': method, 'provider_ref': ref_});
    if (!mounted) return;
    if (r.data['success'] == true) {
      this.ref.refresh(_subsProv);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('🎉 ${r.data['message']}'), backgroundColor: Colors.green, duration: const Duration(seconds: 4)));
    }
  }

  Future<void> _cancel(BuildContext context) async {
    final confirmed = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Cancel Subscription?'),
      content: const Text('You can keep using premium features until your billing period ends.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')), TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cancel Subscription', style: TextStyle(color: Colors.red)))],
    ));
    if (confirmed != true) return;
    setState(() => _cancelling = true);
    await ref.read(apiServiceProvider).post('/payments/subscription/cancel').catchError((_){});
    ref.refresh(_subsProv);
    if (mounted) { setState(() => _cancelling = false); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Subscription cancelled'))); }
  }

  void _showPaymentMethods(BuildContext context, Map plan) {
    showModalBottomSheet(context: context, backgroundColor: Colors.transparent, builder: (_) {
      final dark = Theme.of(context).brightness == Brightness.dark;
      return Container(margin: const EdgeInsets.all(10), decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(20)), padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Subscribe to ${plan['name']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        Text('\$${plan['price_usd']}/month', style: const TextStyle(color: AppTheme.orange, fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 16),
        _PMBtn('💳', 'Credit / Debit Card', 'Stripe', () { Navigator.pop(context); _subscribe(context, plan, 'stripe'); }),
        const SizedBox(height: 8),
        _PMBtn('🅿️', 'PayPal', 'Fast checkout', () { Navigator.pop(context); _subscribe(context, plan, 'paypal'); }),
        const SizedBox(height: 8),
        _PMBtn('🇷🇼', 'MTN Mobile Money', 'Rwanda', () { Navigator.pop(context); _subscribe(context, plan, 'MTN_RW'); }),
        const SizedBox(height: 8),
        _PMBtn('🇷🇼', 'Airtel Money', 'Rwanda', () { Navigator.pop(context); _subscribe(context, plan, 'AIRTEL_RW'); }),
        const SizedBox(height: 8),
        _PMBtn('🇰🇪', 'M-Pesa', 'Kenya', () { Navigator.pop(context); _subscribe(context, plan, 'MPESA_KE'); }),
        const SizedBox(height: 8),
        _PMBtn('🇺🇬', 'MTN Mobile Money', 'Uganda', () { Navigator.pop(context); _subscribe(context, plan, 'MTN_UG'); }),
        const SizedBox(height: 14),
        const Center(child: Text('Secure  •  No hidden fees  •  Cancel anytime', style: TextStyle(color: Colors.grey, fontSize: 11))),
      ]));
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(_subsProv);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('Premium', style: TextStyle(fontWeight: FontWeight.w800))),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.orange)),
        error: (e, _) => Center(child: ElevatedButton(onPressed: () => ref.refresh(_subsProv), child: const Text('Retry'))),
        data: (d) {
          final plans   = List<dynamic>.from(d['plans'] ?? []);
          final current = d['current_subscription'] as Map?;
          return ListView(padding: const EdgeInsets.all(16), children: [
            // Current subscription
            if (current != null) Container(margin: const EdgeInsets.only(bottom: 16), padding: const EdgeInsets.all(16), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF7B1FA2), Color(0xFF9C27B0)]), borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Icon(_planIcons[current['plan_name']] ?? Icons.workspace_premium_rounded, color: Colors.white, size: 24), const SizedBox(width: 10), Text('${current['plan_name']} Active', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)), const Spacer(), _cancelling ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : TextButton(onPressed: () => _cancel(context), child: const Text('Cancel', style: TextStyle(color: Colors.white60, fontSize: 12)))]),
              const SizedBox(height: 4),
              Text('Renews ${current['expires_at']?.toString().substring(0,10) ?? '—'}', style: const TextStyle(color: Colors.white60, fontSize: 12)),
            ])),

            // Hero
            Container(margin: const EdgeInsets.only(bottom: 20), padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(18)), child: Column(children: [
              const Text('🏆', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 10),
              const Text('Unlock Premium Features', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22, height: 1.2), textAlign: TextAlign.center),
              const SizedBox(height: 6),
              const Text('Verified badge, monthly coins, exclusive features and more.', style: TextStyle(color: Colors.grey, fontSize: 13), textAlign: TextAlign.center),
            ])),

            // Plan cards
            ...plans.map((plan) {
              final pName    = plan['name'] as String? ?? '';
              final isActive = current?['plan_id'] == plan['id'];
              final gradients = _planGradients[pName] ?? [AppTheme.orange, AppTheme.orangeDark];
              final icon     = _planIcons[pName]     ?? Icons.workspace_premium_rounded;
              final features = plan['features'] is List ? List<String>.from(plan['features']) : <String>[];
              final isActivating = _activating == plan['id'];
              return Container(margin: const EdgeInsets.only(bottom: 14), decoration: BoxDecoration(
                gradient: isActive ? LinearGradient(colors: gradients) : null,
                color: isActive ? null : (dark ? AppTheme.dCard : Colors.white),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isActive ? Colors.transparent : gradients[0].withOpacity(0.3), width: 1.5),
                boxShadow: [BoxShadow(color: gradients[0].withOpacity(0.15), blurRadius: 16)],
              ), child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(width: 48, height: 48, decoration: BoxDecoration(color: isActive ? Colors.white24 : gradients[0].withOpacity(0.12), borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: isActive ? Colors.white : gradients[0], size: 26)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(pName, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: isActive ? Colors.white : null)),
                    Text('\$${plan['price_usd']}/month', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: isActive ? Colors.white70 : gradients[0])),
                  ])),
                  if (isActive) Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)), child: const Text('Active', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700))),
                ]),
                const SizedBox(height: 14),
                ...features.map((f) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [Icon(Icons.check_circle_rounded, color: isActive ? Colors.white : gradients[0], size: 18), const SizedBox(width: 8), Expanded(child: Text(f, style: TextStyle(fontSize: 13, color: isActive ? Colors.white : null, height: 1.3)))]))),
                const SizedBox(height: 14),
                if (isActive)
                  Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(12)), child: const Text('Currently Active', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14), textAlign: TextAlign.center))
                else SizedBox(width: double.infinity, child: ElevatedButton(
                  onPressed: isActivating ? null : () => _showPaymentMethods(context, plan),
                  style: ElevatedButton.styleFrom(backgroundColor: gradients[0], padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: isActivating ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)), SizedBox(width: 8), Text('Processing...')])
                    : Text('Subscribe • \$${plan['price_usd']}/mo', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Colors.white)),
                )),
              ])));
            }),

            const SizedBox(height: 10),
            const Center(child: Text('Cancel anytime • No hidden fees\nStripe • PayPal • Flutterwave', style: TextStyle(color: Colors.grey, fontSize: 11), textAlign: TextAlign.center)),
            const SizedBox(height: 30),
          ]);
        },
      ),
    );
  }
}

class _PMBtn extends StatelessWidget {
  final String icon, label, sub; final VoidCallback onTap;
  const _PMBtn(this.icon, this.label, this.sub, this.onTap);
  @override Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(12), child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), decoration: BoxDecoration(color: dark ? AppTheme.dSurf : const Color(0xFFF8F8F8), borderRadius: BorderRadius.circular(12)), child: Row(children: [Text(icon, style: const TextStyle(fontSize: 22)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)), Text(sub, style: const TextStyle(color: Colors.grey, fontSize: 11))])), const Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 18)])));
  }
}
