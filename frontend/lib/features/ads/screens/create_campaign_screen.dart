import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/api_service.dart';
import 'package:dio/dio.dart';

class CreateCampaignScreen extends ConsumerStatefulWidget {
  const CreateCampaignScreen({super.key});
  @override ConsumerState<CreateCampaignScreen> createState() => _S();
}
class _S extends ConsumerState<CreateCampaignScreen> {
  final _pc = PageController();
  int _step = 0;

  // Campaign
  String _name = '', _objective = '', _bidStrategy = 'lowest_cost';
  String _budgetType = 'daily'; double _budget = 5.0;
  DateTime _startDate = DateTime.now().add(const Duration(hours: 1));
  DateTime? _endDate;

  // Targeting
  List<String> _countries = ['all'], _genders = ['all'], _interests = [], _platforms = ['all'];
  int _ageMin = 18, _ageMax = 65;
  int? _audienceEst;

  // Creative
  String _adName = '', _format = 'image', _headline = '', _primaryText = '';
  String _ctaText = 'Learn More', _ctaUrl = '', _displayUrl = '';
  File? _mediaFile;
  bool _submitting = false;

  static final _objectives = [
    ['awareness',       Icons.visibility_rounded,   'Brand Awareness',   'Show your brand to as many people as possible'],
    ['reach',           Icons.group_rounded,         'Maximum Reach',     'Reach the most unique people in your audience'],
    ['traffic',         Icons.open_in_new_rounded,   'Website Traffic',   'Drive people to your website or landing page'],
    ['engagement',      Icons.thumb_up_rounded,      'Engagement',        'Get more likes, comments, saves and shares'],
    ['leads',           Icons.contact_mail_rounded,  'Lead Generation',   'Collect customer information and contacts'],
    ['conversions',     Icons.shopping_cart_rounded, 'Conversions',       'Drive purchases, sign-ups or app actions'],
    ['video_views',     Icons.play_circle_rounded,   'Video Views',       'Get more people to watch your video'],
    ['follower_growth', Icons.person_add_rounded,    'Follower Growth',   'Increase your RedOrrange followers'],
    ['app_installs',    Icons.phone_android_rounded, 'App Installs',      'Drive people to download your app'],
  ];

  static final _formats = [
    ['image',   Icons.image_rounded,         'Image',    'Single photo ad'],
    ['video',   Icons.videocam_rounded,      'Video',    'Short video ad'],
    ['carousel',Icons.view_carousel_rounded, 'Carousel', 'Multiple images'],
    ['story',   Icons.auto_stories_rounded,  'Story',    'Full screen 9:16'],
    ['reel',    Icons.movie_creation_rounded,'Reel',     'Vertical video'],
    ['collection',Icons.grid_on_rounded,     'Collection','Product showcase'],
  ];

  static const _ctaOptions = ['Learn More','Shop Now','Sign Up','Get Quote','Contact Us','Download','Book Now','Watch More','Apply Now','Subscribe','See Menu','Visit Website'];

  @override void dispose() { _pc.dispose(); super.dispose(); }

  Future<void> _fetchAudience() async {
    try {
      final r = await ref.read(apiServiceProvider).post('/ads/audience-estimate', data: {'target_countries': _countries, 'target_age_min': _ageMin, 'target_age_max': _ageMax, 'target_genders': _genders, 'target_interests': _interests});
      if (mounted) setState(() => _audienceEst = r.data['audience_size'] as int?);
    } catch (_) {}
  }

  Future<void> _pickMedia() async {
    final f = _format == 'video' ? await ImagePicker().pickVideo(source: ImageSource.gallery) : await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (f != null && mounted) setState(() => _mediaFile = File(f.path));
  }

