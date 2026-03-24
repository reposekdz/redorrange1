
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/api_service.dart';

class ReportScreen extends ConsumerStatefulWidget {
  final String targetType, targetId;
  const ReportScreen({super.key, required this.targetType, required this.targetId});
  @override ConsumerState<ReportScreen> createState() => _S();
}
class _S extends ConsumerState<ReportScreen> {
  String? _reason; final _detailCtrl = TextEditingController(); bool _submitting = false;
  static const _reasons = ['Spam','Nudity or sexual activity','Hate speech or symbols','Violence or dangerous organizations','Bullying or harassment','Selling illegal or regulated goods','Intellectual property violation','Eating disorders','Suicide or self-injury','Misinformation','Other'];
  @override void dispose() { _detailCtrl.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: Text('Report ${widget.targetType[0].toUpperCase()}${widget.targetType.substring(1)}', style: const TextStyle(fontWeight: FontWeight.w800))),
      body: Column(children: [
        Container(margin: const EdgeInsets.all(14), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: dark ? AppTheme.dCard : AppTheme.lInput, borderRadius: BorderRadius.circular(12)), child: const Text('Your report is anonymous. We review all reports and take action on content that violates our Community Guidelines.', style: TextStyle(fontSize: 13, height: 1.4))),
        Expanded(child: ListView(children: [
          ..._reasons.map((r) => RadioListTile<String>(value: r, groupValue: _reason, onChanged: (v) => setState(() => _reason = v), title: Text(r, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)), activeColor: AppTheme.orange)),
          if (_reason == 'Other') Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: TextField(controller: _detailCtrl, maxLines: 4, maxLength: 500, decoration: const InputDecoration(hintText: 'Provide more details...', border: OutlineInputBorder()))),
        ])),
        Padding(padding: const EdgeInsets.all(14), child: SizedBox(width: double.infinity, child: ElevatedButton(
          onPressed: (_reason == null || _submitting) ? null : () async {
            setState(() => _submitting = true);
            await ref.read(apiServiceProvider).post('/interactions/report', data: {'target_type': widget.targetType, 'target_id': widget.targetId, 'reason': _reason, 'details': _detailCtrl.text.trim()}).catchError((_){});
            if (mounted) { context.pop(); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report submitted. Thank you for keeping RedOrrange safe.'))); }
          },
          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), backgroundColor: Colors.red),
          child: _submitting ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2) : const Text('Submit Report', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        ))),
      ]),
    );
  }
}
