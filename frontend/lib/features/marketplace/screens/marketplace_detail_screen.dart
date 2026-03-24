// marketplace_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/widgets/app_avatar.dart';
import '../../../shared/utils/format_utils.dart';
import 'dart:convert';
import '../../wallet/screens/payment_screen.dart';

class MarketplaceDetailScreen extends ConsumerStatefulWidget {
  final String itemId;
  const MarketplaceDetailScreen({super.key, required this.itemId});
  @override ConsumerState<MarketplaceDetailScreen> createState() => _S();
}
class _S extends ConsumerState<MarketplaceDetailScreen> {
  Map<String,dynamic>? _item; bool _l = true; int _imgIdx = 0;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try {
      final r = await ref.read(apiServiceProvider).get('/marketplace/${widget.itemId}');
      setState(() { _item = r.data['item']; _l = false; });
    } catch (_) { setState(() => _l = false); }
  }
  Future<void> _toggleSave() async {
    await ref.read(apiServiceProvider).post('/marketplace/${widget.itemId}/save');
    _load();
  }
  void _openChat() {
    if (_item == null) return;
    final seller = _item!['seller'] as Map<String,dynamic>? ?? {};
    context.push('/new-chat', extra: {'userId': seller['id'], 'name': seller['name']});
  }

  Future<void> _buyNow() async {
    if (_item == null) return;
    final item = _item!;
    final price = double.tryParse(item['price']?.toString() ?? '0') ?? 0;
    
    final result = await context.push('/payment', extra: {
      'targetType': PaymentTarget.marketplaceItem,
      'targetId':   item['id'],
      'priceUsd':   price,
      'title':      item['title'],
      'subtitle':   'Escrow Purchase — Held securely',
    });

    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Purchase successful! Item is now in escrow.')));
      context.push('/marketplace/orders'); // We'll create this next
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_l) return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppTheme.orange)));
    if (_item == null) return const Scaffold(body: Center(child: Text('Item not found')));
    final item = _item!;
    final me = ref.watch(currentUserProvider);
    final isMine = item['seller_id'] == me?.id;
    final dark = Theme.of(context).brightness == Brightness.dark;
    List<String> images = [];
    try { images = List<String>.from(item['images'] is String ? jsonDecode(item['images']) : (item['images'] ?? [])); } catch (_) {}
    final saved = item['is_saved'] == true || item['is_saved'] == 1;

    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverAppBar(expandedHeight: 320, pinned: true,
          leading: IconButton(icon: const Icon(Icons.arrow_back_rounded, color: Colors.white), onPressed: () => context.pop()),
          actions: [
            IconButton(icon: Icon(saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, color: Colors.white), onPressed: _toggleSave),
            IconButton(icon: const Icon(Icons.share_rounded, color: Colors.white), onPressed: () {}),
          ],
          flexibleSpace: FlexibleSpaceBar(background: images.isNotEmpty
            ? Stack(children: [
                PageView.builder(onPageChanged: (i) => setState(() => _imgIdx = i), itemCount: images.length,
                  itemBuilder: (_, i) => CachedNetworkImage(imageUrl: images[i], fit: BoxFit.cover, errorWidget: (_, __, ___) => Container(color: AppTheme.orangeSurf))),
                if (images.length > 1) Positioned(bottom: 12, left: 0, right: 0, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(images.length, (i) => Container(width: 7, height: 7, margin: const EdgeInsets.symmetric(horizontal: 3), decoration: BoxDecoration(shape: BoxShape.circle, color: i == _imgIdx ? Colors.white : Colors.white54))))),
              ])
            : Container(color: AppTheme.orangeSurf, child: const Center(child: Icon(Icons.store_rounded, size: 80, color: AppTheme.orange))))),
        SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Price + Title
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(FormatUtils.price(double.tryParse(item['price']?.toString() ?? ''), item['currency'] ?? 'USD'), style: const TextStyle(color: AppTheme.orange, fontWeight: FontWeight.w800, fontSize: 26)),
              const SizedBox(height: 4),
              Text(item['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
            ])),
            if (item['condition_type'] != null) Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: AppTheme.orangeSurf, borderRadius: BorderRadius.circular(20)), child: Text(item['condition_type'].toString().toUpperCase(), style: const TextStyle(color: AppTheme.orange, fontSize: 11, fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            if (item['category'] != null) Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: dark ? AppTheme.dCard : AppTheme.lInput, borderRadius: BorderRadius.circular(12)), child: Text(item['category'], style: const TextStyle(fontSize: 12))),
            if (item['location'] != null) ...[const SizedBox(width: 8), const Icon(Icons.location_on_rounded, size: 14, color: Colors.grey), Text(item['location'], style: const TextStyle(fontSize: 13, color: Colors.grey))],
          ]),
          const SizedBox(height: 16), const Divider(),
          // Description
          if (item['description'] != null && item['description'].toString().isNotEmpty) ...[
            const Text('Description', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 6),
            Text(item['description'], style: const TextStyle(fontSize: 14, height: 1.6)),
            const SizedBox(height: 16), const Divider(),
          ],
          // Seller info
          const Text('Seller', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 10),
          GestureDetector(onTap: () => context.push('/profile/${item['seller_id']}'), child: Row(children: [
            AppAvatar(url: item['avatar_url'], size: 50, username: item['username']),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Text(item['display_name'] ?? item['username'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)), if (item['is_verified'] == 1) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.verified_rounded, color: AppTheme.orange, size: 15))]),
              Text('@${item['username'] ?? ''}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
            ])),
            const Icon(Icons.chevron_right_rounded, color: Colors.grey),
          ])),
          const SizedBox(height: 20),
          Row(children: [
            const Icon(Icons.remove_red_eye_rounded, size: 14, color: Colors.grey),
            const SizedBox(width: 4),
            Text('${item['views_count'] ?? 0} views', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(width: 12),
            const Icon(Icons.access_time_rounded, size: 14, color: Colors.grey),
            const SizedBox(width: 4),
            Text(FormatUtils.relativeTime(item['created_at']), style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ]),
          if (isMine) ...[
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.edit_rounded), label: const Text('Edit Listing'))),
              const SizedBox(width: 10),
              Expanded(child: OutlinedButton.icon(onPressed: () async { await ref.read(apiServiceProvider).put('/marketplace/${widget.itemId}', data: {'status': 'sold'}); _load(); }, icon: const Icon(Icons.sell_rounded), label: const Text('Mark as Sold'), style: OutlinedButton.styleFrom(foregroundColor: Colors.green, side: const BorderSide(color: Colors.green)))),
            ]),
          ],
          const SizedBox(height: 100),
        ]))),
      ]),
      bottomNavigationBar: isMine ? null : Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        decoration: BoxDecoration(color: dark ? AppTheme.dSurf : Colors.white, border: Border(top: BorderSide(color: dark ? AppTheme.dDiv : AppTheme.lDiv, width: 0.5))),
        child: Row(children: [
          Expanded(child: OutlinedButton.icon(onPressed: _openChat, icon: const Icon(Icons.chat_rounded), label: const Text('Message'))),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: ElevatedButton.icon(onPressed: _buyNow, icon: const Icon(Icons.shopping_bag_rounded), label: const Text('Buy Now Escrow'))),
        ]),
      ),
    );
  }
}

