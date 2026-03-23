import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/utils/format_utils.dart';

final _campDetailProv = FutureProvider.family.autoDispose<Map<String,dynamic>, String>((ref, id) async {
  final r = await ref.read(apiServiceProvider).get('/ads/campaigns/$id');
  return Map<String,dynamic>.from(r.data);
});

class CampaignDetailScreen extends ConsumerStatefulWidget {
  final String campaignId;
  const CampaignDetailScreen({super.key, required this.campaignId});
  @override ConsumerState<CampaignDetailScreen> createState() => _S();
}
class _S extends ConsumerState<CampaignDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tc;
  bool _toggling = false;
  @override void initState() { super.initState(); _tc = TabController(length: 3, vsync: this); }
  @override void dispose() { _tc.dispose(); super.dispose(); }

  Future<void> _toggleStatus(String current) async {
    final ns = current == 'active' ? 'paused' : 'active';
    setState(() => _toggling = true);
    await ref.read(apiServiceProvider).put('/ads/campaigns/${widget.campaignId}', data: {'status': ns}).catchError((_){});
    ref.refresh(_campDetailProv(widget.campaignId));
    setState(() => _toggling = false);
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(_campDetailProv(widget.campaignId));
    final dark = Theme.of(context).brightness == Brightness.dark;
    return data.when(
      loading: () => Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator(color: AppTheme.orange))),
      error:   (e, _) => Scaffold(appBar: AppBar(), body: Center(child: Text('$e'))),
      data: (d) {
        final campaign = Map<String,dynamic>.from(d['campaign'] as Map? ?? {});
        final ads      = List<dynamic>.from(d['ads'] ?? []);
        final daily    = List<dynamic>.from(d['daily_stats'] ?? []);
        final status   = campaign['status'] as String? ?? 'draft';
        final spent    = (campaign['spent_amount'] as num? ?? 0).toDouble();
        final budget   = (campaign['budget_amount'] as num? ?? 1).toDouble();
        final pct      = (spent / budget).clamp(0.0, 1.0);

        return Scaffold(
          backgroundColor: dark ? AppTheme.dBg : const Color(0xFFF0F2F5),
          appBar: AppBar(
            title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(campaign['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(campaign['objective']?.toString().replaceAll('_', ' ').toUpperCase() ?? '', style: const TextStyle(fontSize: 10, color: Colors.grey)),
            ]),
            actions: [
              if (['active','paused'].contains(status)) _toggling
                ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.orange)))
                : TextButton(
                    onPressed: () => _toggleStatus(status),
                    child: Text(status == 'active' ? '⏸ Pause' : '▶ Resume', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
              PopupMenuButton<String>(onSelected: (v) async {
                if (v == 'delete') {
                  final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('Archive Campaign?'), content: const Text('All ads will be archived too.'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Archive', style: TextStyle(color: Colors.red)))]));
                  if (ok == true) { await ref.read(apiServiceProvider).delete('/ads/campaigns/${widget.campaignId}').catchError((_){}); if (context.mounted) context.pop(); }
                }
              }, itemBuilder: (_) => [const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.archive_rounded, size: 18, color: Colors.red), SizedBox(width: 8), Text('Archive', style: TextStyle(color: Colors.red))]))]),
            ],
            bottom: TabBar(controller: _tc, indicatorColor: AppTheme.orange, labelColor: AppTheme.orange, unselectedLabelColor: Colors.grey, tabs: const [Tab(text: 'Overview'), Tab(text: 'Ads'), Tab(text: 'Analytics')]),
          ),
          body: TabBarView(controller: _tc, children: [
            // OVERVIEW
            SingleChildScrollView(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Status + budget
              Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(16)), child: Column(children: [
                Row(children: [
                  _StatusPill(status),
                  const Spacer(),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('\$${spent.toStringAsFixed(2)} / \$${budget.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    Text('${campaign['budget_type'] ?? 'daily'} budget', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ]),
                ]),
                const SizedBox(height: 10),
                ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: pct, backgroundColor: Colors.grey.withOpacity(0.15), valueColor: AlwaysStoppedAnimation(pct >= 0.9 ? Colors.red : AppTheme.orange), minHeight: 10)),
                const SizedBox(height: 6),
                Row(children: [Text('${(pct*100).toInt()}% budget used', style: const TextStyle(fontSize: 11, color: Colors.grey)), const Spacer(), Text('\$${(budget - spent).toStringAsFixed(2)} remaining', style: const TextStyle(fontSize: 11, color: Colors.grey))]),
              ])),
              const SizedBox(height: 12),

              // KPIs
              Row(children: [
                Expanded(child: _KPI('Impressions', FormatUtils.count(campaign['impressions_total'] as int? ?? 0), const Color(0xFF2196F3), dark)),
                const SizedBox(width: 10),
                Expanded(child: _KPI('Clicks', FormatUtils.count(campaign['clicks_total'] as int? ?? 0), AppTheme.orange, dark)),
                const SizedBox(width: 10),
                Expanded(child: _KPI('Reach', FormatUtils.count(campaign['reach_total'] as int? ?? 0), const Color(0xFF9C27B0), dark)),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _KPI('CTR', campaign['impressions_total'] != null && (campaign['impressions_total'] as int) > 0 ? '${((campaign['clicks_total'] as int? ?? 0) / (campaign['impressions_total'] as int) * 100).toStringAsFixed(2)}%' : '0%', Colors.teal, dark)),
                const SizedBox(width: 10),
                Expanded(child: _KPI('Conversions', '${campaign['conversions_total'] ?? 0}', Colors.green, dark)),
                const SizedBox(width: 10),
                Expanded(child: _KPI('Spent', '\$${spent.toStringAsFixed(2)}', const Color(0xFF4CAF50), dark)),
              ]),
              const SizedBox(height: 14),

              // Targeting summary
              const Text('Targeting', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 8),
              Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(14)), child: Column(children: [
                _TRow('Age', '${campaign['target_age_min'] ?? 18} – ${campaign['target_age_max'] ?? 65}'),
                _TRow('Gender', _parseJson(campaign['target_genders'], 'All Genders')),
                _TRow('Countries', _parseJson(campaign['target_countries'], 'All Countries')),
                _TRow('Interests', _parseJson(campaign['target_interests'], 'All Interests')),
                _TRow('Platforms', _parseJson(campaign['target_platforms'], 'All Platforms')),
                _TRow('Start', campaign['start_date'] as String? ?? '—'),
                _TRow('End', campaign['end_date'] as String? ?? 'No end date'),
              ])),
            ])),

            // ADS
            Column(children: [
              Padding(padding: const EdgeInsets.all(14), child: Row(children: [Text('${ads.length} Ads', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)), const Spacer(), ElevatedButton.icon(onPressed: () => context.push('/ads/create-campaign'), icon: const Icon(Icons.add_rounded, size: 16), label: const Text('Add Ad'), style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), textStyle: const TextStyle(fontSize: 13)))])),
              Expanded(child: ads.isEmpty ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.image_outlined, size: 64, color: Colors.grey), SizedBox(height: 12), Text('No ads yet. Add a creative.', style: TextStyle(color: Colors.grey))]))
                : ListView.builder(padding: const EdgeInsets.fromLTRB(14, 0, 14, 80), itemCount: ads.length, itemBuilder: (_, i) => _AdTile(ad: ads[i], dark: dark, campaignId: widget.campaignId, onToggle: () => ref.refresh(_campDetailProv(widget.campaignId))))),
            ]),

            // ANALYTICS
            _CampaignAnalytics(daily: daily, dark: dark),
          ]),
        );
      },
    );
  }

  static String _parseJson(dynamic v, String fallback) {
    if (v == null) return fallback;
    if (v is List) return v.isEmpty ? fallback : v.join(', ');
    if (v is String) { try { final l = (v as dynamic).toString(); return l == '["all"]' || l == 'all' ? fallback : l; } catch (_) { return fallback; } }
    return fallback;
  }
}

