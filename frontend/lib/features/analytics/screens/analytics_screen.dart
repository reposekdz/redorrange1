import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/api_service.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../shared/utils/format_utils.dart';

final _analyticsProv = FutureProvider.autoDispose<Map<String,dynamic>>((ref) async {
  final r = await ref.read(apiServiceProvider).get('/analytics/profile');
  return Map<String,dynamic>.from(r.data);
});

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});
  @override ConsumerState<AnalyticsScreen> createState() => _S();
}
class _S extends ConsumerState<AnalyticsScreen> with SingleTickerProviderStateMixin {
  late TabController _tc;
  String _period = '7d';
  @override void initState() { super.initState(); _tc = TabController(length: 3, vsync: this); }
  @override void dispose() { _tc.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final data  = ref.watch(_analyticsProv);
    final me    = ref.watch(currentUserProvider);
    final dark  = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          // Period selector
          Container(margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.symmetric(horizontal: 4), decoration: BoxDecoration(color: dark ? AppTheme.dCard : AppTheme.lInput, borderRadius: BorderRadius.circular(10)),
            child: DropdownButtonHideUnderline(child: DropdownButton<String>(
              value: _period, isDense: true,
              items: const [
                DropdownMenuItem(value: '7d',  child: Text('7 days')),
                DropdownMenuItem(value: '30d', child: Text('30 days')),
                DropdownMenuItem(value: '90d', child: Text('90 days')),
              ],
              onChanged: (v) { setState(() => _period = v!); ref.refresh(_analyticsProv); },
            ))),
        ],
        bottom: TabBar(controller: _tc, indicatorColor: AppTheme.orange, labelColor: AppTheme.orange, unselectedLabelColor: Colors.grey,
          tabs: const [Tab(text: 'Overview'), Tab(text: 'Content'), Tab(text: 'Audience')]),
      ),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.orange)),
        error: (e, _) => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.bar_chart_rounded, size: 64, color: Colors.grey),
          const SizedBox(height: 12), Text('$e', style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 12), ElevatedButton(onPressed: () => ref.refresh(_analyticsProv), child: const Text('Retry')),
        ])),
        data: (d) => TabBarView(controller: _tc, children: [
          _Overview(data: d, dark: dark, period: _period),
          _Content(data: d, dark: dark),
          _Audience(data: d, dark: dark),
        ]),
      ),
    );
  }
}

// ─────────── Overview Tab
class _Overview extends StatelessWidget {
  final Map<String,dynamic> data;
  final bool dark;
  final String period;
  const _Overview({required this.data, required this.dark, required this.period});

  @override
  Widget build(BuildContext ctx) => ListView(padding: const EdgeInsets.all(14), children: [
    // Summary cards grid
    GridView.count(crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.5, children: [
      _StatCard('Profile Views',    FormatUtils.count(data['profile_views'] as int? ?? 0),     Icons.remove_red_eye_rounded,       const Color(0xFF2196F3), _trend(data, 'profile_views_trend')),
      _StatCard('Impressions',      FormatUtils.count(data['impressions'] as int? ?? 0),        Icons.bar_chart_rounded,            AppTheme.orange,         _trend(data, 'impressions_trend')),
      _StatCard('Followers',        FormatUtils.count(data['followers_count'] as int? ?? 0),    Icons.people_rounded,               const Color(0xFF4CAF50), _trend(data, 'followers_trend')),
      _StatCard('Engagement Rate',  '${data['engagement_rate'] ?? '0.0'}%',                     Icons.trending_up_rounded,          const Color(0xFF9C27B0), _trend(data, 'engagement_trend')),
      _StatCard('Story Views',      FormatUtils.count(data['story_views'] as int? ?? 0),        Icons.auto_stories_rounded,         const Color(0xFFE91E63), null),
      _StatCard('Reel Views',       FormatUtils.count(data['reel_views'] as int? ?? 0),         Icons.play_circle_rounded,          Colors.red,              null),
    ]),
    const SizedBox(height: 16),

    // Follower growth chart
    _ChartCard(
      title: 'Follower Growth',
      subtitle: 'Last $period',
      icon: Icons.show_chart_rounded,
      data: List<Map<String,dynamic>>.from(data['daily_followers'] ?? []),
      dark: dark,
    ),
    const SizedBox(height: 12),

    // Reach vs impressions
    _ChartCard(
      title: 'Reach vs Impressions',
      subtitle: 'Unique accounts reached',
      icon: Icons.people_alt_rounded,
      data: List<Map<String,dynamic>>.from(data['reach_data'] ?? []),
      dark: dark,
      color: const Color(0xFF2196F3),
    ),
  ]);

