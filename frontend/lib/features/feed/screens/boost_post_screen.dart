
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/api_service.dart';

class BoostPostScreen extends ConsumerStatefulWidget {
  final String postId, postCaption;
  const BoostPostScreen({super.key, required this.postId, required this.postCaption});
  @override ConsumerState<BoostPostScreen> createState() => _S();
}
class _S extends ConsumerState<BoostPostScreen> {
  double _budget = 5.0;
  int _days = 7;
  String _goal = 'reach';
  bool _saving = false;

  static const _budgets = [5.0, 10.0, 25.0, 50.0, 100.0];
  static const _dayOptions = [3, 7, 14, 30];
  static const _goals = [('reach', Icons.people_rounded, 'More Reach', 'Show your post to more people'), ('clicks', Icons.touch_app_rounded, 'Link Clicks', 'Drive traffic to your profile'), ('followers', Icons.person_add_rounded, 'Get Followers', 'Gain more followers')];

  Future<void> _boost() async {
    setState(() => _saving = true);
    try {
      await ref.read(apiServiceProvider).post('/posts/${widget.postId}/boost', data: {'budget': _budget, 'duration_days': _days, 'goal': _goal});
      if (mounted) { context.pop(); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Post is now boosted!'))); }
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'))); }
    finally { if (mounted) setState(() => _saving = false); }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final estimated = ((_budget / 1.5) * _days).round();
    return Scaffold(
      appBar: AppBar(title: const Text('Boost Post', style: TextStyle(fontWeight: FontWeight.w800))),
      body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Post preview
        Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(12)), child: Row(children: [
          Container(width: 56, height: 56, decoration: BoxDecoration(color: AppTheme.orangeSurf, borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.image_rounded, color: AppTheme.orange, size: 28)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Your Post', style: TextStyle(fontWeight: FontWeight.w700)),
            Text(widget.postCaption.isEmpty ? 'No caption' : widget.postCaption, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Colors.grey)),
          ])),
        ])),
        const SizedBox(height: 20),

        // Goal
        const Text('Campaign Goal', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 10),
        ..._goals.map(((type, icon, title, sub)) => GestureDetector(
          onTap: () => setState(() => _goal = type),
          child: AnimatedContainer(duration: const Duration(milliseconds: 150), margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: _goal == type ? AppTheme.orangeSurf : (dark ? AppTheme.dCard : Colors.white), borderRadius: BorderRadius.circular(12), border: Border.all(color: _goal == type ? AppTheme.orange : Colors.transparent, width: 1.5)),
            child: Row(children: [Container(width: 40, height: 40, decoration: BoxDecoration(color: (_goal == type ? AppTheme.orange : Colors.grey).withOpacity(0.15), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: _goal == type ? AppTheme.orange : Colors.grey, size: 22)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: _goal == type ? AppTheme.orange : null)), Text(sub, style: const TextStyle(fontSize: 12, color: Colors.grey))])), if (_goal == type) const Icon(Icons.check_circle_rounded, color: AppTheme.orange)]),
          ))),

        const SizedBox(height: 20),
        const Text('Daily Budget (USD)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 10),
        Row(children: _budgets.map((b) => Expanded(child: GestureDetector(onTap: () => setState(() => _budget = b), child: AnimatedContainer(duration: const Duration(milliseconds: 150), margin: const EdgeInsets.symmetric(horizontal: 3), padding: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: _budget == b ? AppTheme.orange : (dark ? AppTheme.dCard : Colors.white), borderRadius: BorderRadius.circular(10), border: Border.all(color: _budget == b ? AppTheme.orange : Colors.transparent)), child: Center(child: Text('$$b', style: TextStyle(fontWeight: FontWeight.w700, color: _budget == b ? Colors.white : null, fontSize: 14))))))).toList()),

        const SizedBox(height: 20),
        const Text('Duration', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 10),
        Row(children: _dayOptions.map((d) => Expanded(child: GestureDetector(onTap: () => setState(() => _days = d), child: AnimatedContainer(duration: const Duration(milliseconds: 150), margin: const EdgeInsets.symmetric(horizontal: 3), padding: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: _days == d ? AppTheme.orange : (dark ? AppTheme.dCard : Colors.white), borderRadius: BorderRadius.circular(10), border: Border.all(color: _days == d ? AppTheme.orange : Colors.transparent)), char: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text('$d', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: _days == d ? Colors.white : null)), Text('days', style: TextStyle(fontSize: 10, color: _days == d ? Colors.white70 : Colors.grey))]))))).toList()),

        const SizedBox(height: 20),
        Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: AppTheme.orangeSurf, borderRadius: BorderRadius.circular(12)), child: Row(children: [
          const Icon(Icons.bar_chart_rounded, color: AppTheme.orange, size: 22),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Estimated Reach', style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.orange)),
            Text('~${(estimated * 150).toStringAsFixed(0)}–${(estimated * 300).toStringAsFixed(0)} people over $_days days', style: const TextStyle(fontSize: 13, color: AppTheme.orangeDark)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('$${(_budget * _days).toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppTheme.orange)),
            const Text('total', style: TextStyle(fontSize: 11, color: AppTheme.orange)),
          ]),
        ])),
        const SizedBox(height: 20),
        SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _saving ? null : _boost, style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
          child: _saving ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)), SizedBox(width: 8), Text('Boosting...')])
            : const Text('Boost Now', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)))),
        const SizedBox(height: 8),
        const Center(child: Text('You will not be charged until the boost is approved.', style: TextStyle(fontSize: 12, color: Colors.grey), textAlign: TextAlign.center)),
        const SizedBox(height: 30),
      ])),
    );
  }
}