class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill(this.status);
  @override Widget build(BuildContext _) {
    Color c; IconData i; String l;
    switch (status) { case 'active': c = Colors.green; i = Icons.play_circle_filled_rounded; l = 'Active'; break; case 'paused': c = Colors.orange; i = Icons.pause_circle_filled_rounded; l = 'Paused'; break; case 'pending_review': c = const Color(0xFF2196F3); i = Icons.hourglass_top_rounded; l = 'In Review'; break; case 'rejected': c = Colors.red; i = Icons.cancel_rounded; l = 'Rejected'; break; case 'draft': c = Colors.grey; i = Icons.edit_rounded; l = 'Draft'; break; default: c = Colors.grey; i = Icons.info_rounded; l = status; }
    return Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(20)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(i, color: c, size: 16), const SizedBox(width: 5), Text(l, style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 13))]));
  }
}

class _KPI extends StatelessWidget {
  final String l, v; final Color c; final bool dark;
  const _KPI(this.l, this.v, this.c, this.dark);
  @override Widget build(BuildContext _) => Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(12)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(v, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: c)), Text(l, style: const TextStyle(fontSize: 11, color: Colors.grey))]));
}

class _TRow extends StatelessWidget {
  final String l, v;
  const _TRow(this.l, this.v);
  @override Widget build(BuildContext _) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [Text(l, style: const TextStyle(color: Colors.grey, fontSize: 13)), const Spacer(), Text(v, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis)]));
}

