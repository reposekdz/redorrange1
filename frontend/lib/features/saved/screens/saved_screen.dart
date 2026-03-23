import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/utils/format_utils.dart';
import '../../../shared/widgets/app_avatar.dart';

final _savedProv = FutureProvider.autoDispose<Map<String,dynamic>>((ref) async {
  final api = ref.read(apiServiceProvider);
  final [posts, reels, products] = await Future.wait([
    api.get('/posts/saved'),
    api.get('/reels/saved').catchError((_) => null),
    api.get('/marketplace', q: {'filter': 'saved'}).catchError((_) => null),
  ]);
  return {
    'posts':    posts.data['posts'] ?? [],
    'reels':    reels?.data['reels'] ?? [],
    'products': products?.data['items'] ?? [],
  };
});

class SavedScreen extends ConsumerStatefulWidget {
  const SavedScreen({super.key});
  @override ConsumerState<SavedScreen> createState() => _S();
}
class _S extends ConsumerState<SavedScreen> with SingleTickerProviderStateMixin {
  late TabController _tc;
  @override void initState() { super.initState(); _tc = TabController(length: 3, vsync: this); }
  @override void dispose() { _tc.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(_savedProv);
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
        actions: [
          IconButton(icon: const Icon(Icons.add_rounded), onPressed: () => _showCreateCollection(context), tooltip: 'New Collection'),
        ],
        bottom: TabBar(
          controller: _tc,
          indicatorColor: AppTheme.orange, labelColor: AppTheme.orange, unselectedLabelColor: Colors.grey,
          labelStyle: const TextStyle(fontWeight: FontWeight.w600),
          tabs: data.when(
            loading: () => const [Tab(text: 'Posts'), Tab(text: 'Reels'), Tab(text: 'Products')],
            error: (_, __) => const [Tab(text: 'Posts'), Tab(text: 'Reels'), Tab(text: 'Products')],
            data: (d) => [
              Tab(text: 'Posts (${(d['posts'] as List).length})'),
              Tab(text: 'Reels (${(d['reels'] as List).length})'),
              Tab(text: 'Products (${(d['products'] as List).length})'),
            ],
          ),
        ),
      ),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.orange)),
        error: (e, _) => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.bookmark_remove_rounded, size: 64, color: Colors.grey),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: () => ref.refresh(_savedProv), child: const Text('Retry')),
        ])),
        data: (d) {
          final posts    = List<dynamic>.from(d['posts'] as List? ?? []);
          final reels    = List<dynamic>.from(d['reels'] as List? ?? []);
          final products = List<dynamic>.from(d['products'] as List? ?? []);

          return TabBarView(controller: _tc, children: [
            // SAVED POSTS
            posts.isEmpty ? _Empty('No saved posts yet', Icons.bookmark_border_rounded, 'Browse the feed and tap the bookmark icon to save posts here') : _PostsGrid(posts: posts, dark: dark, onUnsave: (id) async {
              await ref.read(apiServiceProvider).post('/posts/$id/save').catchError((_){});
              ref.refresh(_savedProv);
            }),

            // SAVED REELS
            reels.isEmpty ? _Empty('No saved reels', Icons.bookmark_border_rounded, 'Save reels while watching to find them here') : _ReelsGrid(reels: reels, dark: dark, onUnsave: (id) async {
              await ref.read(apiServiceProvider).post('/reels/$id/save').catchError((_){});
              ref.refresh(_savedProv);
            }),

            // SAVED PRODUCTS
            products.isEmpty ? _Empty('No saved products', Icons.shopping_bag_outlined, 'Save marketplace items to find them later') : _ProductsGrid(products: products, dark: dark, onUnsave: (id) async {
              await ref.read(apiServiceProvider).post('/marketplace/$id/save').catchError((_){});
              ref.refresh(_savedProv);
            }),
          ]);
        },
      ),
    );
  }

  void _showCreateCollection(BuildContext context) {
    final ctrl = TextEditingController();
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (_) {
      final dark = Theme.of(context).brightness == Brightness.dark;
      return Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom), child: Container(margin: const EdgeInsets.all(10), decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(20)), padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('New Collection', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        const SizedBox(height: 16),
        TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(labelText: 'Collection name', hintText: 'e.g. Inspiration, Travel Ideas...')),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () async {
          if (ctrl.text.trim().isEmpty) return;
          Navigator.pop(context);
          await ref.read(apiServiceProvider).post('/collections', data: {'name': ctrl.text.trim()}).catchError((_){});
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Collection "${ctrl.text}" created')));
        }, child: const Text('Create Collection', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)))),
      ])));
    });
  }
}