  void _next() {
    if (_step == 0 && (_name.isEmpty || _objective.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a campaign name and select an objective')));
      return;
    }
    if (_step == 3 && _ctaUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Destination URL is required')));
      return;
    }
    if (_step < 3) {
      _pc.nextPage(duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
      setState(() => _step++);
      if (_step == 1) _fetchAudience();
    } else { _launch(); }
  }

  void _back() {
    if (_step > 0) { _pc.previousPage(duration: const Duration(milliseconds: 350), curve: Curves.easeInOut); setState(() => _step--); }
    else context.pop();
  }

  Future<void> _launch() async {
    setState(() => _submitting = true);
    try {
      final cR = await ref.read(apiServiceProvider).post('/ads/campaigns', data: {
        'name': _name, 'objective': _objective, 'budget_type': _budgetType, 'budget_amount': _budget,
        'start_date': _startDate.toIso8601String().split('T')[0],
        if (_endDate != null) 'end_date': _endDate!.toIso8601String().split('T')[0],
        'bid_strategy': _bidStrategy,
        'target_countries': _countries, 'target_age_min': _ageMin, 'target_age_max': _ageMax,
        'target_genders': _genders, 'target_interests': _interests, 'target_platforms': _platforms,
      });
      final campId = cR.data['campaign']['id'] as String;

      final fd = FormData.fromMap({
        'name': _adName.isNotEmpty ? _adName : '$_name Creative',
        'format': _format, 'headline': _headline, 'primary_text': _primaryText,
        'cta_text': _ctaText, 'cta_url': _ctaUrl,
        if (_displayUrl.isNotEmpty) 'display_url': _displayUrl,
        if (_mediaFile != null) 'media': await MultipartFile.fromFile(_mediaFile!.path),
      });
      await ref.read(apiServiceProvider).upload('/ads/campaigns/$campId/ads', fd);
      await ref.read(apiServiceProvider).put('/ads/campaigns/$campId', data: {'status': 'active'}).catchError((_){});

      if (mounted) {
        context.go('/ads');
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🚀 Campaign launched! Under review — usually approved within 24h'), backgroundColor: Colors.green, duration: Duration(seconds: 4)));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
    if (mounted) setState(() => _submitting = false);
  }

  @override Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    const steps = ['Objective', 'Targeting', 'Budget', 'Creative'];
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: _back),
        title: const Text('Create Campaign', style: TextStyle(fontWeight: FontWeight.w800)),
        bottom: PreferredSize(preferredSize: const Size.fromHeight(50), child: Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 12), child: Column(children: [
          Row(children: steps.asMap().entries.map((e) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 3), child: Column(children: [AnimatedContainer(duration: const Duration(milliseconds: 250), height: 4, decoration: BoxDecoration(color: e.key <= _step ? AppTheme.orange : (dark ? AppTheme.dCard : Colors.grey.shade200), borderRadius: BorderRadius.circular(2))), const SizedBox(height: 4), Text(e.value, style: TextStyle(fontSize: 9, fontWeight: e.key == _step ? FontWeight.w700 : FontWeight.w400, color: e.key <= _step ? AppTheme.orange : Colors.grey))])))).toList()),
        ]))),
      ),
      body: PageView(controller: _pc, physics: const NeverScrollableScrollPhysics(), children: [
        _Step1(objectives: _objectives, name: _name, selected: _objective, onName: (v) => setState(() => _name = v), onSelect: (v) => setState(() => _objective = v), dark: dark),
        _Step2(ageMin: _ageMin, ageMax: _ageMax, genders: _genders, interests: _interests, platforms: _platforms, estimate: _audienceEst, dark: dark, onAgeMin: (v) { setState(() => _ageMin = v); _fetchAudience(); }, onAgeMax: (v) { setState(() => _ageMax = v); _fetchAudience(); }, onGender: (v) { setState(() => _genders = v); _fetchAudience(); }, onInterests: (v) { setState(() => _interests = v); _fetchAudience(); }, onPlatforms: (v) => setState(() => _platforms = v)),
        _Step3(budget: _budget, budgetType: _budgetType, bidStrategy: _bidStrategy, startDate: _startDate, endDate: _endDate, dark: dark, onBudget: (v) => setState(() => _budget = v), onType: (v) => setState(() => _budgetType = v), onBid: (v) => setState(() => _bidStrategy = v), onStart: (v) => setState(() => _startDate = v), onEnd: (v) => setState(() => _endDate = v)),
        _Step4(format: _format, headline: _headline, primaryText: _primaryText, ctaText: _ctaText, ctaUrl: _ctaUrl, displayUrl: _displayUrl, mediaFile: _mediaFile, ctaOptions: _ctaOptions, formats: _formats, dark: dark, onFormat: (v) => setState(() => _format = v), onHeadline: (v) => setState(() => _headline = v), onPrimary: (v) => setState(() => _primaryText = v), onCta: (v) => setState(() => _ctaText = v), onUrl: (v) => setState(() => _ctaUrl = v), onDisplayUrl: (v) => setState(() => _displayUrl = v), onPickMedia: _pickMedia),
      ]),
      bottomNavigationBar: Container(
        padding: EdgeInsets.only(left: 16, right: 16, top: 12, bottom: MediaQuery.of(context).viewInsets.bottom + 16),
        decoration: BoxDecoration(color: dark ? AppTheme.dSurf : Colors.white, border: Border(top: BorderSide(color: dark ? AppTheme.dDiv : const Color(0xFFEEEEEE), width: 0.5))),
        child: SizedBox(width: double.infinity, child: ElevatedButton(
          onPressed: _submitting ? null : _next,
          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
          child: _submitting ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)), SizedBox(width: 12), Text('Launching campaign...')])
            : Text(_step == 3 ? '🚀 Launch Campaign' : 'Continue →', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        )),
      ),
    );
  }
}

