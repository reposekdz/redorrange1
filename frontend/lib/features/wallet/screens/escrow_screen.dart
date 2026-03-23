import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/widgets/app_avatar.dart';
import '../../../shared/utils/format_utils.dart';

final _escrowProv = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  final r = await ref.read(apiServiceProvider).get('/escrow/orders');
  return List<dynamic>.from(r.data['orders'] ?? []);
});

class EscrowScreen extends ConsumerStatefulWidget {
  const EscrowScreen({super.key});
  @override ConsumerState<EscrowScreen> createState() => _S();
}
class _S extends ConsumerState<EscrowScreen> with SingleTickerProviderStateMixin {
  late TabController _tc;
  @override void initState() { super.initState(); _tc = TabController(length: 2, vsync: this); }
  @override void dispose() { _tc.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final orders = ref.watch(_escrowProv);
    final me     = ref.watch(currentUserProvider);
    final dark   = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Secure Escrow', style: TextStyle(fontWeight: FontWeight.w800)),
        bottom: TabBar(controller: _tc, indicatorColor: AppTheme.orange, labelColor: AppTheme.orange, unselectedLabelColor: Colors.grey, tabs: const [Tab(text: 'Buying'), Tab(text: 'Selling')]),
      ),
      body: Column(children: [
        // Info banner
        Container(margin: const EdgeInsets.all(12), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: AppTheme.orangeSurf, borderRadius: BorderRadius.circular(12)), child: Row(children: [const Icon(Icons.verified_user_rounded, color: AppTheme.orange, size: 20), const SizedBox(width: 10), const Expanded(child: Text('Your money is held safely until delivery is confirmed. 5% platform fee applies.', style: TextStyle(color: AppTheme.orangeDark, fontSize: 12, height: 1.4)))])),

        Expanded(child: orders.when(
          loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.orange)),
          error: (e, _) => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.error_outline_rounded, size: 56, color: Colors.grey), const SizedBox(height: 12), ElevatedButton(onPressed: () => ref.refresh(_escrowProv), child: const Text('Retry'))])),
          data: (list) {
            final buying  = list.where((o) => o['buyer_id'] == me?.id).toList();
            final selling = list.where((o) => o['seller_id'] == me?.id).toList();
            return TabBarView(controller: _tc, children: [
              _OrderList(orders: buying,  role: 'buyer',  onRefresh: () => ref.refresh(_escrowProv)),
              _OrderList(orders: selling, role: 'seller', onRefresh: () => ref.refresh(_escrowProv)),
            ]);
          },
        )),
      ]),
    );
  }
}

class _OrderList extends ConsumerWidget {
  final List<dynamic> orders; final String role; final VoidCallback onRefresh;
  const _OrderList({required this.orders, required this.role, required this.onRefresh});

  @override Widget build(BuildContext context, WidgetRef ref) {
    if (orders.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.security_rounded, size: 72, color: Colors.grey), const SizedBox(height: 16),
      Text('No ${role == 'buyer' ? 'purchases' : 'sales'} yet', style: const TextStyle(color: Colors.grey, fontSize: 16)),
      const SizedBox(height: 8),
      Text(role == 'buyer' ? 'Browse marketplace and buy securely' : 'List items in marketplace', style: const TextStyle(color: Colors.grey, fontSize: 13)),
      const SizedBox(height: 14),
      ElevatedButton(onPressed: () => context.push('/marketplace'), child: Text(role == 'buyer' ? 'Browse Marketplace' : 'My Listings')),
    ]));

    return RefreshIndicator(
      color: AppTheme.orange,
      onRefresh: () async => onRefresh(),
      child: ListView.builder(padding: const EdgeInsets.all(12), itemCount: orders.length, itemBuilder: (_, i) => _OrderCard(order: orders[i], role: role, onRefresh: onRefresh)),
    );
  }
}

class _OrderCard extends ConsumerStatefulWidget {
  final dynamic order; final String role; final VoidCallback onRefresh;
  const _OrderCard({required this.order, required this.role, required this.onRefresh});
  @override ConsumerState<_OrderCard> createState() => _OCS();
}
class _OCS extends ConsumerState<_OrderCard> {
  bool _loading = false;

