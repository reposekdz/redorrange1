import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/utils/format_utils.dart';

class PayoutsScreen extends ConsumerStatefulWidget {
  const PayoutsScreen({super.key});
  @override ConsumerState<PayoutsScreen> createState() => _S();
}
class _S extends ConsumerState<PayoutsScreen> with SingleTickerProviderStateMixin {
  late TabController _tc;
  Map<String,dynamic>? _balance;
  List<dynamic> _history = [];
  bool _l = true;

  // Payout form
  String _method = 'mobile_money';
  String _network = 'mtn_rw';
  final _phoneCtrl   = TextEditingController();
  final _nameCtrl    = TextEditingController();
  final _acctCtrl    = TextEditingController();
  int _coinsToCash   = 1000;
  bool _submitting   = false;

  @override void initState() { super.initState(); _tc = TabController(length: 2, vsync: this); _load(); }
  @override void dispose() { _tc.dispose(); _phoneCtrl.dispose(); _nameCtrl.dispose(); _acctCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    try {
      final [br, hr] = await Future.wait([
        ref.read(apiServiceProvider).get('/payouts/balance'),
        ref.read(apiServiceProvider).get('/payouts/history'),
      ]);
      setState(() { _balance = Map<String,dynamic>.from(br.data); _history = hr.data['payouts'] ?? []; _l = false; });
    } catch (_) { setState(() => _l = false); }
  }

  Future<void> _requestPayout() async {
    if (_coinsToCache < 1000) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Minimum 1,000 coins to cash out'))); return; }
    if (_method == 'mobile_money' && _phoneCtrl.text.trim().isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Phone number required'))); return; }
    setState(() => _submitting = true);
    try {
      final r = await ref.read(apiServiceProvider).post('/payouts/request', data: {
        'coins_to_cash': _coinsToCache,
        'method': _method,
        if (_method == 'mobile_money') 'phone':   _phoneCtrl.text.trim(),
        if (_method == 'mobile_money') 'network': _network,
        if (_method == 'bank_transfer') 'account_number': _acctCtrl.text.trim(),
        if (_method == 'bank_transfer') 'account_name': _nameCtrl.text.trim(),
        'currency': 'RWF',
        'country': 'RW',
      });
      if (r.data['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.data['message'] ?? 'Payout initiated!'), backgroundColor: Colors.green, duration: const Duration(seconds: 5)));
        _load();
        _tc.animateTo(1);
      }
    } catch (e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red)); }
    if (mounted) setState(() => _submitting = false);
  }

