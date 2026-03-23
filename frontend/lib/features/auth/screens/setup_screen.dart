
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/api_service.dart';
import 'package:dio/dio.dart';

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});
  @override ConsumerState<SetupScreen> createState() => _S();
}
class _S extends ConsumerState<SetupScreen> {
  final _nameCtrl     = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _bioCtrl      = TextEditingController();
  File? _avatar;
  bool _saving = false, _checkingUn = false;
  bool? _unAvailable;
  String? _unError;

  @override void dispose() { _nameCtrl.dispose(); _usernameCtrl.dispose(); _bioCtrl.dispose(); super.dispose(); }

  Future<void> _pickAvatar() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked != null && mounted) setState(() => _avatar = File(picked.path));
  }

  Future<void> _checkUsername(String un) async {
    if (un.length < 3) { setState(() { _unAvailable = null; _unError = null; }); return; }
    if (!RegExp(r'^[a-zA-Z0-9._]+$').hasMatch(un)) { setState(() { _unAvailable = false; _unError = 'Only letters, numbers, . and _'; }); return; }
    setState(() { _checkingUn = true; _unError = null; });
    try {
      final r = await ref.read(apiServiceProvider).get('/auth/check-username', q: {'username': un});
      if (mounted) setState(() { _unAvailable = r.data['available'] == true; _checkingUn = false; });
    } catch (_) { if (mounted) setState(() => _checkingUn = false); }
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name required'))); return; }
    if (_usernameCtrl.text.trim().length < 3) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Username must be at least 3 characters'))); return; }
    if (_unAvailable == false) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Username not available'))); return; }
    setState(() => _saving = true);
    try {
      final fd = FormData.fromMap({
        'display_name': _nameCtrl.text.trim(),
        'username':     _usernameCtrl.text.trim().toLowerCase(),
        'bio':          _bioCtrl.text.trim(),
        if (_avatar != null) 'avatar': await MultipartFile.fromFile(_avatar!.path, filename: 'avatar.jpg'),
      });
      await ref.read(apiServiceProvider).upload('/auth/setup-profile', fd);
      await ref.read(authControllerProvider).refreshUser();
      if (mounted) context.go('/');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 20),
        const Text('Set up your profile', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 26)),
        const SizedBox(height: 4),
        Text('Add your name and a photo to personalize your experience', style: TextStyle(color: dark ? AppTheme.dSub : AppTheme.lSub, fontSize: 14)),
        const SizedBox(height: 32),
        Center(child: GestureDetector(onTap: _pickAvatar, child: Stack(children: [
          _avatar != null ? ClipOval(child: Image.file(_avatar!, width: 100, height: 100, fit: BoxFit.cover)) : Container(width: 100, height: 100, decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [AppTheme.orange, AppTheme.orangeDark])), child: const Icon(Icons.person_rounded, color: Colors.white, size: 48)),
          Positioned(bottom: 0, right: 0, child: Container(width: 30, height: 30, decoration: BoxDecoration(color: AppTheme.orange, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)), child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 15))),
        ]))),
        const SizedBox(height: 28),
        const Text('Display Name *', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 6),
        TextField(controller: _nameCtrl, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(hintText: 'Your full name', prefixIcon: Icon(Icons.person_rounded, size: 20))),
        const SizedBox(height: 16),
        const Text('Username *', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 6),
        TextField(
          controller: _usernameCtrl,
          onChanged: (v) { if (v.length >= 3) _checkUsername(v); else setState(() { _unAvailable = null; _unError = null; }); },
          decoration: InputDecoration(
            hintText: 'yourhandle',
            prefixText: '@',
            prefixStyle: const TextStyle(color: AppTheme.orange, fontWeight: FontWeight.w700),
            suffixIcon: _checkingUn ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.orange))) : (_unAvailable == null ? null : Icon(_unAvailable! ? Icons.check_circle_rounded : Icons.cancel_rounded, color: _unAvailable! ? Colors.green : Colors.red, size: 20)),
            errorText: _unError,
          ),
        ),
        if (_unAvailable == true) const Padding(padding: EdgeInsets.only(top: 4, left: 4), child: Text('Username available ✓', style: TextStyle(color: Colors.green, fontSize: 12))),
        const SizedBox(height: 16),
        const Text('Bio (optional)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 6),
        TextField(controller: _bioCtrl, maxLines: 3, maxLength: 200, decoration: const InputDecoration(hintText: 'Tell the world about yourself...')),
        const SizedBox(height: 32),
        SizedBox(width: double.infinity, child: ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
          child: _saving ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)), SizedBox(width: 10), Text('Setting up...')]) : const Text('Complete Setup', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        )),
        const SizedBox(height: 16),
        Center(child: TextButton(onPressed: () => context.go('/'), child: const Text('Skip for now', style: TextStyle(color: AppTheme.orange)))),
      ]))),
    );
  }
}
