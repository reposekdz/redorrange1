import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../core/theme/app_theme.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/socket_service.dart';
import '../../../shared/utils/format_utils.dart';
import 'payment_screen.dart';

final walletProvider = FutureProvider.autoDispose<Map<String,dynamic>>((ref) async {
  final r = await ref.read(apiServiceProvider).get('/payments/wallet');
  return Map<String,dynamic>.from(r.data);
});

final packagesProvider = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  final r = await ref.read(apiServiceProvider).get('/payments/packages');
  return List<dynamic>.from(r.data['packages'] ?? []);
});

class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key});
  @override ConsumerState<WalletScreen> createState() => _WalletState();
}
class _WalletState extends ConsumerState<WalletScreen> with SingleTickerProviderStateMixin {
  late TabController _tc;
  @override void initState() {
    super.initState();
    _tc = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(socketServiceProvider).on('coins_credited', (_) { if (mounted) ref.refresh(walletProvider); });
    });
  }
  @override void dispose() { _tc.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final walletAsync = ref.watch(walletProvider);
    final pkgsAsync   = ref.watch(packagesProvider);
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: dark ? AppTheme.dBg : const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: const Text('Wallet', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
        actions: [
          TextButton.icon(onPressed: () => context.push('/payouts'), icon: const Icon(Icons.account_balance_rounded, size: 18, color: AppTheme.orange), label: const Text('Withdraw', style: TextStyle(color: AppTheme.orange, fontWeight: FontWeight.w700))),
        ],
        bottom: TabBar(controller: _tc, indicatorColor: AppTheme.orange, labelColor: AppTheme.orange, unselectedLabelColor: Colors.grey, labelStyle: const TextStyle(fontWeight: FontWeight.w600), tabs: const [Tab(text: 'Balance'), Tab(text: 'Buy Coins'), Tab(text: 'History')]),
      ),
      body: walletAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.orange)),
        error: (e, _) => Center(child: ElevatedButton(onPressed: () => ref.refresh(walletProvider), child: const Text('Retry'))),
        data: (data) {
          final w = Map<String,dynamic>.from(data['wallet'] as Map? ?? {});
          final txns = List<dynamic>.from(data['transactions'] ?? []);
          final sub  = data['subscription'] as Map?;
          final coins = w['coins'] as int? ?? 0;
          return TabBarView(controller: _tc, children: [
            _BalanceTab(w: w, coins: coins, txns: txns, sub: sub, dark: dark, onRefresh: () => ref.refresh(walletProvider)),
            pkgsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.orange)),
              error: (_, __) => Center(child: ElevatedButton(onPressed: () => ref.refresh(packagesProvider), child: const Text('Retry'))),
              data: (pkgs) => _BuyCoinsTab(packages: pkgs, dark: dark, onRefresh: () { ref.refresh(walletProvider); _tc.animateTo(0); }),
            ),
            _HistoryTab(txns: txns, dark: dark),
          ]);
        },
      ),
    );
  }
}