  static const _statusColors = {
    'pending':   Color(0xFFFF9800), 'funded':      Color(0xFF2196F3),
    'in_transit': Color(0xFF9C27B0), 'delivered':  Color(0xFF009688),
    'completed':  Color(0xFF4CAF50), 'disputed':   Color(0xFFE53935),
    'refunded':   Color(0xFF607D8B), 'cancelled':  Colors.grey,
  };
  static const _statusLabels = {
    'pending':    'Awaiting Payment', 'funded':     'Paid • Awaiting Shipment',
    'in_transit': 'In Transit',       'delivered':  'Delivered',
    'completed':  'Completed',        'disputed':   'Under Dispute',
    'refunded':   'Refunded',         'cancelled':  'Cancelled',
  };

  Future<void> _action(String action, Map? data) async {
    setState(() => _loading = true);
    try {
      final oid = widget.order['id'];
      if (action == 'fund')    await ref.read(apiServiceProvider).post('/escrow/$oid/fund',    data: data ?? {});
      if (action == 'ship')    await ref.read(apiServiceProvider).post('/escrow/$oid/ship',    data: data ?? {});
      if (action == 'confirm') await ref.read(apiServiceProvider).post('/escrow/$oid/confirm', data: {});
      if (action == 'dispute') await ref.read(apiServiceProvider).post('/escrow/$oid/dispute', data: data ?? {});
      widget.onRefresh();
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'))); }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final o    = widget.order;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final status = o['status'] as String? ?? 'pending';
    final statusColor = _statusColors[status] ?? Colors.grey;

    final images = () { try { final imgs = o['item_images']; if (imgs is String) return [imgs]; if (imgs is List) return List<String>.from(imgs); return <String>[]; } catch (_) { return <String>[]; } }();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        ListTile(contentPadding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
          leading: AppAvatar(url: widget.role == 'buyer' ? o['seller_avatar'] : o['buyer_avatar'], size: 42, username: widget.role == 'buyer' ? o['seller_name'] : o['buyer_name']),
          title: Text(widget.role == 'buyer' ? (o['seller_name'] ?? 'Seller') : (o['buyer_name'] ?? 'Buyer'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          subtitle: Text(timeago.format(DateTime.tryParse(o['created_at'] ?? '') ?? DateTime.now()), style: const TextStyle(fontSize: 11)),
          trailing: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: statusColor.withOpacity(0.12), borderRadius: BorderRadius.circular(20)), child: Text(_statusLabels[status] ?? status, style: TextStyle(color: statusColor, fontWeight: FontWeight.w700, fontSize: 10))),
        ),

        // Item info
        Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 10), child: Row(children: [
          ClipRRect(borderRadius: BorderRadius.circular(10), child: images.isNotEmpty ? Image.network(images[0], width: 52, height: 52, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(width: 52, height: 52, color: AppTheme.orangeSurf)) : Container(width: 52, height: 52, color: AppTheme.orangeSurf, child: const Icon(Icons.shopping_bag_rounded, color: AppTheme.orange))),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(o['item_title'] ?? 'Item', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
            Text('$${o['amount_usd']} • Fee: $${o['platform_fee']}', style: const TextStyle(color: Colors.grey, fontSize: 11)),
            if (widget.role == 'seller') Text('You receive: $${o['seller_receives']}', style: const TextStyle(color: AppTheme.orange, fontWeight: FontWeight.w600, fontSize: 12)),
          ])),
        ])),

        // Tracking if in transit
        if (o['tracking_number'] != null) Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 8), child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(color: const Color(0xFF9C27B0).withOpacity(0.08), borderRadius: BorderRadius.circular(10)), child: Row(children: [const Icon(Icons.local_shipping_rounded, color: Color(0xFF9C27B0), size: 16), const SizedBox(width: 8), Expanded(child: Text('Tracking: ${o['tracking_number']}', style: const TextStyle(fontSize: 12, color: Color(0xFF9C27B0), fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis))]))),

        // Auto-release timer
        if (['funded','in_transit'].contains(status) && o['auto_release_at'] != null) Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 8), child: Row(children: [const Icon(Icons.timer_rounded, size: 13, color: Colors.grey), const SizedBox(width: 4), Text('Auto-release ${timeago.format(DateTime.tryParse(o['auto_release_at'] ?? '') ?? DateTime.now())}', style: const TextStyle(fontSize: 11, color: Colors.grey))]),),

        // Action buttons
        if (status != 'completed' && status != 'cancelled' && status != 'refunded') Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 14), child: _loading ? const Center(child: CircularProgressIndicator(color: AppTheme.orange, strokeWidth: 2)) : Wrap(spacing: 8, children: [
          if (widget.role == 'buyer' && status == 'pending')
            ElevatedButton.icon(onPressed: () => _fund(), icon: const Icon(Icons.payment_rounded, size: 16), label: const Text('Fund Escrow'), style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), textStyle: const TextStyle(fontSize: 12))),
          if (widget.role == 'seller' && status == 'funded')
            ElevatedButton.icon(onPressed: () => _ship(), icon: const Icon(Icons.local_shipping_rounded, size: 16), label: const Text('Mark Shipped'), style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), textStyle: const TextStyle(fontSize: 12))),
          if (widget.role == 'buyer' && ['in_transit','funded'].contains(status))
            ElevatedButton.icon(onPressed: () => _action('confirm', null), icon: const Icon(Icons.verified_rounded, size: 16), label: const Text('Confirm Delivery'), style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), textStyle: const TextStyle(fontSize: 12))),
          if (['funded','in_transit'].contains(status))
            OutlinedButton.icon(onPressed: () => _dispute(), icon: const Icon(Icons.gavel_rounded, size: 16, color: Colors.red), label: const Text('Dispute', style: TextStyle(color: Colors.red, fontSize: 12)), style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8))),
          OutlinedButton.icon(onPressed: () => context.push('/escrow/${widget.order['id']}'), icon: const Icon(Icons.info_outline_rounded, size: 16), label: const Text('Details', style: TextStyle(fontSize: 12)), style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8))),
        ])),
      ]),
    );
  }

  void _fund() {
    showDialog(context: context, builder: (_) {
      final ctrl = TextEditingController();
      String method = 'card';
      return StatefulBuilder(builder: (_, set) => AlertDialog(
        title: const Text('Fund Escrow'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Amount: $${widget.order['amount_usd']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppTheme.orange)),
          const SizedBox(height: 12),
          TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Payment Reference (optional)', hintText: 'Transaction ID, receipt...')),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(value: method, decoration: const InputDecoration(labelText: 'Payment Method'), items: const [DropdownMenuItem(value: 'card', child: Text('Credit/Debit Card')), DropdownMenuItem(value: 'mtn', child: Text('MTN MoMo')), DropdownMenuItem(value: 'airtel', child: Text('Airtel Money')), DropdownMenuItem(value: 'paypal', child: Text('PayPal'))], onChanged: (v) => set(() => method = v!)),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), ElevatedButton(onPressed: () { Navigator.pop(context); _action('fund', {'payment_ref': ctrl.text, 'payment_method': method}); }, child: const Text('Fund Now'))],
      ));
    });
  }

  void _ship() {
    showDialog(context: context, builder: (_) {
      final trackCtrl = TextEditingController(); final carrierCtrl = TextEditingController();
      return AlertDialog(title: const Text('Shipping Details'), content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: carrierCtrl, decoration: const InputDecoration(labelText: 'Carrier (DHL, FedEx, etc.)')),
        const SizedBox(height: 8),
        TextField(controller: trackCtrl, decoration: const InputDecoration(labelText: 'Tracking Number')),
      ]), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), ElevatedButton(onPressed: () { Navigator.pop(context); _action('ship', {'tracking_number': trackCtrl.text, 'carrier': carrierCtrl.text}); }, child: const Text('Confirm Shipment'))]);
    });
  }

  void _dispute() {
    showDialog(context: context, builder: (_) {
      final ctrl = TextEditingController();
      return AlertDialog(title: const Text('Open Dispute', style: TextStyle(color: Colors.red)), content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Describe the issue. Our team will review within 24 hours.'),
        const SizedBox(height: 10),
        TextField(controller: ctrl, maxLines: 4, decoration: const InputDecoration(hintText: 'Explain what went wrong...', border: OutlineInputBorder())),
      ]), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), ElevatedButton(onPressed: () { if (ctrl.text.trim().isEmpty) return; Navigator.pop(context); _action('dispute', {'reason': ctrl.text.trim()}); }, style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('Open Dispute'))]);
    });
  }
}
