import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:io';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/api_service.dart';
import 'package:dio/dio.dart';

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});
  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen>
    with TickerProviderStateMixin {
  // ── Controllers
  final _displayNameCtrl = TextEditingController();
  final _usernameCtrl    = TextEditingController();
  final _bioCtrl         = TextEditingController();
  final _cityCtrl        = TextEditingController();
  final _websiteCtrl     = TextEditingController();

  // ── State
  File?   _avatarFile;
  bool    _saving      = false;
  bool    _checkingUn  = false;
  bool?   _unAvailable;
  String? _unError;
  String? _gender;
  DateTime? _birthday;
  int     _step        = 0; // 0=basic, 1=about, 2=done
  String? _globalError;

  // ── Gender options
  static const _genders = ['Male', 'Female', 'Non-binary', 'Prefer not to say'];

  // ── Validation
  String? _nameError;
  String? _websiteError;

  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _displayNameCtrl.addListener(() {
      if (_nameError != null && _displayNameCtrl.text.trim().isNotEmpty) {
        setState(() => _nameError = null);
      }
    });
  }

  @override
  void dispose() {
    _displayNameCtrl.dispose();
    _usernameCtrl.dispose();
    _bioCtrl.dispose();
    _cityCtrl.dispose();
    _websiteCtrl.dispose();
    _tabCtrl.dispose();
    super.dispose();
  }

  // ── Avatar picker
  Future<void> _pickAvatar(ImageSource source) async {
    try {
      final picked = await ImagePicker().pickImage(source: source, imageQuality: 85, maxWidth: 800, maxHeight: 800);
      if (picked != null && mounted) setState(() => _avatarFile = File(picked.path));
    } catch (_) {}
  }

  void _showAvatarPicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, margin: const EdgeInsets.only(top: 12, bottom: 20),
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          ListTile(
            leading: const Icon(Icons.camera_alt_rounded, color: AppTheme.orange),
            title: const Text('Take a photo', style: TextStyle(fontWeight: FontWeight.w600)),
            onTap: () { Navigator.pop(context); _pickAvatar(ImageSource.camera); },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_rounded, color: AppTheme.orange),
            title: const Text('Choose from gallery', style: TextStyle(fontWeight: FontWeight.w600)),
            onTap: () { Navigator.pop(context); _pickAvatar(ImageSource.gallery); },
          ),
          if (_avatarFile != null) ListTile(
            leading: const Icon(Icons.delete_outline_rounded, color: Colors.red),
            title: const Text('Remove photo', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
            onTap: () { Navigator.pop(context); setState(() => _avatarFile = null); },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  // ── Username check
  Future<void> _checkUsername(String un) async {
    if (un.length < 3) { setState(() { _unAvailable = null; _unError = null; }); return; }
    if (!RegExp(r'^[a-zA-Z0-9._]+$').hasMatch(un)) {
      setState(() { _unAvailable = false; _unError = 'Only letters, numbers, . and _'; });
      return;
    }
    setState(() { _checkingUn = true; _unError = null; _unAvailable = null; });
    try {
      final r = await ref.read(apiServiceProvider).get('/auth/check-username', q: {'username': un});
      if (mounted) setState(() { _unAvailable = r.data['available'] == true; _checkingUn = false; });
    } catch (_) { if (mounted) setState(() => _checkingUn = false); }
  }

  // ── Save profile
  Future<void> _save() async {
    // Validate
    final name     = _displayNameCtrl.text.trim();
    final username = _usernameCtrl.text.trim().toLowerCase();
    final city     = _cityCtrl.text.trim();
    final website  = _websiteCtrl.text.trim();

    setState(() { _nameError = null; _unError = null; _websiteError = null; _globalError = null; });

    if (name.isEmpty) { setState(() => _nameError = 'Display name is required'); _tabCtrl.animateTo(0); return; }
    if (username.length < 3) { setState(() { _unError = 'Username must be at least 3 characters'; }); _tabCtrl.animateTo(0); return; }
    if (_unAvailable == false) { setState(() => _unError = 'Username not available'); _tabCtrl.animateTo(0); return; }
    if (website.isNotEmpty && !_isValidUrl(website)) {
      setState(() => _websiteError = 'Enter a valid URL (e.g. https://yoursite.com)');
      _tabCtrl.animateTo(1);
      return;
    }

    setState(() => _saving = true);
    try {
      final fd = FormData.fromMap({
        'display_name': name,
        'username':     username,
        'bio':          _bioCtrl.text.trim(),
        'location':     city.isNotEmpty ? city : null,
        'gender':       _gender,
        'website':      website.isNotEmpty ? website : null,
        'birthday':     _birthday != null ? _birthday!.toIso8601String().split('T').first : null,
        if (_avatarFile != null)
          'avatar': await MultipartFile.fromFile(_avatarFile!.path, filename: 'avatar.jpg'),
      });

      await ref.read(apiServiceProvider).upload('/auth/setup-profile', fd);
      await ref.read(authControllerProvider).refreshUser();

      if (!mounted) return;
      setState(() => _step = 2);
      HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 1600));
      if (mounted) context.go('/');
    } catch (e) {
      if (mounted) setState(() => _globalError = 'Failed to save profile. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool _isValidUrl(String url) {
    try {
      final u = Uri.parse(url.startsWith('http') ? url : 'https://$url');
      return u.hasAuthority;
    } catch (_) { return false; }
  }

  // ── Birthday picker
  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthday ?? DateTime(now.year - 18),
      firstDate: DateTime(1920),
      lastDate: DateTime(now.year - 13),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: AppTheme.orange, onPrimary: Colors.white),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) setState(() => _birthday = picked);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final wide = MediaQuery.sizeOf(context).width >= 800;

    // Done screen
    if (_step == 2) return _DoneScreen(name: _displayNameCtrl.text.trim());

    return Scaffold(
      backgroundColor: dark ? AppTheme.dBg : const Color(0xFFF6F2EE),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: wide ? 600 : double.infinity),
            child: Column(
              children: [
                // ── Header
                _SetupHeader(step: _step, dark: dark),

                // ── Progress bar
                LinearProgressIndicator(
                  value: (_step + 1) / 2,
                  backgroundColor: dark ? AppTheme.dDiv : Colors.grey.shade200,
                  valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.orange),
                  minHeight: 3,
                ),

                // ── Tab bar (step indicator)
                TabBar(
                  controller: _tabCtrl,
                  labelColor: AppTheme.orange,
                  unselectedLabelColor: dark ? AppTheme.dSub : Colors.grey.shade400,
                  indicatorColor: AppTheme.orange,
                  indicatorSize: TabBarIndicatorSize.tab,
                  tabs: const [
                    Tab(text: 'Basic Info'),
                    Tab(text: 'About You'),
                  ],
                  onTap: (i) => setState(() => _step = i),
                ),

                // ── Body
                Expanded(
                  child: TabBarView(
                    controller: _tabCtrl,
                    children: [
                      _BasicInfoTab(
                        dark: dark,
                        avatarFile: _avatarFile,
                        displayNameCtrl: _displayNameCtrl,
                        usernameCtrl: _usernameCtrl,
                        checkingUn: _checkingUn,
                        unAvailable: _unAvailable,
                        nameError: _nameError,
                        unError: _unError,
                        onPickAvatar: _showAvatarPicker,
                        onUsernameChanged: (v) {
                          if (v.length >= 3) _checkUsername(v);
                          else setState(() { _unAvailable = null; _unError = null; });
                        },
                      ),
                      _AboutYouTab(
                        dark: dark,
                        bioCtrl: _bioCtrl,
                        cityCtrl: _cityCtrl,
                        websiteCtrl: _websiteCtrl,
                        gender: _gender,
                        birthday: _birthday,
                        websiteError: _websiteError,
                        onGenderChanged: (g) => setState(() => _gender = g),
                        onPickBirthday: _pickBirthday,
                      ),
                    ],
                  ),
                ),

                // ── Global error
                if (_globalError != null) Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50, borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(children: [
                    Icon(Icons.error_outline_rounded, color: Colors.red.shade600, size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_globalError!, style: TextStyle(color: Colors.red.shade700, fontSize: 13))),
                  ]),
                ),

                // ── Bottom action row
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                  color: dark ? AppTheme.dBg : const Color(0xFFF6F2EE),
                  child: Row(children: [
                    // Skip (only show on first step)
                    if (_tabCtrl.index == 0)
                      TextButton(
                        onPressed: _saving ? null : () => context.go('/'),
                        child: Text('Skip for now',
                          style: TextStyle(color: dark ? AppTheme.dSub : Colors.grey.shade500,
                              fontWeight: FontWeight.w500)),
                      ),
                    if (_tabCtrl.index == 0) const SizedBox(width: 12),

                    // Continue / Complete
                    Expanded(
                      child: SizedBox(
                        height: 54,
                        child: ElevatedButton(
                          onPressed: _saving ? null : () {
                            if (_tabCtrl.index == 0) {
                              _tabCtrl.animateTo(1);
                              setState(() => _step = 1);
                            } else {
                              _save();
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.orange,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            elevation: 3,
                            shadowColor: AppTheme.orange.withOpacity(0.35),
                          ),
                          child: _saving
                            ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)),
                                SizedBox(width: 12),
                                Text('Saving...', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                              ])
                            : Text(
                                _tabCtrl.index == 0 ? 'Continue →' : 'Complete Profile',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                              ),
                        ),
                      ),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────
// SETUP HEADER
// ─────────────────────────────────────────────────
class _SetupHeader extends StatelessWidget {
  final int step; final bool dark;
  const _SetupHeader({required this.step, required this.dark});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
    child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Container(
        width: 44, height: 44,
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [AppTheme.orange, Color(0xFFE64A19)]),
          shape: BoxShape.circle,
        ),
        child: const Center(child: Text('🔴', style: TextStyle(fontSize: 22))),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Set up your profile',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20,
                color: dark ? Colors.white : AppTheme.lText, letterSpacing: -0.3)),
          Text(step == 0 ? 'Step 1 of 2 — Basic information' : 'Step 2 of 2 — About you',
            style: TextStyle(color: dark ? AppTheme.dSub : AppTheme.lSub, fontSize: 13)),
        ]),
      ),
    ]),
  );
}

