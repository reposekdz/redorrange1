import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:country_code_picker/country_code_picker.dart';
import 'dart:async';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/widgets/app_avatar.dart';

class AddContactScreen extends ConsumerStatefulWidget {
  const AddContactScreen({super.key});
  @override ConsumerState<AddContactScreen> createState() => _S();
}

class _S extends ConsumerState<AddContactScreen> {
  final _phoneCtrl    = TextEditingController();
  final _nicknameCtrl = TextEditingController();
  final _phoneFocus   = FocusNode();
  String _cc = '+250'; // Rwanda default
  bool _searching = false;
  Map<String, dynamic>? _result; // null = not searched, {} = searched but not found
  String? _error;
  Timer? _deb;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _phoneFocus.requestFocus());
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _nicknameCtrl.dispose();
    _phoneFocus.dispose();
    _deb?.cancel();
    super.dispose();
  }

  void _onPhoneChanged(String v) {
    setState(() { _result = null; _error = null; });
    _deb?.cancel();
    final digits = v.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 7) {
      setState(() => _searching = true);
      _deb = Timer(const Duration(milliseconds: 600), () => _lookup(digits));
    } else {
      setState(() => _searching = false);
    }
  }

  Future<void> _lookup(String phone) async {
    setState(() { _searching = true; _error = null; });
    try {
      final r = await ref.read(apiServiceProvider).post('/contacts/lookup', data: {
        'phone_number': phone,
        'country_code': _cc,
      });
      final data = Map<String, dynamic>.from(r.data);
      if (mounted) {
        setState(() {
          _searching = false;
          if (data['success'] == true) {
            if (data['exists'] == true) {
              _result = Map<String, dynamic>.from(data['user'] ?? {});
              _result!['already_contact'] = data['already_contact'] ?? false;
              _result!['is_self'] = data['is_self'] ?? false;
            } else {
              _result = {}; // searched but not found
              _error = data['message'] ?? 'This number is not registered on RedOrrange';
            }
          } else {
            _error = data['message'] ?? 'Lookup failed';
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() { _searching = false; _error = 'Network error. Check connection.'; });
    }
  }

  Future<void> _addContact(String userId) async {
    try {
      final r = await ref.read(apiServiceProvider).post('/contacts/add', data: {
        'contact_id': userId,
        if (_nicknameCtrl.text.trim().isNotEmpty) 'nickname': _nicknameCtrl.text.trim(),
      });
      if (mounted) {
        if (r.data['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Row(children: [Icon(Icons.check_circle_rounded, color: Colors.white), SizedBox(width: 8), Text('Contact added successfully!')]),
            backgroundColor: Colors.green,
          ));
          context.pop();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.data['message'] ?? 'Failed')));
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _openChat(String userId) async {
    try {
      final r = await ref.read(apiServiceProvider).post('/messages/conversations', data: {'type': 'direct', 'user_id': userId});
      if (mounted) context.push('/chat/${r.data['conversation']['id']}');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final me = ref.watch(currentUserProvider);

    final userFound = _result != null && _result!.isNotEmpty;
    final notFound  = _result != null && _result!.isEmpty;
    final isSelf    = _result?['is_self'] == true;
    final isContact = _result?['already_contact'] == true;

    return Scaffold(
      backgroundColor: dark ? AppTheme.dBg : const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Add Contact', style: TextStyle(fontWeight: FontWeight.w800)),
        elevation: 0,
      ),
      body: Column(children: [
        // Phone input card
        Container(
          color: dark ? AppTheme.dSurf : Colors.white,
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Phone Number', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.grey, letterSpacing: 0.5)),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: dark ? AppTheme.dCard : const Color(0xFFF0F0F0),
                borderRadius: BorderRadius.circular(14),
                border: _error != null ? Border.all(color: Colors.red, width: 1) : null,
              ),
              child: Row(children: [
                // Country code picker
                CountryCodePicker(
                  onChanged: (c) {
                    setState(() { _cc = c.dialCode ?? '+250'; _result = null; _error = null; });
                    final digits = _phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
                    if (digits.length >= 7) _lookup(digits);
                  },
                  initialSelection: 'RW',
                  favorite: const ['+250', '+254', '+255', '+256', '+233', '+234', '+1', '+44', '+33'],
                  showFlag: true,
                  showCountryOnly: false,
                  alignLeft: false,
                  textStyle: TextStyle(color: dark ? AppTheme.dText : AppTheme.lText, fontWeight: FontWeight.w700, fontSize: 15),
                ),
                Container(width: 1, height: 32, color: dark ? AppTheme.dDiv : const Color(0xFFDDDDDD)),
                Expanded(child: TextField(
                  controller: _phoneCtrl,
                  focusNode: _phoneFocus,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d\s\-\(\)]'))],
                  style: TextStyle(color: dark ? AppTheme.dText : AppTheme.lText, fontSize: 17, fontWeight: FontWeight.w500, letterSpacing: 0.5),
                  decoration: InputDecoration(
                    hintText: '700 000 000',
                    hintStyle: TextStyle(color: dark ? AppTheme.dSub : AppTheme.lSub, fontWeight: FontWeight.w400),
                    border: InputBorder.none,
                    filled: false,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    suffixIcon: _phoneCtrl.text.isNotEmpty
                      ? IconButton(icon: const Icon(Icons.close_rounded, size: 18), onPressed: () { _phoneCtrl.clear(); setState(() { _result = null; _error = null; _searching = false; }); })
                      : null,
                  ),
                  onChanged: _onPhoneChanged,
                )),
              ]),
            ),
            const SizedBox(height: 4),
            AnimatedSwitcher(duration: const Duration(milliseconds: 200), child: _error != null
              ? Padding(key: const ValueKey('err'), padding: const EdgeInsets.only(top: 6, left: 4), child: Row(children: [const Icon(Icons.info_outline_rounded, size: 14, color: Colors.red), const SizedBox(width: 4), Flexible(child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)))]))
              : const SizedBox.shrink(key: ValueKey('no-err'))),
          ]),
        ),

        const SizedBox(height: 12),

        // Searching indicator
        if (_searching) Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Column(children: [
          const CircularProgressIndicator(color: AppTheme.orange, strokeWidth: 2.5),
          const SizedBox(height: 12),
          Text('Searching RedOrrange...', style: TextStyle(color: dark ? AppTheme.dSub : AppTheme.lSub, fontSize: 13)),
        ])),

        // Result card
        if (userFound && !_searching) _UserResultCard(
          user: _result!,
          isSelf: isSelf,
          isContact: isContact,
          nicknameCtrl: _nicknameCtrl,
          dark: dark,
          onAdd: () => _addContact(_result!['id'] as String),
          onMessage: () => _openChat(_result!['id'] as String),
          onViewProfile: () => context.push('/profile/${_result!['id']}'),
        ),

        // Not found card
        if (notFound && !_searching) _NotFoundCard(phone: '${_cc}${_phoneCtrl.text.trim()}', dark: dark),

        // Tips section
        if (_result == null && !_searching) Expanded(child: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('How to add contacts', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 12),
          _Tip(Icons.dialpad_rounded, 'Enter phone number', 'Type the contact\'s full phone number with country code'),
          _Tip(Icons.search_rounded, 'Instant search', 'We\'ll search our database in real-time as you type'),
          _Tip(Icons.person_add_rounded, 'Add & connect', 'Add them to your contacts and start messaging'),
          _Tip(Icons.lock_rounded, 'Privacy protected', 'We never share your phone number without consent'),
          const SizedBox(height: 20),
          Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: AppTheme.orangeSurf, borderRadius: BorderRadius.circular(14)), child: Row(children: [
            const Icon(Icons.lightbulb_rounded, color: AppTheme.orange, size: 22),
            const SizedBox(width: 10),
            const Expanded(child: Text('You can also find people by scanning their QR code in their profile.', style: TextStyle(fontSize: 13, color: AppTheme.orangeDark))),
          ])),
        ])))),
      ]),
    );
  }
}

