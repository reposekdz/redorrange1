import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/utils/format_utils.dart';
import 'campaign_detail_screen.dart';

final _dashProv = FutureProvider.autoDispose<Map<String,dynamic>>((ref) async {
  final r = await ref.read(apiServiceProvider).get('/ads/dashboard');
  return Map<String,dynamic>.from(r.data);
});

final _campaignsProv = StateNotifierProvider.autoDispose<_CampNotifier, _CampState>((ref) => _CampNotifier(ref));

class _CampState { final List<dynamic> campaigns; final bool loading; final String filter;
  const _CampState({this.campaigns = const [], this.loading = true, this.filter = 'all'});
  _CampState copyWith({List? campaigns, bool? loading, String? filter}) => _CampState(campaigns: campaigns ?? this.campaigns, loading: loading ?? this.loading, filter: filter ?? this.filter);
}
class _CampNotifier extends StateNotifier<_CampState> {
  final Ref _ref;
  _CampNotifier(this._ref) : super(const _CampState()) { load(); }
  Future<void> load([String? filter]) async {
    final f = filter ?? state.filter;
    if (filter != null) state = state.copyWith(filter: f, loading: true);
    try {
      final q = f == 'all' ? <String,String>{} : {'status': f};
      final r = await _ref.read(apiServiceProvider).get('/ads/campaigns', q: q);
      state = state.copyWith(campaigns: r.data['campaigns'] ?? [], loading: false, filter: f);
    } catch (_) { if (mounted) state = state.copyWith(loading: false); }
  }
  Future<void> toggle(String id, String currentStatus) async {
    final ns = currentStatus == 'active' ? 'paused' : 'active';
    await _ref.read(apiServiceProvider).put('/ads/campaigns/$id', data: {'status': ns}).catchError((_){});
    load();
  }
}

class AdsManagerScreen extends ConsumerStatefulWidget {
  const AdsManagerScreen({super.key});
  @override ConsumerState<AdsManagerScreen> createState() => _S();
}
class _S extends ConsumerState<AdsManagerScreen> with SingleTickerProviderStateMixin {
  late TabController _tc;
  @override void initState() { super.initState(); _tc = TabController(length: 4, vsync: this); }
  @override void dispose() { _tc.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final dash  = ref.watch(_dashProv);
    final camps = ref.watch(_campaignsProv);
    final dark  = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: dark ? AppTheme.dBg : const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: dark ? AppTheme.dSurf : Colors.white,
        elevation: 0,
        title: Row(children: [
          Container(width: 32, height: 32, decoration: const BoxDecoration(gradient: LinearGradient(colors: [AppTheme.orange, AppTheme.orangeDark]), borderRadius: BorderRadius.all(Radius.circular(9))), child: const Center(child: Icon(Icons.campaign_rounded, color: Colors.white, size: 18))),
          const SizedBox(width: 10),
          const Text('Ads Manager', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19)),
        ]),
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: () { ref.refresh(_dashProv); ref.read(_campaignsProv.notifier).load(); }),
          Padding(padding: const EdgeInsets.only(right: 8), child: ElevatedButton.icon(
            onPressed: () async { final r = await context.push('/ads/create-campaign'); if (r == true) { ref.refresh(_dashProv); ref.read(_campaignsProv.notifier).load(); } },
            icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Create', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
          )),
        ],
        bottom: TabBar(controller: _tc, indicatorColor: AppTheme.orange, labelColor: AppTheme.orange, unselectedLabelColor: Colors.grey, labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          tabs: const [Tab(text: 'Overview'), Tab(text: 'Campaigns'), Tab(text: 'Analytics'), Tab(text: 'Billing')]),
      ),
      body: dash.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.orange)),
        error: (_, __) => _NoAccount(onCreate: () => _createAccount(context)),
        data: (d) {
          if (d['has_account'] == false) return _NoAccount(onCreate: () => _createAccount(context));
          final account = Map<String,dynamic>.from(d['account'] as Map? ?? {});
          final statsToday = Map<String,dynamic>.from(d['stats_today'] as Map? ?? {});
          final statsWeek  = Map<String,dynamic>.from(d['stats_week']  as Map? ?? {});
          final topCamps   = List<dynamic>.from(d['top_campaigns'] ?? []);
          final billing    = List<dynamic>.from(d['recent_billing'] ?? []);
          final campStats  = Map<String,dynamic>.from(d['campaigns'] as Map? ?? {});

          return TabBarView(controller: _tc, children: [
            // ── OVERVIEW
            _OverviewTab(account: account, statsToday: statsToday, statsWeek: statsWeek, topCamps: topCamps, campStats: campStats, dark: dark),
            // ── CAMPAIGNS
            _CampaignsTab(camps: camps, dark: dark),
            // ── ANALYTICS
            _AnalyticsTab(accountId: account['id'] as String? ?? '', dark: dark),
            // ── BILLING
            _BillingTab(account: account, billing: billing, dark: dark),
          ]);
        },
      ),
    );
  }

  Future<void> _createAccount(BuildContext context) async {
    final nameCtrl  = TextEditingController();
    final emailCtrl = TextEditingController();
    final webCtrl   = TextEditingController();
    await showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('Create Ad Account', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.campaign_rounded, color: AppTheme.orange, size: 48),
        const SizedBox(height: 8),
        const Text('Start advertising on RedOrrange and reach thousands of people.', style: TextStyle(color: Colors.grey, fontSize: 13), textAlign: TextAlign.center),
        const SizedBox(height: 16),
        TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Business Name *', hintText: 'e.g. My Store', prefixIcon: Icon(Icons.business_rounded, size: 18))),
        const SizedBox(height: 10),
        TextField(controller: emailCtrl, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Business Email', prefixIcon: Icon(Icons.email_rounded, size: 18))),
        const SizedBox(height: 10),
        TextField(controller: webCtrl, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Website (optional)', hintText: 'https://...', prefixIcon: Icon(Icons.language_rounded, size: 18))),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () async {
            if (nameCtrl.text.trim().isEmpty) return;
            Navigator.pop(context);
            await ref.read(apiServiceProvider).post('/ads/accounts', data: {'business_name': nameCtrl.text.trim(), 'business_email': emailCtrl.text.trim(), 'website_url': webCtrl.text.trim()}).catchError((_){});
            ref.refresh(_dashProv);
          },
          child: const Text('Create Account'),
        ),
      ],
    ));
  }
}

