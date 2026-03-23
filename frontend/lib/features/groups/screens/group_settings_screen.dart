
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/widgets/app_avatar.dart';
import 'package:dio/dio.dart';

class GroupSettingsScreen extends ConsumerStatefulWidget {
  final String groupId;
  const GroupSettingsScreen({super.key, required this.groupId});
  @override ConsumerState<GroupSettingsScreen> createState() => _S();
}
class _S extends ConsumerState<GroupSettingsScreen> {
  Map<String,dynamic>? _group; List<dynamic> _members = []; bool _l = true;
  late TextEditingController _nameCtrl, _descCtrl;
  File? _avatar; bool _saving = false;

  @override void initState() { super.initState(); _nameCtrl = TextEditingController(); _descCtrl = TextEditingController(); _load(); }
  @override void dispose() { _nameCtrl.dispose(); _descCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    final r = await ref.read(apiServiceProvider).get('/groups/${widget.groupId}');
    final g = Map<String,dynamic>.from(r.data['group'] ?? {});
    _nameCtrl.text = g['name'] ?? '';
    _descCtrl.text = g['description'] ?? '';
    setState(() { _group = g; _members = List<dynamic>.from(r.data['members'] ?? []); _l = false; });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      if (_avatar != null) {
        final fd = FormData.fromMap({'name': _nameCtrl.text.trim(), 'description': _descCtrl.text.trim(), 'avatar': await MultipartFile.fromFile(_avatar!.path)});
        await ref.read(apiServiceProvider).upload('/groups/${widget.groupId}', fd);
      } else {
        await ref.read(apiServiceProvider).put('/groups/${widget.groupId}', data: {'name': _nameCtrl.text.trim(), 'description': _descCtrl.text.trim()});
      }
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Group updated!'))); _load(); }
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'))); }
    finally { if (mounted) setState(() => _saving = false); }
  }

  Future<void> _removeMember(String uid) async {
    await ref.read(apiServiceProvider).delete('/groups/${widget.groupId}/remove/$uid');
    _load();
  }

  Future<void> _promote(String uid) async {
    await ref.read(apiServiceProvider).put('/groups/${widget.groupId}/promote/$uid', data: {'role': 'admin'});
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_l) return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppTheme.orange)));
    final me = ref.watch(currentUserProvider);
    final myMember = _members.firstWhere((m) => m['id'] == me?.id, orElse: () => {});
    final isAdmin = myMember['role'] == 'owner' || myMember['role'] == 'admin';
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('Group Settings', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [if (isAdmin) TextButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving...' : 'Save', style: const TextStyle(color: AppTheme.orange, fontWeight: FontWeight.w700, fontSize: 15)))]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (isAdmin) ...[
          Center(child: GestureDetector(onTap: () async { final img = await ImagePicker().pickImage(source: ImageSource.gallery); if (img != null) setState(() => _avatar = File(img.path)); },
            child: Stack(children: [
              _avatar != null ? ClipOval(child: Image.file(_avatar!, width: 80, height: 80, fit: BoxFit.cover)) : AppAvatar(url: _group!['avatar_url'], size: 80, username: _group!['name']),
              Positioned(bottom: 0, right: 0, child: Container(width: 28, height: 28, decoration: const BoxDecoration(color: AppTheme.orange, shape: BoxShape.circle), child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 16))),
            ]))),
          const SizedBox(height: 16),
          TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Group Name', prefixIcon: Icon(Icons.group_rounded))),
          const SizedBox(height: 12),
          TextField(controller: _descCtrl, maxLines: 3, decoration: const InputDecoration(labelText: 'Description', prefixIcon: Icon(Icons.info_outline_rounded))),
          const SizedBox(height: 20),
        ],
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Members (${_members.length})', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          if (isAdmin) TextButton.icon(onPressed: () {}, icon: const Icon(Icons.person_add_rounded, size: 16), label: const Text('Add')),
        ]),
        const SizedBox(height: 8),
        ..._members.map((m) => ListTile(contentPadding: EdgeInsets.zero,
          leading: AppAvatar(url: m['avatar_url'], size: 44, username: m['username'], showOnline: true, isOnline: m['is_online'] == 1),
          title: Row(children: [Text(m['display_name'] ?? m['username'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)), if (m['role'] != 'member') Padding(padding: const EdgeInsets.only(left: 8), child: Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2), decoration: BoxDecoration(color: AppTheme.orangeSurf, borderRadius: BorderRadius.circular(8)), child: Text(m['role'].toString().toUpperCase(), style: const TextStyle(color: AppTheme.orange, fontSize: 9, fontWeight: FontWeight.w800))))]),
          subtitle: Text('@${m['username'] ?? ''}'),
          trailing: (isAdmin && m['id'] != me?.id) ? PopupMenuButton<String>(onSelected: (v) { if (v == 'remove') _removeMember(m['id']); else if (v == 'promote') _promote(m['id']); },
            itemBuilder: (_) => [const PopupMenuItem(value: 'promote', child: Text('Make Admin')), const PopupMenuItem(value: 'remove', child: Text('Remove', style: TextStyle(color: Colors.red)))]) : null,
          onTap: () => context.push('/profile/${m['id']}'),
        )),
        const SizedBox(height: 20),
        OutlinedButton.icon(onPressed: () async { await ref.read(apiServiceProvider).post('/groups/${widget.groupId}/leave'); if (mounted) context.go('/messages'); },
          style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
          icon: const Icon(Icons.exit_to_app_rounded), label: const Text('Leave Group')),
      ]),
    );
  }
}
