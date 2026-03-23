import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/api_service.dart';
import '../../../core/models/models.dart';
import '../../../shared/widgets/app_avatar.dart';
import '../../../shared/utils/format_utils.dart';

final _profileProv = FutureProvider.family.autoDispose<Map<String,dynamic>, String>((ref, uid) async {
  final api = ref.read(apiServiceProvider);
  final results = await Future.wait([
    api.get('/users/$uid'),
    api.get('/users/$uid/posts', q: {'limit': '30'}),
    api.get('/reels/user/$uid'),
    api.get('/stories/highlights/$uid'),
    api.get('/analytics/profile', q: {'period': '30d'}),
  ]);
  return {
    'user': results[0].data['user'] ?? {},
    'posts': results[1].data['posts'] ?? [],
    'reels': results[2].data['reels'] ?? [],
    'highlights': results[3].data['highlights'] ?? [],
    'analytics': results[4].data ?? {},
  };
});

class ProfileScreen extends ConsumerStatefulWidget {
  final String userId;
  const ProfileScreen({super.key, required this.userId});
  @override ConsumerState<ProfileScreen> createState() => _PS();
}
class _PS extends ConsumerState<ProfileScreen> with SingleTickerProviderStateMixin {
  late TabController _tc;
  bool _showAnalytics = false;
  @override void initState() { super.initState(); _tc = TabController(length: 3, vsync: this); }
  @override void dispose() { _tc.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(_profileProv(widget.userId));
    final me   = ref.watch(currentUserProvider);
    final dark = Theme.of(context).brightness == Brightness.dark;

    return data.when(
      loading: () => _Skel(dark: dark),
      error: (e, _) => Scaffold(appBar: AppBar(), body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.error_outline_rounded, size: 56, color: Colors.grey), const SizedBox(height: 12), ElevatedButton(onPressed: () => ref.refresh(_profileProv(widget.userId)), child: const Text('Retry'))]))),
      data: (d) {
        final user = UserModel.fromJson(Map<String,dynamic>.from(d['user'] as Map? ?? {}));
        final posts = List<Map<String,dynamic>>.from(d['posts'] as List? ?? []);
        final reels = List<Map<String,dynamic>>.from(d['reels'] as List? ?? []);
        final highlights = List<Map<String,dynamic>>.from(d['highlights'] as List? ?? []);
        final analytics = Map<String,dynamic>.from(d['analytics'] as Map? ?? {});
        final isMe = user.id == me?.id;
        final isPrivate = user.isPrivate && !isMe && user.followStatus != 'accepted';

        return Scaffold(
          backgroundColor: dark ? AppTheme.dBg : const Color(0xFFF5F5F5),
          body: NestedScrollView(
            headerSliverBuilder: (_, __) => [
              SliverAppBar(
                expandedHeight: 300,
                pinned: true,
                title: Text(user.username ?? '', style: const TextStyle(fontWeight: FontWeight.w800)),
                actions: [
                  if (isMe) IconButton(icon: const Icon(Icons.add_box_outlined), onPressed: () => context.push('/create')),
                  if (isMe) IconButton(icon: Icon(_showAnalytics ? Icons.bar_chart_rounded : Icons.bar_chart_outlined, color: _showAnalytics ? AppTheme.orange : null), onPressed: () => setState(() => _showAnalytics = !_showAnalytics)),
                  PopupMenuButton<String>(onSelected: (v) {
                    if (v == 'settings' && isMe) context.push('/settings');
                    if (v == 'share') { Clipboard.setData(ClipboardData(text: 'https://redorrange.app/${user.username}')); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile link copied!'))); }
                    if (v == 'block' && !isMe) ref.read(apiServiceProvider).post('/users/${user.id}/block').then((_) => ref.refresh(_profileProv(widget.userId)));
                    if (v == 'report' && !isMe) context.push('/report/user/${user.id}');
                  }, itemBuilder: (_) => [
                    if (isMe) const PopupMenuItem(value: 'settings', child: Row(children: [Icon(Icons.settings_rounded, size: 18), SizedBox(width: 10), Text('Settings')])),
                    const PopupMenuItem(value: 'share', child: Row(children: [Icon(Icons.share_rounded, size: 18), SizedBox(width: 10), Text('Share Profile')])),
                    if (!isMe) const PopupMenuItem(value: 'block', child: Row(children: [Icon(Icons.block_rounded, size: 18, color: Colors.red), SizedBox(width: 10), Text('Block', style: TextStyle(color: Colors.red))])),
                    if (!isMe) const PopupMenuItem(value: 'report', child: Row(children: [Icon(Icons.flag_rounded, size: 18, color: Colors.red), SizedBox(width: 10), Text('Report', style: TextStyle(color: Colors.red))])),
                  ]),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  collapseMode: CollapseMode.pin,
                  background: Stack(fit: StackFit.expand, children: [
                    user.coverUrl != null ? CachedNetworkImage(imageUrl: user.coverUrl!, fit: BoxFit.cover) : Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [AppTheme.orange, AppTheme.orangeDark]))),
                    Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, dark ? AppTheme.dBg : const Color(0xFFF5F5F5)], stops: const [0.5, 1.0]))),
                    Positioned(bottom: 0, left: 0, right: 0, child: Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Stack(children: [
                          Container(padding: const EdgeInsets.all(3), decoration: BoxDecoration(color: dark ? AppTheme.dBg : const Color(0xFFF5F5F5), shape: BoxShape.circle), child: AppAvatar(url: user.avatarUrl, size: 80, username: user.username)),
                          if (isMe) Positioned(bottom: 4, right: 4, child: GestureDetector(onTap: () => context.push('/edit-profile'), child: Container(width: 26, height: 26, decoration: const BoxDecoration(color: AppTheme.orange, shape: BoxShape.circle), child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 14)))),
                        ]),
                        const SizedBox(width: 14),
                        Expanded(child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                          _Stat(FormatUtils.count(user.postsCount),     'Posts',     () {}),
                          _Stat(FormatUtils.count(user.followersCount), 'Followers', () => context.push('/followers/${user.id}')),
                          _Stat(FormatUtils.count(user.followingCount), 'Following', () => context.push('/followers/${user.id}')),
                        ])),
                      ]),
                      const SizedBox(height: 10),
                      Row(children: [
                        Flexible(child: Text(user.displayName ?? user.username ?? '', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17))),
                        if (user.isVerified) const Padding(padding: EdgeInsets.only(left: 5), child: Icon(Icons.verified_rounded, color: AppTheme.orange, size: 16)),
                        if (user.isPrivate) const Padding(padding: EdgeInsets.only(left: 5), child: Icon(Icons.lock_rounded, size: 13, color: Colors.grey)),
                      ]),
                      if (user.statusText != null && user.statusText!.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(user.statusText!, style: const TextStyle(color: AppTheme.orange, fontSize: 12))),
                      if (user.bio != null && user.bio!.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(user.bio!, style: TextStyle(fontSize: 13, height: 1.4), maxLines: 3, overflow: TextOverflow.ellipsis)),
                      if (user.website != null) Padding(padding: const EdgeInsets.only(top: 3), child: Text(user.website!.replaceAll('https://', ''), style: const TextStyle(color: AppTheme.orange, fontSize: 12))),
                      if (user.location != null) Padding(padding: const EdgeInsets.only(top: 2), child: Row(children: [const Icon(Icons.location_on_rounded, size: 12, color: Colors.grey), const SizedBox(width: 2), Text(user.location!, style: const TextStyle(fontSize: 12, color: Colors.grey))])),
                      const SizedBox(height: 10),
                      if (isMe) Row(children: [
                        Expanded(child: OutlinedButton(onPressed: () => context.push('/edit-profile'), style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 8)), child: const Text('Edit Profile', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)))),
                        const SizedBox(width: 8),
                        OutlinedButton(onPressed: () => context.push('/auth/qr'), style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)), child: const Icon(Icons.qr_code_rounded, size: 18)),
                        const SizedBox(width: 8),
                        OutlinedButton(onPressed: () => context.push('/wallet'), style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)), child: const Icon(Icons.account_balance_wallet_rounded, size: 18)),
                      ])
                      else _OtherActions(user: user),
                    ]))),
                  ]),
                ),
              ),

              // Analytics bar
              if (isMe && _showAnalytics) SliverToBoxAdapter(child: _AnalyticsBar(analytics: analytics, dark: dark)),

              // Highlights
              if (highlights.isNotEmpty) SliverToBoxAdapter(child: _HighlightsBar(highlights: highlights)),

              // Tab bar
              SliverPersistentHeader(pinned: true, delegate: _TabDel(TabBar(
                controller: _tc, indicatorColor: AppTheme.orange, labelColor: AppTheme.orange, unselectedLabelColor: Colors.grey,
                tabs: const [Tab(icon: Icon(Icons.grid_on_rounded, size: 22)), Tab(icon: Icon(Icons.movie_creation_rounded, size: 22)), Tab(icon: Icon(Icons.person_pin_circle_rounded, size: 22))],
              ), dark: dark)),
            ],
            body: isPrivate ? _PrivateBody(user: user) : TabBarView(controller: _tc, children: [
              _PostsGrid(posts: posts, isMe: isMe),
              _ReelsGrid(reels: reels),
              _TaggedGrid(userId: user.id),
            ]),
          ),
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  final String v, l; final VoidCallback t;
  const _Stat(this.v, this.l, this.t);
  @override Widget build(BuildContext _) => GestureDetector(onTap: t, child: Column(children: [Text(v, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)), const SizedBox(height: 1), Text(l, style: const TextStyle(fontSize: 12, color: Colors.grey))]));
}

