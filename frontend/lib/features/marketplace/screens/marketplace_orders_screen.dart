import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:convert';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/utils/format_utils.dart';

class MarketplaceOrdersScreen extends ConsumerStatefulWidget {
  const MarketplaceOrdersScreen({super.key});
  @override ConsumerState<MarketplaceOrdersScreen> createState() => _S();
}

class _S extends ConsumerState<MarketplaceOrdersScreen> with SingleTickerProviderStateMixin {
  late TabController _tc;
  @override void initState() { super.initState(); _tc = TabController(length: 2, vsync: this); }
  @override void dispose() { _tc.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Marketplace Orders', style: TextStyle(fontWeight: FontWeight.w800)),
        bottom: TabBar(controller: _tc, tabs: const [Tab(text: 'Purchases'), Tab(text: 'Sales')], indicatorColor: AppTheme.orange, labelColor: AppTheme.orange),
      ),
      body: TabBarView(controller: _tc, children: [
        const _OrderList(type: 'purchases'),
        const _OrderList(type: 'sales'),
      ]),
    );
  }
}

class _OrderList extends ConsumerStatefulWidget {
  final String type;
  const _OrderList({required this.type});
  @override ConsumerState<_OrderList> createState() => _OL();
}

class _OL extends ConsumerState<_OrderList> {
  List<dynamic> _orders = []; bool _l = true;
  @override void initState() { super.initState(); _load(); }
  
  Future<void> _load() async {
    try {
      final path = widget.type == 'purchases' ? '/marketplace/user/orders' : '/marketplace/user/sales';
      final r = await ref.read(apiServiceProvider).get(path);
      setState(() { _orders = r.data['orders'] ?? []; _l = false; });
    } catch (_) { setState(() => _l = false); }
  }

  Future<void> _updateStatus(String orderId, String action, {String? tracking}) async {
    try {
      final path = '/marketplace/escrow/$orderId/$action';
      await ref.read(apiServiceProvider).post(path, data: tracking != null ? {'tracking_number': tracking} : {});
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_l) return const Center(child: CircularProgressIndicator(color: AppTheme.orange));
    if (_orders.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.shopping_basket_outlined, size: 60, color: Colors.grey), const SizedBox(height: 16), Text('No ${widget.type} found', style: const TextStyle(color: Colors.grey))]));

    return RefreshIndicator(
      onRefresh: _load,
      color: AppTheme.orange,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _orders.length,
        itemBuilder: (_, i) => _OrderTile(order: _orders[i], type: widget.type, onAction: _updateStatus),
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  final Map<String, dynamic> order;
  final String type;
  final Function(String, String, {String? tracking}) onAction;

  const _OrderTile({required this.order, required this.type, required this.onAction});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final status = order['status'] ?? 'pending';
    final isBuyer = type == 'purchases';
    
    List<String> imgs = [];
    try { imgs = List<String>.from(order['images'] is String ? jsonDecode(order['images']) : (order['images'] ?? [])); } catch (_) {}

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: Row(children: [
          ClipRRect(borderRadius: BorderRadius.circular(12),
            child: imgs.isNotEmpty 
              ? CachedNetworkImage(imageUrl: imgs[0], width: 70, height: 70, fit: BoxFit.cover)
              : Container(width: 70, height: 70, color: AppTheme.orangeSurf, child: const Icon(Icons.shopping_bag, color: AppTheme.orange))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(order['title'] ?? 'Marketplace Item', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(FormatUtils.price(double.tryParse(order['price']?.toString() ?? ''), order['currency'] ?? 'USD'), style: const TextStyle(color: AppTheme.orange, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            _StatusBadge(status),
          ])),
        ])),
        const Divider(height: 1),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), child: Row(children: [
          Text('Order #${order['id'].toString().substring(0, 8)}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
          const Spacer(),
          if (!isBuyer && status == 'funded') TextButton.icon(onPressed: () => onAction(order['id'], 'ship'), icon: const Icon(Icons.local_shipping_rounded, size: 16), label: const Text('Mark Shipped')),
          if (!isBuyer && status == 'in_transit') TextButton.icon(onPressed: () => onAction(order['id'], 'deliver'), icon: const Icon(Icons.check_circle_rounded, size: 16), label: const Text('Mark Delivered')),
          if (isBuyer && (status == 'delivered' || status == 'in_transit' || status == 'funded')) TextButton.icon(onPressed: () => onAction(order['id'], 'confirm'), icon: const Icon(Icons.verified_rounded, size: 16), label: const Text('Confirm Receipt'), style: TextButton.styleFrom(foregroundColor: Colors.green)),
          if (isBuyer && status != 'completed' && status != 'disputed') TextButton(onPressed: () => onAction(order['id'], 'dispute'), child: const Text('Dispute', style: TextStyle(color: Colors.red, fontSize: 12))),
          if (status == 'completed') const Text('Completed', style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
        ])),
      ]),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge(this.status);
  @override Widget build(BuildContext _) {
    Color c = Colors.grey;
    String l = status.toUpperCase();
    switch(status) {
      case 'funded':      c = Colors.blue; l = 'PAID (ESCROW)'; break;
      case 'in_transit':  c = Colors.orange; l = 'SHIPPED'; break;
      case 'delivered':   c = Colors.green; l = 'DELIVERED'; break;
      case 'completed':   c = Colors.teal; l = 'COMPLETED'; break;
      case 'disputed':    c = Colors.red; l = 'DISPUTED'; break;
    }
    return Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Text(l, style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 10)));
  }
}