  int get _coinsToCache => _coinsToCache2;
  int _coinsToCache2 = 1000;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cash Out', style: TextStyle(fontWeight: FontWeight.w800)),
        bottom: TabBar(controller: _tc, indicatorColor: AppTheme.orange, labelColor: AppTheme.orange, unselectedLabelColor: Colors.grey, tabs: const [Tab(text: 'Request Payout'), Tab(text: 'History')]),
      ),
      body: _l ? const Center(child: CircularProgressIndicator(color: AppTheme.orange))
        : TabBarView(controller: _tc, children: [
          // ── REQUEST PAYOUT
          SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Balance card
            Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF1A1A2E), Color(0xFF16213E)]), borderRadius: BorderRadius.circular(18)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Available to Cash Out', style: TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 8),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(FormatUtils.count(_balance?['coins'] as int? ?? 0), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 36)),
                const Padding(padding: EdgeInsets.only(bottom: 5, left: 6), child: Text('coins', style: TextStyle(color: Colors.white54, fontSize: 16))),
              ]),
              const SizedBox(height: 4),
              Text('≈ \$${_balance?['usd_value'] ?? '0.00'} USD', style: const TextStyle(color: Colors.white38, fontSize: 12)),
              const SizedBox(height: 8),
              Row(children: [const Icon(Icons.info_outline_rounded, color: Colors.white38, size: 13), const SizedBox(width: 5), const Text('100 coins = \$0.50 USD • Min 1,000 coins', style: TextStyle(color: Colors.white38, fontSize: 11))]),
            ])),
            const SizedBox(height: 20),

            const Text('Amount to Cash Out', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 8),
            // Coin slider
            Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(14)), child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(FormatUtils.count(_coinsToCache2), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 36, color: AppTheme.orange)),
                const Text(' coins', style: TextStyle(color: Colors.grey, fontSize: 16)),
              ]),
              Text('= \$${(_coinsToCache2 / 100 * 0.5).toStringAsFixed(2)} USD ≈ ${(_coinsToCache2 / 100 * 0.5 * 1220).round()} RWF', style: const TextStyle(color: AppTheme.orange, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Slider(
                value: _coinsToCache2.toDouble(),
                min: 1000, max: (_balance?['coins'] as int? ?? 1000).toDouble().clamp(1000, 100000),
                divisions: ((_balance?['coins'] as int? ?? 1000) - 1000) ~/ 100,
                activeColor: AppTheme.orange,
                onChanged: (v) => setState(() => _coinsToCache2 = (v ~/ 100) * 100),
              ),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('1,000 min', style: TextStyle(fontSize: 11, color: Colors.grey)), Text('${FormatUtils.count(_balance?['coins'] as int? ?? 0)} max', style: const TextStyle(fontSize: 11, color: Colors.grey))]),
            ])),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [for (final amt in [1000, 5000, 10000, 25000]) GestureDetector(onTap: () { if ((_balance?['coins'] as int? ?? 0) >= amt) setState(() => _coinsToCache2 = amt); }, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7), decoration: BoxDecoration(color: _coinsToCache2 == amt ? AppTheme.orange : (dark ? AppTheme.dCard : Colors.white), borderRadius: BorderRadius.circular(20)), child: Text('${FormatUtils.count(amt)} coins', style: TextStyle(color: _coinsToCache2 == amt ? Colors.white : null, fontWeight: FontWeight.w600, fontSize: 12))))]),
            const SizedBox(height: 20),

            const Text('Payout Method', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 10),

            // Method selector
            for (final (id, label, icon, desc) in [('mobile_money','Mobile Money',Icons.phone_android_rounded,'MTN, Airtel, M-Pesa'), ('bank_transfer','Bank Transfer',Icons.account_balance_rounded,'Any local bank')])
              GestureDetector(onTap: () => setState(() => _method = id), child: AnimatedContainer(duration: const Duration(milliseconds: 150), margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: _method == id ? AppTheme.orangeSurf : (dark ? AppTheme.dCard : Colors.white), borderRadius: BorderRadius.circular(14), border: Border.all(color: _method == id ? AppTheme.orange : Colors.transparent, width: 2)), child: Row(children: [Container(width: 42, height: 42, decoration: BoxDecoration(color: _method == id ? AppTheme.orange : Colors.grey.shade200, borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: _method == id ? Colors.white : Colors.grey, size: 22)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: _method == id ? AppTheme.orange : null)), Text(desc, style: const TextStyle(fontSize: 12, color: Colors.grey))])), if (_method == id) const Icon(Icons.check_circle_rounded, color: AppTheme.orange, size: 20)])),
            ),
            const SizedBox(height: 12),

            // Mobile money form
            if (_method == 'mobile_money') ...[
              const Text('Select Network', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final (net, label, flag) in [('mtn_rw','MTN Rwanda','🇷🇼'), ('airtel_rw','Airtel Rwanda','🇷🇼'), ('mpesa','M-Pesa Kenya','🇰🇪'), ('mtn_ug','MTN Uganda','🇺🇬'), ('airtel_ug','Airtel Uganda','🇺🇬')])
                  GestureDetector(onTap: () => setState(() => _network = net), child: AnimatedContainer(duration: const Duration(milliseconds: 150), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(color: _network == net ? AppTheme.orange : (dark ? AppTheme.dCard : Colors.white), borderRadius: BorderRadius.circular(20), border: Border.all(color: _network == net ? AppTheme.orange : Colors.grey.shade300)), child: Text('$flag $label', style: TextStyle(color: _network == net ? Colors.white : null, fontWeight: FontWeight.w600, fontSize: 12)))),
              ]),
              const SizedBox(height: 12),
              TextField(controller: _phoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Mobile Number *', hintText: '+250 7XX XXX XXX', prefixIcon: Icon(Icons.phone_rounded, size: 20))),
            ],

            // Bank transfer form
            if (_method == 'bank_transfer') ...[
              const SizedBox(height: 4),
              TextField(controller: _acctCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Account Number *', hintText: 'Enter your bank account number', prefixIcon: Icon(Icons.account_balance_rounded, size: 20))),
              const SizedBox(height: 10),
              TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Account Name *', hintText: 'Name on bank account', prefixIcon: Icon(Icons.person_rounded, size: 20))),
            ],

            const SizedBox(height: 20),
            // Fee info
            Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: dark ? AppTheme.dCard : AppTheme.lInput, borderRadius: BorderRadius.circular(12)), child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Coins to cash out'), Text(FormatUtils.count(_coinsToCache2))]),
              const SizedBox(height: 4),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Processing fee (0%)'), const Text('Free', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600))]),
              const Divider(height: 14),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('You receive', style: TextStyle(fontWeight: FontWeight.w700)), Text('\$${(_coinsToCache2 / 100 * 0.5).toStringAsFixed(2)} ≈ ${(_coinsToCache2 / 100 * 0.5 * 1220).round()} RWF', style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.orange))]),
            ])),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: _submitting ? null : _requestPayout,
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              child: _submitting ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)), SizedBox(width: 10), Text('Processing...')])
                : Text('Cash Out ${FormatUtils.count(_coinsToCache2)} Coins → ${(_coinsToCache2 / 100 * 0.5 * 1220).round()} RWF', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            )),
            const SizedBox(height: 8),
            const Center(child: Text('Arrives within 1-3 business days via Flutterwave', style: TextStyle(color: Colors.grey, fontSize: 11))),
            const SizedBox(height: 20),
          ])),

          // ── PAYOUT HISTORY
          _history.isEmpty ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.history_rounded, size: 64, color: Colors.grey), SizedBox(height: 12), Text('No payouts yet', style: TextStyle(color: Colors.grey))])) : ListView.builder(padding: const EdgeInsets.all(14), itemCount: _history.length, itemBuilder: (_, i) {
            final p = _history[i];
            final status = p['status'] as String? ?? 'pending';
            final statusColor = status == 'completed' ? Colors.green : status == 'processing' ? const Color(0xFF2196F3) : status == 'failed' ? Colors.red : Colors.orange;
            return Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(14)), child: Row(children: [
              Container(width: 42, height: 42, decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(11)), child: Icon(status == 'completed' ? Icons.check_rounded : Icons.schedule_rounded, color: statusColor, size: 22)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${FormatUtils.count(p['coins_cashed'] as int? ?? 0)} coins → ${p['amount_local']} ${p['currency']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                Text('${p['method']?.toString().replaceAll('_', ' ').toUpperCase() ?? ''} • ${p['phone'] ?? p['account_number'] ?? ''}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                Text(p['created_at']?.toString().split('T')[0] ?? '', style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ])),
              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: Text(status.toUpperCase(), style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w700))),
            ]));
          }),
        ]),
    );
  }
}
