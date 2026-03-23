import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:async';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/widgets/app_avatar.dart';
import '../../../shared/utils/format_utils.dart';

class MarketplaceScreen extends ConsumerStatefulWidget {
  const MarketplaceScreen({super.key});
  @override ConsumerState<MarketplaceScreen> createState() => _S();
}
class _S extends ConsumerState<MarketplaceScreen> with SingleTickerProviderStateMixin {
  late TabController _tc;
  List<dynamic> _items = [], _mine = []; bool _l = true;
  String _selectedCat = 'All'; String _q = '';
  Timer? _deb;
  final _searchCtrl = TextEditingController();
  static const _cats = ['All','Electronics','Clothing','Furniture','Vehicles','Books','Food','Services','Other'];

  @override void initState() { super.initState(); _tc = TabController(length: 3, vsync: this); _load(); }
  @override void dispose() { _tc.dispose(); _searchCtrl.dispose(); _deb?.cancel(); super.dispose(); }

  Future<void> _load([String? q, String? cat]) async {
    setState(() => _l = true);
    try {
      final params = <String,dynamic>{};
      if (q != null && q.isNotEmpty) params['q'] = q;
      if (cat != null && cat != 'All') params['category'] = cat;
      final [all, mine] = await Future.wait([
        ref.read(apiServiceProvider).get('/marketplace', q: params.isNotEmpty ? params : null),
        ref.read(apiServiceProvider).get('/marketplace/my-listings'),
      ]);
      setState(() { _items = all.data['items'] ?? []; _mine = mine.data['items'] ?? []; _l = false; });
    } catch (_) { setState(() => _l = false); }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Marketplace', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(icon: const Icon(Icons.add_circle_rounded, color: AppTheme.orange, size: 28), onPressed: () => context.push('/marketplace/create'), tooltip: 'Sell Item'),
        ],
        bottom: TabBar(controller: _tc, indicatorColor: AppTheme.orange, labelColor: AppTheme.orange, unselectedLabelColor: Colors.grey, tabs: const [Tab(text: 'Browse'), Tab(text: 'My Listings'), Tab(text: 'Saved')]),
      ),
      body: Column(children: [
        // Search + categories (Browse tab only)
        if (_tc.index == 0) ...[
          Padding(padding: const EdgeInsets.fromLTRB(12, 10, 12, 6), child: TextField(controller: _searchCtrl, onChanged: (v) { _q = v; _deb?.cancel(); _deb = Timer(const Duration(milliseconds: 400), () => _load(_q, _selectedCat)); }, decoration: InputDecoration(hintText: 'Search marketplace...', prefixIcon: const Icon(Icons.search_rounded, size: 20), suffixIcon: _q.isNotEmpty ? IconButton(icon: const Icon(Icons.close_rounded, size: 18), onPressed: () { _searchCtrl.clear(); _q = ''; _load(); }) : null))),
          SizedBox(height: 38, child: ListView.builder(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 10), itemCount: _cats.length, itemBuilder: (_, i) {
            final cat = _cats[i]; final sel = cat == _selectedCat;
            return GestureDetector(onTap: () { setState(() => _selectedCat = cat); _load(_q, cat); }, child: AnimatedContainer(duration: const Duration(milliseconds: 200), margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6), decoration: BoxDecoration(color: sel ? AppTheme.orange : (dark ? AppTheme.dCard : AppTheme.lInput), borderRadius: BorderRadius.circular(20)), child: Text(cat, style: TextStyle(color: sel ? Colors.white : null, fontWeight: sel ? FontWeight.w700 : FontWeight.w500, fontSize: 13))));
          })),
          const SizedBox(height: 6),
        ],
        Expanded(child: TabBarView(controller: _tc, children: [
          // Browse
          _l ? const Center(child: CircularProgressIndicator(color: AppTheme.orange)) : _items.isEmpty ? _Empty('No items found', Icons.shopping_bag_outlined) : RefreshIndicator(color: AppTheme.orange, onRefresh: () => _load(_q, _selectedCat), child: GridView.builder(padding: const EdgeInsets.all(10), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 0.72), itemCount: _items.length, itemBuilder: (_, i) => _ItemCard(item: _items[i]))),
          // My listings
          _mine.isEmpty ? _Empty('No listings yet. Start selling!', Icons.storefront_outlined, action: () => context.push('/marketplace/create'), actionLabel: 'Create Listing') : ListView.builder(itemCount: _mine.length, itemBuilder: (_, i) => _MyListing(item: _mine[i], onEdit: () {}, onDelete: () async { await ref.read(apiServiceProvider).delete('/marketplace/${_mine[i]['id']}').catchError((_){}); _load(); })),
          // Saved
          const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.bookmark_outline_rounded, size: 64, color: Colors.grey), SizedBox(height: 12), Text('Saved items will appear here', style: TextStyle(color: Colors.grey))])),
        ])),
      ]),
    );
  }
}