// ─────────────────────────────────────────────────────
// OVERVIEW TAB
// ─────────────────────────────────────────────────────
class _OverviewTab extends StatelessWidget {
  final Map account, statsToday, statsWeek, campStats; final List topCamps; final bool dark;
  const _OverviewTab({required this.account, required this.statsToday, required this.statsWeek, required this.topCamps, required this.campStats, required this.dark});

  @override Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(14), children: [
    // Account balance card
    Container(padding: const EdgeInsets.all(20), decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF1A1A2E), Color(0xFF16213E)], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.all(Radius.circular(20))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Ad Account', style: TextStyle(color: Colors.white54, fontSize: 12)),
          Text(account['business_name'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 4),
          _StatusChip(account['status'] as String? ?? 'active'),
        ]),
        const Spacer(),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          const Text('Balance', style: TextStyle(color: Colors.white54, fontSize: 11)),
          Text('\$${(account['balance_usd'] as num? ?? 0).toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 28)),
          Text('\$${(account['total_spent'] as num? ?? 0).toStringAsFixed(2)} spent total', style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ]),
      ]),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: ElevatedButton.icon(onPressed: () => context.push('/ads/topup'), icon: const Icon(Icons.add_rounded, size: 16), label: const Text('Add Funds', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)), style: ElevatedButton.styleFrom(backgroundColor: AppTheme.orange, padding: const EdgeInsets.symmetric(vertical: 10)))),
        const SizedBox(width: 10),
        Expanded(child: OutlinedButton.icon(onPressed: () => context.push('/ads/create-campaign'), icon: const Icon(Icons.add_circle_outline_rounded, size: 16), label: const Text('New Campaign', style: TextStyle(fontSize: 13)), style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white24), padding: const EdgeInsets.symmetric(vertical: 10)))),
      ]),
    ])),
    const SizedBox(height: 14),

    // Campaign summary
    Row(children: [
      _SummaryCard('${campStats['active'] ?? 0}', 'Active', Icons.play_circle_rounded, Colors.green, dark),
      const SizedBox(width: 10),
      _SummaryCard('${campStats['paused'] ?? 0}', 'Paused', Icons.pause_circle_rounded, Colors.orange, dark),
      const SizedBox(width: 10),
      _SummaryCard('${campStats['draft'] ?? 0}', 'Draft', Icons.edit_rounded, Colors.grey, dark),
      const SizedBox(width: 10),
      _SummaryCard('${campStats['total'] ?? 0}', 'Total', Icons.all_inclusive_rounded, AppTheme.orange, dark),
    ]),
    const SizedBox(height: 14),

    // Today KPIs
    _SectionHeader('Today\'s Performance'),
    const SizedBox(height: 10),
    Row(children: [
      Expanded(child: _KpiCard('Impressions', FormatUtils.count(statsToday['impressions'] as int? ?? 0), Icons.remove_red_eye_rounded, const Color(0xFF2196F3), null, dark)),
      const SizedBox(width: 10),
      Expanded(child: _KpiCard('Clicks', FormatUtils.count(statsToday['clicks'] as int? ?? 0), Icons.touch_app_rounded, AppTheme.orange, null, dark)),
    ]),
    const SizedBox(height: 10),
    Row(children: [
      Expanded(child: _KpiCard('CTR', '${_safeCtr(statsToday)}%', Icons.trending_up_rounded, Colors.teal, 'Click-through rate', dark)),
      const SizedBox(width: 10),
      Expanded(child: _KpiCard('Spend', '\$${(statsToday['spend'] as num? ?? 0).toStringAsFixed(2)}', Icons.attach_money_rounded, const Color(0xFF4CAF50), null, dark)),
    ]),
    const SizedBox(height: 10),
    Row(children: [
      Expanded(child: _KpiCard('Reach', FormatUtils.count(statsToday['reach'] as int? ?? 0), Icons.people_rounded, const Color(0xFF9C27B0), null, dark)),
      const SizedBox(width: 10),
      Expanded(child: _KpiCard('Conversions', '${statsToday['conversions'] ?? 0}', Icons.check_circle_rounded, Colors.green, null, dark)),
    ]),
    const SizedBox(height: 14),

    // Top performing campaigns
    if (topCamps.isNotEmpty) ...[
      _SectionHeader('Top Campaigns (7 days)', action: TextButton(onPressed: () {}, child: const Text('See all', style: TextStyle(color: AppTheme.orange, fontSize: 12)))),
      const SizedBox(height: 10),
      ...topCamps.take(5).map((c) => _CampSummaryRow(c: c, dark: dark)),
    ],
  ]);

  static String _safeCtr(Map m) {
    final imp = (m['impressions'] as num? ?? 0).toDouble();
    final clk = (m['clicks'] as num? ?? 0).toDouble();
    if (imp == 0) return '0.00';
    return (clk / imp * 100).toStringAsFixed(2);
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip(this.status);
  @override Widget build(BuildContext _) {
    Color c; String l;
    switch (status) { case 'active': c = Colors.green; l = '● Active'; break; case 'restricted': c = Colors.orange; l = '⚠ Restricted'; break; default: c = Colors.grey; l = status; }
    return Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: c.withOpacity(0.15), borderRadius: BorderRadius.circular(8)), child: Text(l, style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w700)));
  }
}