class _AnalyticsBar extends StatelessWidget {
  final Map<String,dynamic> analytics; final bool dark;
  const _AnalyticsBar({required this.analytics, required this.dark});
  @override Widget build(BuildContext ctx) => GestureDetector(
    onTap: () => ctx.push('/analytics'),
    child: Container(margin: const EdgeInsets.fromLTRB(12, 6, 12, 4), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.orange.withOpacity(0.25))),
      child: Column(children: [
        Row(children: [const Icon(Icons.analytics_rounded, color: AppTheme.orange, size: 16), const SizedBox(width: 6), const Text('Analytics · Last 30 days', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.orange)), const Spacer(), const Text('Full Report →', style: TextStyle(color: AppTheme.orange, fontSize: 11))]),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _AItem(Icons.remove_red_eye_rounded, FormatUtils.count(analytics['profile_views'] as int? ?? 0), 'Views',      const Color(0xFF2196F3)),
          _AItem(Icons.people_rounded,         FormatUtils.count(analytics['followers_count'] as int? ?? 0), 'Followers', const Color(0xFF4CAF50)),
          _AItem(Icons.bar_chart_rounded,      FormatUtils.count(analytics['impressions'] as int? ?? 0),    'Reach',      AppTheme.orange),
          _AItem(Icons.trending_up_rounded,    '${analytics['engagement_rate'] ?? '0.0'}%',                 'Engage',     const Color(0xFF9C27B0)),
        ]),
      ]),
    ),
  );
}
class _AItem extends StatelessWidget {
  final IconData i; final String v, l; final Color c;
  const _AItem(this.i, this.v, this.l, this.c);
  @override Widget build(BuildContext _) => Column(children: [Icon(i, color: c, size: 18), const SizedBox(height: 3), Text(v, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: c)), Text(l, style: const TextStyle(fontSize: 9, color: Colors.grey))]);
}

