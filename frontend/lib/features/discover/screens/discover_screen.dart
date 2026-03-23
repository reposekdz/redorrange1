
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_theme.dart';
import '../../ads/widgets/ad_widgets.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/widgets/app_avatar.dart';
import '../../../shared/utils/format_utils.dart';
import '../../../shared/utils/responsive.dart';

final _discoverProv = FutureProvider.autoDispose<Map<String,dynamic>>((ref) async {
  final r = await ref.read(apiServiceProvider).get('/discover/explore');
  return Map<String,dynamic>.from(r.data);
});

class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});
  @override ConsumerState<DiscoverScreen> createState() => _S();
}
class _S extends ConsumerState<DiscoverScreen> with SingleTickerProviderStateMixin {
  late TabController _tc;
  @override void initState() { super.initState(); _tc = TabController(length: 4, vsync: this); }
  @override void dispose() { _tc.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext ctx) {
    final data = ref.watch(_discoverProv);
    final dark = Theme.of(ctx).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('Discover', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [IconButton(icon: const Icon(Icons.search_rounded), onPressed: () => ctx.push('/search'))],
        bottom: TabBar(controller: _tc, indicatorColor: AppTheme.orange, labelColor: AppTheme.orange, unselectedLabelColor: Colors.grey, tabs: const [Tab(text: 'Explore'), Tab(text: 'People'), Tab(text: 'Events'), Tab(text: 'Trending')])),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.orange)),
        error: (e, _) => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.wifi_off_rounded, size: 56, color: AppTheme.orange), const SizedBox(height: 12), ElevatedButton(onPressed: () => ref.refresh(_discoverProv), child: const Text('Retry'))])),
        data: (d) => TabBarView(controller: _tc, children: [
          _ExploreTab(posts: List.from(d['posts'] ?? []), hashtags: List.from(d['trending_hashtags'] ?? [])),
          _PeopleTab(users: List.from(d['suggested_users'] ?? [])),
          _EventsTab(events: List.from(d['upcoming_events'] ?? [])),
          _TrendingTab(hashtags: List.from(d['trending_hashtags'] ?? [])),
        ]),
      ),
    );
  }
}

class _ExploreTab extends StatelessWidget {
  final List posts, hashtags;
  const _ExploreTab({required this.posts, required this.hashtags});
  @override
  Widget build(BuildContext ctx) => CustomScrollView(slivers: [
    SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(14,14,14,8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Trending Now', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      const SizedBox(height: 10),
      SizedBox(height: 36, child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: hashtags.length, itemBuilder: (_, i) => GestureDetector(onTap: () => ctx.push('/hashtag/${hashtags[i]['name']}'), child: Container(margin: const EdgeInsets.only(right: 8), child: ActionChip(label: Text('#${hashtags[i]['name']}', style: const TextStyle(fontSize: 12)), backgroundColor: AppTheme.orangeSurf, labelStyle: const TextStyle(color: AppTheme.orange), onPressed: () => ctx.push('/hashtag/${hashtags[i]['name']}')))))),
      const SizedBox(height: 14), const Text('Explore Posts', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
    ]))),
    SliverPadding(padding: const EdgeInsets.symmetric(horizontal: 1), sliver: SliverGrid(
      delegate: SliverChildBuilderDelegate((_, i) {
        final p = posts[i]; final thumb = p['thumbnail'];
        return GestureDetector(onTap: () => ctx.push('/post/${p['id']}'), child: Stack(fit: StackFit.expand, children: [
          thumb != null ? CachedNetworkImage(imageUrl: thumb, fit: BoxFit.cover, errorWidget: (_, __, ___) => Container(color: AppTheme.orangeSurf)) : Container(color: AppTheme.orangeSurf, child: const Icon(Icons.image, color: AppTheme.orange)),
          if (p['type'] == 'video') const Positioned(top: 6, right: 6, child: Icon(Icons.videocam_rounded, color: Colors.white, size: 16)),
          if ((p['media_count'] as int? ?? 0) > 1) const Positioned(top: 6, right: 6, child: Icon(Icons.collections_rounded, color: Colors.white, size: 16)),
        ]));
      }, childCount: posts.length),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 2, mainAxisSpacing: 2),
    )),
  ]);
}

