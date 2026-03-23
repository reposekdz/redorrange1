import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'dart:io';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/widgets/mood_picker.dart';
import 'package:dio/dio.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});
  @override ConsumerState<EditProfileScreen> createState() => _S();
}
class _S extends ConsumerState<EditProfileScreen> {
  final _nameCtrl     = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _bioCtrl      = TextEditingController();
  final _websiteCtrl  = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _statusCtrl   = TextEditingController();

  File? _avatar, _cover;
  String? _gender;
  bool _saving = false;
  bool _checkingUsername = false;
  bool? _usernameAvailable;
  String? _originalUsername;

  @override
  void initState() {
    super.initState();
    final u = ref.read(currentUserProvider);
    if (u != null) {
      _nameCtrl.text     = u.displayName ?? '';
      _usernameCtrl.text = u.username ?? '';
      _bioCtrl.text      = u.bio ?? '';
      _websiteCtrl.text  = u.website ?? '';
      _locationCtrl.text = u.location ?? '';
      _statusCtrl.text   = u.statusText ?? '';
      _gender            = u.gender;
      _originalUsername  = u.username;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _usernameCtrl.dispose(); _bioCtrl.dispose();
    _websiteCtrl.dispose(); _locationCtrl.dispose(); _statusCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage(bool isCover) async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (picked == null) return;
    final cropped = await ImageCropper().cropImage(
      sourcePath: picked.path,
      aspectRatio: isCover ? const CropAspectRatio(ratioX: 3, ratioY: 1) : const CropAspectRatio(ratioX: 1, ratioY: 1),
      compressQuality: 90,
    );
    if (cropped != null) setState(() { if (isCover) _cover = File(cropped.path); else _avatar = File(cropped.path); });
  }

  Future<void> _checkUsername(String un) async {
    if (un == _originalUsername || un.isEmpty || un.length < 3) { setState(() => _usernameAvailable = null); return; }
    setState(() => _checkingUsername = true);
    try {
      final r = await ref.read(apiServiceProvider).get('/auth/check-username', q: {'username': un});
      if (mounted) setState(() { _usernameAvailable = r.data['available'] == true; _checkingUsername = false; });
    } catch (_) { if (mounted) setState(() => _checkingUsername = false); }
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name cannot be empty'))); return; }
    if (_usernameAvailable == false) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Username is not available'))); return; }
    setState(() => _saving = true);
    try {
      final fd = FormData.fromMap({
        'display_name': _nameCtrl.text.trim(),
        'username':     _usernameCtrl.text.trim(),
        'bio':          _bioCtrl.text.trim(),
        'website':      _websiteCtrl.text.trim(),
        'location':     _locationCtrl.text.trim(),
        'status_text':  _statusCtrl.text.trim(),
        if (_gender != null) 'gender': _gender,
        if (_avatar != null) 'avatar': await MultipartFile.fromFile(_avatar!.path, filename: 'avatar.jpg'),
        if (_cover  != null) 'cover':  await MultipartFile.fromFile(_cover!.path,  filename: 'cover.jpg'),
      });
      final r = await ref.read(apiServiceProvider).upload('/users/profile', fd);
      if (r.data['success'] == true && mounted) {
        await ref.read(authControllerProvider).refreshUser();
        if (mounted) { context.pop(); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Profile updated!'))); }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally { if (mounted) setState(() => _saving = false); }
  }

  @override
  Widget build(BuildContext context) {
    final me   = ref.watch(currentUserProvider);
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.orange))
              : const Text('Save', style: TextStyle(color: AppTheme.orange, fontWeight: FontWeight.w700, fontSize: 16)),
          ),
        ],
      ),
      body: ListView(children: [
        // Cover photo
        Stack(children: [
          GestureDetector(
            onTap: () => _pickImage(true),
            child: _cover != null
              ? Image.file(_cover!, height: 150, width: double.infinity, fit: BoxFit.cover)
              : me?.coverUrl != null
                ? Image.network(me!.coverUrl!, height: 150, width: double.infinity, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _CoverPlaceholder())
                : _CoverPlaceholder(),
          ),
          Positioned(top: 10, right: 10, child: _EditBtn(Icons.camera_alt_rounded, () => _pickImage(true))),
        ]),

        // Avatar
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Transform.translate(offset: const Offset(0, -36), child: Row(children: [
          Stack(children: [
            _avatar != null
              ? ClipOval(child: Image.file(_avatar!, width: 88, height: 88, fit: BoxFit.cover))
              : (me?.avatarUrl != null
                ? ClipOval(child: Image.network(me!.avatarUrl!, width: 88, height: 88, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _AvatarPlaceholder(me.username)))
                : _AvatarPlaceholder(me?.username)),
            Positioned(bottom: 0, right: 0, child: _EditBtn(Icons.camera_alt_rounded, () => _pickImage(false), small: true)),
          ]),
          const SizedBox(width: 12),
          GestureDetector(onTap: () => _pickImage(false), child: const Text('Change photo', style: TextStyle(color: AppTheme.orange, fontWeight: FontWeight.w600, fontSize: 14))),
        ]))),

        // Status / Mood
        Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          GestureDetector(
            onTap: () async {
              final result = await showModalBottomSheet<String>(context: context, isScrollControlled: true, builder: (_) => const MoodPickerSheet());
              if (result != null && mounted) setState(() => _statusCtrl.text = result);
            },
            child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), decoration: BoxDecoration(color: dark ? AppTheme.dCard : AppTheme.lInput, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.orange.withOpacity(0.3))),
              child: Row(children: [
                const Icon(Icons.mood_rounded, color: AppTheme.orange, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(_statusCtrl.text.isEmpty ? 'Set your status or mood' : _statusCtrl.text, style: TextStyle(color: _statusCtrl.text.isEmpty ? (dark ? AppTheme.dSub : AppTheme.lSub) : null, fontSize: 14))),
                const Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 18),
              ])),
          ),
          const SizedBox(height: 4),
          Text('Status is visible to your contacts', style: TextStyle(fontSize: 11, color: dark ? AppTheme.dSub : AppTheme.lSub)),
        ])),

        const SizedBox(height: 16),
        const _Divider(),

        // Fields
        _Field(Icons.person_rounded,      'Display Name', 'Your public name', _nameCtrl, maxLen: 100),
        _Field(Icons.alternate_email_rounded, 'Username', '@yourname', _usernameCtrl, maxLen: 30,
          suffix: _checkingUsername
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : _usernameAvailable == null ? null
            : Icon(_usernameAvailable! ? Icons.check_circle_rounded : Icons.cancel_rounded, color: _usernameAvailable! ? Colors.green : Colors.red, size: 20),
          onChange: (v) { if (v != _originalUsername) _checkUsername(v); else setState(() => _usernameAvailable = null); }),
        if (_usernameAvailable == false) const Padding(padding: EdgeInsets.fromLTRB(56, 0, 16, 8), child: Text('Username is already taken', style: TextStyle(color: Colors.red, fontSize: 12))),
        if (_usernameAvailable == true) const Padding(padding: EdgeInsets.fromLTRB(56, 0, 16, 8), child: Text('Username is available', style: TextStyle(color: Colors.green, fontSize: 12))),

        _AreaField(Icons.info_outline_rounded, 'Bio', 'Tell the world about yourself...', _bioCtrl, maxLen: 300),
        _Field(Icons.link_rounded,         'Website', 'https://yoursite.com', _websiteCtrl, maxLen: 300, keyboard: TextInputType.url),
        _Field(Icons.location_on_rounded,  'Location', 'City, Country', _locationCtrl, maxLen: 100),

        // Gender
        Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), child: Row(children: [
          Container(width: 40, height: 40, decoration: BoxDecoration(color: AppTheme.orangeSurf, borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.person_outlined, color: AppTheme.orange, size: 20)),
          const SizedBox(width: 12),
          Expanded(child: DropdownButtonFormField<String>(
            value: _gender,
            decoration: const InputDecoration(labelText: 'Gender', border: InputBorder.none, filled: false),
            items: const [
              DropdownMenuItem(value: null,                    child: Text('Prefer not to say')),
              DropdownMenuItem(value: 'male',                  child: Text('Male')),
              DropdownMenuItem(value: 'female',                child: Text('Female')),
              DropdownMenuItem(value: 'other',                 child: Text('Other')),
              DropdownMenuItem(value: 'prefer_not_to_say',     child: Text('Prefer not to say')),
            ],
            onChanged: (v) => setState(() => _gender = v),
          )),
        ])),

        const _Divider(),
        const SizedBox(height: 8),

        // Delete account link
        Center(child: TextButton.icon(onPressed: () => context.push('/security'), icon: const Icon(Icons.shield_rounded, color: AppTheme.orange, size: 16), label: const Text('Manage Account Security', style: TextStyle(color: AppTheme.orange, fontSize: 13)))),
        const SizedBox(height: 30),
      ]),
    );
  }
}