// ── User found card
class _UserResultCard extends StatelessWidget {
  final Map<String,dynamic> user;
  final bool isSelf, isContact, dark;
  final TextEditingController nicknameCtrl;
  final VoidCallback onAdd, onMessage, onViewProfile;

  const _UserResultCard({
    required this.user, required this.isSelf, required this.isContact,
    required this.nicknameCtrl, required this.dark,
    required this.onAdd, required this.onMessage, required this.onViewProfile,
  });

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      color: dark ? AppTheme.dCard : Colors.white,
      borderRadius: BorderRadius.circular(18),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 4))],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Found banner
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelf ? Colors.blue.withOpacity(0.1) : (isContact ? Colors.green.withOpacity(0.1) : AppTheme.orangeSurf),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: Row(children: [
          Icon(isSelf ? Icons.person_rounded : (isContact ? Icons.check_circle_rounded : Icons.check_circle_rounded),
            color: isSelf ? Colors.blue : (isContact ? Colors.green : AppTheme.orange), size: 16),
          const SizedBox(width: 6),
          Text(
            isSelf ? 'This is your account' : (isContact ? 'Already in your contacts' : 'Found on RedOrrange!'),
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: isSelf ? Colors.blue : (isContact ? Colors.green : AppTheme.orange)),
          ),
        ]),
      ),

      // User info
      Padding(padding: const EdgeInsets.all(16), child: Row(children: [
        AppAvatar(url: user['avatar_url'] as String?, size: 58, username: user['username'] as String?),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Flexible(child: Text(user['display_name'] as String? ?? user['username'] as String? ?? 'Unknown',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18), overflow: TextOverflow.ellipsis)),
            if (user['is_verified'] == true || user['is_verified'] == 1)
              const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.verified_rounded, color: AppTheme.orange, size: 16)),
          ]),
          const SizedBox(height: 2),
          Text('@${user['username'] ?? ''}', style: TextStyle(fontSize: 13, color: dark ? AppTheme.dSub : AppTheme.lSub)),
          if (user['status_text'] != null && (user['status_text'] as String).isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 4), child: Row(children: [
              const Icon(Icons.circle, size: 7, color: AppTheme.orange),
              const SizedBox(width: 5),
              Flexible(child: Text(user['status_text'] as String, style: const TextStyle(fontSize: 12, color: AppTheme.orange), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ])),
        ])),
      ])),

      // Nickname field (only if adding new)
      if (!isContact && !isSelf) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Nickname (optional)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: dark ? AppTheme.dSub : AppTheme.lSub)),
        const SizedBox(height: 6),
        TextField(
          controller: nicknameCtrl,
          decoration: InputDecoration(
            hintText: 'e.g. John Work, Mom, Boss...',
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: dark ? AppTheme.dDiv : AppTheme.lDiv)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.orange)),
            filled: true,
            fillColor: dark ? AppTheme.dInput : AppTheme.lInput,
            isDense: true,
          ),
        ),
      ])),

      // Actions
      if (!isSelf) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), child: Row(children: [
        if (!isContact) Expanded(child: FilledButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.person_add_rounded, size: 18),
          label: const Text('Add Contact', style: TextStyle(fontWeight: FontWeight.w700)),
        )),
        if (!isContact) const SizedBox(width: 10),
        Expanded(child: OutlinedButton.icon(
          onPressed: onMessage,
          icon: const Icon(Icons.chat_rounded, size: 18),
          label: const Text('Message', style: TextStyle(fontWeight: FontWeight.w600)),
        )),
        const SizedBox(width: 10),
        OutlinedButton(
          onPressed: onViewProfile,
          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12)),
          child: const Icon(Icons.person_rounded, size: 18),
        ),
      ])),
    ]),
  );
}

