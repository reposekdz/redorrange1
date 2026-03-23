
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/utils/format_utils.dart';

class HashtagScreen extends ConsumerStatefulWidget {
  final String tag;
  const HashtagScreen({super.key, required this.tag});
  @override ConsumerState<HashtagScreen> createState() => _S();
}
class _S extends ConsumerState<HashtagScreen> {
  List<dynamic> _posts = []; bool _l = true; int _count = 0;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try {
      final r = await ref.read(apiServiceProvider).get('/search', q: {'q': '#${widget.tag}', 'type': 'posts', 'limit': '30'});
      setState(() { _posts = r.data['posts'] ?? []; _count = r.data['total'] as int? ?? _posts.length; _l = false; });
    } catch (_) { setState(() => _l = false); }
  }
  @override Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverAppBar(expandedHeight: 140, pinned: true, flexibleSpace: FlexibleSpaceBar(
          background: Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [AppTheme.orange, AppTheme.orangeDark]))),
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
            Text('#${widget.tag}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: Colors.white)),
            Text('${FormatUtils.count(_count)} posts', style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w400)),
          ]),
        )),
        _l ? const SliverFillRemaining(child: Center(child: CircularProgressIndicator(color: AppTheme.orange)))
          : _posts.isEmpty ? const SliverFillRemaining(child: Center(child: Text('No posts with this hashtag', style: TextStyle(color: Colors.grey))))
          : SliverPadding(padding: const EdgeInsets.all(1.5), sliver: SliverGrid(delegate: SliverChildBuilderDelegate((_, i) {
              final p = _posts[i];
              final thumb = p['thumbnail'] ?? (p['media'] is List && (p['media'] as List).isNotEmpty ? (p['media'] as List)[0]['media_url'] : null);
              return GestureDetector(onTap: () => context.push('/post/${p['id']}'), child: Stack(fit: StackFit.expand, children: [
                thumb != null ? CachedNetworkImage(imageUrl: thumb, fit: BoxFit.cover) : Container(color: AppTheme.orangeSurf, child: const Icon(Icons.image_rounded, color: AppTheme.orange)),
                Positioned(bottom: 4, left: 4, child: Row(children: [const Icon(Icons.favorite_rounded, color: Colors.white, size: 10), const SizedBox(width: 2), Text(FormatUtils.count(p['likes_count'] as int? ?? 0), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600))])),
              ]));
            }, childCount: _posts.length), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 1.5, mainAxisSpacing: 1.5))),
      ]),
    );
  }
}
