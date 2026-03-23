
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';

class StorageScreen extends ConsumerStatefulWidget {
  const StorageScreen({super.key});
  @override ConsumerState<StorageScreen> createState() => _S();
}
class _S extends ConsumerState<StorageScreen> {
  final _categories = [
    _Cat('Photos', 38.4, AppTheme.orange, Icons.image_rounded),
    _Cat('Videos', 124.2, const Color(0xFF2196F3), Icons.videocam_rounded),
    _Cat('Voice Notes', 8.1, const Color(0xFF4CAF50), Icons.mic_rounded),
    _Cat('Documents', 15.7, const Color(0xFF9C27B0), Icons.description_rounded),
    _Cat('Cache', 22.3, Colors.grey, Icons.cached_rounded),
  ];
  bool _clearing = false;

  double get _total => _categories.fold(0, (s, c) => s + c.sizeMB);

  String _fmt(double mb) { if (mb < 1024) return '${mb.toStringAsFixed(1)} MB'; return '${(mb/1024).toStringAsFixed(2)} GB'; }

  Future<void> _clearCache() async {
    setState(() => _clearing = true);
    await Future.delayed(const Duration(seconds: 1));
    setState(() { _categories.firstWhere((c) => c.label == 'Cache').sizeMB = 0; _clearing = false; });
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cache cleared!')));
  }

  @override
  Widget build(BuildContext ctx) {
    final dark = Theme.of(ctx).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('Storage & Data', style: TextStyle(fontWeight: FontWeight.w800))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        // Total usage circle
        Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(16)), child: Column(children: [
          const Text('Total Used', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 16),
          SizedBox(height: 140, width: 140, child: CustomPaint(painter: _DonutPainter(_categories, _total))),
          const SizedBox(height: 16),
          Text(_fmt(_total), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 28, color: AppTheme.orange)),
          const Text('of available storage used', style: TextStyle(color: Colors.grey, fontSize: 13)),
        ])),
        const SizedBox(height: 16),
        Container(decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(14)), child: Column(children: [
          for (int i = 0; i < _categories.length; i++) ...[
            ListTile(
              leading: Container(width: 40, height: 40, decoration: BoxDecoration(color: _categories[i].color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: Icon(_categories[i].icon, color: _categories[i].color, size: 22)),
              title: Text(_categories[i].label, style: const TextStyle(fontWeight: FontWeight.w500)),
              subtitle: LinearProgressIndicator(value: _total > 0 ? _categories[i].sizeMB / _total : 0, backgroundColor: Colors.grey.shade200, valueColor: AlwaysStoppedAnimation(_categories[i].color), minHeight: 4, borderRadius: BorderRadius.circular(2)),
              trailing: Text(_fmt(_categories[i].sizeMB), style: TextStyle(color: _categories[i].color, fontWeight: FontWeight.w600, fontSize: 13)),
            ),
            if (i < _categories.length - 1) const Divider(height: 0.5, indent: 60),
          ],
        ])),
        const SizedBox(height: 16),
        ElevatedButton.icon(onPressed: _clearing ? null : _clearCache, icon: _clearing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.cleaning_services_rounded), label: Text(_clearing ? 'Clearing...' : 'Clear Cache')),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.settings_backup_restore_rounded), label: const Text('Auto-Download Settings')),
      ]),
    );
  }
}

class _Cat { final String label; double sizeMB; final Color color; final IconData icon; _Cat(this.label, this.sizeMB, this.color, this.icon); }

class _DonutPainter extends CustomPainter {
  final List<_Cat> cats; final double total;
  const _DonutPainter(this.cats, this.total);
  @override void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;
    double startAngle = -1.5707; // -pi/2 (top)
    final paint = Paint()..style = PaintingStyle.stroke..strokeWidth = 22;
    for (final c in cats) {
      if (c.sizeMB == 0) continue;
      final sweep = (c.sizeMB / total) * 6.2832;
      paint.color = c.color;
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle, sweep, false, paint);
      startAngle += sweep;
    }
  }
  @override bool shouldRepaint(_) => true;
}