class _SummaryCard extends StatelessWidget {
  final String val, label; final IconData icon; final Color color; final bool dark;
  const _SummaryCard(this.val, this.label, this.icon, this.color, this.dark);
  @override Widget build(BuildContext _) => Expanded(child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(14)), child: Column(children: [Icon(icon, color: color, size: 22), const SizedBox(height: 4), Text(val, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: color)), Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey))])));
}

class _KpiCard extends StatelessWidget {
  final String label, value; final IconData icon; final Color color; final String? subtitle; final bool dark;
  const _KpiCard(this.label, this.value, this.icon, this.color, this.subtitle, this.dark);
  @override Widget build(BuildContext _) => Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(14)), child: Row(children: [Container(width: 42, height: 42, decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: color, size: 22)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(value, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: color)), Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)), if (subtitle != null) Text(subtitle!, style: const TextStyle(fontSize: 9, color: Colors.grey))]))]));}

class _SectionHeader extends StatelessWidget {
  final String text; final Widget? action;
  const _SectionHeader(this.text, {this.action});
  @override Widget build(BuildContext _) => Row(children: [Text(text, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)), if (action != null) ...[const Spacer(), action!]]);
}

class _CampSummaryRow extends StatelessWidget {
  final dynamic c; final bool dark;
  const _CampSummaryRow({required this.c, required this.dark});
  @override Widget build(BuildContext context) => GestureDetector(
    onTap: () => context.push('/ads/campaign/${c['id']}'),
    child: Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(12)), child: Row(children: [
      Container(width: 40, height: 40, decoration: BoxDecoration(color: _color(c['objective'] as String? ?? '').withOpacity(0.12), borderRadius: BorderRadius.circular(10)), child: Icon(_icon(c['objective'] as String? ?? ''), color: _color(c['objective'] as String? ?? ''), size: 20)),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(c['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis), Text('${c['objective']?.toString().replaceAll('_', ' ') ?? ''} · ${_statusLabel(c['status'] as String? ?? '')}', style: TextStyle(fontSize: 11, color: _statusColor(c['status'] as String? ?? '')))])),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text('\$${(c['spend'] as num? ?? 0).toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.orange)),
        Text('${FormatUtils.count(c['clicks'] as int? ?? 0)} clicks', style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ]),
      const SizedBox(width: 6),
      const Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 18),
    ])),
  );
  static Color _color(String o) { if (o.contains('traffic')||o.contains('lead')) return const Color(0xFF2196F3); if (o.contains('engage')) return const Color(0xFF9C27B0); if (o.contains('video')) return Colors.red; if (o.contains('follow')) return AppTheme.orange; return const Color(0xFF4CAF50); }
  static IconData _icon(String o) { if (o.contains('traffic')) return Icons.open_in_new_rounded; if (o.contains('video')) return Icons.play_circle_rounded; if (o.contains('lead')) return Icons.people_alt_rounded; if (o.contains('follow')) return Icons.person_add_rounded; return Icons.campaign_rounded; }
  static String _statusLabel(String s) { switch(s) { case 'active': return 'Active'; case 'paused': return 'Paused'; case 'pending_review': return 'In Review'; case 'draft': return 'Draft'; case 'rejected': return 'Rejected'; default: return s; } }
  static Color _statusColor(String s) { switch(s) { case 'active': return Colors.green; case 'paused': return Colors.orange; case 'pending_review': return const Color(0xFF2196F3); case 'rejected': return Colors.red; default: return Colors.grey; } }
}