class _HighlightsBar extends StatelessWidget {
  final List<Map<String,dynamic>> highlights;
  const _HighlightsBar({required this.highlights});
  @override Widget build(BuildContext ctx) => SizedBox(height: 86, child: ListView.builder(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), itemCount: highlights.length, itemBuilder: (_, i) {
    final h = highlights[i];
    return GestureDetector(onTap: () => ctx.push('/highlight/${h['id']}'), child: Padding(padding: const EdgeInsets.only(right: 12), child: Column(children: [
      Container(width: 54, height: 54, decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [AppTheme.orange, AppTheme.orangeDark])), padding: const EdgeInsets.all(2), child: Container(decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white), padding: const EdgeInsets.all(2), child: ClipOval(child: h['cover_url'] != null ? CachedNetworkImage(imageUrl: h['cover_url'], fit: BoxFit.cover) : Container(color: AppTheme.orangeSurf, child: const Icon(Icons.auto_stories_rounded, color: AppTheme.orange, size: 20))))),
      const SizedBox(height: 3),
      SizedBox(width: 60, child: Text(h['name'] ?? '', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center)),
    ])));
  }));
}

class _PostsGrid extends ConsumerWidget {
  final List<Map<String,dynamic>> posts; final bool isMe;
  const _PostsGrid({required this.posts, required this.isMe});
  @override Widget build(BuildContext ctx, WidgetRef ref) {
    if (posts.isEmpty) return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.grid_on_rounded, size: 64, color: Colors.grey), SizedBox(height: 12), Text('No posts yet', style: TextStyle(color: Colors.grey))]));
    return RefreshIndicator(color: AppTheme.orange, onRefresh: () async {}, child: GridView.builder(
      padding: const EdgeInsets.all(1.5),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 1.5, mainAxisSpacing: 1.5),
      itemCount: posts.length,
      itemBuilder: (_, i) {
        final p = posts[i];
        final thumb = p['thumbnail'] ?? (p['media'] is List && (p['media'] as List).isNotEmpty ? (p['media'] as List)[0]['media_url'] : null);
        final likes = p['likes_count'] as int? ?? 0;
        final views = p['views_count'] as int? ?? 0;
        final isMulti = (p['media_count'] as int? ?? (p['media'] is List ? (p['media'] as List).length : 1)) > 1;
        return GestureDetector(
          onTap: () => ctx.push('/post/${p['id']}'),
          onLongPress: isMe ? () => _showQuick(ctx, ref, p) : null,
          child: Stack(fit: StackFit.expand, children: [
            thumb != null ? CachedNetworkImage(imageUrl: thumb, fit: BoxFit.cover, errorWidget: (_, __, ___) => Container(color: AppTheme.orangeSurf)) : Container(color: AppTheme.orangeSurf, child: const Icon(Icons.image_rounded, color: AppTheme.orange)),
            Positioned.fill(child: Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black.withOpacity(0.5)])))),
            if (isMulti) const Positioned(top: 5, right: 5, child: Icon(Icons.collections_rounded, color: Colors.white, size: 13)),
            Positioned(bottom: 4, left: 4, right: 4, child: Row(children: [
              if (isMe) ...[const Icon(Icons.remove_red_eye_rounded, color: Colors.white, size: 9), const SizedBox(width: 2), Text(FormatUtils.count(views), style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600)), const SizedBox(width: 6)],
              const Icon(Icons.favorite_rounded, color: Colors.white, size: 9), const SizedBox(width: 2), Text(FormatUtils.count(likes), style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600)),
            ])),
          ]),
        );
      },
    ));
  }
  void _showQuick(BuildContext ctx, WidgetRef ref, Map p) {
    showModalBottomSheet(context: ctx, backgroundColor: Colors.transparent, builder: (_) {
      final dark = Theme.of(ctx).brightness == Brightness.dark;
      return Container(margin: const EdgeInsets.all(10), decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(18)), padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Post Performance', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _QS(Icons.remove_red_eye_rounded, FormatUtils.count(p['views_count'] as int? ?? 0), 'Views', const Color(0xFF2196F3)),
          _QS(Icons.favorite_rounded, FormatUtils.count(p['likes_count'] as int? ?? 0), 'Likes', Colors.red),
          _QS(Icons.chat_bubble_rounded, FormatUtils.count(p['comments_count'] as int? ?? 0), 'Comments', const Color(0xFF9C27B0)),
          _QS(Icons.send_rounded, FormatUtils.count(p['shares_count'] as int? ?? 0), 'Shares', AppTheme.orange),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: OutlinedButton.icon(onPressed: () { Navigator.pop(ctx); ctx.push('/post/${p['id']}/insights'); }, icon: const Icon(Icons.analytics_rounded, size: 16), label: const Text('Insights'))),
          const SizedBox(width: 10),
          Expanded(child: ElevatedButton.icon(onPressed: () { Navigator.pop(ctx); ctx.push('/post/${p['id']}/boost'); }, icon: const Icon(Icons.rocket_launch_rounded, size: 16), label: const Text('Boost'))),
        ]),
      ]));
    });
  }
}
class _QS extends StatelessWidget {
  final IconData i; final String v, l; final Color c;
  const _QS(this.i, this.v, this.l, this.c);
  @override Widget build(BuildContext _) => Column(children: [Icon(i, color: c, size: 26), const SizedBox(height: 3), Text(v, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: c)), Text(l, style: const TextStyle(fontSize: 10, color: Colors.grey))]);
}

