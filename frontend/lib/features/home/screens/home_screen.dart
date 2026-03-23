import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/api_service.dart';
import '../../../core/models/models.dart';
import '../../../shared/widgets/app_avatar.dart';
import '../../../shared/utils/format_utils.dart';
import '../../ads/widgets/ad_widgets.dart';
import '../../../shared/utils/responsive.dart';

final feedProvider = StateNotifierProvider.autoDispose<_FeedNotifier, AsyncValue<List<PostModel>>>((ref) => _FeedNotifier(ref));
final storiesProvider = StateNotifierProvider.autoDispose<_StoriesNotifier, AsyncValue<List<Map<String,dynamic>>>>((ref) => _StoriesNotifier(ref));
final suggestedUsersProvider = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  final r = await ref.read(apiServiceProvider).get('/discover/explore');
  return r.data['suggested_users'] ?? [];
});
final trendingTagsProvider = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  final r = await ref.read(apiServiceProvider).get('/discover/explore');
  return r.data['trending_hashtags'] ?? [];
});

class _FeedNotifier extends StateNotifier<AsyncValue<List<PostModel>>> {
  final Ref _ref; int _page = 1; bool _hasMore = true; bool _busy = false;
  _FeedNotifier(this._ref) : super(const AsyncValue.loading()) { load(); }
  Future<void> load({bool more = false}) async {
    if (_busy || (more && !_hasMore)) return;
    _busy = true;
    if (!more) { state = const AsyncValue.loading(); _page = 1; }
    try {
      final r = await _ref.read(apiServiceProvider).get('/posts/feed', q: {'page': '$_page', 'limit': '10'});
      final posts = (r.data['posts'] as List).map((p) => PostModel.fromJson(Map<String,dynamic>.from(p))).toList();
      _hasMore = r.data['has_more'] == true;
      if (more) { state = AsyncValue.data([...state.value ?? [], ...posts]); _page++; }
      else { state = AsyncValue.data(posts); }
    } catch (e, s) { if (!more) state = AsyncValue.error(e, s); }
    _busy = false;
  }
}

class _StoriesNotifier extends StateNotifier<AsyncValue<List<Map<String,dynamic>>>> {
  final Ref _ref;
  _StoriesNotifier(this._ref) : super(const AsyncValue.loading()) { load(); }
  Future<void> load() async {
    try {
      final r = await _ref.read(apiServiceProvider).get('/stories/feed');
      state = AsyncValue.data(List<Map<String,dynamic>>.from(r.data['story_users'] ?? []));
    } catch (e, s) { state = AsyncValue.error(e, s); }
  }
}

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final w = MediaQuery.of(context).size.width;
    if (w >= 1200) return _DesktopLayout(user: user);
    if (w >= 768)  return _TabletLayout(user: user);
    return _MobileLayout(user: user);
  }
}

// ── DESKTOP: left feed + right panel
class _DesktopLayout extends ConsumerWidget {
  final dynamic user;
  const _DesktopLayout({required this.user});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Row(children: [
      Expanded(flex: 6, child: _FeedScroll(user: user, showHeader: true)),
      Container(width: 0.5, color: dark ? AppTheme.dDiv : AppTheme.lDiv),
      SizedBox(width: 320, child: _RightPanel(user: user)),
    ]);
  }
}

// ── TABLET
class _TabletLayout extends ConsumerWidget {
  final dynamic user;
  const _TabletLayout({required this.user});
  @override
  Widget build(BuildContext context, WidgetRef ref) => _FeedScroll(user: user, showHeader: true);
}

// ── MOBILE
class _MobileLayout extends ConsumerWidget {
  final dynamic user;
  const _MobileLayout({required this.user});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: _AppBar(user: user),
      body: _FeedScroll(user: user, showHeader: false),
    );
  }
}

