import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/api_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AD STATE PROVIDER — caches loaded ads per placement
// ─────────────────────────────────────────────────────────────────────────────
final adProvider = StateNotifierProvider.family<AdNotifier, AdState, String>(
  (ref, placement) => AdNotifier(ref, placement),
);

class AdState {
  final Map<String,dynamic>? ad;
  final bool loading, dismissed;
  const AdState({this.ad, this.loading = true, this.dismissed = false});
  AdState copyWith({Map<String,dynamic>? ad, bool? loading, bool? dismissed}) =>
    AdState(ad: ad ?? this.ad, loading: loading ?? this.loading, dismissed: dismissed ?? this.dismissed);
}

class AdNotifier extends StateNotifier<AdState> {
  final Ref _ref;
  final String _placement;
  AdNotifier(this._ref, this._placement) : super(const AdState()) { _load(); }

  Future<void> _load() async {
    try {
      final me = _ref.read(currentUserProvider);
      // Don't show ads to premium subscribers
      // (check subscription in future enhancement)
      final r = await _ref.read(apiServiceProvider).get('/ads/serve/$_placement', q: {
        if (me != null) 'user_id': me.id,
        'platform': 'flutter',
        'country': 'RW',
      });
      if (mounted) {
        state = state.copyWith(
          ad: r.data['ad'] != null ? Map<String,dynamic>.from(r.data['ad']) : null,
          loading: false,
        );
      }
    } catch (_) { if (mounted) state = state.copyWith(loading: false); }
  }

  Future<void> recordClick(String type) async {
    if (state.ad == null) return;
    final me = _ref.read(currentUserProvider);
    _ref.read(apiServiceProvider).post('/ads/click/${state.ad!['id']}', data: {
      if (me != null) 'user_id': me.id,
      'placement': _placement, 'click_type': type,
    }).catchError((_) {});
  }

  Future<void> dismiss(String reason) async {
    if (state.ad == null) return;
    final me = _ref.read(currentUserProvider);
    _ref.read(apiServiceProvider).post('/ads/hide/${state.ad!['id']}', data: {
      if (me != null) 'user_id': me.id, 'reason': reason,
    }).catchError((_) {});
    if (mounted) state = state.copyWith(dismissed: true);
  }

  Future<void> report(String reason) async {
    if (state.ad == null) return;
    final me = _ref.read(currentUserProvider);
    _ref.read(apiServiceProvider).post('/ads/report/${state.ad!['id']}', data: {
      if (me != null) 'user_id': me.id, 'reason': reason,
    }).catchError((_) {});
    if (mounted) state = state.copyWith(dismissed: true);
  }

  Future<void> saveAd() async {
    if (state.ad == null) return;
    final me = _ref.read(currentUserProvider);
    _ref.read(apiServiceProvider).post('/ads/save/${state.ad!['id']}', data: {
      if (me != null) 'user_id': me.id,
    }).catchError((_) {});
  }