  static double? _trend(Map d, String k) {
    final v = d[k];
    if (v == null) return null;
    return double.tryParse(v.toString());
  }
}

// ─────────── Content Tab
class _Content extends StatelessWidget {
  final Map<String,dynamic> data;
  final bool dark;
  const _Content({required this.data, required this.dark});

  @override
  Widget build(BuildContext ctx) {
    final topPosts = List<Map<String,dynamic>>.from(data['top_posts'] ?? []);
    final topReels = List<Map<String,dynamic>>.from(data['top_reels'] ?? []);

    return ListView(padding: const EdgeInsets.all(14), children: [
      // Content breakdown
      Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(14)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Content Performance', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 14),
        _PerfBar('Posts',      data['posts_reach']  as int? ?? 0, data['posts_count']  as int? ?? 1, AppTheme.orange),
        const SizedBox(height: 10),
        _PerfBar('Stories',    data['story_reach']  as int? ?? 0, data['story_count']  as int? ?? 1, const Color(0xFF2196F3)),
        const SizedBox(height: 10),
        _PerfBar('Reels',      data['reels_reach']  as int? ?? 0, data['reels_count']  as int? ?? 1, const Color(0xFFE91E63)),
      ])),
      const SizedBox(height: 14),

      // Top posts
      if (topPosts.isNotEmpty) Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Top Posts', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          TextButton(onPressed: () {}, child: const Text('See all', style: TextStyle(color: AppTheme.orange, fontSize: 13))),
        ]),
        const SizedBox(height: 8),
        ...topPosts.take(3).map((p) => _ContentRow(p: p, type: 'post', dark: dark, onTap: () => ctx.push('/post/${p['id']}'))),
      ]),

      if (topReels.isNotEmpty) Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 14),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Top Reels', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          TextButton(onPressed: () {}, child: const Text('See all', style: TextStyle(color: AppTheme.orange, fontSize: 13))),
        ]),
        const SizedBox(height: 8),
        ...topReels.take(3).map((r) => _ContentRow(p: r, type: 'reel', dark: dark, onTap: () => ctx.push('/reel/${r['id']}'))),
      ]),
    ]);
  }
}

// ─────────── Audience Tab
class _Audience extends StatelessWidget {
  final Map<String,dynamic> data;
  final bool dark;
  const _Audience({required this.data, required this.dark});