class _AppBar extends ConsumerWidget implements PreferredSizeWidget {
  final dynamic user;
  const _AppBar({required this.user});
  @override Size get preferredSize => const Size.fromHeight(kToolbarHeight);
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AppBar(
      backgroundColor: dark ? AppTheme.dSurf : Colors.white,
      elevation: 0, scrolledUnderElevation: 0,
      title: Row(children: [
        Container(width: 28, height: 28, decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppTheme.orange, AppTheme.orangeDark]), borderRadius: BorderRadius.circular(7)),
          child: const Icon(Icons.circle, color: Colors.white, size: 14)),
        const SizedBox(width: 8),
        const Text('RedOrrange', style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.orange, fontSize: 18)),
      ]),
      actions: [
        IconButton(icon: const Icon(Icons.live_tv_rounded), onPressed: () => context.push('/live'), tooltip: 'Live'),
        Stack(alignment: Alignment.topRight, children: [
          IconButton(icon: const Icon(Icons.notifications_none_rounded), onPressed: () => context.push('/notifications')),
          if ((user?.unreadNotifications ?? 0) > 0)
            Positioned(top: 8, right: 8, child: Container(width: 16, height: 16, decoration: const BoxDecoration(color: AppTheme.orange, shape: BoxShape.circle),
              child: Center(child: Text('${user?.unreadNotifications ?? 0}', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800))))),
        ]),
        IconButton(icon: const Icon(Icons.search_rounded), onPressed: () => context.push('/search')),
      ],
    );
  }
}

// ── Feed scroll area
class _FeedScroll extends ConsumerStatefulWidget {
  final dynamic user;
  final bool showHeader;
  const _FeedScroll({required this.user, required this.showHeader});
  @override ConsumerState<_FeedScroll> createState() => _FS();
}
class _FS extends ConsumerState<_FeedScroll> {
  final _sc = ScrollController();
  @override void initState() { super.initState(); _sc.addListener(() { if (_sc.position.pixels >= _sc.position.maxScrollExtent - 600) ref.read(feedProvider.notifier).load(more: true); }); }
  @override void dispose() { _sc.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final feed    = ref.watch(feedProvider);
    final stories = ref.watch(storiesProvider);
    final dark    = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: dark ? AppTheme.dBg : const Color(0xFFF5F5F5),
      appBar: widget.showHeader ? _AppBar(user: widget.user) : null,
      body: RefreshIndicator(
        color: AppTheme.orange,
        onRefresh: () async { ref.refresh(feedProvider); ref.refresh(storiesProvider); },
        child: CustomScrollView(controller: _sc, slivers: [
          // Stories bar
          SliverToBoxAdapter(child: Container(
            margin: const EdgeInsets.only(bottom: 6),
            color: dark ? AppTheme.dSurf : Colors.white,
            child: stories.when(
              loading: () => const SizedBox(height: 96),
              error: (_, __) => const SizedBox.shrink(),
              data: (su) => _StoriesStrip(users: su, me: widget.user),
            ),
          )),

          // Feed
          feed.when(
            loading: () => const SliverToBoxAdapter(child: _FeedShimmer()),
            error: (e, _) => SliverFillRemaining(child: _FeedError(onRetry: () => ref.refresh(feedProvider))),
            data: (posts) {
              if (posts.isEmpty) return SliverFillRemaining(child: _EmptyFeed());
              return SliverList(delegate: SliverChildBuilderDelegate(
                (_, i) {
                  // Every 5th post slot: inject ad (skip for loading indicator)
                  if (i > 0 && i < posts.length && i % 5 == 0) {
                    return FeedAdCard(feedIndex: i ~/ 5);
                  }
                  final postIdx = i > 0 && i > (i ~/ 5) ? i - (i ~/ 5) : i;
                  final realIdx = i - (i ~/ 5).clamp(0, i);
                  final actualIdx = i < posts.length ? i : posts.length;
                  if (actualIdx == posts.length) return const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: CircularProgressIndicator(color: AppTheme.orange)));
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: _PostCard(post: posts[actualIdx]),
                  ).animate().fadeIn(delay: Duration(milliseconds: (actualIdx * 30).clamp(0, 300)));
                },
                childCount: posts.length + 1,
              ));
            },
          ),
        ]),
      ),
    );
  }
}