// ─────────────────────────────────────────────────────
// CAMPAIGNS TAB
// ─────────────────────────────────────────────────────
class _CampaignsTab extends ConsumerWidget {
  final _CampState camps; final bool dark;
  const _CampaignsTab({required this.camps, required this.dark});
  @override Widget build(BuildContext context, WidgetRef ref) => Column(children: [
    // Filter bar
    Padding(padding: const EdgeInsets.fromLTRB(14, 12, 14, 8), child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
      for (final (v, l) in [('all','All'), ('active','Active ▶'), ('paused','Paused ⏸'), ('draft','Draft'), ('pending_review','In Review'), ('rejected','Rejected'), ('archived','Archived')])
        GestureDetector(
          onTap: () => ref.read(_campaignsProv.notifier).load(v),
          child: AnimatedContainer(duration: const Duration(milliseconds: 150), margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), decoration: BoxDecoration(color: camps.filter == v ? AppTheme.orange : (dark ? AppTheme.dCard : Colors.white), borderRadius: BorderRadius.circular(20)),
            child: Text(l, style: TextStyle(color: camps.filter == v ? Colors.white : null, fontWeight: camps.filter == v ? FontWeight.w700 : FontWeight.w500, fontSize: 13))),
        ),
    ]))),
    Expanded(child: camps.loading ? const Center(child: CircularProgressIndicator(color: AppTheme.orange))
      : camps.campaigns.isEmpty ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.campaign_outlined, size: 72, color: Colors.grey), const SizedBox(height: 14), const Text('No campaigns', style: TextStyle(color: Colors.grey, fontSize: 16)), const SizedBox(height: 14), ElevatedButton.icon(onPressed: () => context.push('/ads/create-campaign'), icon: const Icon(Icons.add_rounded), label: const Text('Create Campaign'))]))
      : RefreshIndicator(color: AppTheme.orange, onRefresh: () async => ref.read(_campaignsProv.notifier).load(), child: ListView.builder(padding: const EdgeInsets.fromLTRB(14, 0, 14, 80), itemCount: camps.campaigns.length, itemBuilder: (_, i) => _CampaignCard(c: camps.campaigns[i], dark: dark)))),
  ]);
}