// ─────────────────────────────────────────────────
// BASIC INFO TAB
// ─────────────────────────────────────────────────
class _BasicInfoTab extends StatelessWidget {
  final bool dark;
  final File? avatarFile;
  final TextEditingController displayNameCtrl, usernameCtrl;
  final bool checkingUn;
  final bool? unAvailable;
  final String? nameError, unError;
  final VoidCallback onPickAvatar;
  final ValueChanged<String> onUsernameChanged;

  const _BasicInfoTab({
    required this.dark, required this.avatarFile,
    required this.displayNameCtrl, required this.usernameCtrl,
    required this.checkingUn, required this.unAvailable,
    required this.nameError, required this.unError,
    required this.onPickAvatar, required this.onUsernameChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar
          Center(
            child: GestureDetector(
              onTap: onPickAvatar,
              child: Stack(children: [
                Container(
                  width: 108, height: 108,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: avatarFile == null
                      ? const LinearGradient(colors: [AppTheme.orange, Color(0xFFE64A19)])
                      : null,
                    border: Border.all(color: AppTheme.orange, width: 3),
                  ),
                  child: avatarFile != null
                    ? ClipOval(child: Image.file(avatarFile!, width: 108, height: 108, fit: BoxFit.cover))
                    : const Icon(Icons.person_rounded, color: Colors.white, size: 52),
                ),
                Positioned(
                  bottom: 2, right: 2,
                  child: Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: AppTheme.orange, shape: BoxShape.circle,
                      border: Border.all(color: dark ? AppTheme.dBg : Colors.white, width: 2.5),
                    ),
                    child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 15),
                  ),
                ),
              ]),
            ),
          ).animate().fadeIn(delay: 100.ms).scale(begin: const Offset(0.8, 0.8)),

          const SizedBox(height: 8),
          Center(
            child: Text('Tap to ${avatarFile != null ? 'change' : 'add'} profile photo',
              style: TextStyle(color: dark ? AppTheme.dSub : AppTheme.lSub, fontSize: 13)),
          ),
          const SizedBox(height: 28),

          // Display name
          _FieldLabel(text: 'Display Name *', dark: dark),
          const SizedBox(height: 6),
          TextField(
            controller: displayNameCtrl,
            textCapitalization: TextCapitalization.words,
            style: TextStyle(color: dark ? Colors.white : AppTheme.lText, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              hintText: 'Your full name',
              prefixIcon: const Icon(Icons.person_rounded, size: 20, color: AppTheme.orange),
              errorText: nameError,
              filled: true,
              fillColor: dark ? const Color(0xFF1E1E1E) : Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: dark ? const Color(0xFF2E2E2E) : Colors.grey.shade200)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppTheme.orange, width: 1.5)),
              errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.red, width: 1.5)),
            ),
          ).animate().fadeIn(delay: 200.ms),

          const SizedBox(height: 18),

          // Username
          _FieldLabel(text: 'Username *', dark: dark),
          const SizedBox(height: 6),
          TextField(
            controller: usernameCtrl,
            onChanged: onUsernameChanged,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9._]'))],
            style: TextStyle(color: dark ? Colors.white : AppTheme.lText, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              hintText: 'yourhandle',
              prefixText: '@',
              prefixStyle: const TextStyle(color: AppTheme.orange, fontWeight: FontWeight.w700, fontSize: 16),
              suffixIcon: checkingUn
                ? const Padding(padding: EdgeInsets.all(14),
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.orange)))
                : (unAvailable == null ? null
                    : Icon(unAvailable! ? Icons.check_circle_rounded : Icons.cancel_rounded,
                        color: unAvailable! ? Colors.green : Colors.red, size: 22)),
              errorText: unError,
              helperText: unAvailable == true ? '✓ Username is available' : null,
              helperStyle: const TextStyle(color: Colors.green, fontWeight: FontWeight.w600, fontSize: 12),
              filled: true,
              fillColor: dark ? const Color(0xFF1E1E1E) : Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: dark ? const Color(0xFF2E2E2E) : Colors.grey.shade200)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppTheme.orange, width: 1.5)),
              errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.red, width: 1.5)),
            ),
          ).animate().fadeIn(delay: 300.ms),

          const SizedBox(height: 8),
          Text('3–30 chars, letters, numbers, dots and underscores only',
            style: TextStyle(color: dark ? AppTheme.dSub : Colors.grey.shade500, fontSize: 11)),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────