class _Field extends StatelessWidget {
  final IconData icon; final String label, hint; final TextEditingController ctrl;
  final int maxLen; final Widget? suffix; final void Function(String)? onChange; final TextInputType keyboard;
  const _Field(this.icon, this.label, this.hint, this.ctrl, {this.maxLen = 200, this.suffix, this.onChange, this.keyboard = TextInputType.text});
  @override
  Widget build(BuildContext _) => Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Padding(padding: const EdgeInsets.only(top: 12), child: Container(width: 40, height: 40, decoration: BoxDecoration(color: AppTheme.orangeSurf, borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: AppTheme.orange, size: 20))),
    const SizedBox(width: 12),
    Expanded(child: TextField(controller: ctrl, onChanged: onChange, maxLength: maxLen, keyboardType: keyboard, decoration: InputDecoration(labelText: label, hintText: hint, border: InputBorder.none, filled: false, suffixIcon: suffix, counterText: ''))),
  ]));
}

class _AreaField extends StatelessWidget {
  final IconData icon; final String label, hint; final TextEditingController ctrl; final int maxLen;
  const _AreaField(this.icon, this.label, this.hint, this.ctrl, {this.maxLen = 300});
  @override
  Widget build(BuildContext _) => Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Padding(padding: const EdgeInsets.only(top: 12), child: Container(width: 40, height: 40, decoration: BoxDecoration(color: AppTheme.orangeSurf, borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: AppTheme.orange, size: 20))),
    const SizedBox(width: 12),
    Expanded(child: TextField(controller: ctrl, maxLines: 4, minLines: 2, maxLength: maxLen, decoration: InputDecoration(labelText: label, hintText: hint, border: InputBorder.none, filled: false, alignLabelWithHint: true))),
  ]));
}