class _CampaignCard extends ConsumerWidget {
  final dynamic c; final bool dark;
  const _CampaignCard({required this.c, required this.dark});
  @override Widget build(BuildContext context, WidgetRef ref) {
    final status = c['status'] as String? ?? 'draft';
    final spent  = (c['spent_amount'] as num? ?? 0).toDouble();
    final budget = (c['budget_amount'] as num? ?? 1).toDouble();
    final pct    = (spent / budget).clamp(0.0, 1.0);
    final sc     = _statusColor(status);
    final impr   = c['impressions_7d'] as int? ?? 0;
    final clicks = c['clicks_7d'] as int? ?? 0;
    final spend7 = (c['spend_7d'] as num? ?? 0).toDouble();

    return GestureDetector(
      onTap: () => context.push('/ads/campaign/${c['id']}'),
      child: Container(margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10)]), child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(14, 14, 14, 10), child: Row(children: [
          Container(width: 48, height: 48, decoration: BoxDecoration(color: _objColor(c['objective'] as String? ?? '').withOpacity(0.12), borderRadius: BorderRadius.circular(13)), child: Icon(_objIcon(c['objective'] as String? ?? ''), color: _objColor(c['objective'] as String? ?? ''), size: 26)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(c['objective']?.toString().replaceAll('_', ' ').toUpperCase() ?? '', style: const TextStyle(fontSize: 10, color: Colors.grey, letterSpacing: 0.5)),
          ])),
          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: sc.withOpacity(0.12), borderRadius: BorderRadius.circular(10)), child: Text(_statusLabel(status), style: TextStyle(color: sc, fontSize: 11, fontWeight: FontWeight.w700))),
        ])),

        // Budget bar
        Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 10), child: Column(children: [
          Row(children: [
            Text('\$${spent.toStringAsFixed(2)} / \$${budget.toStringAsFixed(2)} ${c['budget_type'] ?? 'daily'}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const Spacer(),
            Text('${(pct * 100).toInt()}%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: pct >= 0.9 ? Colors.red : AppTheme.orange)),
          ]),
          const SizedBox(height: 4),
          ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: pct, backgroundColor: Colors.grey.withOpacity(0.15), valueColor: AlwaysStoppedAnimation(pct >= 0.9 ? Colors.red : pct >= 0.7 ? Colors.orange : AppTheme.orange), minHeight: 7)),
        ])),

        // 7-day metrics
        Container(padding: const EdgeInsets.fromLTRB(14, 10, 14, 10), decoration: BoxDecoration(color: dark ? Colors.black12 : Colors.grey.shade50, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16))), child: Row(children: [
          _M7('👁', FormatUtils.count(impr),    'Impressions'),
          _Div2(), _M7('🖱', FormatUtils.count(clicks), 'Clicks'),
          _Div2(), _M7('💰', '\$${spend7.toStringAsFixed(2)}', 'Spent 7d'),
          _Div2(), _M7('📊', impr > 0 ? '${(clicks / impr * 100).toStringAsFixed(1)}%' : '0%', 'CTR'),
          const Spacer(),
          // Quick toggle
          if (['active','paused'].contains(status)) GestureDetector(
            onTap: () => ref.read(_campaignsProv.notifier).toggle(c['id'] as String, status),
            child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(border: Border.all(color: sc, width: 1.5), borderRadius: BorderRadius.circular(8)),
              child: Text(status == 'active' ? '⏸ Pause' : '▶ Resume', style: TextStyle(color: sc, fontSize: 11, fontWeight: FontWeight.w700))),
          ),
        ])),
      ])),
    );
  }
  static Color _objColor(String o) { if (o.contains('traffic')) return const Color(0xFF2196F3); if (o.contains('engage')) return const Color(0xFF9C27B0); if (o.contains('video')) return Colors.red; if (o.contains('follow')) return AppTheme.orange; return const Color(0xFF4CAF50); }
  static IconData _objIcon(String o) { if (o.contains('traffic')) return Icons.open_in_new_rounded; if (o.contains('video')) return Icons.play_circle_rounded; if (o.contains('lead')) return Icons.people_alt_rounded; if (o.contains('follow')) return Icons.person_add_rounded; return Icons.campaign_rounded; }
  static String _statusLabel(String s) { switch(s) { case 'active': return 'Active'; case 'paused': return 'Paused'; case 'pending_review': return 'In Review'; case 'draft': return 'Draft'; case 'rejected': return 'Rejected'; default: return s; } }
  static Color _statusColor(String s) { switch(s) { case 'active': return Colors.green; case 'paused': return Colors.orange; case 'pending_review': return const Color(0xFF2196F3); case 'rejected': return Colors.red; default: return Colors.grey; } }
}
class _M7 extends StatelessWidget {
  final String icon, val, label;
  const _M7(this.icon, this.val, this.label);
  @override Widget build(BuildContext _) => Column(children: [Text('$icon $val', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)), Text(label, style: const TextStyle(fontSize: 9, color: Colors.grey))]);
}
class _Div2 extends StatelessWidget {
  @override Widget build(BuildContext _) => Container(width: 1, height: 28, margin: const EdgeInsets.symmetric(horizontal: 10), color: Colors.grey.withOpacity(0.2));
}