// ABOUT YOU TAB
// ─────────────────────────────────────────────────
class _AboutYouTab extends StatelessWidget {
  final bool dark;
  final TextEditingController bioCtrl, cityCtrl, websiteCtrl;
  final String? gender;
  final DateTime? birthday;
  final String? websiteError;
  final ValueChanged<String?> onGenderChanged;
  final VoidCallback onPickBirthday;

  static const _genders = ['Male', 'Female', 'Non-binary', 'Prefer not to say'];

  const _AboutYouTab({
    required this.dark, required this.bioCtrl, required this.cityCtrl,
    required this.websiteCtrl, required this.gender, required this.birthday,
    required this.websiteError, required this.onGenderChanged, required this.onPickBirthday,
  });

  InputDecoration _fieldDeco({required bool dark, required String hint, IconData? icon}) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: icon != null ? Icon(icon, size: 20, color: AppTheme.orange) : null,
      filled: true,
      fillColor: dark ? const Color(0xFF1E1E1E) : Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: dark ? const Color(0xFF2E2E2E) : Colors.grey.shade200)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppTheme.orange, width: 1.5)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = TextStyle(color: dark ? Colors.white : AppTheme.lText, fontWeight: FontWeight.w500);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Bio
          _FieldLabel(text: 'Bio', dark: dark),
          const SizedBox(height: 6),
          TextField(
            controller: bioCtrl,
            maxLines: 3, maxLength: 200,
            style: textStyle,
            decoration: _fieldDeco(dark: dark, hint: 'Tell the world about yourself...', icon: Icons.edit_rounded),
          ).animate().fadeIn(delay: 100.ms),

          const SizedBox(height: 18),

          // City
          _FieldLabel(text: 'City / Location', dark: dark),
          const SizedBox(height: 6),
          TextField(
            controller: cityCtrl,
            textCapitalization: TextCapitalization.words,
            style: textStyle,
            decoration: _fieldDeco(dark: dark, hint: 'e.g. Kigali, Rwanda', icon: Icons.location_city_rounded),
          ).animate().fadeIn(delay: 200.ms),

          const SizedBox(height: 18),

          // Gender
          _FieldLabel(text: 'Gender', dark: dark),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: _genders.map((g) => GestureDetector(
              onTap: () => onGenderChanged(gender == g ? null : g),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                decoration: BoxDecoration(
                  color: gender == g ? AppTheme.orange : (dark ? const Color(0xFF1E1E1E) : Colors.white),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: gender == g ? AppTheme.orange : (dark ? const Color(0xFF2E2E2E) : Colors.grey.shade200),
                  ),
                ),
                child: Text(g, style: TextStyle(
                  color: gender == g ? Colors.white : (dark ? AppTheme.dText : AppTheme.lText),
                  fontWeight: gender == g ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 13,
                )),
              ),
            )).toList(),
          ).animate().fadeIn(delay: 300.ms),

          const SizedBox(height: 18),

          // Birthday
          _FieldLabel(text: 'Birthday', dark: dark),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: onPickBirthday,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: dark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: dark ? const Color(0xFF2E2E2E) : Colors.grey.shade200),
              ),
              child: Row(children: [
                const Icon(Icons.cake_rounded, color: AppTheme.orange, size: 20),
                const SizedBox(width: 12),
                Text(
                  birthday != null
                    ? '${birthday!.day.toString().padLeft(2, '0')} / ${birthday!.month.toString().padLeft(2, '0')} / ${birthday!.year}'
                    : 'Select your birthday',
                  style: TextStyle(
                    color: birthday != null ? (dark ? Colors.white : AppTheme.lText) : Colors.grey.shade400,
                    fontWeight: birthday != null ? FontWeight.w500 : FontWeight.w400,
                    fontSize: 15,
                  ),
                ),
                const Spacer(),
                Icon(Icons.chevron_right_rounded, color: dark ? AppTheme.dSub : Colors.grey.shade400),
              ]),
            ),
          ).animate().fadeIn(delay: 400.ms),

          const SizedBox(height: 18),

          // Website
          _FieldLabel(text: 'Website', dark: dark),
          const SizedBox(height: 6),
          TextField(
            controller: websiteCtrl,
            keyboardType: TextInputType.url,
            style: textStyle,
            decoration: _fieldDeco(dark: dark, hint: 'yoursite.com', icon: Icons.link_rounded).copyWith(
              errorText: websiteError,
              errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.red, width: 1.5)),
            ),
          ).animate().fadeIn(delay: 500.ms),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────
