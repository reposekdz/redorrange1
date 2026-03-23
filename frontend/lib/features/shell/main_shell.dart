import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/auth_provider.dart';
import '../../shared/widgets/app_avatar.dart';

final navIndexProvider = StateProvider<int>((ref) => 0);

class _T { final String path, label; final IconData on, off; const _T(this.path, this.on, this.off, this.label); }

const _mainTabs = [
  _T('/', Icons.home_rounded, Icons.home_outlined, 'Home'),
  _T('/messages', Icons.chat_bubble_rounded, Icons.chat_bubble_outline_rounded, 'Messages'),
  _T('/create', Icons.add_circle_rounded, Icons.add_circle_outline_rounded, 'Create'),
  _T('/reels', Icons.play_circle_rounded, Icons.play_circle_outline_rounded, 'Reels'),
  _T('/discover', Icons.explore_rounded, Icons.explore_outlined, 'Explore'),
];

const _secondaryTabs = [
  _T('/contacts',       Icons.contacts_rounded,       Icons.contacts_outlined,       'Contacts'),
  _T('/events',         Icons.event_rounded,           Icons.event_outlined,          'Events'),
  _T('/live',           Icons.live_tv_rounded,         Icons.live_tv_outlined,        'Live'),
  _T('/marketplace',    Icons.store_rounded,           Icons.store_outlined,          'Marketplace'),
  _T('/channels',       Icons.podcasts_rounded,        Icons.podcasts_outlined,       'Channels'),
];

const _tertiaryTabs = [
  _T('/calls-history',  Icons.call_rounded,            Icons.call_outlined,           'Calls'),
  _T('/saved',          Icons.bookmark_rounded,        Icons.bookmark_outline_rounded,'Saved'),
  _T('/analytics',      Icons.analytics_rounded,       Icons.analytics_outlined,      'Analytics'),
  _T('/wallet',         Icons.account_balance_wallet_rounded, Icons.account_balance_wallet_outlined, 'Wallet'),
  _T('/ads',            Icons.campaign_rounded,               Icons.campaign_outlined,              'Ads'),
  _T('/notifications',  Icons.notifications_rounded,   Icons.notifications_outlined,  'Activity'),
  _T('/settings',       Icons.settings_rounded,        Icons.settings_outlined,       'Settings'),
];

class MainShell extends ConsumerWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user  = ref.watch(currentUserProvider);
    final idx   = ref.watch(navIndexProvider);
    final dark   = Theme.of(context).brightness == Brightness.dark;
    final w      = MediaQuery.of(context).size.width;
    final isWide = w >= 768;

    if (isWide) {
      return Scaffold(body: Row(children: [
        _Sidebar(idx: idx, user: user, dark: dark, expanded: w >= 1100, ref: ref),
        Container(width: 0.5, color: dark ? AppTheme.dDiv : AppTheme.lDiv),
        Expanded(child: child),
      ]));
    }

    return Scaffold(
      body: child,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: dark ? AppTheme.dSurf : Colors.white,
          border: Border(top: BorderSide(color: dark ? AppTheme.dDiv : AppTheme.lDiv, width: 0.5)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0,-2))],
        ),
        child: SafeArea(top: false, child: SizedBox(height: 58,
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            for (int i = 0; i < _mainTabs.length; i++)
              _BottomItem(t: _mainTabs[i], active: idx == i, isCreate: i == 2, onTap: () { ref.read(navIndexProvider.notifier).state = i; context.go(_mainTabs[i].path); }),
          ]),
        )),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final int idx; final dynamic user; final bool dark, expanded; final WidgetRef ref;
  const _Sidebar({required this.idx, required this.user, required this.dark, required this.expanded, required this.ref});

  @override
  Widget build(BuildContext context) {
    final w = expanded ? 256.0 : 70.0;
    return Container(width: w, color: dark ? AppTheme.dSurf : Colors.white, child: SafeArea(child: Column(children: [
      // Logo
      Padding(padding: EdgeInsets.symmetric(horizontal: expanded ? 16 : 10, vertical: 14), child: Row(children: [
        Container(width: 34, height: 34, decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppTheme.orange, AppTheme.orangeDark]), borderRadius: BorderRadius.circular(9)),
          child: const Icon(Icons.circle, color: Colors.white, size: 18)),
        if (expanded) ...[const SizedBox(width: 10), const Expanded(child: Text('RedOrrange', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AppTheme.orange), overflow: TextOverflow.ellipsis))],
      ])),

      Expanded(child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Main navigation
        for (int i = 0; i < _mainTabs.length; i++)
          _SItem(t: _mainTabs[i], active: idx == i, exp: expanded, isCreate: i == 2, onTap: () { ref.read(navIndexProvider.notifier).state = i; context.go(_mainTabs[i].path); }),

        if (expanded) Padding(padding: const EdgeInsets.fromLTRB(16,14,16,6), child: Text('SOCIAL', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: dark ? AppTheme.dSub : AppTheme.lSub, letterSpacing: 1.2)))
        else Padding(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8), child: Divider(color: dark ? AppTheme.dDiv : AppTheme.lDiv, height: 1)),

        for (final t in _secondaryTabs)
          _SItem(t: t, active: false, exp: expanded, onTap: () => context.push(t.path)),

        if (expanded) Padding(padding: const EdgeInsets.fromLTRB(16,14,16,6), child: Text('TOOLS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: dark ? AppTheme.dSub : AppTheme.lSub, letterSpacing: 1.2)))
        else Padding(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8), child: Divider(color: dark ? AppTheme.dDiv : AppTheme.lDiv, height: 1)),

        for (final t in _tertiaryTabs)
          _SItem(t: t, active: false, exp: expanded, onTap: () => context.push(t.path)),
      ]))),

      // Profile footer
      Divider(height: 1, color: dark ? AppTheme.dDiv : AppTheme.lDiv),
      InkWell(
        onTap: () { if (user?.id != null) context.push('/profile/${user.id}'); },
        child: Padding(padding: EdgeInsets.symmetric(horizontal: expanded ? 14 : 8, vertical: 12), child: Row(children: [
          Stack(children: [
            AppAvatar(url: user?.avatarUrl, size: 36, username: user?.username),
            Positioned(bottom: 0, right: 0, child: Container(width: 10, height: 10, decoration: BoxDecoration(color: const Color(0xFF4CAF50), shape: BoxShape.circle, border: Border.all(color: dark ? AppTheme.dSurf : Colors.white, width: 1.5)))),
          ]),
          if (expanded) ...[
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(user?.displayName ?? user?.username ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), overflow: TextOverflow.ellipsis, maxLines: 1),
              Text('@${user?.username ?? ''}', style: TextStyle(fontSize: 11, color: dark ? AppTheme.dSub : AppTheme.lSub), overflow: TextOverflow.ellipsis),
            ])),
            Icon(Icons.more_horiz_rounded, size: 18, color: dark ? AppTheme.dSub : AppTheme.lSub),
          ],
        ])),
      ),
      const SizedBox(height: 6),
    ])));
  }
}