  @override
  Widget build(BuildContext ctx) {
    final locations = List<Map<String,dynamic>>.from(data['top_locations'] ?? []);
    final genders   = data['gender_split'] as Map? ?? {};

    return ListView(padding: const EdgeInsets.all(14), children: [
      // Gender split
      Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(14)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Gender Split', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _GenderBar('Male',   genders['male']   as int? ?? 55, AppTheme.orange)),
          const SizedBox(width: 10),
          Expanded(child: _GenderBar('Female', genders['female'] as int? ?? 40, const Color(0xFFE91E63))),
          const SizedBox(width: 10),
          Expanded(child: _GenderBar('Other',  genders['other']  as int? ?? 5,  Colors.grey)),
        ]),
      ])),
      const SizedBox(height: 12),

      // Age groups
      Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(14)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Age Groups', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 12),
        ...[['13–17', 5], ['18–24', 38], ['25–34', 32], ['35–44', 15], ['45+', 10]].map((e) { final age = e[0] as String; final pct = e[1] as int; return
          Padding(padding: const EdgeInsets.only(bottom: 8), child: _PerfBar(age, pct, 100, AppTheme.orange)); }),
      ])),
      const SizedBox(height: 12),

      // Top locations
      if (locations.isNotEmpty) Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(14)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Top Locations', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 12),
        ...locations.take(5).toList().asMap().entries.map((e) => ListTile(contentPadding: EdgeInsets.zero, dense: true,
          leading: CircleAvatar(backgroundColor: AppTheme.orangeSurf, radius: 16, child: Text('${e.key+1}', style: const TextStyle(color: AppTheme.orange, fontWeight: FontWeight.w800, fontSize: 12))),
          title: Text(e.value['city'] ?? e.value['country'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          trailing: Text('${e.value['pct'] ?? 0}%', style: const TextStyle(color: AppTheme.orange, fontWeight: FontWeight.w700)))),
      ])),
      const SizedBox(height: 12),

      // Peak hours
      Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(14)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Best Time to Post', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 4),
        Text('Based on when your audience is most active', style: TextStyle(fontSize: 12, color: dark ? AppTheme.dSub : AppTheme.lSub)),
        const SizedBox(height: 16),
        Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          for (final (h, lbl, rel) in [
            ('06', '6am', 0.3), ('09', '9am', 0.6), ('12', '12pm', 0.8),
            ('15', '3pm', 0.5), ('18', '6pm', 1.0), ('21', '9pm', 0.9), ('00', '12am', 0.4),
          ]) Column(children: [
            Container(width: 26, height: 90 * rel, decoration: BoxDecoration(
              gradient: rel >= 0.8 ? const LinearGradient(colors: [AppTheme.orange, AppTheme.orangeDark], begin: Alignment.topCenter, end: Alignment.bottomCenter) : null,
              color: rel < 0.8 ? AppTheme.orange.withOpacity(0.3) : null,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
            )),
            const SizedBox(height: 4),
            Text(lbl, style: TextStyle(fontSize: 9, color: rel >= 0.8 ? AppTheme.orange : Colors.grey, fontWeight: rel >= 0.8 ? FontWeight.w700 : FontWeight.w400)),
          ]),
        ]),
        const SizedBox(height: 8),
        Center(child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: AppTheme.orangeSurf, borderRadius: BorderRadius.circular(20)), child: const Text('Best: 6 PM – 9 PM', style: TextStyle(color: AppTheme.orange, fontWeight: FontWeight.w700, fontSize: 12)))),
      ])),
    ]);
  }
}

// ─────────── Sub-widgets
class _StatCard extends StatelessWidget {
  final String label, value; final IconData icon; final Color color; final double? trend;
  const _StatCard(this.label, this.value, this.icon, this.color, this.trend);
  @override Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Container(width: 34, height: 34, decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(9)), child: Icon(icon, color: color, size: 18)),
          if (trend != null) Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(trend! >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded, size: 14, color: trend! >= 0 ? Colors.green : Colors.red),
            Text('${trend!.abs().toStringAsFixed(0)}%', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: trend! >= 0 ? Colors.green : Colors.red)),
          ]),
        ]),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: color)),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ]),
      ]));
  }
}

class _PerfBar extends StatelessWidget {
  final String label; final int value, max; final Color color;
  const _PerfBar(this.label, this.value, this.max, this.color);
  @override Widget build(BuildContext _) => Row(children: [
    SizedBox(width: 70, child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
    Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: max > 0 ? (value / max).clamp(0.0, 1.0) : 0, backgroundColor: Colors.grey.shade200, valueColor: AlwaysStoppedAnimation(color), minHeight: 8))),
    const SizedBox(width: 8),
    SizedBox(width: 40, child: Text(max == 100 ? '$value%' : FormatUtils.count(value), style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12), textAlign: TextAlign.right)),
  ]);
}