// DONE SCREEN
// ─────────────────────────────────────────────────
class _DoneScreen extends StatelessWidget {
  final String name;
  const _DoneScreen({required this.name});
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.green, size: 96)
              .animate().scale(begin: const Offset(0.3, 0.3), curve: Curves.elasticOut, duration: 700.ms),
            const SizedBox(height: 24),
            Text('Welcome, ${name.split(' ').first}! 🎉',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 28, letterSpacing: -0.5),
              textAlign: TextAlign.center,
            ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.3),
            const SizedBox(height: 12),
            const Text('Your profile is set up.\nTaking you to your feed...',
              style: TextStyle(fontSize: 16, color: Colors.grey, height: 1.5),
              textAlign: TextAlign.center,
            ).animate().fadeIn(delay: 600.ms),
            const SizedBox(height: 40),
            const CircularProgressIndicator(color: AppTheme.orange, strokeWidth: 2.5)
              .animate().fadeIn(delay: 900.ms),
          ],
        ),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────
// SHARED FIELD LABEL
// ─────────────────────────────────────────────────
class _FieldLabel extends StatelessWidget {
  final String text; final bool dark;
  const _FieldLabel({required this.text, required this.dark});
  @override
  Widget build(BuildContext context) => Text(text,
    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13,
        color: dark ? AppTheme.dText : AppTheme.lText));
}