class _BalanceTab extends StatelessWidget {
  final Map w; final int coins; final List txns; final Map? sub; final bool dark; final VoidCallback onRefresh;
  const _BalanceTab({required this.w, required this.coins, required this.txns, required this.sub, required this.dark, required this.onRefresh});
  @override Widget build(BuildContext context) => RefreshIndicator(color: AppTheme.orange, onRefresh: () async => onRefresh(), child: ListView(padding: const EdgeInsets.all(16), children: [
    Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFFFF6B35), Color(0xFFE85520)]), borderRadius: BorderRadius.all(Radius.circular(22))), padding: const EdgeInsets.all(22), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [const Icon(Icons.monetization_on_rounded, color: Colors.white70, size: 16), const SizedBox(width: 5), const Text('Available Balance', style: TextStyle(color: Colors.white70, fontSize: 12))]),
      const SizedBox(height: 8),
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [Text(FormatUtils.count(coins), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 46, letterSpacing: -1.5)), const Padding(padding: EdgeInsets.only(bottom: 9, left: 7), child: Text('coins', style: TextStyle(color: Colors.white70, fontSize: 15)))]),
      Text('≈ \$${(coins * 0.005).toStringAsFixed(2)} USD', style: const TextStyle(color: Colors.white60, fontSize: 13)),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: _WS(FormatUtils.count(w['total_earned'] as int? ?? 0), 'Earned', Icons.trending_up_rounded)),
        Container(width: 1, height: 40, color: Colors.white20),
        Expanded(child: _WS(FormatUtils.count(w['locked_coins'] as int? ?? 0), 'In Escrow', Icons.lock_rounded)),
        Container(width: 1, height: 40, color: Colors.white20),
        Expanded(child: _WS(FormatUtils.count(w['total_spent'] as int? ?? 0), 'Spent', Icons.shopping_bag_rounded)),
      ]),
    ])),
    const SizedBox(height: 16),
    Row(children: [
      Expanded(child: _QB(Icons.add_rounded, 'Buy Coins', AppTheme.orange, () => context.go('/wallet'))),
      const SizedBox(width: 10),
      Expanded(child: _QB(Icons.card_giftcard_rounded, 'Send Gift', const Color(0xFF9C27B0), () => context.push('/gifts'))),
      const SizedBox(width: 10),
      Expanded(child: _QB(Icons.account_balance_rounded, 'Withdraw', const Color(0xFF2196F3), () => context.push('/payouts'))),
      const SizedBox(width: 10),
      Expanded(child: _QB(Icons.workspace_premium_rounded, 'Premium', const Color(0xFFFFB300), () => context.push('/subscription'))),
    ]),
    const SizedBox(height: 16),
    if (sub != null)
      Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF9C27B0), Color(0xFF673AB7)]), borderRadius: BorderRadius.circular(14)), child: Row(children: [const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 24), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(sub['plan_name']??'Premium', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)), Text('Expires ${sub['expires_at']?.toString().substring(0,10)??'—'}', style: const TextStyle(color: Colors.white60, fontSize: 11))])), TextButton(onPressed: () => context.push('/subscription'), child: const Text('Manage', style: TextStyle(color: Colors.white70, fontSize: 12)))]))
    else
      GestureDetector(onTap: () => context.push('/subscription'), child: Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF9C27B0), Color(0xFF673AB7)]), borderRadius: BorderRadius.circular(14)), child: const Row(children: [Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 24), SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Go Premium', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)), Text('Verified badge + 500 coins/mo + No ads', style: TextStyle(color: Colors.white70, fontSize: 11))])), Padding(padding: EdgeInsets.all(8), child: Text('From \$4.99', style: TextStyle(color: Colors.white70, fontSize: 12)))]))),
    const SizedBox(height: 16),
    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Recent Activity', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)), TextButton(onPressed: onRefresh, child: const Text('Refresh', style: TextStyle(color: AppTheme.orange)))]),
    const SizedBox(height: 8),
    if (txns.isEmpty) const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('No transactions yet', style: TextStyle(color: Colors.grey))))
    else ...txns.take(6).map((t) => _TxnTile(t: t, dark: dark)),
  ]));
}

class _WS extends StatelessWidget {
  final String v, l; final IconData i;
  const _WS(this.v, this.l, this.i);
  @override Widget build(BuildContext _) => Column(children: [Icon(i, color: Colors.white60, size: 14), const SizedBox(height: 2), Text(v, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)), Text(l, style: const TextStyle(color: Colors.white60, fontSize: 9))]);
}

class _QB extends StatelessWidget {
  final IconData i; final String l; final Color c; final VoidCallback t;
  const _QB(this.i, this.l, this.c, this.t);
  @override Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(onTap: t, child: Container(padding: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(14)), child: Column(children: [Container(width: 36, height: 36, decoration: BoxDecoration(color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(10)), child: Icon(i, color: c, size: 19)), const SizedBox(height: 5), Text(l, style: TextStyle(color: c, fontWeight: FontWeight.w600, fontSize: 10), textAlign: TextAlign.center)])));
  }
}

