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
import '../../../shared/utils/responsive.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});
  @override ConsumerState<SearchScreen> createState() => _SS();
}

class _SS extends ConsumerState<SearchScreen> with SingleTickerProviderStateMixin {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  late TabController _tc;

  String _query = '';
  bool _searching = false;
  Map<String, dynamic> _results = {};
  List<dynamic> _history = [];
  List<dynamic> _trending = [];
  Timer? _debounce;
  String _activeTab = 'all';

  static const _tabs = ['All', 'People', 'Posts', 'Reels', 'Tags', 'Events'];

  @override
  void initState() {
    super.initState();
    _tc = TabController(length: _tabs.length, vsync: this);
    _tc.addListener(() { if (!_tc.indexIsChanging) setState(() => _activeTab = _tabs[_tc.index].toLowerCase()); });
    _loadHistory();
    _loadTrending();
  }

  @override
  void dispose() { _ctrl.dispose(); _focus.dispose(); _tc.dispose(); _debounce?.cancel(); super.dispose(); }

  Future<void> _loadHistory() async {
    try {
      final r = await ref.read(apiServiceProvider).get('/search/history');
      if (mounted) setState(() => _history = r.data['history'] ?? []);
    } catch (_) {}
  }

  Future<void> _loadTrending() async {
    try {
      final r = await ref.read(apiServiceProvider).get('/discover/explore');
      if (mounted) setState(() => _trending = r.data['trending_hashtags'] ?? []);
    } catch (_) {}
  }

  void _onChanged(String q) {
    setState(() => _query = q);
    _debounce?.cancel();
    if (q.trim().isEmpty) { setState(() { _results = {}; _searching = false; }); return; }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(q.trim()));
  }

  Future<void> _search(String q) async {
    if (q.isEmpty) return;
    try {
      final r = await ref.read(apiServiceProvider).get('/search', q: {'q': q, 'limit': '15'});
      if (mounted) setState(() { _results = Map<String,dynamic>.from(r.data); _searching = false; });
    } catch (_) { if (mounted) setState(() => _searching = false); }
  }

  Future<void> _clearHistory() async {
    await ref.read(apiServiceProvider).delete('/search/history').catchError((_){});
    setState(() => _history = []);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final isWide = Responsive.isWide(context);

    return Scaffold(
      backgroundColor: dark ? AppTheme.dBg : const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: dark ? AppTheme.dSurf : Colors.white,
        elevation: 0,
        titleSpacing: 8,
        leading: _query.isNotEmpty
          ? IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () { _ctrl.clear(); setState(() { _query = ''; _results = {}; }); })
          : null,
        title: Container(
          decoration: BoxDecoration(
            color: dark ? AppTheme.dCard : const Color(0xFFF0F0F0),
            borderRadius: BorderRadius.circular(14),
          ),
          child: TextField(
            controller: _ctrl,
            focusNode: _focus,
            autofocus: true,
            onChanged: _onChanged,
            onSubmitted: (q) { if (q.trim().isNotEmpty) _search(q.trim()); },
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search people, posts, tags...',
              hintStyle: TextStyle(color: dark ? AppTheme.dSub : AppTheme.lSub, fontSize: 15),
              prefixIcon: Icon(Icons.search_rounded, color: dark ? AppTheme.dSub : AppTheme.lSub, size: 22),
              suffixIcon: _query.isNotEmpty
                ? IconButton(icon: const Icon(Icons.close_rounded, size: 20), onPressed: () { _ctrl.clear(); setState(() { _query = ''; _results = {}; _focus.requestFocus(); }); })
                : _searching ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.orange))) : null,
              border: InputBorder.none,
              filled: false,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        bottom: _query.isNotEmpty ? TabBar(
          controller: _tc, isScrollable: true, tabAlignment: TabAlignment.start,
          indicatorColor: AppTheme.orange, labelColor: AppTheme.orange, unselectedLabelColor: Colors.grey,
          tabs: _tabs.map((t) => Tab(text: t)).toList(),
        ) : null,
      ),
      body: _query.isEmpty ? _HomeState(history: _history, trending: _trending, onClearHistory: _clearHistory, onSelect: (q) { _ctrl.text = q; _onChanged(q); }) : _ResultsView(results: _results, query: _query, activeTab: _activeTab, searching: _searching),
    );
  }
}