class _SItem extends StatelessWidget {
  final _T t; final bool active, exp, isCreate; final VoidCallback onTap;
  const _SItem({required this.t, required this.active, required this.exp, required this.onTap, this.isCreate = false});
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (isCreate && exp) {
      return Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), child: GestureDetector(onTap: onTap, child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppTheme.orange, AppTheme.orangeDark]), borderRadius: BorderRadius.circular(12)),
        child: Row(children: [const Icon(Icons.add_rounded, color: Colors.white, size: 22), const SizedBox(width: 12), const Text('Create', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15))]),
      )));
    }
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), child: AnimatedContainer(duration: const Duration(milliseconds: 180),
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(12), child: Container(
        padding: EdgeInsets.symmetric(horizontal: exp ? 12 : 11, vertical: 11),
        decoration: BoxDecoration(color: active ? AppTheme.orange.withOpacity(0.1) : Colors.transparent, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Icon(active ? t.on : t.off, color: active ? AppTheme.orange : (dark ? AppTheme.dSub : const Color(0xFF555555)), size: 23),
          if (exp) ...[const SizedBox(width: 12), Text(t.label, style: TextStyle(fontWeight: active ? FontWeight.w700 : FontWeight.w500, color: active ? AppTheme.orange : (dark ? AppTheme.dText : AppTheme.lText), fontSize: 15))],
        ]),
      )),
    ));
  }
}

class _BottomItem extends StatelessWidget {
  final _T t; final bool active, isCreate; final VoidCallback onTap;
  const _BottomItem({required this.t, required this.active, required this.onTap, this.isCreate = false});
  @override
  Widget build(BuildContext context) {
    if (isCreate) return GestureDetector(onTap: onTap, child: Container(width: 44, height: 44,
      decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppTheme.orange, AppTheme.orangeDark]), borderRadius: BorderRadius.circular(13),
        boxShadow: [BoxShadow(color: AppTheme.orange.withOpacity(0.4), blurRadius: 10, offset: const Offset(0,2))]),
      child: const Icon(Icons.add_rounded, color: Colors.white, size: 26)));
    return GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque,
      child: SizedBox(width: 62, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(active ? t.on : t.off, size: 26, color: active ? AppTheme.orange : const Color(0xFF888888)),
        const SizedBox(height: 2),
        Text(t.label, style: TextStyle(fontSize: 10, fontWeight: active ? FontWeight.w700 : FontWeight.w400, color: active ? AppTheme.orange : const Color(0xFF888888))),
      ])));
  }
}