// ── Step 1: Objective
class _Step1 extends StatelessWidget {
  final List<List<dynamic>> objectives; final String name, selected;
  final void Function(String) onName, onSelect; final bool dark;
  const _Step1({required this.objectives, required this.name, required this.selected, required this.onName, required this.onSelect, required this.dark});
  @override Widget build(BuildContext _) => ListView(padding: const EdgeInsets.all(16), children: [
    const Text('What\'s your campaign goal?', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22)),
    const SizedBox(height: 4),
    const Text('Choose the objective that best describes what you want to achieve.', style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.5)),
    const SizedBox(height: 16),
    TextFormField(initialValue: name, onChanged: onName, decoration: const InputDecoration(labelText: 'Campaign Name *', hintText: 'e.g. Summer Sale 2025', prefixIcon: Icon(Icons.edit_rounded, size: 20))),
    const SizedBox(height: 16),
    ...objectives.map((e) { final id = e[0] as String; final icon = e[1] as IconData; final objName = e[2] as String; final desc = e[3] as String; return GestureDetector(
      onTap: () => onSelect(id),
      child: AnimatedContainer(duration: const Duration(milliseconds: 150), margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: selected == id ? AppTheme.orange : (dark ? const Color(0xFF1E1E1E) : Colors.white), borderRadius: BorderRadius.circular(14), border: Border.all(color: selected == id ? AppTheme.orange : Colors.transparent, width: 2), boxShadow: [BoxShadow(color: selected == id ? AppTheme.orange.withOpacity(0.25) : Colors.black.withOpacity(0.04), blurRadius: 8)]),
        child: Row(children: [
          Container(width: 48, height: 48, decoration: BoxDecoration(color: selected == id ? Colors.white24 : AppTheme.orangeSurf, borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: selected == id ? Colors.white : AppTheme.orange, size: 24)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(objName, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: selected == id ? Colors.white : null)), const SizedBox(height: 2), Text(desc, style: TextStyle(fontSize: 12, color: selected == id ? Colors.white70 : Colors.grey))])),
          if (selected == id) const Icon(Icons.check_circle_rounded, color: Colors.white, size: 22),
        ]),
      ),
    ); }),
  ]);
}

// ── Step 2: Targeting
class _Step2 extends StatelessWidget {
  final int ageMin, ageMax; final int? estimate;
  final List<String> genders, interests, platforms; final bool dark;
  final void Function(int) onAgeMin, onAgeMax;
  final void Function(List<String>) onGender, onInterests, onPlatforms;

  const _Step2({required this.ageMin, required this.ageMax, required this.genders, required this.interests, required this.platforms, required this.estimate, required this.dark, required this.onAgeMin, required this.onAgeMax, required this.onGender, required this.onInterests, required this.onPlatforms});

  static const _interestList = [
    ['technology','Technology'],['fashion','Fashion'],['food','Food & Cooking'],['fitness','Fitness'],
    ['travel','Travel'],['music','Music'],['sports','Sports'],['gaming','Gaming'],
    ['business','Business'],['education','Education'],['beauty','Beauty'],['finance','Finance'],
    ['art','Art'],['parenting','Parenting'],['news','News'],['movies','Movies & TV'],
    ['animals','Pets'],['automotive','Automotive'],['real_estate','Real Estate'],['startups','Startups'],
  ];