class _EditBtn extends StatelessWidget {
  final IconData icon; final VoidCallback onTap; final bool small;
  const _EditBtn(this.icon, this.onTap, {this.small = false});
  @override Widget build(BuildContext _) => GestureDetector(onTap: onTap, child: Container(
    width: small ? 28 : 36, height: small ? 28 : 36,
    decoration: BoxDecoration(color: AppTheme.orange, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
    child: Icon(icon, color: Colors.white, size: small ? 14 : 18),
  ));
}

class _CoverPlaceholder extends StatelessWidget {
  @override Widget build(BuildContext _) => Container(height: 150, width: double.infinity, decoration: const BoxDecoration(gradient: LinearGradient(colors: [AppTheme.orange, AppTheme.orangeDark])), child: const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.add_photo_alternate_rounded, color: Colors.white70, size: 32), SizedBox(height: 6), Text('Tap to add cover', style: TextStyle(color: Colors.white70, fontSize: 13))])));
}

class _AvatarPlaceholder extends StatelessWidget {
  final String? username;
  const _AvatarPlaceholder(this.username);
  @override Widget build(BuildContext _) => Container(width: 88, height: 88, decoration: const BoxDecoration(shape: BoxShape.circle, color: AppTheme.orange), child: Center(child: Text((username?.isNotEmpty == true ? username![0] : '?').toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 34))));
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override Widget build(BuildContext _) => const Divider(height: 1, indent: 68);
}