class _PeopleTab extends ConsumerWidget {
  final List users;
  const _PeopleTab({required this.users});
  @override
  Widget build(BuildContext ctx, WidgetRef ref) => users.isEmpty
    ? const Center(child: Text('No suggestions available', style: TextStyle(color: Colors.grey)))
    : ListView.builder(padding: const EdgeInsets.all(12), itemCount: users.length, itemBuilder: (_, i) {
        final u = users[i];
        return Card(margin: const EdgeInsets.only(bottom: 8), child: ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          leading: AppAvatar(url: u['avatar_url'], size: 50, username: u['username']),
          title: Row(children: [Text(u['display_name'] ?? u['username'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700)), if (u['is_verified'] == 1 || u['is_verified'] == true) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.verified_rounded, color: AppTheme.orange, size: 14))]),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('@${u['username'] ?? ''}'), Text('${FormatUtils.count(u['followers_count'] as int? ?? 0)} followers  •  ${u['mutual_count'] != null ? '${u['mutual_count']} mutual' : ''}', style: const TextStyle(fontSize: 11))]),
          trailing: SizedBox(height: 34, child: ElevatedButton(onPressed: () async { await ref.read(apiServiceProvider).post('/users/${u['id']}/follow'); }, style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0), textStyle: const TextStyle(fontSize: 12)), child: const Text('Follow'))),
          onTap: () => ctx.push('/profile/${u['id']}'),
        ));
      });
}

class _EventsTab extends StatelessWidget {
  final List events;
  const _EventsTab({required this.events});
  @override
  Widget build(BuildContext ctx) => events.isEmpty
    ? const Center(child: Text('No upcoming events', style: TextStyle(color: Colors.grey)))
    : ListView.builder(padding: const EdgeInsets.all(12), itemCount: events.length, itemBuilder: (_, i) {
        final e = events[i];
        return Card(margin: const EdgeInsets.only(bottom: 10), child: InkWell(onTap: () => ctx.push('/event/${e['id']}'), borderRadius: BorderRadius.circular(14), child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
          ClipRRect(borderRadius: BorderRadius.circular(10), child: e['cover_url'] != null ? CachedNetworkImage(imageUrl: e['cover_url'], width: 72, height: 72, fit: BoxFit.cover) : Container(width: 72, height: 72, color: AppTheme.orangeSurf, child: const Icon(Icons.event_rounded, color: AppTheme.orange, size: 36))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(e['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14), maxLines: 2),
            const SizedBox(height: 4),
            Row(children: [const Icon(Icons.calendar_today_rounded, size: 12, color: AppTheme.orange), const SizedBox(width: 4), Text(_fmtDate(e['start_datetime']), style: const TextStyle(fontSize: 12, color: AppTheme.orange, fontWeight: FontWeight.w500))]),
            if (e['location'] != null) Row(children: [const Icon(Icons.location_on_rounded, size: 12, color: Colors.grey), const SizedBox(width: 4), Expanded(child: Text(e['location'], style: const TextStyle(fontSize: 12, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis))]),
            Text('${e['going_count'] ?? 0} going', style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ])),
        ]))));
      });
  static String _fmtDate(String? s) { if (s == null) return ''; try { final d = DateTime.parse(s).toLocal(); const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec']; return '${m[d.month-1]} ${d.day}'; } catch (_) { return s ?? ''; } }
}

class _TrendingTab extends StatelessWidget {
  final List hashtags;
  const _TrendingTab({required this.hashtags});
  @override
  Widget build(BuildContext ctx) => hashtags.isEmpty
    ? const Center(child: Text('No trending topics', style: TextStyle(color: Colors.grey)))
    : ListView.builder(padding: const EdgeInsets.all(12), itemCount: hashtags.length, itemBuilder: (_, i) {
        final h = hashtags[i];
        return Card(margin: const EdgeInsets.only(bottom: 8), child: ListTile(
          leading: Container(width: 48, height: 48, decoration: BoxDecoration(color: AppTheme.orangeSurf, borderRadius: BorderRadius.circular(12)), child: Center(child: Text('#', style: TextStyle(color: AppTheme.orange, fontWeight: FontWeight.w900, fontSize: 22)))),
          title: Text('#${h['name']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          subtitle: Text('${FormatUtils.count(h['posts_count'] as int? ?? 0)} posts', style: const TextStyle(fontSize: 12)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [Text('#${i+1}', style: TextStyle(color: AppTheme.orange.withOpacity(0.7), fontWeight: FontWeight.w800, fontSize: 16))]),
          onTap: () => ctx.push('/hashtag/${h['name']}'),
        ));
      });
}
