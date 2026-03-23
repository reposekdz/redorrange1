
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';

final smartReplyProvider = Provider<SmartReplyService>((ref) => SmartReplyService(ref));

class SmartReplyService {
  final Ref _ref;
  SmartReplyService(this._ref);

  Future<List<String>> getFor(String messageId) async {
    try {
      final r = await _ref.read(apiServiceProvider).get('/messages/$messageId/smart-replies');
      return List<String>.from(r.data['suggestions'] ?? []);
    } catch (_) {
      return ['👍', 'Got it!', 'Thanks'];
    }
  }

  List<String> localSuggestions(String text) {
    final t = text.toLowerCase().trim();
    if (t.contains('how are you') || t.contains('how r u')) return ["I'm great!", 'Pretty good! You?', 'All good 😊'];
    if (t.contains('thank') || t.contains('thanks')) return ["You're welcome!", 'No problem!', 'Anytime!'];
    if (t.contains('hello') || t.contains('hi') || t.contains('hey')) return ['Hey! 👋', 'Hello!', 'Hi there!'];
    if (t.contains('ok') || t.contains('okay') || t.contains('sure')) return ['Sounds good!', 'Perfect ✅', 'Got it!'];
    if (t.contains('when') || t.contains('what time')) return ['Let me check', 'Around 3pm?', 'What works for you?'];
    if (t.contains('love') || t.contains('miss')) return ['❤️', 'Miss you too!', '😊'];
    if (t.contains('good morning')) return ['Good morning! ☀️', 'Morning! How are you?', '☀️'];
    if (t.contains('good night')) return ['Good night! 🌙', 'Sleep well!', '🌙'];
    if (t.contains('?')) return ['Yes', 'No', 'Let me check'];
    return ['👍', 'Got it!', 'OK sure'];
  }
}