  Future<void> openUrl() async {
    final url = state.ad?['cta_url'] as String? ?? '';
    if (url.isNotEmpty) {
      await recordClick('cta');
      try { await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication); } catch (_) {}
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. FEED AD CARD — appears between posts every 5 items
// ─────────────────────────────────────────────────────────────────────────────
class FeedAdCard extends ConsumerStatefulWidget {
  final int feedIndex;
  const FeedAdCard({super.key, required this.feedIndex});
  @override ConsumerState<FeedAdCard> createState() => _FAC();
}
class _FAC extends ConsumerState<FeedAdCard> with SingleTickerProviderStateMixin {
  late AnimationController _ac;
  late Animation<double> _fade;
  bool _expanded = false;

  @override void initState() {
    super.initState();
    _ac = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _fade = CurvedAnimation(parent: _ac, curve: Curves.easeOut);
    _ac.forward();
  }
  @override void dispose() { _ac.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final placement = 'feed_${widget.feedIndex}';
    final adState = ref.watch(adProvider(placement));
    if (adState.loading || adState.dismissed || adState.ad == null) return const SizedBox.shrink();
    final ad   = adState.ad!;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final notif = ref.read(adProvider(placement).notifier);
    final fmt  = ad['format'] as String? ?? 'image';

    return FadeTransition(opacity: _fade, child: Container(
      margin: const EdgeInsets.fromLTRB(0, 4, 0, 8),
      decoration: BoxDecoration(
        color: dark ? AppTheme.dCard : Colors.white,
        border: Border(
          top:    BorderSide(color: dark ? AppTheme.dDiv : const Color(0xFFEEEEEE), width: 0.5),
          bottom: BorderSide(color: dark ? AppTheme.dDiv : const Color(0xFFEEEEEE), width: 0.5),
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header row
        Padding(padding: const EdgeInsets.fromLTRB(14, 10, 8, 6), child: Row(children: [
          _AdLogo(ad: ad, size: 36),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(ad['business_name'] ?? 'Sponsored', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14), overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 6),
              _SponsoredBadge(),
            ]),
            if (ad['display_url'] != null) Text(ad['display_url'] as String, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ])),
          _AdOptionsMenu(ad: ad, notifier: notif, dark: dark),
        ])),

        // Primary text
        if (ad['primary_text'] != null && (ad['primary_text'] as String).isNotEmpty)
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 8), child: Text(
              ad['primary_text'] as String,
              style: const TextStyle(fontSize: 14, height: 1.5),
              maxLines: _expanded ? null : 3,
              overflow: _expanded ? null : TextOverflow.ellipsis,
            )),
          ),

        // Creative
        GestureDetector(
          onTap: () => notif.openUrl(),
          child: fmt == 'carousel'
            ? _CarouselCreative(items: ad['carousel_items'], onTap: notif.recordClick)
            : fmt == 'collection'
              ? _CollectionCreative(ad: ad, onTap: notif.recordClick)
              : _SingleImageCreative(ad: ad, height: 280),
        ),

        // Footer: headline + CTA
        Padding(padding: const EdgeInsets.fromLTRB(14, 10, 14, 4), child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (ad['headline'] != null && (ad['headline'] as String).isNotEmpty)
              Text(ad['headline'] as String, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, height: 1.2), maxLines: 2, overflow: TextOverflow.ellipsis),
          ])),
          const SizedBox(width: 12),
          _CtaButton(label: ad['cta_text'] as String? ?? 'Learn More', onTap: () => notif.openUrl()),
        ])),

        // Engagement row
        Padding(padding: const EdgeInsets.fromLTRB(14, 4, 14, 12), child: Row(children: [
          _EngageBtn(Icons.favorite_border_rounded, 'Like',     () => notif.recordClick('like')),
          const SizedBox(width: 18),
          _EngageBtn(Icons.chat_bubble_outline_rounded, 'Comment', () => notif.recordClick('comment')),
          const SizedBox(width: 18),
          _EngageBtn(Icons.share_outlined, 'Share',   () => notif.recordClick('share')),
          const Spacer(),
          GestureDetector(onTap: () { notif.saveAd(); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ad saved 🔖'))); }, child: const Icon(Icons.bookmark_border_rounded, size: 20, color: Colors.grey)),
        ])),
      ]),
    ));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. STORY AD — full-screen 9:16 overlay between stories
// ─────────────────────────────────────────────────────────────────────────────
class StoryAdWidget extends ConsumerStatefulWidget {
  final VoidCallback onSkip;
  const StoryAdWidget({super.key, required this.onSkip});
  @override ConsumerState<StoryAdWidget> createState() => _SAW();
}
class _SAW extends ConsumerState<StoryAdWidget> with SingleTickerProviderStateMixin {
  late AnimationController _progressAc;
  Timer? _autoSkip;
  bool _showCta = false;