class _GenderBar extends StatelessWidget {
  final String label; final int pct; final Color color;
  const _GenderBar(this.label, this.pct, this.color);
  @override Widget build(BuildContext _) => Column(children: [
    Container(width: 48, height: 48, decoration: BoxDecoration(shape: BoxShape.circle, color: color.withOpacity(0.1)),
      child: Center(child: Text('$pct%', style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13)))),
    const SizedBox(height: 6),
    Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
  ]);
}

class _ChartCard extends StatelessWidget {
  final String title, subtitle; final IconData icon;
  final List<Map<String,dynamic>> data; final bool dark; final Color? color;
  const _ChartCard({required this.title, required this.subtitle, required this.icon, required this.data, required this.dark, this.color});

  @override
  Widget build(BuildContext _) {
    if (data.isEmpty) return const SizedBox.shrink();
    final vals = data.map((d) => (d['count'] as int? ?? d['value'] as int? ?? 0).toDouble()).toList();
    final maxV = vals.isEmpty ? 1.0 : (vals.reduce((a, b) => a > b ? a : b));
    final c = color ?? AppTheme.orange;

    return Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(14)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(icon, color: c, size: 20), const SizedBox(width: 8), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)), Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey))])]),
      const SizedBox(height: 16),
      SizedBox(height: 80, child: Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        for (int i = 0; i < vals.length; i++) Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 1), child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
          Container(height: maxV > 0 ? (vals[i] / maxV * 70).clamp(4.0, 70.0) : 4,
            decoration: BoxDecoration(color: i == vals.length - 1 ? c : c.withOpacity(0.4), borderRadius: const BorderRadius.vertical(top: Radius.circular(3)))),
          const SizedBox(height: 4),
          if (data[i]['date'] != null) Text(_fmtDate(data[i]['date'].toString()), style: const TextStyle(fontSize: 8, color: Colors.grey)),
        ]))),
      ])),
    ]));
  }
  static String _fmtDate(String d) { try { final dt = DateTime.parse(d); return '${dt.day}/${dt.month}'; } catch (_) { return d.length > 5 ? d.substring(d.length - 5) : d; } }
}

class _ContentRow extends StatelessWidget {
  final Map<String,dynamic> p; final String type; final bool dark; final VoidCallback onTap;
  const _ContentRow({required this.p, required this.type, required this.dark, required this.onTap});
  @override Widget build(BuildContext _) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(12), child: Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(12)), child: Row(children: [
    ClipRRect(borderRadius: BorderRadius.circular(8), child: p['thumbnail'] != null ? CachedNetworkImage(imageUrl: p['thumbnail'], width: 48, height: 48, fit: BoxFit.cover, errorWidget: (_, __, ___) => Container(width: 48, height: 48, color: AppTheme.orangeSurf, child: Icon(type == 'reel' ? Icons.play_arrow_rounded : Icons.image_rounded, color: AppTheme.orange))) : Container(width: 48, height: 48, color: AppTheme.orangeSurf, child: Icon(type == 'reel' ? Icons.play_arrow_rounded : Icons.image_rounded, color: AppTheme.orange))),
    const SizedBox(width: 12),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(p['caption'] ?? '(No caption)', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      const SizedBox(height: 3),
      Row(children: [
        _Chip(Icons.remove_red_eye_rounded, FormatUtils.count(p['views_count'] as int? ?? 0)),
        const SizedBox(width: 10),
        _Chip(Icons.favorite_rounded, FormatUtils.count(p['likes_count'] as int? ?? 0)),
        const SizedBox(width: 10),
        _Chip(Icons.chat_bubble_rounded, FormatUtils.count(p['comments_count'] as int? ?? 0)),
      ]),
    ])),
    const Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 18),
  ])));
}

class _Chip extends StatelessWidget {
  final IconData icon; final String val;
  const _Chip(this.icon, this.val);
  @override Widget build(BuildContext _) => Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 11, color: Colors.grey), const SizedBox(width: 3), Text(val, style: const TextStyle(fontSize: 11, color: Colors.grey))]);
}