// ─────────────────────────────────────────────────────
// ANALYTICS TAB
// ─────────────────────────────────────────────────────
class _AnalyticsTab extends ConsumerStatefulWidget {
  final String accountId; final bool dark;
  const _AnalyticsTab({required this.accountId, required this.dark});
  @override ConsumerState<_AnalyticsTab> createState() => _ATS();
}
class _ATS extends ConsumerState<_AnalyticsTab> {
  String _period = '7d';
  Map<String,dynamic> _data = {}; bool _l = true;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    setState(() => _l = true);
    try { final r = await ref.read(apiServiceProvider).get('/ads/dashboard', q: {'period': _period}); setState(() { _data = Map<String,dynamic>.from(r.data); _l = false; }); } catch (_) { setState(() => _l = false); }
  }
  @override Widget build(BuildContext context) {
    final statsWeek = Map<String,dynamic>.from(_data['stats_week'] as Map? ?? {});
    final imp  = (statsWeek['impressions'] as num? ?? 0).toInt();
    final clk  = (statsWeek['clicks']     as num? ?? 0).toInt();
    final spd  = (statsWeek['spend']      as num? ?? 0).toDouble();
    final ctr  = imp > 0 ? (clk / imp * 100) : 0.0;
    final cpm  = imp > 0 ? (spd / imp * 1000) : 0.0;
    final cpc  = clk > 0 ? (spd / clk) : 0.0;

    return ListView(padding: const EdgeInsets.all(14), children: [
      // Period selector
      Row(children: [const Text('Analytics', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)), const Spacer(),
        for (final p in ['7d','30d','90d'])
          GestureDetector(onTap: () { setState(() => _period = p); _load(); }, child: AnimatedContainer(duration: const Duration(milliseconds: 150), margin: const EdgeInsets.only(left: 8), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: _period == p ? AppTheme.orange : (widget.dark ? AppTheme.dCard : Colors.white), borderRadius: BorderRadius.circular(16)), child: Text(p, style: TextStyle(color: _period == p ? Colors.white : null, fontWeight: _period == p ? FontWeight.w700 : FontWeight.w500, fontSize: 12)))),
      ]),
      const SizedBox(height: 14),

      if (_l) const Center(child: CircularProgressIndicator(color: AppTheme.orange))
      else ...[
        // Key metrics grid
        GridView.count(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: 3, childAspectRatio: 1.1, crossAxisSpacing: 10, mainAxisSpacing: 10, children: [
          _MetricBox('Impressions', FormatUtils.count(imp), Icons.remove_red_eye_rounded, const Color(0xFF2196F3), widget.dark),
          _MetricBox('Clicks', FormatUtils.count(clk), Icons.touch_app_rounded, AppTheme.orange, widget.dark),
          _MetricBox('CTR', '${ctr.toStringAsFixed(2)}%', Icons.trending_up_rounded, Colors.teal, widget.dark),
          _MetricBox('Spend', '\$${spd.toStringAsFixed(2)}', Icons.attach_money_rounded, const Color(0xFF4CAF50), widget.dark),
          _MetricBox('CPM', '\$${cpm.toStringAsFixed(2)}', Icons.bar_chart_rounded, const Color(0xFF9C27B0), widget.dark),
          _MetricBox('CPC', '\$${cpc.toStringAsFixed(2)}', Icons.mouse_rounded, Colors.orange, widget.dark),
        ]),
        const SizedBox(height: 16),

        // Impressions chart (mock sparkline using fl_chart)
        Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: widget.dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Impressions over time', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 14),
          SizedBox(height: 120, child: LineChart(LineChartData(
            gridData: FlGridData(show: true, horizontalInterval: 1000, getDrawingHorizontalLine: (_) => FlLine(color: Colors.grey.withOpacity(0.1), strokeWidth: 1)),
            titlesData: FlTitlesData(show: false),
            borderData: FlBorderData(show: false),
            lineBarsData: [LineChartBarData(
              spots: List.generate(7, (i) => FlSpot(i.toDouble(), (imp / 7 * (0.7 + i * 0.05)).clamp(0, imp.toDouble()).toDouble())),
              isCurved: true, color: const Color(0xFF2196F3), barWidth: 2.5,
              belowBarData: BarAreaData(show: true, color: const Color(0xFF2196F3).withOpacity(0.1)),
              dotData: const FlDotData(show: false),
            )],
          ))),
        ])),
        const SizedBox(height: 10),

        // Clicks chart
        Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: widget.dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Clicks over time', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 14),
          SizedBox(height: 120, child: BarChart(BarChartData(
            gridData: const FlGridData(show: false),
            titlesData: FlTitlesData(show: true, bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, _) { final days = ['M','T','W','T','F','S','S']; return Text(days[v.toInt() % 7], style: const TextStyle(fontSize: 10, color: Colors.grey)); })), leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)), topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)), rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false))),
            borderData: FlBorderData(show: false),
            barGroups: List.generate(7, (i) => BarChartGroupData(x: i, barRods: [BarChartRodData(toY: (clk / 7 * (0.6 + i * 0.06)).clamp(0, clk.toDouble()), color: AppTheme.orange, width: 16, borderRadius: const BorderRadius.vertical(top: Radius.circular(4)))])),
          ))),
        ])),
        const SizedBox(height: 10),

        // Placement breakdown (pie)
        Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: widget.dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Placement Breakdown', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 12),
          Row(children: [
            SizedBox(width: 100, height: 100, child: PieChart(PieChartData(sections: [
              PieChartSectionData(value: 45, color: AppTheme.orange,         title: '45%', radius: 38, titleStyle: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
              PieChartSectionData(value: 25, color: const Color(0xFF2196F3), title: '25%', radius: 38, titleStyle: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
              PieChartSectionData(value: 20, color: const Color(0xFF9C27B0), title: '20%', radius: 38, titleStyle: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
              PieChartSectionData(value: 10, color: Colors.teal,             title: '10%', radius: 38, titleStyle: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
            ], sectionsSpace: 2, centerSpaceRadius: 12))),
            const SizedBox(width: 20),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _Legend(AppTheme.orange,         'Feed'),
              _Legend(const Color(0xFF2196F3), 'Stories'),
              _Legend(const Color(0xFF9C27B0), 'Reels'),
              _Legend(Colors.teal,             'Explore'),
            ]),
          ]),
        ])),
      ],
    ]);
  }
}
class _MetricBox extends StatelessWidget {
  final String l, v; final IconData i; final Color c; final bool dark;
  const _MetricBox(this.l, this.v, this.i, this.c, this.dark);
  @override Widget build(BuildContext _) => Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(14)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(i, color: c, size: 18), const SizedBox(height: 4), Text(v, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: c)), const SizedBox(height: 2), Text(l, style: const TextStyle(fontSize: 10, color: Colors.grey))]));
}
class _Legend extends StatelessWidget {
  final Color c; final String l;
  const _Legend(this.c, this.l);
  @override Widget build(BuildContext _) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(children: [Container(width: 12, height: 12, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))), const SizedBox(width: 8), Text(l, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))]));
}