class _PostsGrid extends StatelessWidget {
  final List<dynamic> posts; final bool dark; final void Function(String) onUnsave;
  const _PostsGrid({required this.posts, required this.dark, required this.onUnsave});
  @override Widget build(BuildContext context) => GridView.builder(
    padding: const EdgeInsets.all(1.5),
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 1.5, mainAxisSpacing: 1.5),
    itemCount: posts.length,
    itemBuilder: (_, i) {
      final p = posts[i];
      final thumb = p['thumbnail'] ?? (p['media'] is List && (p['media'] as List).isNotEmpty ? (p['media'] as List)[0]['media_url'] : null);
      return GestureDetector(
        onTap: () => context.push('/post/${p['id']}'),
        onLongPress: () => _showOptions(context, p),
        child: Stack(fit: StackFit.expand, children: [
          thumb != null ? CachedNetworkImage(imageUrl: thumb, fit: BoxFit.cover) : Container(color: AppTheme.orangeSurf, child: const Icon(Icons.image_rounded, color: AppTheme.orange)),
          Positioned.fill(child: Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black.withOpacity(0.4)])))),
          Positioned(bottom: 4, left: 4, child: Row(children: [const Icon(Icons.favorite_rounded, color: Colors.white, size: 10), const SizedBox(width: 2), Text(FormatUtils.count(p['likes_count'] as int? ?? 0), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600))])),
          Positioned(top: 4, right: 4, child: GestureDetector(onTap: () => onUnsave(p['id'] as String), child: Container(width: 24, height: 24, decoration: const BoxDecoration(color: Colors.black38, shape: BoxShape.circle), child: const Icon(Icons.bookmark_remove_rounded, color: Colors.white, size: 14)))),
        ]),
      );
    },
  );

  void _showOptions(BuildContext context, dynamic p) {
    showModalBottomSheet(context: context, builder: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(leading: const Icon(Icons.open_in_new_rounded, color: AppTheme.orange), title: const Text('Open Post'), onTap: () { Navigator.pop(context); context.push('/post/${p['id']}'); }),
      ListTile(leading: const Icon(Icons.folder_rounded, color: AppTheme.orange), title: const Text('Add to Collection'), onTap: () => Navigator.pop(context)),
      ListTile(leading: const Icon(Icons.bookmark_remove_rounded, color: Colors.red), title: const Text('Remove from Saved', style: TextStyle(color: Colors.red)), onTap: () { Navigator.pop(context); onUnsave(p['id'] as String); }),
    ]));
  }
}

class _ReelsGrid extends StatelessWidget {
  final List<dynamic> reels; final bool dark; final void Function(String) onUnsave;
  const _ReelsGrid({required this.reels, required this.dark, required this.onUnsave});
  @override Widget build(BuildContext context) => GridView.builder(
    padding: const EdgeInsets.all(1.5),
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 1.5, mainAxisSpacing: 1.5, childAspectRatio: 0.6),
    itemCount: reels.length,
    itemBuilder: (_, i) {
      final r = reels[i];
      return GestureDetector(
        onTap: () => context.push('/reel/${r['id']}'),
        child: Stack(fit: StackFit.expand, children: [
          r['thumbnail_url'] != null ? CachedNetworkImage(imageUrl: r['thumbnail_url'], fit: BoxFit.cover) : Container(color: const Color(0xFF1A1A1A)),
          Positioned.fill(child: Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black.withOpacity(0.7)])))),
          Positioned(bottom: 4, left: 4, child: Row(children: [const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 14), const SizedBox(width: 2), Text(FormatUtils.count(r['views_count'] as int? ?? 0), style: const TextStyle(color: Colors.white, fontSize: 10))])),
          Positioned(top: 4, right: 4, child: GestureDetector(onTap: () => onUnsave(r['id'] as String), child: Container(width: 24, height: 24, decoration: const BoxDecoration(color: Colors.black38, shape: BoxShape.circle), child: const Icon(Icons.bookmark_remove_rounded, color: Colors.white, size: 14)))),
        ]),
      );
    },
  );
}

class _ProductsGrid extends StatelessWidget {
  final List<dynamic> products; final bool dark; final void Function(String) onUnsave;
  const _ProductsGrid({required this.products, required this.dark, required this.onUnsave});
  @override Widget build(BuildContext context) => GridView.builder(
    padding: const EdgeInsets.all(10),
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 0.72),
    itemCount: products.length,
    itemBuilder: (_, i) {
      final p = products[i];
      return GestureDetector(
        onTap: () => context.push('/marketplace/${p['id']}'),
        child: Container(decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)]), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(14)), child: Stack(children: [
            p['images'] != null && (p['images'] as List).isNotEmpty ? CachedNetworkImage(imageUrl: (p['images'] as List)[0] as String, height: 130, width: double.infinity, fit: BoxFit.cover) : Container(height: 130, color: AppTheme.orangeSurf, child: const Icon(Icons.shopping_bag_rounded, color: AppTheme.orange, size: 36)),
            Positioned(top: 6, right: 6, child: GestureDetector(onTap: () => onUnsave(p['id'] as String), child: Container(width: 28, height: 28, decoration: const BoxDecoration(color: Colors.black38, shape: BoxShape.circle), child: const Icon(Icons.bookmark_rounded, color: AppTheme.orange, size: 15)))),
          ])),
          Padding(padding: const EdgeInsets.all(8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text('\$${p['price'] ?? '0'}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppTheme.orange)),
          ])),
        ])),
      );
    },
  );
}

class _Empty extends StatelessWidget {
  final String title, subtitle; final IconData icon;
  const _Empty(this.title, this.icon, this.subtitle);
  @override Widget build(BuildContext _) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Container(width: 80, height: 80, decoration: BoxDecoration(color: AppTheme.orangeSurf, borderRadius: BorderRadius.circular(20)), child: Icon(icon, color: AppTheme.orange, size: 40)),
    const SizedBox(height: 20),
    Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
    const SizedBox(height: 8),
    Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 13, height: 1.5), textAlign: TextAlign.center),
  ])));
}
