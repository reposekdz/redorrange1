
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/utils/format_utils.dart';

class PostInsightsScreen extends ConsumerStatefulWidget {
  final String postId;
  const PostInsightsScreen({super.key, required this.postId});
  @override ConsumerState<PostInsightsScreen> createState() => _S();
}
class _S extends ConsumerState<PostInsightsScreen> {
  Map<String,dynamic>? _data; bool _l = true;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try {
      final r = await ref.read(apiServiceProvider).get('/posts/${widget.postId}/insights');
      setState(() { _data = r.data; _l = false; });
    } catch (_) { setState(() => _l = false); }
  }
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('Post Insights', style: TextStyle(fontWeight: FontWeight.w800))),
      body: _l ? const Center(child: CircularProgressIndicator(color: AppTheme.orange)) : ListView(padding: const EdgeInsets.all(16), children: [
        // Key metrics grid
        GridView.count(crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.6, children: [
          _InsightCard('Impressions',  FormatUtils.count(_data?['views_count'] as int? ?? 0),    Icons.remove_red_eye_rounded, const Color(0xFF2196F3)),
          _InsightCard('Reach',        FormatUtils.count(_data?['reach'] as int? ?? 0),           Icons.people_rounded,          AppTheme.orange),
          _InsightCard('Likes',        FormatUtils.count(_data?['likes_count'] as int? ?? 0),     Icons.favorite_rounded,        Colors.red),
          _InsightCard('Comments',     FormatUtils.count(_data?['comments_count'] as int? ?? 0),  Icons.chat_bubble_rounded,     const Color(0xFF9C27B0)),
          _InsightCard('Shares',       FormatUtils.count(_data?['shares_count'] as int? ?? 0),    Icons.share_rounded,           const Color(0xFF4CAF50)),
          _InsightCard('Saves',        FormatUtils.count(_data?['saves_count'] as int? ?? 0),     Icons.bookmark_rounded,        const Color(0xFFFF9800)),
        ]),
        const SizedBox(height: 20),
        // Engagement rate
        Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(14)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Engagement Rate', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 12),
          Row(children: [
            const Icon(Icons.trending_up_rounded, color: AppTheme.orange, size: 28),
            const SizedBox(width: 12),
            Text('${_data?['engagement_rate'] ?? '0.0'}%', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 32, color: AppTheme.orange)),
          ]),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: (double.tryParse(_data?['engagement_rate']?.toString() ?? '0') ?? 0) / 100, backgroundColor: AppTheme.orangeSurf, valueColor: const AlwaysStoppedAnimation(AppTheme.orange), minHeight: 6, borderRadius: BorderRadius.circular(3)),
          const SizedBox(height: 6),
          Text('Industry average: 3.2% — yours is above average!', style: TextStyle(fontSize: 12, color: dark ? AppTheme.dSub : AppTheme.lSub)),
        ])),
        const SizedBox(height: 16),
        // Audience info
        Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(14)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Audience', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 10),
          _AudienceBar('Followers', _data?['followers_pct'] as int? ?? 72, AppTheme.orange),
          const SizedBox(height: 8),
          _AudienceBar('Non-Followers', 100 - (_data?['followers_pct'] as int? ?? 72), const Color(0xFF2196F3)),
        ])),
        const SizedBox(height: 20),
        SizedBox(width: double.infinity, child: ElevatedButton.icon(onPressed: () => context.push('/posts/${widget.postId}/boost'), icon: const Icon(Icons.rocket_launch_rounded), label: const Text('Boost This Post'), style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)))),
      ]),
    );
  }
}

class _InsightCard extends StatelessWidget {
  final String label, value; final IconData icon; final Color color;
  const _InsightCard(this.label, this.value, this.icon, this.color);
  @override Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)]), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Container(width: 34, height: 34, decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: color, size: 18)),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: color)), Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey))]),
    ]));
  }
}

class _AudienceBar extends StatelessWidget {
  final String label; final int pct; final Color color;
  const _AudienceBar(this.label, this.pct, this.color);
  @override Widget build(BuildContext _) => Row(children: [
    SizedBox(width: 110, child: Text(label, style: const TextStyle(fontSize: 13))),
    Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: pct / 100, backgroundColor: Colors.grey.shade200, valueColor: AlwaysStoppedAnimation(color), minHeight: 8))),
    const SizedBox(width: 8), Text('$pct%', style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
  ]);
}