// ─────────────────────────────────────────────────────
// BILLING TAB
// ─────────────────────────────────────────────────────
class _BillingTab extends StatelessWidget {
  final Map account; final List billing; final bool dark;
  const _BillingTab({required this.account, required this.billing, required this.dark});
  @override Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(14), children: [
    Container(padding: const EdgeInsets.all(20), decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF0D1B2A), Color(0xFF1B2838)]), borderRadius: BorderRadius.all(Radius.circular(18))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Ad Balance', style: TextStyle(color: Colors.white54, fontSize: 12)),
      const SizedBox(height: 4),
      Text('\$${(account['balance_usd'] as num? ?? 0).toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 38)),
      const SizedBox(height: 4),
      Text('Total spent: \$${(account['total_spent'] as num? ?? 0).toStringAsFixed(2)}', style: const TextStyle(color: Colors.white38, fontSize: 12)),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: ElevatedButton.icon(onPressed: () => context.push('/ads/topup'), icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Add Funds'), style: ElevatedButton.styleFrom(backgroundColor: AppTheme.orange, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)))),
        const SizedBox(width: 10),
        Expanded(child: OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.receipt_long_rounded, size: 18), label: const Text('Invoices'), style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white24), padding: const EdgeInsets.symmetric(vertical: 12)))),
      ]),
    ])),
    const SizedBox(height: 16),
    // Payment methods
    Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(14)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Payment Methods', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
      const SizedBox(height: 12),
      _PmRow('💳', 'Stripe — Credit Card', 'Visa / Mastercard / Amex'),
      _PmRow('🅿️', 'PayPal',               'Fast global checkout'),
      _PmRow('🇷🇼', 'MTN Mobile Money',      'Rwanda — RWF'),
      _PmRow('🇰🇪', 'M-Pesa',               'Kenya — KES'),
      const SizedBox(height: 8),
      GestureDetector(onTap: () => context.push('/ads/topup'), child: const Row(children: [Icon(Icons.add_circle_outline_rounded, color: AppTheme.orange, size: 18), SizedBox(width: 6), Text('Add funds with any method', style: TextStyle(color: AppTheme.orange, fontWeight: FontWeight.w600, fontSize: 13))])),
    ])),
    const SizedBox(height: 14),
    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Transaction History', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)), TextButton(onPressed: () {}, child: const Text('Export CSV', style: TextStyle(color: AppTheme.orange, fontSize: 12)))]),
    const SizedBox(height: 8),
    if (billing.isEmpty) Container(padding: const EdgeInsets.all(24), child: const Center(child: Text('No transactions yet', style: TextStyle(color: Colors.grey))))
    else ...billing.map((t) {
      final isCharge = (t['type'] as String? ?? '').contains('charge') || (t['amount'] as num? ?? 0) < 0;
      return Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(12)), child: Row(children: [
        Container(width: 40, height: 40, decoration: BoxDecoration(color: isCharge ? Colors.red.withOpacity(0.1) : Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: Icon(isCharge ? Icons.remove_rounded : Icons.add_rounded, color: isCharge ? Colors.red : Colors.green, size: 22)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t['description'] ?? t['type'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis), Text(t['created_at']?.toString().substring(0,10) ?? '', style: const TextStyle(fontSize: 11, color: Colors.grey))])),
        Text('${isCharge ? '-' : '+'}\$${(t['amount'] as num? ?? 0).abs().toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: isCharge ? Colors.red : Colors.green)),
      ]));
    }),
  ]);
}
class _PmRow extends StatelessWidget {
  final String icon, name, sub;
  const _PmRow(this.icon, this.name, this.sub);
  @override Widget build(BuildContext _) => Padding(padding: const EdgeInsets.only(bottom: 10), child: Row(children: [Text(icon, style: const TextStyle(fontSize: 22)), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)), Text(sub, style: const TextStyle(fontSize: 11, color: Colors.grey))])), const Icon(Icons.check_circle_rounded, color: Colors.green, size: 18)]));
}