class _ItemCard extends StatelessWidget {
  final dynamic item;
  const _ItemCard({required this.item});
  @override Widget build(BuildContext context) {
    final images = List<dynamic>.from(item['images'] ?? []);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(onTap: () => context.push('/marketplace/${item['id']}'), child: Container(decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))]), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(14)), child: AspectRatio(aspectRatio: 1, child: images.isNotEmpty ? CachedNetworkImage(imageUrl: images[0].toString(), fit: BoxFit.cover, errorWidget: (_, __, ___) => Container(color: AppTheme.orangeSurf, child: const Icon(Icons.image_rounded, color: AppTheme.orange, size: 36))) : Container(color: AppTheme.orangeSurf, child: const Icon(Icons.image_rounded, color: AppTheme.orange, size: 36)))),
      Padding(padding: const EdgeInsets.all(10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(item['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 4),
        Text(FormatUtils.price(item['price'] != null ? double.tryParse(item['price'].toString()) : null, item['currency'] ?? 'USD'), style: const TextStyle(color: AppTheme.orange, fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(height: 3),
        if (item['location'] != null) Row(children: [const Icon(Icons.location_on_rounded, size: 11, color: Colors.grey), const SizedBox(width: 2), Flexible(child: Text(item['location'], style: const TextStyle(fontSize: 11, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis))]),
        if (item['condition_type'] != null) Container(margin: const EdgeInsets.only(top: 4), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: AppTheme.orangeSurf, borderRadius: BorderRadius.circular(8)), child: Text(item['condition_type'], style: const TextStyle(color: AppTheme.orange, fontSize: 10, fontWeight: FontWeight.w600))),
      ])),
    ])));
  }
}

class _MyListing extends StatelessWidget {
  final dynamic item; final VoidCallback onEdit, onDelete;
  const _MyListing({required this.item, required this.onEdit, required this.onDelete});
  @override Widget build(BuildContext context) {
    final images = List<dynamic>.from(item['images'] ?? []);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5), decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(12)), child: ListTile(
      contentPadding: const EdgeInsets.all(10),
      leading: ClipRRect(borderRadius: BorderRadius.circular(10), child: images.isNotEmpty ? CachedNetworkImage(imageUrl: images[0].toString(), width: 56, height: 56, fit: BoxFit.cover) : Container(width: 56, height: 56, color: AppTheme.orangeSurf, child: const Icon(Icons.image_rounded, color: AppTheme.orange))),
      title: Text(item['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(FormatUtils.price(item['price'] != null ? double.tryParse(item['price'].toString()) : null, item['currency'] ?? 'USD'), style: const TextStyle(color: AppTheme.orange, fontWeight: FontWeight.w700)), Container(margin: const EdgeInsets.only(top: 3), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: item['status'] == 'active' ? Colors.green.withOpacity(0.1) : Colors.grey.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Text((item['status'] ?? 'active').toUpperCase(), style: TextStyle(color: item['status'] == 'active' ? Colors.green : Colors.grey, fontSize: 9, fontWeight: FontWeight.w800)))]),
      trailing: PopupMenuButton<String>(onSelected: (v) { if (v == 'edit') onEdit(); else if (v == 'delete') onDelete(); }, itemBuilder: (_) => [const PopupMenuItem(value: 'edit', child: Text('Edit')), const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red)))]),
      onTap: () => context.push('/marketplace/${item['id']}'),
    ));
  }
}

class _Empty extends StatelessWidget {
  final String msg; final IconData icon; final VoidCallback? action; final String? actionLabel;
  const _Empty(this.msg, this.icon, {this.action, this.actionLabel});
  @override Widget build(BuildContext _) => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 72, color: Colors.grey), const SizedBox(height: 16), Text(msg, style: const TextStyle(color: Colors.grey, fontSize: 15, fontWeight: FontWeight.w600)), if (action != null) ...[const SizedBox(height: 12), ElevatedButton(onPressed: action, child: Text(actionLabel ?? 'Go'))]]));
}

class MyListingsScreen extends ConsumerWidget {
  const MyListingsScreen({super.key});
  @override Widget build(BuildContext context, WidgetRef ref) => const MarketplaceScreen();
}