// ── RIGHT PANEL for desktop
class _RightPanel extends ConsumerWidget {
  final dynamic user;
  const _RightPanel({required this.user});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggested = ref.watch(suggestedUsersProvider);
    final trending  = ref.watch(trendingTagsProvider);
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      color: dark ? AppTheme.dBg : const Color(0xFFF5F5F5),
      child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 24), children: [
        // Search bar
        Container(
          decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(12)),
          child: TextField(
            onTap: () => context.push('/search'),
            readOnly: true,
            decoration: InputDecoration(hintText: 'Search RedOrrange', prefixIcon: const Icon(Icons.search_rounded, size: 20), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), filled: true, fillColor: Colors.transparent, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
          ),
        ),
        const SizedBox(height: 14),

        // My profile mini card
        if (user != null) _Card(child: Column(children: [
          Row(children: [
            AppAvatar(url: user.avatarUrl, size: 48, username: user.username),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Flexible(child: Text(user.displayName ?? user.username ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14), overflow: TextOverflow.ellipsis)), if (user.isVerified) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.verified_rounded, color: AppTheme.orange, size: 14))]),
              Text('@${user.username ?? ''}', style: TextStyle(fontSize: 12, color: dark ? AppTheme.dSub : AppTheme.lSub)),
            ])),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            _PStat(FormatUtils.count(user.followersCount), 'Followers', () => context.push('/followers/${user.id}', extra: {'type': 'followers'})),
            _PStat(FormatUtils.count(user.followingCount), 'Following', () => context.push('/followers/${user.id}', extra: {'type': 'following'})),
            _PStat(FormatUtils.count(user.postsCount), 'Posts', () => context.push('/profile/${user.id}')),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => context.push('/edit-profile'), style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 8), textStyle: const TextStyle(fontSize: 12)), child: const Text('Edit Profile'))),
            const SizedBox(width: 8),
            Expanded(child: ElevatedButton(onPressed: () => context.push('/profile/${user.id}'), style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 8), textStyle: const TextStyle(fontSize: 12)), child: const Text('View Profile'))),
          ]),
        ])),
        const SizedBox(height: 12),

        // Quick action buttons
        _Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Quick Actions', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 10),
          GridView.count(crossAxisCount: 3, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 1.1, children: [
            _QABtn(Icons.add_photo_alternate_rounded, 'Post',      AppTheme.orange,            () => context.push('/create')),
            _QABtn(Icons.auto_stories_rounded,        'Story',     const Color(0xFF9C27B0),    () => context.push('/create-story')),
            _QABtn(Icons.videocam_rounded,            'Reel',      const Color(0xFFE91E63),    () => context.push('/create')),
            _QABtn(Icons.event_rounded,               'Event',     const Color(0xFF2196F3),    () => context.push('/create-event')),
            _QABtn(Icons.store_rounded,               'Sell',      const Color(0xFF4CAF50),    () => context.push('/marketplace')),
            _QABtn(Icons.live_tv_rounded,             'Go Live',   const Color(0xFFFF5722),    () => context.push('/live')),
          ]),
        ])),
        const SizedBox(height: 12),

        // Trending hashtags
        trending.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (tags) => _Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Trending', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              TextButton(onPressed: () => context.go('/discover'), child: const Text('See all', style: TextStyle(fontSize: 11))),
            ]),
            ...tags.take(6).map((t) => ListTile(contentPadding: EdgeInsets.zero, dense: true,
              leading: Container(width: 34, height: 34, decoration: BoxDecoration(color: AppTheme.orangeSurf, borderRadius: BorderRadius.circular(8)), child: const Center(child: Text('#', style: TextStyle(color: AppTheme.orange, fontWeight: FontWeight.w800, fontSize: 15)))),
              title: Text('#${t['name']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              subtitle: Text('${FormatUtils.count(t['posts_count'] as int? ?? 0)} posts', style: const TextStyle(fontSize: 11)),
              onTap: () => context.push('/search?q=${t['name']}'),
            )),
          ])),
        ),
        const SizedBox(height: 12),

        // Suggested users
        suggested.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (users) => _Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('People you may know', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              TextButton(onPressed: () => context.go('/discover'), child: const Text('More', style: TextStyle(fontSize: 11))),
            ]),
            const SizedBox(height: 4),
            ...users.take(5).map((u) => _SugTile(u: u)),
          ])),
        ),
        const SizedBox(height: 12),

        // Footer links
        Wrap(spacing: 8, runSpacing: 4, children: [
          _FootLink('Events',      () => context.push('/events')),
          _FootLink('Marketplace', () => context.push('/marketplace')),
          _FootLink('Channels',    () => context.push('/channels')),
          _FootLink('Saved',       () => context.push('/saved')),
          _FootLink('Analytics',   () => context.push('/analytics')),
          _FootLink('Settings',    () => context.push('/settings')),
        ]),
      ]),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(14)), child: child);
  }
}