  @override void initState() {
    super.initState();
    _progressAc = AnimationController(vsync: this, duration: const Duration(seconds: 6))..forward();
    _autoSkip   = Timer(const Duration(seconds: 6), widget.onSkip);
    Future.delayed(const Duration(seconds: 2), () { if (mounted) setState(() => _showCta = true); });
  }
  @override void dispose() { _progressAc.dispose(); _autoSkip?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final adState = ref.watch(adProvider('story'));
    if (adState.loading || adState.ad == null) {
      return GestureDetector(onTap: widget.onSkip, child: Container(color: Colors.black, child: const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: AppTheme.orange, strokeWidth: 2)))));
    }
    if (adState.dismissed) { WidgetsBinding.instance.addPostFrameCallback((_) => widget.onSkip()); return const SizedBox.shrink(); }
    final ad     = adState.ad!;
    final notif  = ref.read(adProvider('story').notifier);

    return GestureDetector(
      onTapUp: (d) {
        final w = MediaQuery.of(context).size.width;
        if (d.globalPosition.dx > w * 0.7) widget.onSkip();
      },
      child: Stack(fit: StackFit.expand, children: [
        // Background
        ad['media_url'] != null
          ? CachedNetworkImage(imageUrl: ad['media_url'] as String, fit: BoxFit.cover,
              errorWidget: (_, __, ___) => _GradientBg(ad: ad))
          : _GradientBg(ad: ad),

        // Scrim
        Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black.withOpacity(0.4), Colors.transparent, Colors.black.withOpacity(0.65)], stops: const [0.0, 0.4, 1.0]))),

        // Progress bar
        Positioned(top: 0, left: 0, right: 0, child: SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(14, 8, 14, 0), child: Column(children: [
          AnimatedBuilder(animation: _progressAc, builder: (_, __) => ClipRRect(borderRadius: BorderRadius.circular(2), child: LinearProgressIndicator(value: _progressAc.value, backgroundColor: Colors.white24, valueColor: const AlwaysStoppedAnimation(Colors.white), minHeight: 3))),
          const SizedBox(height: 10),
          Row(children: [
            _AdLogo(ad: ad, size: 32),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(ad['business_name'] ?? 'Sponsor', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
              _SponsoredBadge(light: true),
            ]),
            const Spacer(),
            _AdOptionsMenu(ad: ad, notifier: notif, dark: true, light: true),
            GestureDetector(onTap: widget.onSkip, child: Container(width: 32, height: 32, decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.close_rounded, color: Colors.white, size: 18))),
          ]),
        ])))),

        // Story text overlay
        if (ad['story_text_overlay'] != null)
          Center(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 28), child: Text(ad['story_text_overlay'] as String, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 26, shadows: [Shadow(blurRadius: 16, color: Colors.black)]), textAlign: TextAlign.center))),

        // Bottom CTA
        Positioned(bottom: 0, left: 0, right: 0, child: SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), child: Column(children: [
          if (ad['headline'] != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(ad['headline'] as String, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 20, shadows: [Shadow(blurRadius: 8)]), maxLines: 2, textAlign: TextAlign.center)),
          AnimatedSlide(offset: _showCta ? Offset.zero : const Offset(0, 1), duration: const Duration(milliseconds: 400), curve: Curves.easeOutBack, child: AnimatedOpacity(opacity: _showCta ? 1.0 : 0.0, duration: const Duration(milliseconds: 300), child: GestureDetector(
            onTap: () { notif.openUrl(); _autoSkip?.cancel(); },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(color: AppTheme.orange, borderRadius: BorderRadius.circular(14)),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(ad['cta_text'] as String? ?? 'Learn More', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(width: 6),
                const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 14),
              ]),
            ),
          ))),
          // Swipe up hint
          const SizedBox(height: 8),
          const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white54, size: 18), Text('Swipe up for more', style: TextStyle(color: Colors.white38, fontSize: 11))]),
        ])))),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. REEL AD — appears between reels (full vertical video)