class _ReelsGrid extends StatelessWidget {
  final List<Map<String,dynamic>> reels;
  const _ReelsGrid({required this.reels});
  @override Widget build(BuildContext ctx) {
    if (reels.isEmpty) return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.movie_creation_rounded, size: 64, color: Colors.grey), SizedBox(height: 12), Text('No reels yet', style: TextStyle(color: Colors.grey))]));
    return GridView.builder(padding: const EdgeInsets.all(1.5), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 1.5, mainAxisSpacing: 1.5, childAspectRatio: 0.6), itemCount: reels.length, itemBuilder: (_, i) {
      final r = reels[i];
      return GestureDetector(onTap: () => ctx.push('/reel/${r['id']}'), child: Stack(fit: StackFit.expand, children: [
        r['thumbnail_url'] != null ? CachedNetworkImage(imageUrl: r['thumbnail_url'], fit: BoxFit.cover) : Container(color: const Color(0xFF1A1A1A), child: const Icon(Icons.play_circle_rounded, color: Colors.white38, size: 36)),
        Positioned.fill(child: Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black.withOpacity(0.7)])))),
        Positioned(bottom: 5, left: 5, child: Row(children: [const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 13), const SizedBox(width: 2), Text(FormatUtils.count(r['views_count'] as int? ?? 0), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600))])),
      ]));
    });
  }
}

