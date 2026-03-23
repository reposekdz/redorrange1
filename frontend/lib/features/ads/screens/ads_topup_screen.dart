import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/api_service.dart';
import '../../wallet/screens/payment_screen.dart';

class AdsTopupScreen extends ConsumerStatefulWidget {
  const AdsTopupScreen({super.key});
  @override ConsumerState<AdsTopupScreen> createState() => _S();
}

class _S extends ConsumerState<AdsTopupScreen> {
  final _amountCtrl = TextEditingController(text: '10.00');
  bool _loading = false;
  String? _accountId;

  @override void initState() { super.initState(); _loadAccount(); }
  @override void dispose() { _amountCtrl.dispose(); super.dispose(); }

  Future<void> _loadAccount() async {
    setState(() => _loading = true);
    try {
      final r = await ref.read(apiServiceProvider).get('/ads/dashboard');
      if (r.data['has_account'] == true) {
        setState(() { _accountId = r.data['account']['id']; _loading = false; });
      } else {
        setState(() => _loading = false);
      }
    } catch (_) { setState(() => _loading = false); }
  }

  Future<void> _proceed() async {
    final amt = double.tryParse(_amountCtrl.text) ?? 0;
    if (amt < 5) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Minimum top-up is $5.00')));
      return;
    }
    if (_accountId == null) return;

    final result = await context.push('/payment', extra: {
      'targetType': PaymentTarget.adTopup,
      'targetId':   _accountId,
      'priceUsd':   amt,
      'title':      'Ad Account Top-up',
      'subtitle':   'Funds for your ad campaigns',
    });

    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account funded successfully!')));
      context.pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: dark ? AppTheme.dBg : const Color(0xFFF4F6F9),
      appBar: AppBar(title: const Text('Top up Ad Account', style: TextStyle(fontWeight: FontWeight.w800))),
      body: _loading ? const Center(child: CircularProgressIndicator(color: AppTheme.orange))
        : _accountId == null ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.error_outline_rounded, size: 64, color: Colors.grey), const SizedBox(height: 16), const Text('Ad account not found'), const SizedBox(height: 16), ElevatedButton(onPressed: () => context.pop(), child: const Text('Go Back'))]))
        : SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppTheme.orange.withOpacity(0.1))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Funding Amount (USD)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 12),
              TextField(
                controller: _amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: AppTheme.orange),
                decoration: InputDecoration(
                  prefixText: '\$ ',
                  prefixStyle: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppTheme.orange),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  fillColor: Colors.transparent,
                  hintText: '0.00',
                ),
              ),
              const Divider(),
              const SizedBox(height: 10),
              const Text('Suggested amounts:', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 10),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                _chip('10.00'), _chip('25.00'), _chip('50.00'), _chip('100.00'),
              ]),
            ])),
            const SizedBox(height: 24),
            const Text('Information', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 12),
            _infoRow(Icons.bolt_rounded, 'Funds are added instantly to your balance.'),
            _infoRow(Icons.verified_user_rounded, 'Payments are 100% secure and encrypted.'),
            _infoRow(Icons.receipt_long_rounded, 'An invoice will be generated for your records.'),
            const SizedBox(height: 32),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: _proceed,
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              child: const Text('Proceed to Payment', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            )),
            const SizedBox(height: 20),
            const Center(child: Text('Minimum \$5.00 top-up required.', style: TextStyle(fontSize: 11, color: Colors.grey))),
        ])),
    );
  }

  Widget _chip(String amt) => ActionChip(
    label: Text('\$$amt', style: TextStyle(color: _amountCtrl.text == amt ? Colors.white : AppTheme.orange, fontWeight: FontWeight.w700)),
    backgroundColor: _amountCtrl.text == amt ? AppTheme.orange : null,
    onPressed: () => setState(() => _amountCtrl.text = amt),
  );

  Widget _infoRow(IconData icon, String text) => Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(children: [Icon(icon, size: 18, color: AppTheme.orange), const SizedBox(width: 12), Expanded(child: Text(text, style: const TextStyle(fontSize: 13, height: 1.4)))]));
}