// ── Home state (no query)
class _HomeState extends StatelessWidget {
  final List<dynamic> history, trending;
  final VoidCallback onClearHistory;
  final void Function(String) onSelect;
  const _HomeState({required this.history, required this.trending, required this.onClearHistory, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ListView(padding: const EdgeInsets.all(16), children: [
      // Recent searches
      if (history.isNotEmpty) ...[
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Recent', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          TextButton(onPressed: onClearHistory, child: const Text('Clear all', style: TextStyle(color: AppTheme.orange, fontSize: 13))),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: history.take(10).map((h) {
          final q = h['query'] as String? ?? '';
          return GestureDetector(onTap: () => onSelect(q), child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: dark ? AppTheme.dDiv : AppTheme.lDiv, width: 0.5)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.history_rounded, size: 14, color: dark ? AppTheme.dSub : AppTheme.lSub),
              const SizedBox(width: 6),
              Text(q, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            ]),
          ));
        }).toList()),
        const SizedBox(height: 20),
      ],

      // Trending
      const Text('Trending', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
      const SizedBox(height: 12),
      ...trending.take(8).toList().asMap().entries.map((e) {
        final h = e.value;
        return InkWell(
          onTap: () => context.push('/hashtag/${h['name']}'),
          borderRadius: BorderRadius.circular(12),
          child: Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Container(width: 40, height: 40, decoration: BoxDecoration(color: AppTheme.orangeSurf, borderRadius: BorderRadius.circular(10)),
                child: Center(child: Text('#', style: TextStyle(color: AppTheme.orange, fontWeight: FontWeight.w900, fontSize: 18)))),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('#${h['name']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                Text('${FormatUtils.count(h['posts_count'] as int? ?? 0)} posts', style: TextStyle(fontSize: 12, color: dark ? AppTheme.dSub : AppTheme.lSub)),
              ])),
              Text('#${e.key + 1}', style: TextStyle(color: AppTheme.orange.withOpacity(0.6), fontWeight: FontWeight.w800, fontSize: 16)),
            ]),
          ),
        );
      }),
    ]);
  }
}

// ── Results view
class _ResultsView extends StatelessWidget {
  final Map<String, dynamic> results;
  final String query, activeTab;
  final bool searching;
  const _ResultsView({required this.results, required this.query, required this.activeTab, required this.searching});

  @override
  Widget build(BuildContext context) {
    if (searching && results.isEmpty) return const Center(child: CircularProgressIndicator(color: AppTheme.orange));

    final users    = List<dynamic>.from(results['users']    ?? []);
    final posts    = List<dynamic>.from(results['posts']    ?? []);
    final reels    = List<dynamic>.from(results['reels']    ?? []);
    final hashtags = List<dynamic>.from(results['hashtags'] ?? []);
    final events   = List<dynamic>.from(results['events']   ?? []);

    if (results.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.search_off_rounded, size: 64, color: Colors.grey),
      const SizedBox(height: 14),
      Text('No results for "$query"', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: Colors.grey)),
    ]));

    switch (activeTab) {
      case 'people': return _UserList(users);
      case 'posts':  return _PostGrid(posts);
      case 'reels':  return _PostGrid(reels, isReel: true);
      case 'tags':   return _TagList(hashtags);
      case 'events': return _EventList(events);
      default:       return _AllResults(users: users, posts: posts, hashtags: hashtags, events: events, reels: reels);
    }
  }
}

class _AllResults extends StatelessWidget {
  final List users, posts, hashtags, events, reels;
  const _AllResults({required this.users, required this.posts, required this.hashtags, required this.events, required this.reels});
  @override
  Widget build(BuildContext context) => ListView(children: [
    if (users.isNotEmpty) ...[_SectionHeader('People', () {}), _UserList(users.take(3).toList(), shrink: true)],
    if (hashtags.isNotEmpty) ...[_SectionHeader('Tags', () {}), _TagList(hashtags.take(4).toList(), shrink: true)],
    if (posts.isNotEmpty) ...[_SectionHeader('Posts', () {}), SizedBox(height: 180, child: _PostGrid(posts.take(6).toList(), horizontal: true))],
    if (reels.isNotEmpty) ...[_SectionHeader('Reels', () {}), SizedBox(height: 180, child: _PostGrid(reels.take(6).toList(), isReel: true, horizontal: true))],
    if (events.isNotEmpty) ...[_SectionHeader('Events', () {}), _EventList(events.take(3).toList(), shrink: true)],
    const SizedBox(height: 24),
  ]);
}

class _SectionHeader extends StatelessWidget {
  final String title; final VoidCallback onSeeAll;
  const _SectionHeader(this.title, this.onSeeAll);
  @override Widget build(BuildContext _) => Padding(padding: const EdgeInsets.fromLTRB(16,14,16,8), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
    Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
    GestureDetector(onTap: onSeeAll, child: const Text('See all', style: TextStyle(color: AppTheme.orange, fontSize: 13))),
  ]));
}

class _UserList extends ConsumerWidget {
  final List users; final bool shrink;
  const _UserList(this.users, {this.shrink = false});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = shrink ? users : users;
    return ListView.builder(
      shrinkWrap: shrink, physics: shrink ? const NeverScrollableScrollPhysics() : null,
      itemCount: items.length,
      itemBuilder: (_, i) {
        final u = items[i];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: AppAvatar(url: u['avatar_url'], size: 48, username: u['username']),
          title: Row(children: [
            Flexible(child: Text(u['display_name'] ?? u['username'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
            if (u['is_verified'] == 1 || u['is_verified'] == true) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.verified_rounded, color: AppTheme.orange, size: 14)),
          ]),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('@${u['username'] ?? ''}', style: const TextStyle(fontSize: 12)),
            if (u['bio'] != null && (u['bio'] as String).isNotEmpty) Text(u['bio'], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ]),
          trailing: _FollowButton(uid: u['id'], isFollowing: u['is_following'] == 1 || u['is_following'] == true),
          onTap: () => context.push('/profile/${u['id']}'),
        );
      },
    );
  }
}