class _TaggedGrid extends ConsumerStatefulWidget {
  final String userId;
  const _TaggedGrid({required this.userId});
  @override ConsumerState<_TaggedGrid> createState() => _TGS();
}
class _TGS extends ConsumerState<_TaggedGrid> {
  List<dynamic> _p = []; bool _l = true;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async { try { final r = await ref.read(apiServiceProvider).get('/users/${widget.userId}/tagged'); setState(() { _p = r.data['posts'] ?? []; _l = false; }); } catch (_) { setState(() => _l = false); } }
  @override Widget build(BuildContext ctx) {
    if (_l) return const Center(child: CircularProgressIndicator(color: AppTheme.orange));
    if (_p.isEmpty) return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.person_pin_circle_rounded, size: 64, color: Colors.grey), SizedBox(height: 12), Text('No tagged posts', style: TextStyle(color: Colors.grey))]));
    return GridView.builder(padding: const EdgeInsets.all(1.5), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 1.5, mainAxisSpacing: 1.5), itemCount: _p.length, itemBuilder: (_, i) {
      final p = _p[i];
      return GestureDetector(onTap: () => ctx.push('/post/${p['id']}'), child: p['thumbnail'] != null ? CachedNetworkImage(imageUrl: p['thumbnail'], fit: BoxFit.cover) : Container(color: AppTheme.orangeSurf));
    });
  }
}