class _PStat extends StatelessWidget {
  final String v, l; final VoidCallback onTap;
  const _PStat(this.v, this.l, this.onTap);
  @override
  Widget build(BuildContext _) => Expanded(child: GestureDetector(onTap: onTap, child: Column(children: [Text(v, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)), Text(l, style: const TextStyle(fontSize: 11, color: Colors.grey))])));
}

class _QABtn extends StatelessWidget {
  final IconData icon; final String label; final Color color; final VoidCallback onTap;
  const _QABtn(this.icon, this.label, this.color, this.onTap);
  @override
  Widget build(BuildContext _) => GestureDetector(onTap: onTap, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Container(width: 42, height: 42, decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: color, size: 22)),
    const SizedBox(height: 4), Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
  ]));
}

class _SugTile extends ConsumerWidget {
  final dynamic u;
  const _SugTile({required this.u});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ListTile(contentPadding: EdgeInsets.zero, dense: true,
    leading: AppAvatar(url: u['avatar_url'], size: 40, username: u['username']),
    title: Row(mainAxisSize: MainAxisSize.min, children: [Flexible(child: Text(u['display_name'] ?? u['username'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), overflow: TextOverflow.ellipsis)), if (u['is_verified'] == 1 || u['is_verified'] == true) const Padding(padding: EdgeInsets.only(left: 3), child: Icon(Icons.verified_rounded, color: AppTheme.orange, size: 12))]),
    subtitle: Text(FormatUtils.count(u['followers_count'] as int? ?? 0) + ' followers', style: const TextStyle(fontSize: 11)),
    trailing: SizedBox(height: 28, child: ElevatedButton(onPressed: () async { await ref.read(apiServiceProvider).post('/users/${u['id']}/follow'); }, style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10), textStyle: const TextStyle(fontSize: 11)), child: const Text('Follow'))),
    onTap: () => context.push('/profile/${u['id']}'),
  );
}

class _FootLink extends StatelessWidget {
  final String l; final VoidCallback onTap;
  const _FootLink(this.l, this.onTap);
  @override Widget build(BuildContext _) => GestureDetector(onTap: onTap, child: Text(l, style: const TextStyle(fontSize: 11, color: AppTheme.orange, fontWeight: FontWeight.w500)));
}

// ── Stories strip
class _StoriesStrip extends StatelessWidget {
  final List<Map<String,dynamic>> users; final dynamic me;
  const _StoriesStrip({required this.users, this.me});
  @override
  Widget build(BuildContext context) => SizedBox(height: 96, child: ListView.builder(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), itemCount: users.length + 1, itemBuilder: (_, i) {
    if (i == 0) return _SI(uid: me?.id ?? '', label: 'Add Story', avatar: me?.avatarUrl, isMine: true, onTap: () => context.push('/create-story'));
    final u = users[i-1];
    return _SI(uid: u['id'], label: u['username'] ?? '', avatar: u['avatar_url'], hasStory: (u['stories_count'] as int? ?? 0) > 0, isViewed: (u['viewed_count'] as int? ?? 0) >= (u['stories_count'] as int? ?? 1), onTap: () => context.push('/story/${u['id']}'));
  }));
}
class _SI extends StatelessWidget {
  final String uid, label; final String? avatar; final bool hasStory, isViewed, isMine; final VoidCallback onTap;
  const _SI({required this.uid, required this.label, this.avatar, this.hasStory = false, this.isViewed = false, this.isMine = false, required this.onTap});
  @override Widget build(_) => GestureDetector(onTap: onTap, child: SizedBox(width: 70, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    StoryRing(url: avatar, size: 52, username: label, hasStory: hasStory, isViewed: isViewed, isMine: isMine),
    const SizedBox(height: 4), Text(isMine ? 'Add Story' : label, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
  ])));
}

