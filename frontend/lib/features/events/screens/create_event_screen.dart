import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/api_service.dart';
import 'package:dio/dio.dart';

class CreateEventScreen extends ConsumerStatefulWidget {
  const CreateEventScreen({super.key});
  @override ConsumerState<CreateEventScreen> createState() => _S();
}
class _S extends ConsumerState<CreateEventScreen> {
  final _titleCtrl = TextEditingController();
  final _descCtrl  = TextEditingController();
  final _locCtrl   = TextEditingController();
  final _linkCtrl  = TextEditingController();
  DateTime? _start, _end;
  String _type = 'in_person'; // in_person, online, hybrid
  String _privacy = 'public';
  File? _cover;
  bool _saving = false;

  @override void dispose() { _titleCtrl.dispose(); _descCtrl.dispose(); _locCtrl.dispose(); _linkCtrl.dispose(); super.dispose(); }

  Future<void> _pickDate(bool isStart) async {
    final d = await showDatePicker(context: context, initialDate: DateTime.now().add(const Duration(days: 1)), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 18, minute: 0));
    if (t == null) return;
    final dt = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    setState(() { if (isStart) _start = dt; else _end = dt; });
  }

  Future<void> _pickCover() async {
    final p = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (p != null && mounted) setState(() => _cover = File(p.path));
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Title required'))); return; }
    if (_start == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Start date required'))); return; }
    setState(() => _saving = true);
    try {
      final fd = FormData.fromMap({
        'title': _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'start_datetime': _start!.toUtc().toIso8601String(),
        if (_end != null) 'end_datetime': _end!.toUtc().toIso8601String(),
        'event_type': _type,
        'privacy': _privacy,
        if (_locCtrl.text.isNotEmpty) 'location': _locCtrl.text.trim(),
        if (_linkCtrl.text.isNotEmpty) 'online_link': _linkCtrl.text.trim(),
        if (_cover != null) 'cover': await MultipartFile.fromFile(_cover!.path, filename: 'cover.jpg'),
      });
      final r = await ref.read(apiServiceProvider).upload('/events', fd);
      if (r.data['success'] == true && mounted) { context.pop(); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Event created! ✅'))); }
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'))); }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fmt  = DateFormat('EEE, MMM d  •  h:mm a');
    return Scaffold(
      appBar: AppBar(title: const Text('Create Event', style: TextStyle(fontWeight: FontWeight.w800)), actions: [TextButton(onPressed: _saving ? null : _save, child: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.orange)) : const Text('Publish', style: TextStyle(color: AppTheme.orange, fontWeight: FontWeight.w700, fontSize: 16)))]),
      body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Cover
        GestureDetector(onTap: _pickCover, child: Container(height: 160, width: double.infinity, decoration: BoxDecoration(color: dark ? AppTheme.dCard : AppTheme.lInput, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.orange.withOpacity(0.3), style: BorderStyle.solid)), child: _cover != null ? ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.file(_cover!, fit: BoxFit.cover, width: double.infinity)) : Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.add_photo_alternate_rounded, color: AppTheme.orange, size: 36), const SizedBox(height: 8), const Text('Add Cover Photo', style: TextStyle(color: AppTheme.orange, fontWeight: FontWeight.w600))]))),
        const SizedBox(height: 16),
        _field(_titleCtrl, 'Event Title *', 'What is this event?', Icons.event_rounded),
        const SizedBox(height: 12),
        _field(_descCtrl, 'Description', 'Tell people what this event is about...', Icons.description_rounded, maxLines: 4),
        const SizedBox(height: 16),
        const Text('Event Type', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        const SizedBox(height: 8),
        Row(children: [['in_person', Icons.place_rounded, 'In-Person'], ['online', Icons.videocam_rounded, 'Online'], ['hybrid', Icons.merge_type_rounded, 'Hybrid']].map((e) { final type = e[0] as String; final icon = e[1] as IconData; final label = e[2] as String; return Expanded(child: GestureDetector(onTap: () => setState(() => _type = type), child: AnimatedContainer(duration: const Duration(milliseconds: 150), margin: const EdgeInsets.only(right: 6), padding: const EdgeInsets.symmetric(vertical: 10), decoration: BoxDecoration(color: _type == type ? AppTheme.orange : (dark ? AppTheme.dCard : Colors.white), borderRadius: BorderRadius.circular(10), border: Border.all(color: _type == type ? AppTheme.orange : Colors.transparent)), child: Column(children: [Icon(icon, color: _type == type ? Colors.white : Colors.grey, size: 20), const SizedBox(height: 4), Text(label, style: TextStyle(color: _type == type ? Colors.white : Colors.grey, fontSize: 11, fontWeight: FontWeight.w600), textAlign: TextAlign.center)])))); }).toList()),
        const SizedBox(height: 14),
        if (_type != 'online') ...[_field(_locCtrl, 'Location', 'Enter address or venue name', Icons.location_on_rounded), const SizedBox(height: 12)],
        if (_type != 'in_person') ...[_field(_linkCtrl, 'Online Link', 'https://meet.google.com/...', Icons.link_rounded), const SizedBox(height: 12)],
        _datePicker('Start Date & Time *', _start, () => _pickDate(true), fmt, required: true),
        const SizedBox(height: 10),
        _datePicker('End Date & Time', _end, () => _pickDate(false), fmt),
        const SizedBox(height: 16),
        const Text('Privacy', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        const SizedBox(height: 8),
        Row(children: [['public', Icons.public_rounded, 'Public'], ['followers', Icons.people_rounded, 'Followers'], ['private', Icons.lock_rounded, 'Private']].map((e) { final type = e[0] as String; final icon = e[1] as IconData; final label = e[2] as String; return Expanded(child: GestureDetector(onTap: () => setState(() => _privacy = type), child: AnimatedContainer(duration: const Duration(milliseconds: 150), margin: const EdgeInsets.only(right: 6), padding: const EdgeInsets.symmetric(vertical: 8), decoration: BoxDecoration(color: _privacy == type ? AppTheme.orangeSurf : (dark ? AppTheme.dCard : Colors.white), borderRadius: BorderRadius.circular(10), border: Border.all(color: _privacy == type ? AppTheme.orange : Colors.transparent)), child: Column(children: [Icon(icon, color: _privacy == type ? AppTheme.orange : Colors.grey, size: 18), const SizedBox(height: 3), Text(label, style: TextStyle(color: _privacy == type ? AppTheme.orange : Colors.grey, fontSize: 11, fontWeight: _privacy == type ? FontWeight.w700 : FontWeight.w500), textAlign: TextAlign.center)])))); }).toList()),
        const SizedBox(height: 30),
      ])),
    );
  }

  Widget _field(TextEditingController ctrl, String label, String hint, IconData icon, {int maxLines = 1}) => TextField(controller: ctrl, maxLines: maxLines, decoration: InputDecoration(labelText: label, hintText: hint, prefixIcon: Icon(icon, size: 20, color: AppTheme.orange)));

  Widget _datePicker(String label, DateTime? dt, VoidCallback onTap, DateFormat fmt, {bool required = false}) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(onTap: onTap, child: Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: dt != null ? AppTheme.orange : (dark ? AppTheme.dDiv : const Color(0xFFEEEEEE)))),
      child: Row(children: [Icon(Icons.access_time_rounded, color: dt != null ? AppTheme.orange : Colors.grey, size: 20), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: TextStyle(fontSize: 11, color: dt != null ? AppTheme.orange : Colors.grey)), const SizedBox(height: 2), Text(dt != null ? fmt.format(dt) : 'Tap to select', style: TextStyle(fontWeight: dt != null ? FontWeight.w600 : FontWeight.w400, color: dt != null ? null : Colors.grey))])), if (dt != null) GestureDetector(onTap: () => setState(() { if (label.contains('Start')) _start = null; else _end = null; }), child: const Icon(Icons.close_rounded, size: 16, color: Colors.grey))])));
  }
}
