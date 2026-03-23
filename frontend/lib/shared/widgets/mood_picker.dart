
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/api_service.dart';
import '../../core/providers/auth_provider.dart';

const _moods = [
  ('happy',    Icons.sentiment_very_satisfied_rounded, '😊 Happy',      Color(0xFFFFC107)),
  ('excited',  Icons.celebration_rounded,              '🎉 Excited',    Color(0xFFFF9800)),
  ('working',  Icons.laptop_mac_rounded,               '💻 Working',    Color(0xFF2196F3)),
  ('studying', Icons.menu_book_rounded,                '📚 Studying',   Color(0xFF9C27B0)),
  ('gym',      Icons.fitness_center_rounded,           '💪 At the gym', Color(0xFF4CAF50)),
  ('travel',   Icons.flight_rounded,                   '✈️ Travelling', Color(0xFF00BCD4)),
  ('music',    Icons.music_note_rounded,               '🎵 Listening',  Color(0xFFE91E63)),
  ('sleeping', Icons.bedtime_rounded,                  '😴 Sleeping',   Color(0xFF607D8B)),
  ('eating',   Icons.restaurant_rounded,               '🍴 Eating',     Color(0xFFFF5722)),
  ('busy',     Icons.do_not_disturb_on_rounded,        '🔴 Do not disturb', Colors.red),
];

class MoodPickerSheet extends ConsumerStatefulWidget {
  const MoodPickerSheet({super.key});
  @override ConsumerState<MoodPickerSheet> createState() => _S();
}
class _S extends ConsumerState<MoodPickerSheet> {
  final _customCtrl = TextEditingController();
  String? _selected;
  bool _saving = false;

  @override void dispose() { _customCtrl.dispose(); super.dispose(); }

  Future<void> _save(String? mood, String? text) async {
    setState(() => _saving = true);
    try {
      await ref.read(apiServiceProvider).put('/users/status', data: {'status_text': text ?? mood ?? '', 'mood_type': mood});
      if (mounted) Navigator.pop(context, text ?? mood);
    } catch (_) {} finally { if (mounted) setState(() => _saving = false); }
  }

  Future<void> _clear() async {
    await ref.read(apiServiceProvider).put('/users/status', data: {'status_text': '', 'mood_type': null});
    if (mounted) Navigator.pop(context, '');
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 16, left: 16, right: 16, top: 16),
      decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Set Your Status', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          TextButton(onPressed: _clear, child: const Text('Clear', style: TextStyle(color: Colors.red))),
        ]),
        const SizedBox(height: 12),
        // Custom text
        TextField(_customCtrl, decoration: const InputDecoration(hintText: 'Set a custom status...', prefixIcon: Icon(Icons.edit_rounded, size: 18)), onChanged: (_) => setState(() {})),
        const SizedBox(height: 14),
        const Align(alignment: Alignment.centerLeft, child: Text('Quick Select', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.grey))),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: _moods.map(((type, icon, label, color)) => GestureDetector(
          onTap: () => setState(() => _selected = type),
          child: AnimatedContainer(duration: const Duration(milliseconds: 150), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: _selected == type ? color.withOpacity(0.15) : (dark ? AppTheme.dInput : AppTheme.lInput), borderRadius: BorderRadius.circular(20), border: Border.all(color: _selected == type ? color : Colors.transparent, width: 1.5)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 16, color: color), const SizedBox(width: 5), Text(label.split(' ').sublist(1).join(' '), style: TextStyle(fontSize: 13, color: _selected == type ? color : null))])),
        )).toList()),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, child: ElevatedButton(
          onPressed: _saving ? null : () => _save(_selected, _customCtrl.text.trim().isEmpty ? null : _customCtrl.text.trim()),
          child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Set Status', style: TextStyle(fontWeight: FontWeight.w700)),
        )),
      ]),
    );
  }
}