class _AdTile extends ConsumerWidget {
  final dynamic ad; final bool dark; final String campaignId; final VoidCallback onToggle;
  const _AdTile({required this.ad, required this.dark, required this.campaignId, required this.onToggle});
  @override Widget build(BuildContext context, WidgetRef ref) {
    final status = ad['status'] as String? ?? 'active';
    final imp    = ad['impressions'] as int? ?? 0;
    final clicks = ad['clicks']     as int? ?? 0;
    final spend  = (ad['spend'] as num? ?? 0).toDouble();
    return Container(margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(16)), child: Column(children: [
      // Preview row
      Padding(padding: const EdgeInsets.all(14), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(borderRadius: BorderRadius.circular(10), child: ad['media_url'] != null ? CachedNetworkImage(imageUrl: ad['media_url'] as String, width: 72, height: 72, fit: BoxFit.cover) : Container(width: 72, height: 72, color: AppTheme.orangeSurf, child: const Icon(Icons.image_rounded, color: AppTheme.orange, size: 32))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(ad['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 3),
          Row(children: [_FmtChip(ad['format'] as String? ?? 'image'), const SizedBox(width: 6), _StChip(status)]),
          const SizedBox(height: 6),
          Text(ad['headline'] ?? ad['primary_text'] ?? '', style: const TextStyle(fontSize: 12, color: Colors.grey), maxLines: 2, overflow: TextOverflow.ellipsis),
        ])),
        // Quick toggle
        if (['active','paused'].contains(status)) GestureDetector(
          onTap: () async {
            final ns = status == 'active' ? 'paused' : 'active';
            await ref.read(apiServiceProvider).put('/ads/${ad['id']}', data: {'status': ns}).catchError((_){});
            onToggle();
          },
          child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5), decoration: BoxDecoration(border: Border.all(color: status == 'active' ? Colors.orange : Colors.green), borderRadius: BorderRadius.circular(8)),
            child: Text(status == 'active' ? '⏸' : '▶', style: const TextStyle(fontSize: 14))),
        ),
      ])),
      // Metrics
      Container(padding: const EdgeInsets.fromLTRB(14, 8, 14, 12), decoration: BoxDecoration(color: dark ? Colors.black12 : Colors.grey.shade50, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16))), child: Row(children: [
        _AM('👁', FormatUtils.count(imp), 'Impressions'),
        _AM('🖱', FormatUtils.count(clicks), 'Clicks'),
        _AM('📊', imp > 0 ? '${(clicks/imp*100).toStringAsFixed(1)}%' : '0%', 'CTR'),
        _AM('💰', '\$${spend.toStringAsFixed(2)}', 'Spend'),
      ])),
    ]));
  }
}
class _AM extends StatelessWidget {
  final String icon, val, lbl;
  const _AM(this.icon, this.val, this.lbl);
  @override Widget build(BuildContext _) => Expanded(child: Column(children: [Text('$icon $val', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)), Text(lbl, style: const TextStyle(fontSize: 9, color: Colors.grey))]));
}
class _FmtChip extends StatelessWidget {
  final String f;
  const _FmtChip(this.f);
  @override Widget build(BuildContext _) => Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2), decoration: BoxDecoration(color: AppTheme.orangeSurf, borderRadius: BorderRadius.circular(6)), child: Text(f.toUpperCase(), style: const TextStyle(color: AppTheme.orange, fontSize: 9, fontWeight: FontWeight.w700)));
}
class _StChip extends StatelessWidget {
  final String s;
  const _StChip(this.s);
  @override Widget build(BuildContext _) {
    Color c; switch(s) { case 'active': c=Colors.green; break; case 'paused': c=Colors.orange; break; case 'pending_review': c=const Color(0xFF2196F3); break; case 'rejected': c=Colors.red; break; default: c=Colors.grey; }
    return Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2), decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(6)), child: Text(s == 'pending_review' ? 'IN REVIEW' : s.toUpperCase(), style: TextStyle(color: c, fontSize: 9, fontWeight: FontWeight.w700)));
  }
}