// ─────────────────────────────────────────────────────────────────────────────
class ReelAdOverlay extends ConsumerWidget {
  const ReelAdOverlay({super.key});
  @override Widget build(BuildContext context, WidgetRef ref) {
    final adState = ref.watch(adProvider('reel'));
    if (adState.loading || adState.dismissed || adState.ad == null) return const SizedBox.shrink();
    final ad     = adState.ad!;
    final notif  = ref.read(adProvider('reel').notifier);
    return Stack(fit: StackFit.expand, children: [
      ad['media_url'] != null
        ? CachedNetworkImage(imageUrl: ad['media_url'] as String, fit: BoxFit.cover)
        : _GradientBg(ad: ad),
      Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black.withOpacity(0.8)], stops: const [0.4, 1.0]))),
      // Top: sponsored label
      Positioned(top: 0, left: 0, right: 0, child: SafeArea(child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [_SponsoredBadge(light: true), const Spacer(), _AdOptionsMenu(ad: ad, notifier: notif, dark: true, light: true)])))),
      // Bottom content
      Positioned(bottom: 0, left: 0, right: 0, child: SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 80), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [_AdLogo(ad: ad, size: 38), const SizedBox(width: 10), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(ad['business_name'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)), Text(ad['display_url'] ?? '', style: const TextStyle(color: Colors.white60, fontSize: 11))])]),
        const SizedBox(height: 8),
        if (ad['headline'] != null) Text(ad['headline'] as String, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18), maxLines: 2),
        if (ad['primary_text'] != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(ad['primary_text'] as String, style: const TextStyle(color: Colors.white70, fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis)),
        const SizedBox(height: 12),
        GestureDetector(onTap: () => notif.openUrl(), child: Container(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), decoration: BoxDecoration(color: AppTheme.orange, borderRadius: BorderRadius.circular(24)), child: Text(ad['cta_text'] as String? ?? 'Learn More', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)))),
      ])))),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. EXPLORE GRID AD — native grid card in discover screen
// ─────────────────────────────────────────────────────────────────────────────
class ExploreAdCard extends ConsumerWidget {
  const ExploreAdCard({super.key});
  @override Widget build(BuildContext context, WidgetRef ref) {
    final adState = ref.watch(adProvider('explore'));
    if (adState.loading || adState.dismissed || adState.ad == null) return const SizedBox.shrink();
    final ad    = adState.ad!;
    final notif = ref.read(adProvider('explore').notifier);
    return GestureDetector(
      onTap: () => notif.openUrl(),
      child: Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 10)]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Image
          ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(14)), child: Stack(children: [
            ad['media_url'] != null
              ? CachedNetworkImage(imageUrl: ad['media_url'] as String, height: 130, width: double.infinity, fit: BoxFit.cover)
              : Container(height: 130, decoration: const BoxDecoration(gradient: LinearGradient(colors: [AppTheme.orange, AppTheme.orangeDark]))),
            Positioned(top: 6, left: 6, child: _SponsoredBadge()),
          ])),
          Padding(padding: const EdgeInsets.all(10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(ad['business_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 3),
            Text(ad['headline'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: AppTheme.orange, borderRadius: BorderRadius.circular(6)), child: Text(ad['cta_text'] as String? ?? 'Learn More', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700))),
          ])),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 5. CHAT AD BANNER — appears at top of messages list
// ─────────────────────────────────────────────────────────────────────────────
class ChatAdBanner extends ConsumerWidget {
  const ChatAdBanner({super.key});
  @override Widget build(BuildContext context, WidgetRef ref) {
    final adState = ref.watch(adProvider('chat'));
    if (adState.loading || adState.dismissed || adState.ad == null) return const SizedBox.shrink();
    final ad    = adState.ad!;
    final notif = ref.read(adProvider('chat').notifier);
    final dark  = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () => notif.openUrl(),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.orange.withOpacity(0.2))),
        child: Row(children: [
          ClipRRect(borderRadius: BorderRadius.circular(8), child: ad['media_url'] != null ? CachedNetworkImage(imageUrl: ad['media_url'] as String, width: 48, height: 48, fit: BoxFit.cover) : Container(width: 48, height: 48, color: AppTheme.orangeSurf, child: const Icon(Icons.campaign_rounded, color: AppTheme.orange))),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Text(ad['business_name'] ?? 'Sponsor', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)), const SizedBox(width: 5), _SponsoredBadge(small: true)]),
            Text(ad['headline'] ?? ad['primary_text'] ?? '', style: const TextStyle(fontSize: 12, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
          ])),
          const SizedBox(width: 8),
          Text(ad['cta_text'] as String? ?? 'Visit', style: const TextStyle(color: AppTheme.orange, fontWeight: FontWeight.w700, fontSize: 12)),
          const SizedBox(width: 4),
          GestureDetector(onTap: () => notif.dismiss('not_relevant'), child: const Icon(Icons.close_rounded, size: 14, color: Colors.grey)),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 6. LIVE AD GIFT BANNER — appears during live streams
