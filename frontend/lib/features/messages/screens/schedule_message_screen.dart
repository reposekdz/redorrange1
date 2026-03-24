
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/api_service.dart';

class ScheduleMessageScreen extends ConsumerStatefulWidget {
  final String convId;
  const ScheduleMessageScreen({super.key, required this.convId});
  @override ConsumerState<ScheduleMessageScreen> createState() => _S();
}
class _S extends ConsumerState<ScheduleMessageScreen> {
  final _ctrl = TextEditingController();
  DateTime? _dt; bool _saving = false;
  List<dynamic> _scheduled = []; bool _l = true;

  @override void initState() { super.initState(); _load(); }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    try { final r = await ref.read(apiServiceProvider).get('/messages/conversations/${widget.convId}/scheduled'); setState(() { _scheduled = r.data['scheduled'] ?? []; _l = false; }); } catch (_) { setState(() => _l = false); }
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(context: context, initialDate: DateTime.now().add(const Duration(minutes: 10)), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(DateTime.now().add(const Duration(minutes: 10))));
    if (time == null) return;
    setState(() => _dt = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _schedule() async {
    if (_ctrl.text.trim().isEmpty || _dt == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(apiServiceProvider).post('/messages/conversations/${widget.convId}/schedule', data: {'content': _ctrl.text.trim(), 'scheduled_at': _dt!.toUtc().toIso8601String()});
      _ctrl.clear(); setState(() { _dt = null; }); _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Message scheduled ✅')));
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'))); }
    if (mounted) setState(() => _saving = false);
  }

  @override Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fmt = DateFormat('MMM d, y  h:mm a');
    return Scaffold(
      appBar: AppBar(title: const Text('Scheduled Messages', style: TextStyle(fontWeight: FontWeight.w800))),
      body: Column(children: [
        Container(color: dark ? AppTheme.dCard : Colors.white, padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Schedule a message', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 10),
          TextField(controller: _ctrl, maxLines: 3, decoration: const InputDecoration(hintText: 'Type your message...', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          GestureDetector(onTap: _pickDateTime, child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), decoration: BoxDecoration(border: Border.all(color: AppTheme.orange), borderRadius: BorderRadius.circular(10)), child: Row(children: [const Icon(Icons.schedule_rounded, color: AppTheme.orange, size: 20), const SizedBox(width: 8), Text(_dt == null ? 'Select date & time' : fmt.format(_dt!), style: TextStyle(color: _dt == null ? Colors.grey : AppTheme.orange, fontWeight: FontWeight.w600))]))),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: ElevatedButton(onPressed: (_ctrl.text.isEmpty || _dt == null || _saving) ? null : _schedule, style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)), child: _saving ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2) : const Text('Schedule', style: TextStyle(fontWeight: FontWeight.w700)))),
        ])),
        const Divider(height: 0),
        Padding(padding: const EdgeInsets.fromLTRB(14, 12, 14, 4), child: Row(children: [const Text('Scheduled', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)), if (_scheduled.isNotEmpty) Container(margin: const EdgeInsets.only(left: 8), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: AppTheme.orange, borderRadius: BorderRadius.circular(10)), child: Text('${_scheduled.length}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)))])),
        Expanded(child: _l ? const Center(child: CircularProgressIndicator(color: AppTheme.orange)) : _scheduled.isEmpty ? const Center(child: Text('No scheduled messages', style: TextStyle(color: Colors.grey))) : ListView.builder(itemCount: _scheduled.length, itemBuilder: (_, i) {
          final s = _scheduled[i];
          final dt = DateTime.tryParse(s['scheduled_at'] ?? '');
          return ListTile(leading: const Icon(Icons.schedule_rounded, color: AppTheme.orange), title: Text(s['content'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)), subtitle: dt != null ? Text(fmt.format(dt.toLocal()), style: const TextStyle(color: AppTheme.orange, fontSize: 11, fontWeight: FontWeight.w600)) : null, trailing: IconButton(icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20), onPressed: () async { await ref.read(apiServiceProvider).delete('/messages/conversations/${widget.convId}/scheduled/${s['id']}').catchError((_){}); _load(); }));
        })),
      ]),
    );
  }
}