// ── Full post card
class _PostCard extends ConsumerStatefulWidget {
  final PostModel post;
  const _PostCard({required this.post});
  @override ConsumerState<_PostCard> createState() => _PCState();
}
class _PCState extends ConsumerState<_PostCard> {
  late bool _liked; late int _likes; late bool _saved; int _mi = 0; bool _expanded = false;
  @override void initState() { super.initState(); _liked = widget.post.isLiked; _likes = widget.post.likesCount; _saved = widget.post.isSaved; }
  Future<void> _like() async {
    final p = _liked; setState(() { _liked = !_liked; _likes += _liked ? 1 : -1; });
    await ref.read(apiServiceProvider).post('/posts/${widget.post.id}/like').catchError((_) => setState(() { _liked = p; _likes += p ? 1 : -1; }));
  }
  Future<void> _save() async { setState(() => _saved = !_saved); await ref.read(apiServiceProvider).post('/posts/${widget.post.id}/save').catchError((_) => setState(() => _saved = !_saved)); }

  @override
  Widget build(BuildContext context) {
    final p = widget.post; final u = p.user; final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(color: dark ? AppTheme.dSurf : Colors.white, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Header
      Padding(padding: const EdgeInsets.fromLTRB(12, 10, 4, 6), child: Row(children: [
        GestureDetector(onTap: () => context.push('/profile/${u?.id}'), child: AppAvatar(url: u?.avatarUrl, size: 42, username: u?.username)),
        const SizedBox(width: 10),
        Expanded(child: GestureDetector(onTap: () => context.push('/profile/${u?.id}'), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Flexible(child: Text(u?.displayName ?? u?.username ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14), overflow: TextOverflow.ellipsis)), if (u?.isVerified == true) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.verified_rounded, color: AppTheme.orange, size: 14))]),
          Row(children: [Text(FormatUtils.relativeTime(p.createdAt), style: TextStyle(fontSize: 11, color: dark ? AppTheme.dSub : AppTheme.lSub)), if (p.location != null) ...[const SizedBox(width: 8), const Icon(Icons.location_on_rounded, size: 11, color: AppTheme.orange), Flexible(child: Text(p.location!, style: const TextStyle(fontSize: 11, color: AppTheme.orange), overflow: TextOverflow.ellipsis))]]),
        ]))),
        PopupMenuButton<String>(
          icon: Icon(Icons.more_horiz_rounded, color: dark ? AppTheme.dSub : AppTheme.lSub),
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'save',   child: Row(children: [Icon(Icons.bookmark_border_rounded, size: 18), SizedBox(width: 8), Text('Save')])),
            const PopupMenuItem(value: 'share',  child: Row(children: [Icon(Icons.share_rounded, size: 18), SizedBox(width: 8), Text('Share')])),
            const PopupMenuItem(value: 'report', child: Row(children: [Icon(Icons.flag_outlined, size: 18, color: Colors.red), SizedBox(width: 8), Text('Report', style: TextStyle(color: Colors.red))])),
          ],
          onSelected: (v) async { if (v == 'save') _save(); else if (v == 'share') await ref.read(apiServiceProvider).post('/posts/${p.id}/share'); },
        ),
      ])),

      // Media
      if (p.media.isNotEmpty) ...[
        if (p.media.length == 1)
          GestureDetector(onDoubleTap: () { if (!_liked) _like(); }, onTap: () => context.push('/post/${p.id}'), child: _MediaTile(media: p.media[0]))
        else
          Stack(children: [
            SizedBox(height: 340, child: PageView.builder(onPageChanged: (i) => setState(() => _mi = i), itemCount: p.media.length, itemBuilder: (_, i) => GestureDetector(onTap: () => context.push('/post/${p.id}'), child: _MediaTile(media: p.media[i])))),
            Positioned(top: 12, right: 12, child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)), child: Text('${_mi+1}/${p.media.length}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)))),
            Positioned(bottom: 10, left: 0, right: 0, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(p.media.length, (i) => Container(width: 6, height: 6, margin: const EdgeInsets.symmetric(horizontal: 2), decoration: BoxDecoration(shape: BoxShape.circle, color: i == _mi ? AppTheme.orange : Colors.white60))))),
          ]),
      ],

      // Actions
      Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), child: Row(children: [
        _Btn(_liked ? Icons.favorite_rounded : Icons.favorite_border_rounded, _liked ? Colors.red : null, FormatUtils.count(_likes), _like),
        _Btn(Icons.chat_bubble_outline_rounded, null, FormatUtils.count(p.commentsCount), () => context.push('/post/${p.id}')),
        _Btn(Icons.send_rounded, null, 'Share', () async { await ref.read(apiServiceProvider).post('/posts/${p.id}/share'); }),
        const Spacer(),
        GestureDetector(onTap: _save, child: Padding(padding: const EdgeInsets.all(8), child: Icon(_saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, color: _saved ? AppTheme.orange : null, size: 22))),
      ])),

      // Caption
      if (p.caption != null && p.caption!.isNotEmpty)
        Padding(padding: const EdgeInsets.fromLTRB(14, 2, 14, 6), child: GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: RichText(maxLines: _expanded ? null : 3, overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis, text: TextSpan(style: Theme.of(context).textTheme.bodyMedium, children: [
            TextSpan(text: '${u?.username ?? ''} ', style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: p.caption!),
          ])),
        )),
      if (p.commentsCount > 0) Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 8), child: GestureDetector(onTap: () => context.push('/post/${p.id}'), child: Text('View all ${FormatUtils.count(p.commentsCount)} comments', style: TextStyle(fontSize: 13, color: dark ? AppTheme.dSub : AppTheme.lSub)))),
      const SizedBox(height: 6),
    ]));
  }
}