// my_listings_screen.dart
class MyListingsScreen extends ConsumerStatefulWidget {
  const MyListingsScreen({super.key});
  @override ConsumerState<MyListingsScreen> createState() => _ML();
}
class _ML extends ConsumerState<MyListingsScreen> {
  List<dynamic> _items = []; bool _l = true;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final r = await ref.read(apiServiceProvider).get('/marketplace/user/my-listings');
    setState(() { _items = r.data['items'] ?? []; _l = false; });
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('My Listings', style: TextStyle(fontWeight: FontWeight.w800)),
      actions: [IconButton(icon: const Icon(Icons.add_rounded), onPressed: () => context.push('/marketplace/create'))]),
    body: _l ? const Center(child: CircularProgressIndicator(color: AppTheme.orange))
      : _items.isEmpty ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.sell_outlined, size: 72, color: Colors.grey),
          const SizedBox(height: 16), const Text('No listings yet', style: TextStyle(fontSize: 16, color: Colors.grey)),
          const SizedBox(height: 14), ElevatedButton.icon(onPressed: () => context.push('/marketplace/create'), icon: const Icon(Icons.add_rounded), label: const Text('Create Listing')),
        ]))
      : ListView.builder(padding: const EdgeInsets.all(16), itemCount: _items.length, itemBuilder: (_, i) {
          final it = _items[i];
          List<String> imgs = [];
          try { imgs = List<String>.from(it['images'] is String ? jsonDecode(it['images']) : (it['images'] ?? [])); } catch (_) {}
          final statusColor = it['status'] == 'active' ? Colors.green : it['status'] == 'sold' ? Colors.blue : Colors.grey;
          return Card(margin: const EdgeInsets.only(bottom: 10), child: InkWell(onTap: () => context.push('/marketplace/${it['id']}'), borderRadius: BorderRadius.circular(14), child: Row(children: [
            ClipRRect(borderRadius: const BorderRadius.horizontal(left: Radius.circular(14)),
              child: imgs.isNotEmpty ? CachedNetworkImage(imageUrl: imgs[0], width: 90, height: 90, fit: BoxFit.cover, errorWidget: (_, __, ___) => Container(width: 90, height: 90, color: AppTheme.orangeSurf)) : Container(width: 90, height: 90, color: AppTheme.orangeSurf, child: const Icon(Icons.image, color: AppTheme.orange))),
            Expanded(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(it['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis)),
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: Text((it['status'] ?? '').toUpperCase(), style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.w700))),
              ]),
              const SizedBox(height: 4),
              Text(FormatUtils.price(double.tryParse(it['price']?.toString() ?? ''), it['currency'] ?? 'USD'), style: const TextStyle(color: AppTheme.orange, fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 4),
              Row(children: [const Icon(Icons.remove_red_eye_rounded, size: 12, color: Colors.grey), const SizedBox(width: 3), Text('${it['views_count'] ?? 0} views', style: const TextStyle(fontSize: 11, color: Colors.grey)), const SizedBox(width: 10), Text(FormatUtils.relativeTime(it['created_at']), style: const TextStyle(fontSize: 11, color: Colors.grey))]),
            ]))),
          ])));
        }),
    floatingActionButton: FloatingActionButton(onPressed: () => context.push('/marketplace/create'), backgroundColor: AppTheme.orange, child: const Icon(Icons.add_rounded, color: Colors.white)),
  );
}