  @override Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
    const Text('Who should see your ad?', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22)),
    const SizedBox(height: 14),

    // Audience estimate
    if (estimate != null) Container(padding: const EdgeInsets.all(14), margin: const EdgeInsets.only(bottom: 14), decoration: BoxDecoration(color: AppTheme.orangeSurf, borderRadius: BorderRadius.circular(12)), child: Row(children: [const Icon(Icons.people_rounded, color: AppTheme.orange, size: 24), const SizedBox(width: 10), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Estimated Reach', style: TextStyle(color: Colors.grey, fontSize: 11)), Text('${_fmt(estimate!)}+ people', style: const TextStyle(color: AppTheme.orange, fontWeight: FontWeight.w900, fontSize: 22))]), const Spacer(), const Icon(Icons.refresh_rounded, color: AppTheme.orange, size: 20)])),

    _Label('Age Range'),
    Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Min: $ageMin', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)), Slider(value: ageMin.toDouble(), min: 13, max: ageMax.toDouble()-1, activeColor: AppTheme.orange, onChanged: (v) => onAgeMin(v.round()))])),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Max: $ageMax', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)), Slider(value: ageMax.toDouble(), min: ageMin.toDouble()+1, max: 65, activeColor: AppTheme.orange, onChanged: (v) => onAgeMax(v.round()))])),
    ]),

    _Label('Gender'),
    Wrap(spacing: 8, children: [['all','All Genders'], ['male','Male'], ['female','Female']].map((e) { final v = e[0]; final l = e[1]; return GestureDetector(onTap: () => onGender([v]), child: AnimatedContainer(duration: const Duration(milliseconds: 150), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9), decoration: BoxDecoration(color: genders.contains(v) ? AppTheme.orange : (dark ? const Color(0xFF1E1E1E) : Colors.white), borderRadius: BorderRadius.circular(20)), child: Text(l, style: TextStyle(color: genders.contains(v) ? Colors.white : null, fontWeight: FontWeight.w600)))); }).toList()),
    const SizedBox(height: 14),

    _Label('Interests'),
    Wrap(spacing: 8, runSpacing: 8, children: _interestList.map((e) { final id = e[0]; final intName = e[1]; return GestureDetector(
      onTap: () { final list = List<String>.from(interests); list.contains(id) ? list.remove(id) : list.add(id); onInterests(list); },
      child: AnimatedContainer(duration: const Duration(milliseconds: 150), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7), decoration: BoxDecoration(color: interests.contains(id) ? AppTheme.orange : AppTheme.orangeSurf, borderRadius: BorderRadius.circular(20)), child: Text(intName, style: TextStyle(color: interests.contains(id) ? Colors.white : AppTheme.orange, fontWeight: FontWeight.w600, fontSize: 12))),
    ); }).toList()),
    const SizedBox(height: 14),

    _Label('Platforms'),
    Wrap(spacing: 8, runSpacing: 8, children: [['all','All',Icons.devices_rounded], ['android','Android',Icons.phone_android_rounded], ['ios','iOS',Icons.phone_iphone_rounded], ['web','Web',Icons.language_rounded]].map((e) { final v = e[0] as String; final l = e[1] as String; final i = e[2] as IconData; return GestureDetector(
      onTap: () { if (v=='all') { onPlatforms(['all']); } else { final list = List<String>.from(platforms)..remove('all'); list.contains(v) ? list.remove(v) : list.add(v); onPlatforms(list.isEmpty ? ['all'] : list); } },
      child: AnimatedContainer(duration: const Duration(milliseconds: 150), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7), decoration: BoxDecoration(color: platforms.contains(v) ? AppTheme.orange : (dark ? const Color(0xFF1E1E1E) : Colors.white), borderRadius: BorderRadius.circular(20)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(i, size: 14, color: platforms.contains(v) ? Colors.white : Colors.grey), const SizedBox(width: 5), Text(l, style: TextStyle(color: platforms.contains(v) ? Colors.white : null, fontWeight: FontWeight.w600, fontSize: 12))]))
    ); }).toList()),
  ]);

  static String _fmt(int n) => n >= 1000 ? '${(n/1000).toStringAsFixed(0)}K' : '$n';
}

