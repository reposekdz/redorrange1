
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/services/api_service.dart';

class AppearanceScreen extends ConsumerStatefulWidget {
  const AppearanceScreen({super.key});
  @override ConsumerState<AppearanceScreen> createState() => _S();
}
class _S extends ConsumerState<AppearanceScreen> {
  double _fontSize = 1.0;
  static const _themes = [(ThemeMode.system, 'System Default', Icons.settings_suggest_rounded), (ThemeMode.light, 'Light', Icons.light_mode_rounded), (ThemeMode.dark, 'Dark', Icons.dark_mode_rounded)];
  static const _accents = [Colors.orange, Color(0xFF2196F3), Color(0xFF4CAF50), Color(0xFF9C27B0), Colors.pink, Colors.red, Colors.teal];

  @override Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('Appearance', style: TextStyle(fontWeight: FontWeight.w800))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Theme', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 10),
        Row(children: _themes.map((e) { final mode = e.$1; final label = e.$2; final icon = e.$3;
          final sel = themeMode == mode;
          return Expanded(child: GestureDetector(onTap: () => ref.read(themeModeProvider.notifier).set(mode), child: AnimatedContainer(duration: const Duration(milliseconds: 200), margin: const EdgeInsets.symmetric(horizontal: 4), padding: const EdgeInsets.symmetric(vertical: 14), decoration: BoxDecoration(color: sel ? AppTheme.orange : (dark ? AppTheme.dCard : Colors.white), borderRadius: BorderRadius.circular(14), border: Border.all(color: sel ? AppTheme.orange : Colors.transparent, width: 2)),
            child: Column(children: [Icon(icon, color: sel ? Colors.white : null, size: 26), const SizedBox(height: 6), Text(label, style: TextStyle(color: sel ? Colors.white : null, fontWeight: sel ? FontWeight.w700 : FontWeight.w500, fontSize: 12), textAlign: TextAlign.center)]))));
        }).toList()),
        const SizedBox(height: 20),
        const Text('Font Size', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 8),
        Row(children: [const Text('A', style: TextStyle(fontSize: 13)), Expanded(child: Slider(value: _fontSize, min: 0.8, max: 1.3, divisions: 5, activeColor: AppTheme.orange, onChanged: (v) => setState(() => _fontSize = v))), const Text('A', style: TextStyle(fontSize: 22))]),
        const SizedBox(height: 4),
        Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: dark ? AppTheme.dCard : AppTheme.lInput, borderRadius: BorderRadius.circular(10)), child: Text('Preview: The quick brown fox jumps over the lazy dog.', style: TextStyle(fontSize: 14 * _fontSize, height: 1.5))),
        const SizedBox(height: 20),
        const Text('Accent Color', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 10),
        Wrap(spacing: 12, children: _accents.map((c) => GestureDetector(onTap: () {}, child: Container(width: 40, height: 40, decoration: BoxDecoration(color: c, shape: BoxShape.circle, boxShadow: [BoxShadow(color: c.withOpacity(0.4), blurRadius: 8, spreadRadius: 2)]), child: c == AppTheme.orange ? const Icon(Icons.check_rounded, color: Colors.white, size: 20) : null))).toList()),
        const SizedBox(height: 20),
        const Text('Display Options', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 8),
        _Toggle('Reduce Motion', 'Minimize animations', false, (v) {}),
        _Toggle('High Contrast', 'Increase contrast for accessibility', false, (v) {}),
        _Toggle('Bold Text', 'Make text bolder throughout', false, (v) {}),
      ]),
    );
  }
}
class _Toggle extends StatefulWidget {
  final String t, s; final bool v; final void Function(bool) onChange;
  const _Toggle(this.t, this.s, this.v, this.onChange);
  @override State<_Toggle> createState() => _TS();
}
class _TS extends State<_Toggle> {
  late bool _v;
  @override void initState() { super.initState(); _v = widget.v; }
  @override Widget build(BuildContext _) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(margin: const EdgeInsets.only(bottom: 6), decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(12)), child: SwitchListTile.adaptive(title: Text(widget.t, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)), subtitle: Text(widget.s, style: const TextStyle(fontSize: 12)), value: _v, onChanged: (v) { setState(() => _v = v); widget.onChange(v); }, activeColor: AppTheme.orange));
  }
}
