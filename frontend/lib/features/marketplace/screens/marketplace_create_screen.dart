// marketplace_create_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/api_service.dart';
import 'package:dio/dio.dart';

class MarketplaceCreateScreen extends ConsumerStatefulWidget {
  const MarketplaceCreateScreen({super.key});
  @override ConsumerState<MarketplaceCreateScreen> createState() => _S();
}
class _S extends ConsumerState<MarketplaceCreateScreen> {
  final _titleCtrl = TextEditingController();
  final _descCtrl  = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _locCtrl   = TextEditingController();
  String _category = 'Other';
  String _condition = 'used';
  String _currency = 'USD';
  List<File> _images = [];
  bool _saving = false;
  String? _error;

  final _cats = ['Electronics','Clothing','Furniture','Vehicles','Books','Sports','Tools','Baby','Pets','Garden','Other'];
  final _conditions = ['new', 'used', 'refurbished'];

  @override
  void dispose() { _titleCtrl.dispose(); _descCtrl.dispose(); _priceCtrl.dispose(); _locCtrl.dispose(); super.dispose(); }

  Future<void> _pickImages() async {
    final imgs = await ImagePicker().pickMultiImage(imageQuality: 85);
    if (imgs.isNotEmpty) setState(() => _images = [..._images, ...imgs.map((x) => File(x.path))].take(10).toList());
  }

  Future<void> _submit() async {
    if (_titleCtrl.text.trim().isEmpty) { setState(() => _error = 'Title required'); return; }
    setState(() { _saving = true; _error = null; });
    try {
      final fd = FormData.fromMap({
        'title': _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'price': _priceCtrl.text.trim().isEmpty ? null : _priceCtrl.text.trim(),
        'currency': _currency,
        'category': _category,
        'condition_type': _condition,
        'location': _locCtrl.text.trim(),
        if (_images.isNotEmpty)
          'images': await Future.wait(_images.map((f) => MultipartFile.fromFile(f.path, filename: f.path.split('/').last))),
      });
      final r = await ref.read(apiServiceProvider).upload('/marketplace', fd);
      if (r.data['success'] == true && mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Item listed successfully!')));
      }
    } catch (e) { setState(() => _error = 'Failed: ${e.toString().substring(0, 60)}'); }
    finally { if (mounted) setState(() => _saving = false); }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('List an Item', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          TextButton(
            onPressed: _saving ? null : _submit,
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.orange))
                : const Text('Post', style: TextStyle(color: AppTheme.orange, fontWeight: FontWeight.w700, fontSize: 16)),
          ),
        ],
      ),
      body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Images
        _Label('Photos (up to 10)'),
        const SizedBox(height: 8),
        SizedBox(height: 100, child: ListView(scrollDirection: Axis.horizontal, children: [
          GestureDetector(onTap: _pickImages, child: Container(width: 100, height: 100, margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(color: dark ? AppTheme.dCard : AppTheme.lInput, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.orange.withOpacity(0.4), width: 1.5, style: BorderStyle.solid)),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.add_photo_alternate_rounded, color: AppTheme.orange, size: 28), const SizedBox(height: 4), Text('${_images.length}/10', style: const TextStyle(fontSize: 11, color: AppTheme.orange))]))),
          ..._images.asMap().entries.map((e) => Stack(children: [
            Container(width: 100, height: 100, margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
              child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(e.value, fit: BoxFit.cover))),
            Positioned(top: 4, right: 12, child: GestureDetector(onTap: () => setState(() => _images.removeAt(e.key)),
              child: Container(width: 22, height: 22, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                child: const Icon(Icons.close_rounded, color: Colors.white, size: 14)))),
          ])),
        ])),
        const SizedBox(height: 16),

        _Label('Title *'), const SizedBox(height: 6),
        TextField(controller: _titleCtrl, decoration: const InputDecoration(hintText: 'What are you selling?')),
        const SizedBox(height: 14),

        _Label('Description'), const SizedBox(height: 6),
        TextField(controller: _descCtrl, maxLines: 4, decoration: const InputDecoration(hintText: 'Describe your item, condition, etc...')),
        const SizedBox(height: 14),

        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _Label('Price'), const SizedBox(height: 6),
            TextField(controller: _priceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: '0.00', prefixText: '$ ')),
          ])),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _Label('Currency'), const SizedBox(height: 6),
            DropdownButton<String>(value: _currency, onChanged: (v) => setState(() => _currency = v!),
              items: ['USD','EUR','GBP','RWF','KES','NGN','ZAR','GHS'].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList()),
          ]),
        ]),
        const SizedBox(height: 14),

        _Label('Category'), const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 6, children: _cats.map((c) => ChoiceChip(label: Text(c, style: const TextStyle(fontSize: 12)), selected: _category == c, onSelected: (s) => setState(() => _category = c), selectedColor: AppTheme.orange, labelStyle: TextStyle(color: _category == c ? Colors.white : null))).toList()),
        const SizedBox(height: 14),

        _Label('Condition'), const SizedBox(height: 8),
        Row(children: _conditions.map((c) => Padding(padding: const EdgeInsets.only(right: 10), child: ChoiceChip(label: Text(c[0].toUpperCase() + c.substring(1), style: const TextStyle(fontSize: 12)), selected: _condition == c, onSelected: (_) => setState(() => _condition = c), selectedColor: AppTheme.orange, labelStyle: TextStyle(color: _condition == c ? Colors.white : null)))).toList()),
        const SizedBox(height: 14),

        _Label('Location'), const SizedBox(height: 6),
        TextField(controller: _locCtrl, decoration: const InputDecoration(hintText: 'City, Area', prefixIcon: Icon(Icons.location_on_rounded, size: 18))),

        if (_error != null) ...[const SizedBox(height: 12), Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: Text(_error!, style: const TextStyle(color: Colors.red)))],
        const SizedBox(height: 24),
        SizedBox(width: double.infinity, child: ElevatedButton.icon(onPressed: _saving ? null : _submit, icon: const Icon(Icons.sell_rounded), label: Text(_saving ? 'Publishing...' : 'List for Sale'))),
        const SizedBox(height: 30),
      ])),
    );
  }
  Widget _Label(String t) => Text(t, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13));
}