class _BuyCoinsTab extends StatelessWidget {
  final List packages; final bool dark; final VoidCallback onRefresh;
  const _BuyCoinsTab({required this.packages, required this.dark, required this.onRefresh});
  @override Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(14), children: [
    Container(padding: const EdgeInsets.all(12), margin: const EdgeInsets.only(bottom: 14), decoration: BoxDecoration(color: AppTheme.orangeSurf, borderRadius: BorderRadius.circular(12)), child: const Row(children: [Icon(Icons.info_outline_rounded, color: AppTheme.orange, size: 18), SizedBox(width: 8), Expanded(child: Text('Coins work across gifts, marketplace, tips and live streams.', style: TextStyle(color: AppTheme.orangeDark, fontSize: 12)))])),
    GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 0.82, crossAxisSpacing: 12, mainAxisSpacing: 12),
      itemCount: packages.length,
      itemBuilder: (_, i) {
        final p = packages[i];
        final bonus = p['bonus_coins'] as int? ?? 0;
        final isBest = i == 3;
        return GestureDetector(
          onTap: () async {
            final result = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => PaymentScreen(
              targetType: PaymentTarget.coins,
              targetId: p['id'] as String,
              priceUsd: double.parse('${p['price_usd']}'),
              title: p['name'] as String,
              coins: p['coins'] as int,
              bonusCoins: bonus,
            )));
            if (result == true) onRefresh();
          },
          child: Container(decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: isBest ? AppTheme.orange : Colors.transparent, width: 2), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]), child: Stack(children: [
            Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Row(children: [const Text('🪙', style: TextStyle(fontSize: 28)), const Spacer(), if (isBest) Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: AppTheme.orange, borderRadius: BorderRadius.circular(8)), child: const Text('BEST', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)))]),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p['name']??'', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 4),
                Text(FormatUtils.count(p['coins'] as int? ?? 0), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: AppTheme.orange)),
                const Text('coins', style: TextStyle(color: Colors.grey, fontSize: 11)),
                if (bonus > 0) Text('+$bonus bonus', style: const TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.w600)),
              ]),
              Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 9), decoration: const BoxDecoration(gradient: LinearGradient(colors: [AppTheme.orange, AppTheme.orangeDark]), borderRadius: BorderRadius.all(Radius.circular(10))), child: Text('\$${double.parse('${p['price_usd']}').toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14), textAlign: TextAlign.center)),
            ])),
          ])),
        );
      },
    ),
    const SizedBox(height: 16),
    const Center(child: Text('🔒  SSL Secured  •  PCI DSS Compliant', style: TextStyle(color: Colors.grey, fontSize: 11))),
    const SizedBox(height: 4),
    const Center(child: Text('Powered by  Stripe  •  PayPal  •  Flutterwave', style: TextStyle(color: Colors.grey, fontSize: 11))),
  ]);
}

class _HistoryTab extends StatelessWidget {
  final List txns; final bool dark;
  const _HistoryTab({required this.txns, required this.dark});
  @override Widget build(BuildContext context) => txns.isEmpty
    ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.receipt_long_rounded, size: 72, color: Colors.grey), SizedBox(height: 16), Text('No transactions yet', style: TextStyle(color: Colors.grey, fontSize: 16))]))
    : ListView.separated(padding: const EdgeInsets.all(12), itemCount: txns.length, separatorBuilder: (_, __) => const SizedBox(height: 6), itemBuilder: (_, i) => _TxnTile(t: txns[i], dark: dark, full: true));
}

class _TxnTile extends StatelessWidget {
  final dynamic t; final bool dark; final bool full;
  const _TxnTile({required this.t, required this.dark, this.full = false});
  IconData get _icon { switch(t['type']) { case 'purchase': return Icons.add_circle_rounded; case 'gift_sent': return Icons.send_rounded; case 'gift_received': return Icons.card_giftcard_rounded; case 'withdrawal': return Icons.account_balance_rounded; case 'subscription_bonus': return Icons.workspace_premium_rounded; default: return Icons.monetization_on_rounded; } }
  Color  get _color { switch(t['type']) { case 'purchase': return Colors.green; case 'gift_sent': return Colors.orange; case 'gift_received': return const Color(0xFF9C27B0); case 'withdrawal': return const Color(0xFF2196F3); default: return AppTheme.orange; } }
  bool   get _isCredit => ['purchase','gift_received','bonus','reward','subscription_bonus','escrow_released'].contains(t['type']);
  @override Widget build(BuildContext _) => Container(
    padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(12)),
    child: Row(children: [
      Container(width: 42, height: 42, decoration: BoxDecoration(color: _color.withOpacity(0.1), borderRadius: BorderRadius.circular(11)), child: Icon(_icon, color: _color, size: 22)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t['description']??t['type']??'', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis), const SizedBox(height: 2), Text(timeago.format(DateTime.tryParse(t['created_at']??'')??DateTime.now()), style: const TextStyle(fontSize: 11, color: Colors.grey))])),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text('${_isCredit ? '+' : '-'}${FormatUtils.count((t['amount'] as num? ?? 0).toInt())}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: _isCredit ? Colors.green : Colors.red)),
        const Text('coins', style: TextStyle(fontSize: 10, color: Colors.grey)),
      ]),
    ]),
  );
}
