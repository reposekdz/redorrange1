
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/api_service.dart';
import '../../../core/providers/auth_provider.dart';

class PollWidget extends ConsumerStatefulWidget {
  final String pollId;
  final bool compact;
  const PollWidget({super.key, required this.pollId, this.compact = false});
  @override ConsumerState<PollWidget> createState() => _S();
}
class _S extends ConsumerState<PollWidget> {
  Map<String,dynamic>? _poll; bool _l = true; List<int> _selectedOptions = []; bool _voting = false;

  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try {
      final r = await ref.read(apiServiceProvider).get('/polls/${widget.pollId}');
      setState(() { _poll = r.data['poll']; _l = false; });
    } catch (_) { setState(() => _l = false); }
  }

  Future<void> _vote() async {
    if (_selectedOptions.isEmpty) return;
    setState(() => _voting = true);
    try {
      await ref.read(apiServiceProvider).post('/polls/${widget.pollId}/vote', data: {'option_ids': _selectedOptions});
      _load();
    } catch (_) {} finally { if (mounted) setState(() => _voting = false); }
  }

  @override
  Widget build(BuildContext context) {
    if (_l) return const Padding(padding: EdgeInsets.all(8), child: Center(child: CircularProgressIndicator(color: AppTheme.orange)));
    if (_poll == null) return const SizedBox.shrink();
    final poll = _poll!;
    final options = List<Map<String,dynamic>>.from(poll['options'] ?? []);
    final total = poll['total_votes'] as int? ?? 0;
    final hasVoted = poll['user_voted'] == true;
    final expired = poll['expires_at'] != null && DateTime.tryParse(poll['expires_at'])?.isBefore(DateTime.now()) == true;
    final multiple = poll['multiple'] == 1 || poll['multiple'] == true;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(margin: const EdgeInsets.symmetric(vertical: 8), padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: dark ? AppTheme.dCard : AppTheme.orangeSurf, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.orange.withOpacity(0.2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.poll_rounded, color: AppTheme.orange, size: 16),
          const SizedBox(width: 6),
          const Text('Poll', style: TextStyle(color: AppTheme.orange, fontWeight: FontWeight.w700, fontSize: 12)),
          const Spacer(),
          if (expired) const Text('Ended', style: TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.w600))
          else if (poll['expires_at'] != null) Text('Ends ${_fmt(poll['expires_at'])}', style: const TextStyle(color: Colors.grey, fontSize: 11)),
        ]),
        const SizedBox(height: 8),
        Text(poll['question'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        if (multiple) const Text('Select all that apply', style: TextStyle(color: Colors.grey, fontSize: 11)),
        const SizedBox(height: 10),
        ...options.map((opt) {
          final votes = opt['votes'] as int? ?? 0;
          final pct = total > 0 ? votes / total : 0.0;
          final isSelected = _selectedOptions.contains(opt['id']);
          final isWinner = hasVoted && votes == options.map((o) => o['votes'] as int? ?? 0).reduce((a,b) => a > b ? a : b);
          return GestureDetector(
            onTap: hasVoted || expired ? null : () {
              setState(() {
                if (multiple) { if (isSelected) _selectedOptions.remove(opt['id']); else _selectedOptions.add(opt['id']); }
                else _selectedOptions = [opt['id']];
              });
            },
            child: Container(margin: const EdgeInsets.only(bottom: 8), decoration: BoxDecoration(
              color: hasVoted ? Colors.transparent : (isSelected ? AppTheme.orange.withOpacity(0.15) : (dark ? AppTheme.dSurf : Colors.white)),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: isSelected && !hasVoted ? AppTheme.orange : Colors.transparent, width: 1.5),
            ),
            child: Stack(children: [
              if (hasVoted) Positioned.fill(child: ClipRRect(borderRadius: BorderRadius.circular(10), child: FractionallySizedBox(widthFactor: pct, alignment: Alignment.centerLeft, child: Container(color: isWinner ? AppTheme.orange.withOpacity(0.2) : Colors.grey.withOpacity(0.1))))),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11), child: Row(children: [
                Expanded(child: Text(opt['text'] ?? '', style: TextStyle(fontWeight: (hasVoted && isWinner) ? FontWeight.w700 : FontWeight.w500, fontSize: 14))),
                if (hasVoted) ...[Text('${(pct * 100).toStringAsFixed(0)}%', style: TextStyle(color: isWinner ? AppTheme.orange : Colors.grey, fontWeight: FontWeight.w600, fontSize: 13)), const SizedBox(width: 6), Text('($votes)', style: const TextStyle(color: Colors.grey, fontSize: 11))],
                if (!hasVoted && isSelected) const Icon(Icons.check_circle_rounded, color: AppTheme.orange, size: 18),
              ])),
            ])),
          );
        }),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('$total ${total == 1 ? "vote" : "votes"}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
          if (!hasVoted && !expired && _selectedOptions.isNotEmpty)
            ElevatedButton(onPressed: _voting ? null : _vote, style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), textStyle: const TextStyle(fontSize: 12)), child: _voting ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Vote')),
        ]),
      ]),
    );
  }
  String _fmt(String ts) { try { final d = DateTime.parse(ts).toLocal(); final diff = d.difference(DateTime.now()); if (diff.inHours < 24) return '${diff.inHours}h'; return '${diff.inDays}d'; } catch (_) { return ''; } }
}
