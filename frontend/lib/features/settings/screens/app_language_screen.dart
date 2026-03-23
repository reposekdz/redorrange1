
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/api_service.dart';

class AppLanguageScreen extends ConsumerStatefulWidget {
  const AppLanguageScreen({super.key});
  @override ConsumerState<AppLanguageScreen> createState() => _S();
}
class _S extends ConsumerState<AppLanguageScreen> {
  String _selected = 'en';
  static const _langs = [('en','English','🇬🇧'),('rw','Kinyarwanda','🇷🇼'),('fr','Français','🇫🇷'),('sw','Kiswahili','🇹🇿'),('ar','العربية','🇸🇦'),('es','Español','🇪🇸'),('pt','Português','🇵🇹'),('de','Deutsch','🇩🇪'),('zh','中文','🇨🇳'),('hi','हिंदी','🇮🇳'),('ja','日本語','🇯🇵'),('ko','한국어','🇰🇷')];

  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Language', style: TextStyle(fontWeight: FontWeight.w800))),
    body: Column(children: [
      Container(margin: const EdgeInsets.all(12), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: AppTheme.orangeSurf, borderRadius: BorderRadius.circular(12)), child: const Row(children: [Icon(Icons.language_rounded, color: AppTheme.orange, size: 20), SizedBox(width: 8), Expanded(child: Text('Choose your preferred language for the app interface.', style: TextStyle(color: AppTheme.orangeDark, fontSize: 12)))])),
      Expanded(child: ListView(_langs.map(((code, name, flag)) => RadioListTile<String>(
        value: code, groupValue: _selected,
        onChanged: (v) async { setState(() => _selected = v!); await ref.read(apiServiceProvider).put('/settings', data: {'language': v}).catchError((_){}); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Language set to $name'))); },
        title: Text('$flag  $name', style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
        activeColor: AppTheme.orange,
      )).toList())),
    ]),
  );
}
