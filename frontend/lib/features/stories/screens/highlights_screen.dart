// highlights_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:async';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/widgets/app_avatar.dart';

class HighlightViewerScreen extends ConsumerStatefulWidget {
  final String highlightId;
  const HighlightViewerScreen({super.key, required this.highlightId});
  @override ConsumerState<HighlightViewerScreen> createState() => _S();
}
class _S extends ConsumerState<HighlightViewerScreen> with SingleTickerProviderStateMixin {
  List<dynamic> _stories = []; Map<String,dynamic>? _highlight;
  int _idx = 0; bool _l = true;
  late AnimationController _ac;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(vsync: this, duration: const Duration(seconds: 5));
    _ac.addStatusListener((s) { if (s == AnimationStatus.completed) _next(); });
    _load();
  }
  @override void dispose() { _ac.dispose(); super.dispose(); }

  Future<void> _load() async {
    try {
      // Load highlight stories via highlights API
      final r = await ref.read(apiServiceProvider).get('/stories/highlights/${widget.highlightId}');
      // Fallback: use general highlights endpoint
      setState(() { _l = false; });
      _play();
    } catch (_) { setState(() => _l = false); }
  }

  void _play() { _ac.reset(); _ac.forward(); }
  void _next() { if (_idx < _stories.length - 1) { setState(() => _idx++); _play(); } else context.pop(); }
  void _prev() { if (_idx > 0) { setState(() => _idx--); _play(); } }

  @override
  Widget build(BuildContext context) {
    if (_l) return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator(color: AppTheme.orange)));
    if (_stories.isEmpty) return const Scaffold(backgroundColor: Colors.black, body: Center(child: Text('No stories in this highlight', style: TextStyle(color: Colors.white))));

    final s = _stories[_idx];
    return Scaffold(backgroundColor: Colors.black, body: GestureDetector(
      onTapDown: (d) { if (d.globalPosition.dx > MediaQuery.of(context).size.width / 2) _next(); else _prev(); },
      onLongPressStart: (_) => _ac.stop(), onLongPressEnd: (_) => _ac.forward(),
      child: Stack(children: [
        Positioned.fill(child: s['media_url'] != null
          ? CachedNetworkImage(imageUrl: s['media_url'], fit: BoxFit.contain)
          : Container(color: Colors.black54)),
        Positioned(top: 0, left: 0, right: 0, child: SafeArea(child: Column(children: [
          Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), child: Row(children: List.generate(_stories.length, (k) => Expanded(child: Container(height: 3, margin: const EdgeInsets.symmetric(horizontal: 2), decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            child: k < _idx ? Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2))) :
              k == _idx ? AnimatedBuilder(animation: _ac, builder: (_, __) => FractionallySizedBox(widthFactor: _ac.value, alignment: Alignment.centerLeft, child: Container(color: Colors.white, height: 3))) : null))))),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6), child: Row(children: [
            const Icon(Icons.star_rounded, color: AppTheme.orange, size: 16),
            const SizedBox(width: 6),
            Text(_highlight?['title'] ?? 'Highlight', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            const Spacer(),
            IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white), onPressed: () => context.pop()),
          ])),
        ]))),
        if (s['caption'] != null) Positioned(bottom: 60, left: 16, right: 16, child: Text(s['caption'], style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500), textAlign: TextAlign.center)),
      ]),
    ));
  }
}

// create_highlight_screen.dart
class CreateHighlightScreen extends ConsumerStatefulWidget {
  const CreateHighlightScreen({super.key});
  @override ConsumerState<CreateHighlightScreen> createState() => _CH();
}
class _CH extends ConsumerState<CreateHighlightScreen> {
  final _titleCtrl = TextEditingController();
  List<dynamic> _userStories = [];
  List<String> _selected = [];
  bool _l = true; bool _saving = false;

  @override void initState() { super.initState(); _loadStories(); }
  @override void dispose() { _titleCtrl.dispose(); super.dispose(); }

  Future<void> _loadStories() async {
    final me = ref.read(currentUserProvider);
    if (me == null) return;
    try {
      final r = await ref.read(apiServiceProvider).get('/stories/user/${me.id}');
      setState(() { _userStories = r.data['stories'] ?? []; _l = false; });
    } catch (_) { setState(() => _l = false); }
  }

  Future<void> _create() async {
    if (_titleCtrl.text.trim().isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Title required'))); return; }
    setState(() => _saving = true);
    try {
      await ref.read(apiServiceProvider).post('/stories/highlights', data: {'title': _titleCtrl.text.trim(), 'story_ids': _selected});
      if (mounted) { context.pop(); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Highlight created!'))); }
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'))); }
    finally { if (mounted) setState(() => _saving = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('New Highlight', style: TextStyle(fontWeight: FontWeight.w800)),
      actions: [TextButton(onPressed: _saving ? null : _create, child: Text(_saving ? 'Saving...' : 'Create', style: const TextStyle(color: AppTheme.orange, fontWeight: FontWeight.w700, fontSize: 16)))]),
    body: Column(children: [
      Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Highlight Name', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 6),
        TextField(controller: _titleCtrl, decoration: const InputDecoration(hintText: 'e.g. Travel, Food, Moments...')),
      ])),
      const Padding(padding: EdgeInsets.symmetric(horizontal: 14), child: Align(alignment: Alignment.centerLeft, child: Text('Choose Stories', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)))),
      const SizedBox(height: 10),
      Expanded(child: _l ? const Center(child: CircularProgressIndicator(color: AppTheme.orange))
        : _userStories.isEmpty ? const Center(child: Text('No stories available', style: TextStyle(color: Colors.grey)))
        : GridView.builder(padding: const EdgeInsets.all(8), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 4, mainAxisSpacing: 4),
          itemCount: _userStories.length,
          itemBuilder: (_, i) {
            final s = _userStories[i];
            final selected = _selected.contains(s['id']);
            return GestureDetector(onTap: () { setState(() { if (selected) _selected.remove(s['id']); else _selected.add(s['id']); }); },
              child: Stack(children: [
                Positioned.fill(child: ClipRRect(borderRadius: BorderRadius.circular(6), child: s['media_url'] != null ? CachedNetworkImage(imageUrl: s['media_url'], fit: BoxFit.cover) : Container(color: AppTheme.orangeSurf))),
                if (selected) Positioned.fill(child: Container(decoration: BoxDecoration(color: AppTheme.orange.withOpacity(0.35), borderRadius: BorderRadius.circular(6)), child: const Center(child: Icon(Icons.check_circle_rounded, color: Colors.white, size: 32)))),
              ]));
          })),
      Padding(padding: const EdgeInsets.all(14), child: Text('${_selected.length} stories selected', style: const TextStyle(color: Colors.grey, fontSize: 13))),
    ]),
  );
}