class _OtherActions extends ConsumerStatefulWidget {
  final UserModel user;
  const _OtherActions({required this.user});
  @override ConsumerState<_OtherActions> createState() => _OAS();
}
class _OAS extends ConsumerState<_OtherActions> {
  String? _fs; bool _l = false;
  @override void initState() { super.initState(); _fs = widget.user.followStatus; }
  @override Widget build(BuildContext ctx) => Row(children: [
    Expanded(child: ElevatedButton(onPressed: _l ? null : () async { setState(() => _l = true); final r = await ref.read(apiServiceProvider).post('/users/${widget.user.id}/follow').catchError((_) => null); if (mounted) setState(() { _fs = r?.data['status'] ?? (_fs == 'accepted' ? null : 'pending'); _l = false; }); }, style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 9)), child: _l ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(_fs == 'accepted' ? 'Following' : _fs == 'pending' ? 'Requested' : 'Follow', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)))),
    const SizedBox(width: 8),
    Expanded(child: OutlinedButton(onPressed: () async { final r = await ref.read(apiServiceProvider).post('/messages/conversations', data: {'type': 'direct', 'user_id': widget.user.id}); if (ctx.mounted) ctx.push('/chat/${r.data['conversation']['id']}'); }, style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 9)), child: const Text('Message', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)))),
    const SizedBox(width: 8),
    OutlinedButton(onPressed: () => ctx.push('/call/audio', extra: {'user_id': widget.user.id, 'user_name': widget.user.displayName ?? '', 'avatar': widget.user.avatarUrl, 'is_incoming': false}), style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9)), child: const Icon(Icons.call_rounded, size: 18)),
  ]);
}

class _PrivateBody extends StatelessWidget {
  final UserModel user;
  const _PrivateBody({required this.user});
  @override Widget build(BuildContext _) => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.lock_rounded, size: 52, color: Colors.grey), const SizedBox(height: 14), const Text('This Account is Private', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)), const SizedBox(height: 8), Text('Follow to see posts from ${user.displayName ?? user.username}', style: const TextStyle(color: Colors.grey, fontSize: 13), textAlign: TextAlign.center)]));
}

class _TabDel extends SliverPersistentHeaderDelegate {
  final TabBar t; final bool dark;
  const _TabDel(this.t, {required this.dark});
  @override double get minExtent => t.preferredSize.height;
  @override double get maxExtent => t.preferredSize.height;
  @override Widget build(_, __, ___) => Container(color: dark ? AppTheme.dBg : const Color(0xFFF5F5F5), child: t);
  @override bool shouldRebuild(_) => false;
}

class _Skel extends StatelessWidget {
  final bool dark;
  const _Skel({required this.dark});
  @override Widget build(BuildContext ctx) => Scaffold(appBar: AppBar(), body: Shimmer.fromColors(baseColor: dark ? const Color(0xFF2A2A2A) : const Color(0xFFE0E0E0), highlightColor: dark ? const Color(0xFF383838) : const Color(0xFFF5F5F5), child: ListView(children: [
    Container(height: 200, color: Colors.white),
    Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Container(width: 80, height: 80, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white)), const SizedBox(width: 16), Expanded(child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [Container(width: 50, height: 40, color: Colors.white), Container(width: 50, height: 40, color: Colors.white), Container(width: 50, height: 40, color: Colors.white)]))]),
      const SizedBox(height: 12), Container(height: 16, width: 160, color: Colors.white), const SizedBox(height: 8), Container(height: 12, width: 220, color: Colors.white),
    ])),
  ])));
}
