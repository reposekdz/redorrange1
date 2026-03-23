// starred_messages_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/widgets/app_avatar.dart';
import '../../../shared/utils/format_utils.dart';

class StarredMessagesScreen extends ConsumerStatefulWidget {
  const StarredMessagesScreen({super.key});
  @override ConsumerState<StarredMessagesScreen> createState() => _S();
}
class _S extends ConsumerState<StarredMessagesScreen> {
  List<dynamic> _msgs = []; bool _l = true;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final r = await ref.read(apiServiceProvider).get('/starred');
    setState(() { _msgs = r.data['messages'] ?? []; _l = false; });
  }
  Future<void> _unstar(String msgId) async {
    await ref.read(apiServiceProvider).post('/starred/$msgId');
    _load();
  }
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('Starred Messages', style: TextStyle(fontWeight: FontWeight.w800))),
      body: _l ? const Center(child: CircularProgressIndicator(color: AppTheme.orange))
        : _msgs.isEmpty ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.star_outline_rounded, size: 72, color: Colors.grey), SizedBox(height: 16), Text('No starred messages', style: TextStyle(color: Colors.grey, fontSize: 15)), SizedBox(height: 8), Text('Star messages to save them here.', style: TextStyle(color: Colors.grey, fontSize: 13))]))
        : ListView.builder(padding: const EdgeInsets.all(8), itemCount: _msgs.length, itemBuilder: (_, i) {
            final m = _msgs[i];
            return Card(margin: const EdgeInsets.only(bottom: 8), child: InkWell(
              onTap: () => context.push('/chat/${m['conversation_id']}'),
              borderRadius: BorderRadius.circular(12),
              child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Chat info
                Row(children: [
                  AppAvatar(url: m['avatar_url'], size: 32, username: m['username']),
                  const SizedBox(width: 8),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(m['display_name'] ?? m['username'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    Text('in ${m['conv_type'] == 'group' ? m['conv_name'] ?? 'Group' : 'direct message'}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ])),
                  Text(FormatUtils.date(m['starred_at']), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  const SizedBox(width: 4),
                  GestureDetector(onTap: () => _unstar(m['id']), child: const Icon(Icons.star_rounded, color: AppTheme.orange, size: 20)),
                ]),
                const SizedBox(height: 8),
                // Message content
                Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: dark ? AppTheme.dCard : AppTheme.orangeSurf, borderRadius: BorderRadius.circular(10)), child: _buildContent(m, dark)),
              ])),
            ));
          }),
    );
  }
  Widget _buildContent(dynamic m, bool dark) {
    switch (m['type']) {
      case 'image': return Row(children: [const Icon(Icons.photo_rounded, size: 16, color: Colors.grey), const SizedBox(width: 6), const Text('Photo', style: TextStyle(color: Colors.grey))]);
      case 'voice_note': return Row(children: [const Icon(Icons.mic_rounded, size: 16, color: AppTheme.orange), const SizedBox(width: 6), const Text('Voice note', style: TextStyle(color: AppTheme.orange))]);
      case 'file': return Row(children: [const Icon(Icons.attach_file_rounded, size: 16, color: Colors.grey), const SizedBox(width: 6), Text(m['media_name'] ?? 'File', style: const TextStyle(color: Colors.grey))]);
      default: return Text(m['content'] ?? '', style: const TextStyle(fontSize: 14), maxLines: 3, overflow: TextOverflow.ellipsis);
    }
  }
}
