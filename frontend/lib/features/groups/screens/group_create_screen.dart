// group_create_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/widgets/app_avatar.dart';
import 'package:dio/dio.dart';

class GroupCreateScreen extends ConsumerStatefulWidget {
  const GroupCreateScreen({super.key});
  @override ConsumerState<GroupCreateScreen> createState() => _S();
}
class _S extends ConsumerState<GroupCreateScreen> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  List<dynamic> _selected = [];
  List<dynamic> _searchResults = [];
  File? _avatar;
  bool _saving = false; bool _searching = false;

  @override void dispose() { _nameCtrl.dispose(); _descCtrl.dispose(); _searchCtrl.dispose(); super.dispose(); }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) { setState(() => _searchResults = []); return; }
    setState(() => _searching = true);
    final r = await ref.read(apiServiceProvider).get('/search', q: {'q': q, 'type': 'users'});
    setState(() { _searchResults = r.data['users'] ?? []; _searching = false; });
  }

  Future<void> _create() async {
    if (_nameCtrl.text.trim().isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Group name required'))); return; }
    if (_selected.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add at least one member'))); return; }
    setState(() => _saving = true);
    try {
      final fd = FormData.fromMap({
        'type': 'group', 'name': _nameCtrl.text.trim(), 'description': _descCtrl.text.trim(),
        'user_ids': _selected.map((u) => u['id']).toList(),
        if (_avatar != null) 'avatar': await MultipartFile.fromFile(_avatar!.path, filename: 'avatar.jpg'),
      });
      final r = await ref.read(apiServiceProvider).upload('/messages/conversations', fd);
      if (r.data['success'] == true && mounted) {
        final convId = r.data['conversation']['id'];
        context.go('/chat/$convId');
      }
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'))); }
    finally { if (mounted) setState(() => _saving = false); }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Group', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [TextButton(onPressed: _saving ? null : _create, child: Text(_saving ? 'Creating...' : 'Create', style: const TextStyle(color: AppTheme.orange, fontWeight: FontWeight.w700, fontSize: 16)))],
      ),
      body: Column(children: [
        // Group info
        Container(padding: const EdgeInsets.all(16), color: dark ? AppTheme.dSurf : Colors.white, child: Row(children: [
          GestureDetector(onTap: () async { final img = await ImagePicker().pickImage(source: ImageSource.gallery); if (img != null) setState(() => _avatar = File(img.path)); },
            child: Stack(children: [
              _avatar != null ? ClipOval(child: Image.file(_avatar!, width: 60, height: 60, fit: BoxFit.cover)) : Container(width: 60, height: 60, decoration: BoxDecoration(color: AppTheme.orangeSurf, shape: BoxShape.circle), child: const Icon(Icons.group_rounded, color: AppTheme.orange, size: 32)),
              Positioned(bottom: 0, right: 0, child: Container(width: 22, height: 22, decoration: const BoxDecoration(color: AppTheme.orange, shape: BoxShape.circle), child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 13))),
            ])),
          const SizedBox(width: 14),
          Expanded(child: Column(children: [
            TextField(controller: _nameCtrl, decoration: const InputDecoration(hintText: 'Group name', border: InputBorder.none, filled: false)),
            const Divider(height: 1),
            TextField(controller: _descCtrl, decoration: const InputDecoration(hintText: 'Description (optional)', border: InputBorder.none, filled: false)),
          ])),
        ])),

        const SizedBox(height: 8),

        // Selected members
        if (_selected.isNotEmpty) Container(height: 80, color: dark ? AppTheme.dSurf : Colors.white, child: ListView.builder(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), itemCount: _selected.length, itemBuilder: (_, i) {
          final u = _selected[i];
          return Stack(children: [
            Padding(padding: const EdgeInsets.only(right: 16), child: Column(children: [
              AppAvatar(url: u['avatar_url'], size: 44, username: u['username']),
              const SizedBox(height: 3),
              Text(u['display_name'] ?? u['username'] ?? '', style: const TextStyle(fontSize: 10), overflow: TextOverflow.ellipsis),
            ])),
            Positioned(top: 0, right: 12, child: GestureDetector(onTap: () => setState(() => _selected.remove(u)),
              child: Container(width: 18, height: 18, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle), child: const Icon(Icons.close_rounded, color: Colors.white, size: 12)))),
          ]);
        })),

        // Search
        Padding(padding: const EdgeInsets.all(12), child: TextField(controller: _searchCtrl, onChanged: _search, decoration: InputDecoration(hintText: 'Search people to add...', prefixIcon: const Icon(Icons.search_rounded), suffixIcon: _searching ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.orange))) : null))),

        // Results
        Expanded(child: ListView.builder(itemCount: _searchResults.length, itemBuilder: (_, i) {
          final u = _searchResults[i];
          final isSelected = _selected.any((s) => s['id'] == u['id']);
          return ListTile(
            leading: AppAvatar(url: u['avatar_url'], size: 44, username: u['username']),
            title: Text(u['display_name'] ?? u['username'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('@${u['username'] ?? ''}'),
            trailing: isSelected
              ? Container(width: 28, height: 28, decoration: const BoxDecoration(color: AppTheme.orange, shape: BoxShape.circle), child: const Icon(Icons.check_rounded, color: Colors.white, size: 18))
              : Container(width: 28, height: 28, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.grey.shade400, width: 1.5))),
            onTap: () { setState(() { if (isSelected) _selected.removeWhere((s) => s['id'] == u['id']); else _selected.add(u); }); },
          );
        })),
      ]),
    );
  }
}