// ── Not found card
class _NotFoundCard extends StatelessWidget {
  final String phone; final bool dark;
  const _NotFoundCard({required this.phone, required this.dark});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 16),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: dark ? AppTheme.dCard : Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Colors.grey.withOpacity(0.2)),
    ),
    child: Column(children: [
      Container(width: 70, height: 70, decoration: BoxDecoration(color: Colors.grey.shade100, shape: BoxShape.circle), child: const Icon(Icons.person_search_rounded, size: 36, color: Colors.grey)),
      const SizedBox(height: 14),
      const Text('Number not found', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
      const SizedBox(height: 6),
      Text('$phone\nis not registered on RedOrrange.', textAlign: TextAlign.center, style: TextStyle(color: dark ? AppTheme.dSub : AppTheme.lSub, fontSize: 14, height: 1.5)),
      const SizedBox(height: 18),
      Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), decoration: BoxDecoration(color: AppTheme.orangeSurf, borderRadius: BorderRadius.circular(12)), child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.share_rounded, color: AppTheme.orange, size: 18),
        const SizedBox(width: 8),
        const Flexible(child: Text('Invite them to join RedOrrange', style: TextStyle(color: AppTheme.orange, fontWeight: FontWeight.w600, fontSize: 13))),
      ])),
    ]),
  );
}

class _Tip extends StatelessWidget {
  final IconData icon; final String title, subtitle;
  const _Tip(this.icon, this.title, this.subtitle);
  @override Widget build(BuildContext _) => Padding(padding: const EdgeInsets.only(bottom: 14), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Container(width: 38, height: 38, decoration: BoxDecoration(color: AppTheme.orangeSurf, borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: AppTheme.orange, size: 20)),
    const SizedBox(width: 12),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      const SizedBox(height: 2),
      Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey, height: 1.4)),
    ])),
  ]));
}