// ── Step 3: Budget
class _Step3 extends StatelessWidget {
  final double budget; final String budgetType, bidStrategy; final DateTime startDate; final DateTime? endDate;
  final bool dark;
  final void Function(double) onBudget; final void Function(String) onType, onBid;
  final void Function(DateTime) onStart; final void Function(DateTime?) onEnd;
  const _Step3({required this.budget, required this.budgetType, required this.bidStrategy, required this.startDate, required this.endDate, required this.dark, required this.onBudget, required this.onType, required this.onBid, required this.onStart, required this.onEnd});

  Widget _bidItem(String v, String l, String d, String badge) {
    return GestureDetector(
      onTap: () => onBid(v),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bidStrategy == v ? AppTheme.orangeSurf : (dark ? const Color(0xFF1E1E1E) : Colors.white),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: bidStrategy == v ? AppTheme.orange : Colors.transparent),
        ),
        child: Row(children: [
          Radio<String>(value: v, groupValue: bidStrategy, onChanged: (nv) => onBid(nv!), activeColor: AppTheme.orange),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(l, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: bidStrategy == v ? AppTheme.orange : null)),
              if (badge.isNotEmpty) Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: Colors.green.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
                child: const Text('Recommended', style: TextStyle(color: Colors.green, fontSize: 9, fontWeight: FontWeight.w700)),
              ),
            ]),
            Text(d, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ])),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Set your budget', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22)),
      const SizedBox(height: 14),
      Row(children: [['daily','Daily Budget',Icons.calendar_today_rounded], ['lifetime','Lifetime Budget',Icons.calendar_month_rounded]].map((e) { final t = e[0] as String; final l = e[1] as String; final i = e[2] as IconData; return Expanded(child: GestureDetector(onTap: () => onType(t), child: AnimatedContainer(duration: const Duration(milliseconds: 150), margin: EdgeInsets.only(right: t=='daily' ? 8 : 0), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: budgetType==t ? AppTheme.orangeSurf : (dark ? const Color(0xFF1E1E1E) : Colors.white), borderRadius: BorderRadius.circular(14), border: Border.all(color: budgetType==t ? AppTheme.orange : Colors.transparent, width: 2)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(i, color: budgetType==t ? AppTheme.orange : Colors.grey, size: 22), const SizedBox(height: 6), Text(l, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: budgetType==t ? AppTheme.orange : null))])))); }).toList()),
      const SizedBox(height: 16),
      Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: dark ? const Color(0xFF1E1E1E) : Colors.white, borderRadius: BorderRadius.circular(16)), child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [const Text('\$', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 28, color: AppTheme.orange)), Text(budget.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 52, color: AppTheme.orange)), Text(budgetType == 'daily' ? '/day' : ' total', style: const TextStyle(color: Colors.grey, fontSize: 16))]),
        Slider(value: budget, min: 1, max: 500, divisions: 499, activeColor: AppTheme.orange, onChanged: (v) => onBudget(double.parse(v.toStringAsFixed(2)))),
        Wrap(spacing: 8, children: [1.0,5.0,10.0,25.0,50.0,100.0].map((a) => GestureDetector(onTap: () => onBudget(a), child: AnimatedContainer(duration: const Duration(milliseconds: 150), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7), decoration: BoxDecoration(color: budget==a ? AppTheme.orange : (dark ? AppTheme.dCard : Colors.grey.shade100), borderRadius: BorderRadius.circular(16)), child: Text('\$${a.toInt()}', style: TextStyle(color: budget==a ? Colors.white : null, fontWeight: FontWeight.w700))))).toList()),
      ])),
      const SizedBox(height: 14),
      Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: dark ? const Color(0xFF1E1E1E) : Colors.white, borderRadius: BorderRadius.circular(14)), child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Est. Daily Reach', style: TextStyle(fontSize: 13)), Text('${_fmt((budget*300).round())} – ${_fmt((budget*800).round())} people', style: const TextStyle(color: AppTheme.orange, fontWeight: FontWeight.w600))]),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Est. Impressions/Day', style: TextStyle(fontSize: 13)), Text('${_fmt((budget*1000).round())} – ${_fmt((budget*3000).round())}', style: const TextStyle(color: AppTheme.orange, fontWeight: FontWeight.w600))]),
      ])),
      const SizedBox(height: 14),
      _Label('Bid Strategy'),
      _bidItem('lowest_cost', 'Lowest Cost', 'Recommended — get the most results', 'Recommended'),
      _bidItem('target_cost', 'Target Cost', 'Control average cost', ''),
      _bidItem('manual_bid', 'Manual Bid', 'Set your maximum bid', ''),
      const SizedBox(height: 14),
      _Label('Schedule'),
      _DatePick('Start Date *', startDate, () async { final d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365))); if (d != null) onStart(d); }, dark),
      const SizedBox(height: 8),
      _DatePick(endDate != null ? 'End: ${endDate!.toString().split(' ')[0]}' : 'No End Date', endDate, () async { final d = await showDatePicker(context: context, initialDate: startDate.add(const Duration(days: 7)), firstDate: startDate.add(const Duration(days: 1)), lastDate: DateTime.now().add(const Duration(days: 365))); onEnd(d); }, dark),
    ]);
  }

  static String _fmt(int n) => n >= 1000 ? '${(n/1000).toStringAsFixed(0)}K' : '$n';
}