// ─────────────────────────────────────────────────────────────────────────────
class LiveAdBanner extends ConsumerWidget {
  const LiveAdBanner({super.key});
  @override Widget build(BuildContext context, WidgetRef ref) {
    final adState = ref.watch(adProvider('live'));
    if (adState.loading || adState.dismissed || adState.ad == null) return const SizedBox.shrink();
    final ad    = adState.ad!;
    final notif = ref.read(adProvider('live').notifier);
    return GestureDetector(
      onTap: () => notif.openUrl(),
      child: Container(
        margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(30)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _SponsoredBadge(light: true, small: true),
          const SizedBox(width: 8),
          Text(ad['headline'] ?? ad['business_name'] ?? 'Sponsor', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12), maxLines: 1),
          const SizedBox(width: 8),
          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: AppTheme.orange, borderRadius: BorderRadius.circular(12)), child: Text(ad['cta_text'] as String? ?? 'See More', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700))),
          const SizedBox(width: 4),
          GestureDetector(onTap: () => notif.dismiss('not_relevant'), child: const Icon(Icons.close_rounded, color: Colors.white38, size: 14)),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED COMPONENTS
// ─────────────────────────────────────────────────────────────────────────────
class _AdLogo extends StatelessWidget {
  final Map<String,dynamic> ad; final double size;
  const _AdLogo({required this.ad, required this.size});
  @override Widget build(BuildContext _) => Container(
    width: size, height: size,
    decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppTheme.orange, AppTheme.orangeDark]), borderRadius: BorderRadius.circular(size * 0.25)),
    child: Center(child: Text((ad['business_name'] as String? ?? 'A').substring(0, 1).toUpperCase(), style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: size * 0.45))),
  );
}

class _SponsoredBadge extends StatelessWidget {
  final bool light, small;
  const _SponsoredBadge({this.light = false, this.small = false});
  @override Widget build(BuildContext _) => Container(
    padding: EdgeInsets.symmetric(horizontal: small ? 5 : 7, vertical: small ? 2 : 3),
    decoration: BoxDecoration(color: light ? Colors.white24 : AppTheme.orangeSurf, borderRadius: BorderRadius.circular(6)),
    child: Text('Sponsored', style: TextStyle(color: light ? Colors.white70 : AppTheme.orange, fontWeight: FontWeight.w700, fontSize: small ? 9 : 10)),
  );
}

class _CtaButton extends StatelessWidget {
  final String label; final VoidCallback onTap;
  const _CtaButton({required this.label, required this.onTap});
  @override Widget build(BuildContext _) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(color: AppTheme.orange, borderRadius: BorderRadius.circular(10)),
      child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
    ),
  );
}

class _EngageBtn extends StatefulWidget {
  final IconData icon; final String label; final VoidCallback onTap;
  const _EngageBtn(this.icon, this.label, this.onTap);
  @override State<_EngageBtn> createState() => _EBS();
}
class _EBS extends State<_EngageBtn> {
  bool _tapped = false;
  @override Widget build(BuildContext _) => GestureDetector(onTap: () { setState(() => _tapped = !_tapped); widget.onTap(); }, child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(widget.icon, size: 18, color: _tapped ? AppTheme.orange : Colors.grey), const SizedBox(width: 4), Text(widget.label, style: TextStyle(fontSize: 13, color: _tapped ? AppTheme.orange : Colors.grey, fontWeight: FontWeight.w500))]));
}

