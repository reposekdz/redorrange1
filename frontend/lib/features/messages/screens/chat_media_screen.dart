
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/utils/format_utils.dart';

class ChatMediaScreen extends ConsumerStatefulWidget {
  final String convId, displayName;
  const ChatMediaScreen({super.key, required this.convId, required this.displayName});
  @override ConsumerState<ChatMediaScreen> createState() => _S();
}
class _S extends ConsumerState<ChatMediaScreen> with SingleTickerProviderStateMixin {
  late TabController _tc;
  List<dynamic> _media = [], _docs = [], _links = [], _voice = [];
  bool _l = true;

  @override void initState() { super.initState(); _tc = TabController(length: 4, vsync: this); _load(); }
  @override void dispose() { _tc.dispose(); super.dispose(); }

  Future<void> _load() async {
    try {
      final r = await ref.read(apiServiceProvider).get('/messages/conversations/${widget.convId}/media');
      final all = List<Map<String,dynamic>>.from(r.data['messages'] ?? []);
      setState(() {
        _media = all.where((m) => ['image','video'].contains(m['type'])).toList();
        _docs  = all.where((m) => ['file','audio'].contains(m['type'])).toList();
        _links = all.where((m) => m['type'] == 'link').toList();
        _voice = all.where((m) => m['type'] == 'voice_note').toList();
        _l = false;
      });
    } catch (_) { setState(() => _l = false); }
  }

  @override
  Widget build(BuildContext ctx) => Scaffold(
    appBar: AppBar(title: Text('${widget.displayName} — Media', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      bottom: TabBar(controller: _tc, indicatorColor: AppTheme.orange, labelColor: AppTheme.orange, unselectedLabelColor: Colors.grey, isScrollable: true, tabs: [
        Tab(text: 'Media (${_media.length})'), Tab(text: 'Docs (${_docs.length})'), Tab(text: 'Links (${_links.length})'), Tab(text: 'Audio (${_voice.length})'),
      ])),
    body: _l ? const Center(child: CircularProgressIndicator(color: AppTheme.orange)) : TabBarView(controller: _tc, children: [
      _MediaGrid(_media),
      _DocList(_docs),
      _LinkList(_links),
      _VoiceList(_voice),
    ]),
  );
}

class _MediaGrid extends StatelessWidget {
  final List<dynamic> items;
  const _MediaGrid(this.items);
  @override Widget build(BuildContext ctx) => items.isEmpty
    ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.photo_library_outlined, size: 64, color: Colors.grey), SizedBox(height: 12), Text('No media shared', style: TextStyle(color: Colors.grey))]))
    : GridView.builder(padding: const EdgeInsets.all(2), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 2, mainAxisSpacing: 2), itemCount: items.length, itemBuilder: (_, i) {
        final m = items[i];
        return Stack(children: [
          Positioned.fill(child: m['media_url'] != null ? CachedNetworkImage(imageUrl: m['media_url'], fit: BoxFit.cover, errorWidget: (_, __, ___) => Container(color: AppTheme.orangeSurf)) : Container(color: AppTheme.orangeSurf)),
          if (m['type'] == 'video') const Positioned.fill(child: Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 36))),
        ]);
      });
}

class _DocList extends StatelessWidget {
  final List<dynamic> items;
  const _DocList(this.items);
  @override Widget build(BuildContext ctx) => items.isEmpty
    ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.description_outlined, size: 64, color: Colors.grey), SizedBox(height: 12), Text('No documents', style: TextStyle(color: Colors.grey))]))
    : ListView.separated(itemCount: items.length, separatorBuilder: (_, __) => const Divider(height: 0.5), itemBuilder: (_, i) {
        final d = items[i];
        return ListTile(leading: Container(width: 44, height: 44, decoration: BoxDecoration(color: AppTheme.orangeSurf, borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.insert_drive_file_rounded, color: AppTheme.orange, size: 24)),
          title: Text(d['media_name'] ?? 'File', style: const TextStyle(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(d['media_size'] != null ? FormatUtils.fileSize(d['media_size']) : '', style: const TextStyle(fontSize: 12)),
          trailing: const Icon(Icons.download_rounded, color: AppTheme.orange));
      });
}

class _LinkList extends StatelessWidget { final List items; const _LinkList(this.items); @override Widget build(_) => items.isEmpty ? const Center(child: Text('No links', style: TextStyle(color: Colors.grey))) : const Center(child: Text('Links coming soon')); }
class _VoiceList extends StatelessWidget { final List items; const _VoiceList(this.items); @override Widget build(_) => items.isEmpty ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.mic_none_rounded, size: 64, color: Colors.grey), SizedBox(height: 12), Text('No voice notes', style: TextStyle(color: Colors.grey))])) : ListView.builder(itemCount: items.length, itemBuilder: (_, i) { final v = items[i]; return ListTile(leading: const CircleAvatar(backgroundColor: AppTheme.orangeSurf, child: Icon(Icons.mic_rounded, color: AppTheme.orange)), title: Text(v['media_duration'] != null ? FormatUtils.dur(v['media_duration']) : 'Voice note'), subtitle: Text(FormatUtils.date(v['created_at']))); }); }