class _FollowButton extends ConsumerStatefulWidget {
  final String uid; final bool isFollowing;
  const _FollowButton({required this.uid, required this.isFollowing});
  @override ConsumerState<_FollowButton> createState() => _FB();
}
class _FB extends ConsumerState<_FollowButton> {
  late bool _following; bool _loading = false;
  @override void initState() { super.initState(); _following = widget.isFollowing; }
  Future<void> _toggle() async {
    setState(() => _loading = true);
    await ref.read(apiServiceProvider).post('/users/${widget.uid}/follow').catchError((_){});
    if (mounted) setState(() { _following = !_following; _loading = false; });
  }
  @override
  Widget build(BuildContext _) => SizedBox(height: 32, child: _loading
    ? const SizedBox(width: 32, child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.orange)))
    : _following
      ? OutlinedButton(onPressed: _toggle, style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14), textStyle: const TextStyle(fontSize: 12)), child: const Text('Following'))
      : ElevatedButton(onPressed: _toggle, style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16), textStyle: const TextStyle(fontSize: 12)), child: const Text('Follow')));
}

class _PostGrid extends StatelessWidget {
  final List posts; final bool isReel, horizontal;
  const _PostGrid(this.posts, {this.isReel = false, this.horizontal = false});
  @override
  Widget build(BuildContext context) {
    if (horizontal) return ListView.builder(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: posts.length,
      itemBuilder: (_, i) {
        final p = posts[i]; final thumb = p['thumbnail'];
        return GestureDetector(onTap: () => context.push(isReel ? '/reel/${p['id']}' : '/post/${p['id']}'),
          child: Container(width: 120, height: 160, margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: AppTheme.orangeSurf),
            child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Stack(fit: StackFit.expand, children: [
              thumb != null ? CachedNetworkImage(imageUrl: thumb, fit: BoxFit.cover) : Container(color: AppTheme.orangeSurf, child: Icon(isReel ? Icons.play_circle_rounded : Icons.image_rounded, color: AppTheme.orange, size: 32)),
              if (isReel) const Positioned(bottom: 8, left: 8, child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22)),
            ]))));
      });
    return GridView.builder(padding: const EdgeInsets.all(2), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 2, mainAxisSpacing: 2),
      itemCount: posts.length,
      itemBuilder: (_, i) {
        final p = posts[i]; final thumb = p['thumbnail'];
        return GestureDetector(onTap: () => context.push(isReel ? '/reel/${p['id']}' : '/post/${p['id']}'),
          child: Stack(fit: StackFit.expand, children: [
            thumb != null ? CachedNetworkImage(imageUrl: thumb, fit: BoxFit.cover, errorWidget: (_, __, ___) => Container(color: AppTheme.orangeSurf)) : Container(color: AppTheme.orangeSurf, child: Icon(isReel ? Icons.play_circle_rounded : Icons.image_rounded, color: AppTheme.orange)),
            if (isReel) const Positioned(top: 4, right: 4, child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 18)),
          ]));
      });
  }
}

class _TagList extends StatelessWidget {
  final List tags; final bool shrink;
  const _TagList(this.tags, {this.shrink = false});
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ListView.builder(
      shrinkWrap: shrink, physics: shrink ? const NeverScrollableScrollPhysics() : null,
      itemCount: tags.length,
      itemBuilder: (_, i) {
        final t = tags[i];
        return ListTile(
          leading: Container(width: 46, height: 46, decoration: BoxDecoration(color: AppTheme.orangeSurf, borderRadius: BorderRadius.circular(12)),
            child: Center(child: Text('#', style: TextStyle(color: AppTheme.orange, fontWeight: FontWeight.w900, fontSize: 20)))),
          title: Text('#${t['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('${FormatUtils.count(t['posts_count'] as int? ?? 0)} posts', style: const TextStyle(fontSize: 12)),
          onTap: () => context.push('/hashtag/${t['name']}'),
        );
      },
    );
  }
}

class _EventList extends StatelessWidget {
  final List events; final bool shrink;
  const _EventList(this.events, {this.shrink = false});
  @override
  Widget build(BuildContext context) => ListView.builder(
    shrinkWrap: shrink, physics: shrink ? const NeverScrollableScrollPhysics() : null,
    itemCount: events.length,
    itemBuilder: (_, i) {
      final e = events[i];
      return ListTile(
        leading: Container(width: 46, height: 46, decoration: BoxDecoration(color: AppTheme.orangeSurf, borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.event_rounded, color: AppTheme.orange, size: 24)),
        title: Text(e['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('${e['going_count'] ?? 0} going', style: const TextStyle(fontSize: 12)),
        onTap: () => context.push('/event/${e['id']}'),
      );
    },
  );
}