class _AdOptionsMenu extends StatelessWidget {
  final Map<String,dynamic> ad; final AdNotifier notifier; final bool dark, light;
  const _AdOptionsMenu({required this.ad, required this.notifier, required this.dark, this.light = false});
  @override Widget build(BuildContext context) => PopupMenuButton<String>(
    icon: Icon(Icons.more_horiz_rounded, color: light ? Colors.white70 : Colors.grey, size: 20),
    onSelected: (v) {
      if (v == 'save') { notifier.saveAd(); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ad saved 🔖'))); }
      if (v == 'hide') _showHideReasons(context);
      if (v == 'report') _showReport(context);
      if (v == 'about') _showAbout(context);
    },
    itemBuilder: (_) => [
      const PopupMenuItem(value: 'about', child: Row(children: [Icon(Icons.info_outline_rounded, size: 18), SizedBox(width: 8), Text('Why am I seeing this?')])),
      const PopupMenuItem(value: 'save',  child: Row(children: [Icon(Icons.bookmark_border_rounded, size: 18, color: AppTheme.orange), SizedBox(width: 8), Text('Save this ad')])),
      const PopupMenuItem(value: 'hide',  child: Row(children: [Icon(Icons.not_interested_rounded, size: 18), SizedBox(width: 8), Text('Hide this ad')])),
      const PopupMenuItem(value: 'report',child: Row(children: [Icon(Icons.flag_rounded, size: 18, color: Colors.red), SizedBox(width: 8), Text('Report', style: TextStyle(color: Colors.red))])),
    ],
  );

  void _showAbout(BuildContext ctx) {
    showDialog(context: ctx, builder: (_) => AlertDialog(
      title: const Text('About this ad', style: TextStyle(fontWeight: FontWeight.w700)),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Advertiser: ${ad['business_name'] ?? 'Unknown'}', style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        const Text('This ad is shown based on your interests, location, and activity on RedOrrange. Advertisers pay to reach people like you.', style: TextStyle(fontSize: 13, height: 1.5)),
        const SizedBox(height: 8),
        const Text('RedOrrange does not share your personal data with advertisers.', style: TextStyle(fontSize: 12, color: Colors.grey)),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Got it'))],
    ));
  }

  void _showHideReasons(BuildContext ctx) {
    showModalBottomSheet(context: ctx, builder: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
      const Padding(padding: EdgeInsets.all(16), child: Text('Why are you hiding this ad?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
      for (final (r, l) in [('not_relevant','Not relevant to me'), ('seen_too_much','I\'ve seen this too many times'), ('offensive','Offensive or inappropriate'), ('misleading','Misleading information'), ('spam','Spam')])
        ListTile(title: Text(l), onTap: () { Navigator.pop(ctx); notifier.dismiss(r); ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Ad hidden. You\'ll see fewer ads like this.'))); }),
      const SizedBox(height: 12),
    ]));
  }

  void _showReport(BuildContext ctx) {
    showModalBottomSheet(context: ctx, builder: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
      const Padding(padding: EdgeInsets.all(16), child: Text('Report this ad', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
      for (final (r, l) in [('misleading','Misleading or deceptive'), ('inappropriate','Inappropriate content'), ('scam','Potential scam or fraud'), ('spam','Spam'), ('violent','Violent or dangerous')])
        ListTile(title: Text(l), trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey), onTap: () { Navigator.pop(ctx); notifier.report(r); ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Report submitted. Thank you.'))); }),
      const SizedBox(height: 12),
    ]));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CREATIVE FORMATS
// ─────────────────────────────────────────────────────────────────────────────
class _SingleImageCreative extends StatelessWidget {
  final Map<String,dynamic> ad; final double height;
  const _SingleImageCreative({required this.ad, this.height = 280});
  @override Widget build(BuildContext _) => ad['media_url'] != null
    ? CachedNetworkImage(imageUrl: ad['media_url'] as String, height: height, width: double.infinity, fit: BoxFit.cover,
        placeholder: (_, __) => Container(height: height, color: AppTheme.orangeSurf),
        errorWidget: (_, __, ___) => _GradientBg(ad: ad, height: height))
    : _GradientBg(ad: ad, height: height);
}

class _GradientBg extends StatelessWidget {
  final Map<String,dynamic> ad; final double height;
  const _GradientBg({required this.ad, this.height = 280});
  @override Widget build(BuildContext _) {
    Color bg = AppTheme.orange;
    try { if (ad['story_bg_color'] != null) bg = Color(int.parse('0xFF${(ad['story_bg_color'] as String).replaceAll('#', '')}')); } catch (_) {}
    return Container(height: height, decoration: BoxDecoration(gradient: LinearGradient(colors: [bg, bg.withOpacity(0.7)], begin: Alignment.topLeft, end: Alignment.bottomRight)), child: Center(child: Text(ad['headline'] ?? ad['business_name'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 22), textAlign: TextAlign.center)));
  }
}

class _CarouselCreative extends StatefulWidget {
  final dynamic items; final Future<void> Function(String) onTap;
  const _CarouselCreative({required this.items, required this.onTap});
  @override State<_CarouselCreative> createState() => _CC();
}
class _CC extends State<_CarouselCreative> {
  int _idx = 0;
  final _pc = PageController(viewportFraction: 0.85);
  @override void dispose() { _pc.dispose(); super.dispose(); }
  @override Widget build(BuildContext _) {
    final list = widget.items is List ? widget.items as List : [];
    if (list.isEmpty) return const SizedBox.shrink();
    return Column(children: [
      SizedBox(height: 240, child: PageView.builder(controller: _pc, itemCount: list.length, onPageChanged: (i) => setState(() => _idx = i), itemBuilder: (_, i) {
        final item = list[i] is Map ? list[i] as Map : {};
        return GestureDetector(onTap: () => widget.onTap('carousel'), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Stack(fit: StackFit.expand, children: [
          item['image_url'] != null ? CachedNetworkImage(imageUrl: item['image_url'] as String, fit: BoxFit.cover) : Container(color: AppTheme.orangeSurf),
          Positioned(bottom: 0, left: 0, right: 0, child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black.withOpacity(0.7), Colors.transparent])), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [if (item['title'] != null) Text(item['title'] as String, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)), if (item['price'] != null) Text(item['price'] as String, style: const TextStyle(color: AppTheme.orange, fontWeight: FontWeight.w800))]))),
        ]))));
      })),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(list.length, (i) => AnimatedContainer(duration: const Duration(milliseconds: 200), width: _idx == i ? 16 : 6, height: 6, margin: const EdgeInsets.symmetric(horizontal: 2), decoration: BoxDecoration(color: _idx == i ? AppTheme.orange : Colors.grey.shade300, borderRadius: BorderRadius.circular(3))))),
    ]);
  }
}

class _CollectionCreative extends StatelessWidget {
  final Map<String,dynamic> ad; final Future<void> Function(String) onTap;
  const _CollectionCreative({required this.ad, required this.onTap});
  @override Widget build(BuildContext _) {
    final items = ad['carousel_items'] is List ? ad['carousel_items'] as List : [];
    return Column(children: [
      // Hero
      GestureDetector(onTap: () => onTap('hero'), child: ad['media_url'] != null ? CachedNetworkImage(imageUrl: ad['media_url'] as String, height: 180, width: double.infinity, fit: BoxFit.cover) : Container(height: 180, color: AppTheme.orangeSurf)),
      // Grid of 4
      if (items.isNotEmpty) GridView.count(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: 4, mainAxisSpacing: 2, crossAxisSpacing: 2, children: items.take(4).map((item) => GestureDetector(onTap: () => onTap('grid'), child: item['image_url'] != null ? CachedNetworkImage(imageUrl: item['image_url'] as String, fit: BoxFit.cover) : Container(color: AppTheme.orangeSurf))).toList()),
    ]);
  }
}