class _CampaignAnalytics extends StatelessWidget {
  final List daily; final bool dark;
  const _CampaignAnalytics({required this.daily, required this.dark});
  @override Widget build(BuildContext context) {
    if (daily.isEmpty) return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.analytics_outlined, size: 64, color: Colors.grey), SizedBox(height: 12), Text('No analytics data yet', style: TextStyle(color: Colors.grey)), SizedBox(height: 6), Text('Data appears once your campaign starts running', style: TextStyle(color: Colors.grey, fontSize: 12))]));
    final maxImp = daily.map((d) => (d['impressions'] as int? ?? 0).toDouble()).reduce((a,b) => a > b ? a : b);
    return ListView(padding: const EdgeInsets.all(14), children: [
      Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Daily Impressions', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        const SizedBox(height: 14),
        SizedBox(height: 140, child: BarChart(BarChartData(
          maxY: maxImp * 1.2,
          gridData: FlGridData(show: true, horizontalInterval: maxImp / 4, getDrawingHorizontalLine: (_) => FlLine(color: Colors.grey.withOpacity(0.1))),
          titlesData: FlTitlesData(bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, _) { final i = v.toInt(); if (i < 0 || i >= daily.length) return const SizedBox.shrink(); return Text(daily[i]['stat_date']?.toString().substring(5) ?? '', style: const TextStyle(fontSize: 9, color: Colors.grey)); })), leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)), topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)), rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false))),
          borderData: FlBorderData(show: false),
          barGroups: daily.asMap().entries.map((e) => BarChartGroupData(x: e.key, barRods: [BarChartRodData(toY: (e.value['impressions'] as int? ?? 0).toDouble(), gradient: const LinearGradient(colors: [AppTheme.orange, AppTheme.orangeDark], begin: Alignment.bottomCenter, end: Alignment.topCenter), width: 18, borderRadius: const BorderRadius.vertical(top: Radius.circular(4)))])).toList(),
        ))),
      ])),
      const SizedBox(height: 12),
      // Data table
      Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Daily Breakdown', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        const SizedBox(height: 10),
        Row(children: [const Text('Date', style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.w600)), const Spacer(), ...['Imp','Clicks','CTR','Spend'].map((h) => SizedBox(width: 54, child: Text(h, style: const TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.w600), textAlign: TextAlign.right)))]),
        const Divider(height: 12),
        ...daily.take(10).map((d) {
          final imp = d['impressions'] as int? ?? 0; final clk = d['clicks'] as int? ?? 0;
          final ctr = imp > 0 ? (clk/imp*100).toStringAsFixed(1) : '0';
          final spd = (d['spend'] as num? ?? 0).toStringAsFixed(2);
          return Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [Text(d['stat_date']?.toString() ?? '', style: const TextStyle(fontSize: 12)), const Spacer(), ...([FormatUtils.count(imp), FormatUtils.count(clk), '$ctr%', '\$$spd']).map((v) => SizedBox(width: 54, child: Text(v, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600), textAlign: TextAlign.right)))]));
        }),
      ])),
    ]);
  }
}