// ─────────────────────────────────────────────────────
// NO ACCOUNT STATE
// ─────────────────────────────────────────────────────
class _NoAccount extends StatelessWidget {
  final VoidCallback onCreate;
  const _NoAccount({required this.onCreate});
  @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Container(width: 100, height: 100, decoration: const BoxDecoration(gradient: LinearGradient(colors: [AppTheme.orange, AppTheme.orangeDark]), shape: BoxShape.circle), child: const Icon(Icons.campaign_rounded, color: Colors.white, size: 52)),
    const SizedBox(height: 24),
    const Text('Grow Your Business', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 26), textAlign: TextAlign.center),
    const SizedBox(height: 10),
    const Text('Reach thousands of people on RedOrrange with targeted ads. Real results, any budget.', style: TextStyle(color: Colors.grey, fontSize: 14, height: 1.7), textAlign: TextAlign.center),
    const SizedBox(height: 24),
    // Features
    for (final (icon, text) in [(Icons.people_rounded,'Reach 50,000+ active users in Rwanda'), (Icons.tune_rounded,'Target by age, gender, location & interests'), (Icons.bar_chart_rounded,'Real-time analytics & reporting'), (Icons.payment_rounded,'Pay with MTN, Airtel, M-Pesa, Stripe, PayPal'), (Icons.verified_rounded,'Campaigns reviewed within 24 hours')])
      Padding(padding: const EdgeInsets.only(bottom: 10), child: Row(children: [Container(width: 36, height: 36, decoration: BoxDecoration(color: AppTheme.orangeSurf, borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: AppTheme.orange, size: 18)), const SizedBox(width: 12), Expanded(child: Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)))])),
    const SizedBox(height: 24),
    SizedBox(width: double.infinity, child: ElevatedButton(onPressed: onCreate, style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)), child: const Text('Create Ad Account — Free', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)))),
    const SizedBox(height: 10),
    const Text('✓ No minimum spend  ✓ Cancel anytime  ✓ Results guaranteed', style: TextStyle(color: Colors.grey, fontSize: 12), textAlign: TextAlign.center),
  ]));
}