// ── Step 4: Creative
class _Step4 extends StatelessWidget {
  final String format, headline, primaryText, ctaText, ctaUrl, displayUrl;
  final File? mediaFile;
  final List<List<dynamic>> formats;
  final List<String> ctaOptions;
  final bool dark;
  final void Function(String) onFormat, onHeadline, onPrimary, onCta, onUrl, onDisplayUrl;
  final VoidCallback onPickMedia;

  const _Step4({required this.format, required this.headline, required this.primaryText, required this.ctaText, required this.ctaUrl, required this.displayUrl, required this.mediaFile, required this.formats, required this.ctaOptions, required this.dark, required this.onFormat, required this.onHeadline, required this.onPrimary, required this.onCta, required this.onUrl, required this.onDisplayUrl, required this.onPickMedia});

  @override Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
    const Text('Create your ad', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22)),
    const SizedBox(height: 14),

    _Label('Format'),
    SizedBox(height: 88, child: ListView(scrollDirection: Axis.horizontal, children: formats.map((e) { final id = e[0] as String; final icon = e[1] as IconData; final name = e[2] as String; return GestureDetector(onTap: () => onFormat(id), child: AnimatedContainer(duration: const Duration(milliseconds: 150), margin: const EdgeInsets.only(right: 10), width: 90, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: format==id ? AppTheme.orange : (dark ? const Color(0xFF1E1E1E) : Colors.white), borderRadius: BorderRadius.circular(14), border: Border.all(color: format==id ? AppTheme.orange : Colors.transparent, width: 2)), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, color: format==id ? Colors.white : AppTheme.orange, size: 24), const SizedBox(height: 5), Text(name, style: TextStyle(color: format==id ? Colors.white : null, fontWeight: FontWeight.w700, fontSize: 12), textAlign: TextAlign.center)]))); }).toList())),
    const SizedBox(height: 14),

    _Label('Media'),
    GestureDetector(onTap: onPickMedia, child: Container(height: 160, decoration: BoxDecoration(color: dark ? const Color(0xFF1E1E1E) : AppTheme.lInput, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.orange.withOpacity(0.3))), child: mediaFile != null ? ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.file(mediaFile!, fit: BoxFit.cover, width: double.infinity)) : Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(format=='video' ? Icons.video_call_rounded : Icons.add_photo_alternate_rounded, color: AppTheme.orange, size: 36), const SizedBox(height: 8), Text('Upload ${format=='video' ? 'Video' : 'Image'}', style: const TextStyle(color: AppTheme.orange, fontWeight: FontWeight.w600)), const SizedBox(height: 4), const Text('Tap to browse', style: TextStyle(color: Colors.grey, fontSize: 12))]))),
    const SizedBox(height: 14),

    TextField(onChanged: onHeadline, maxLength: 40, decoration: const InputDecoration(labelText: 'Headline', hintText: 'Grab attention...', counterText: '')),
    const SizedBox(height: 10),
    TextField(onChanged: onPrimary, maxLines: 3, maxLength: 125, decoration: const InputDecoration(labelText: 'Primary Text', hintText: 'Describe your offer...')),
    const SizedBox(height: 10),
    TextField(onChanged: onUrl, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Destination URL *', hintText: 'https://yourwebsite.com', prefixIcon: Icon(Icons.link_rounded, size: 18))),
    const SizedBox(height: 10),
    TextField(onChanged: onDisplayUrl, decoration: const InputDecoration(labelText: 'Display URL', hintText: 'yourwebsite.com', prefixIcon: Icon(Icons.language_rounded, size: 18))),
    const SizedBox(height: 14),

    _Label('Call to Action'),
    Wrap(spacing: 8, runSpacing: 8, children: ctaOptions.map((cta) => GestureDetector(onTap: () => onCta(cta), child: AnimatedContainer(duration: const Duration(milliseconds: 150), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), decoration: BoxDecoration(color: ctaText==cta ? AppTheme.orange : (dark ? const Color(0xFF1E1E1E) : Colors.white), borderRadius: BorderRadius.circular(20), border: Border.all(color: ctaText==cta ? AppTheme.orange : Colors.grey.shade300)), child: Text(cta, style: TextStyle(color: ctaText==cta ? Colors.white : null, fontWeight: FontWeight.w600, fontSize: 13))))).toList()),
    const SizedBox(height: 16),

    // Preview
    _Label('Preview'),
    Container(decoration: BoxDecoration(color: dark ? const Color(0xFF1E1E1E) : Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.orange.withOpacity(0.2))), child: Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(12, 12, 12, 6), child: Row(children: [Container(width: 32, height: 32, decoration: const BoxDecoration(color: AppTheme.orange, shape: BoxShape.circle), child: const Center(child: Text('R', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)))), const SizedBox(width: 8), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Your Business', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)), Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1), decoration: BoxDecoration(color: AppTheme.orangeSurf, borderRadius: BorderRadius.circular(4)), child: const Text('Sponsored', style: TextStyle(color: AppTheme.orange, fontSize: 9, fontWeight: FontWeight.w700)))])])),
      mediaFile != null ? Image.file(mediaFile!, height: 160, width: double.infinity, fit: BoxFit.cover) : Container(height: 120, color: AppTheme.orangeSurf, child: const Center(child: Icon(Icons.image_rounded, color: AppTheme.orange, size: 40))),
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [if (headline.isNotEmpty) Text(headline, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)), if (displayUrl.isNotEmpty) Text(displayUrl, style: const TextStyle(color: Colors.grey, fontSize: 11))])), const SizedBox(width: 10), Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(color: AppTheme.orange, borderRadius: BorderRadius.circular(8)), child: Text(ctaText, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)))])),
    ])),
    const SizedBox(height: 14),
    const Center(child: Text('By creating an ad you agree to our Advertising Policies. Ads are reviewed within 24 hours.', style: TextStyle(color: Colors.grey, fontSize: 11), textAlign: TextAlign.center)),
    const SizedBox(height: 20),
  ]);
}

class _Label extends StatelessWidget {
  final String t;
  const _Label(this.t);
  @override Widget build(BuildContext _) => Padding(padding: const EdgeInsets.only(bottom: 8, top: 6), child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)));
}

class _DatePick extends StatelessWidget {
  final String l; final DateTime? dt; final VoidCallback onTap; final bool dark;
  const _DatePick(this.l, this.dt, this.onTap, this.dark);
  @override Widget build(BuildContext _) => GestureDetector(onTap: onTap, child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: dark ? const Color(0xFF1E1E1E) : Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: dt != null ? AppTheme.orange : Colors.grey.shade300)), child: Row(children: [Icon(Icons.calendar_today_rounded, color: dt != null ? AppTheme.orange : Colors.grey, size: 16), const SizedBox(width: 8), Expanded(child: Text(l, style: TextStyle(fontWeight: dt!=null ? FontWeight.w600 : FontWeight.w400, color: dt != null ? AppTheme.orange : Colors.grey)))])));
}
