
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});
  @override Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('About', style: TextStyle(fontWeight: FontWeight.w800))),
      body: ListView(children: [
        Container(margin: const EdgeInsets.all(20), child: Column(children: [
          Container(width: 90, height: 90, decoration: const BoxDecoration(gradient: LinearGradient(colors: [AppTheme.orange, AppTheme.orangeDark]), borderRadius: BorderRadius.all(Radius.circular(22))), child: const Center(child: Text('R', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 48)))),
          const SizedBox(height: 14),
          const Text('RedOrrange', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 24)),
          const Text('Version 2.0.0 (Build 100)', style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 6),
          Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6), decoration: BoxDecoration(color: AppTheme.orangeSurf, borderRadius: BorderRadius.circular(20)), child: const Text('Stay Connected. Stay Real.', style: TextStyle(color: AppTheme.orange, fontWeight: FontWeight.w600, fontSize: 13))),
        ])),
        _L('Privacy Policy',         Icons.privacy_tip_rounded,        () => launchUrl(Uri.parse('https://redorrange.app/privacy'))),
        _L('Terms of Service',       Icons.description_rounded,         () => launchUrl(Uri.parse('https://redorrange.app/terms'))),
        _L('Community Guidelines',   Icons.rule_rounded,                () => launchUrl(Uri.parse('https://redorrange.app/community'))),
        _L('Cookie Policy',          Icons.cookie_rounded,              () => launchUrl(Uri.parse('https://redorrange.app/cookies'))),
        const Divider(height: 20),
        _L('Rate RedOrrange',         Icons.star_rounded,               () {}, color: Colors.amber),
        _L('Share RedOrrange',        Icons.share_rounded,              () {}),
        _L('Send Feedback',           Icons.feedback_rounded,           () => launchUrl(Uri.parse('mailto:support@redorrange.app'))),
        _L('Report a Bug',            Icons.bug_report_rounded,         () => launchUrl(Uri.parse('mailto:bugs@redorrange.app'))),
        const Divider(height: 20),
        _L('Open Source Licenses',    Icons.code_rounded,               () {}),
        const SizedBox(height: 20),
        const Center(child: Text('Made with ❤️ for everyone\n© 2025 RedOrrange Inc.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 12, height: 1.6))),
        const SizedBox(height: 30),
      ]),
    );
  }
}
class _L extends StatelessWidget {
  final String t; final IconData i; final VoidCallback onTap; final Color? color;
  const _L(this.t, this.i, this.onTap, {this.color});
  @override Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3), decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(12)), child: ListTile(leading: Icon(i, color: color ?? AppTheme.orange, size: 22), title: Text(t, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)), trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 18), onTap: onTap));
  }
}