class _MediaTile extends StatelessWidget {
  final MediaItem media;
  const _MediaTile({required this.media});
  @override
  Widget build(BuildContext _) {
    if (media.mediaType == 'video') {
      return Container(height: 340, color: Colors.black87, child: const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 72)));
    }
    final h = (media.height != null && media.width != null && media.width! > 0)
        ? (340.0 * media.height! / media.width!).clamp(180.0, 500.0)
        : 340.0;
    return CachedNetworkImage(imageUrl: media.mediaUrl, height: h, width: double.infinity, fit: BoxFit.cover,
      placeholder: (_, __) => Container(height: h, color: Colors.grey.shade100),
      errorWidget: (_, __, ___) => Container(height: 220, color: AppTheme.orangeSurf, child: const Center(child: Icon(Icons.broken_image_rounded, color: AppTheme.orange, size: 52))));
  }
}

class _Btn extends StatelessWidget {
  final IconData icon; final Color? color; final String label; final VoidCallback onTap;
  const _Btn(this.icon, this.color, this.label, this.onTap);
  @override Widget build(BuildContext _) => GestureDetector(onTap: onTap, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 22, color: color), const SizedBox(width: 4), Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))])));
}

class _FeedError extends StatelessWidget {
  final VoidCallback onRetry;
  const _FeedError({required this.onRetry});
  @override Widget build(BuildContext _) => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.wifi_off_rounded, size: 56, color: AppTheme.orange), const SizedBox(height: 14), const Text('Connection error', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)), const SizedBox(height: 12), ElevatedButton(onPressed: onRetry, child: const Text('Retry'))]));
}

class _EmptyFeed extends ConsumerWidget {
  @override Widget build(BuildContext context, WidgetRef ref) => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.people_outline_rounded, size: 72, color: AppTheme.orange), const SizedBox(height: 16), const Text('Your feed is empty', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)), const SizedBox(height: 8), const Text('Follow people to see posts here', style: TextStyle(color: Colors.grey)), const SizedBox(height: 20), ElevatedButton.icon(onPressed: () => context.go('/discover'), icon: const Icon(Icons.explore_rounded), label: const Text('Discover people')), const SizedBox(height: 10), OutlinedButton.icon(onPressed: () => context.push('/create'), icon: const Icon(Icons.add_rounded), label: const Text('Create your first post'))]));
}

class _FeedShimmer extends StatelessWidget {
  const _FeedShimmer();
  @override Widget build(BuildContext _) => Column(children: List.generate(2, (_) => Container(margin: const EdgeInsets.only(bottom: 6), color: Colors.white, padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Container(width: 42, height: 42, decoration: BoxDecoration(color: Colors.grey.shade200, shape: BoxShape.circle)), const SizedBox(width: 10), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Container(width: 120, height: 13, color: Colors.grey.shade200), const SizedBox(height: 5), Container(width: 80, height: 11, color: Colors.grey.shade200)])]), const SizedBox(height: 10), Container(height: 260, color: Colors.grey.shade200)]))));
}
