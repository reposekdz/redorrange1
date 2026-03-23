
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/api_service.dart';

class DisappearingMessagesScreen extends ConsumerStatefulWidget {
  final String convId;
  const DisappearingMessagesScreen({super.key, required this.convId});
  @override ConsumerState<DisappearingMessagesScreen> createState() => _S();
}
class _S extends ConsumerState<DisappearingMessagesScreen> {
  int _timer = 0; bool _saving = false;
  static const _opts = [(0, 'Off'), (3600, '1 hour'), (86400, '24 hours'), (604800, '7 days'), (2592000, '30 days')];

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('Disappearing Messages', style: TextStyle(fontWeight: FontWeight.w800))),
      body: Column(children: [
        Container(margin: const EdgeInsets.all(14), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: dark ? AppTheme.dCard : AppTheme.orangeSurf, borderRadius: BorderRadius.circular(12)), child: const Row(children: [Icon(Icons.timer_rounded, color: AppTheme.orange, size: 22), SizedBox(width: 10), Expanded(child: Text('Messages will automatically disappear after the timer. Both sides are affected.', style: TextStyle(color: AppTheme.orangeDark, fontSize: 13, height: 1.4)))])),
        Expanded(child: ListView(children: _opts.map(((secs, label)) => RadioListTile<int>(
          value: secs, groupValue: _timer,
          onChanged: (v) => setState(() => _timer = v!),
          title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          subtitle: secs > 0 ? Text('Messages delete after $label', style: const TextStyle(fontSize: 12)) : const Text('Messages stay forever', style: TextStyle(fontSize: 12)),
          activeColor: AppTheme.orange,
          secondary: Container(width: 42, height: 42, decoration: BoxDecoration(color: AppTheme.orangeSurf, borderRadius: BorderRadius.circular(12)), child: Icon(secs == 0 ? Icons.timer_off_rounded : Icons.timer_rounded, color: AppTheme.orange, size: 22)),
        )).toList())),
        Padding(padding: const EdgeInsets.all(14), child: SizedBox(width: double.infinity, child: ElevatedButton(
          onPressed: _saving ? null : () async {
            setState(() => _saving = true);
            await ref.read(apiServiceProvider).put('/messages/conversations/${widget.convId}/disappearing', data: {'timer': _timer}).catchError((_){});
            if (mounted) { context.pop(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_timer == 0 ? 'Disappearing messages turned off' : 'Disappearing messages set to ${_opts.firstWhere((o) => o.$1 == _timer).$2}'))); }
          },
          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          child: _saving ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2) : const Text('Save', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        ))),
      ]),
    );
  }
}
