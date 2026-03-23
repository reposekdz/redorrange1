import 'package:intl/intl.dart';

class FormatUtils {
  static String count(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(n % 1000000 == 0 ? 0 : 1)}M';
    if (n >= 1000)    return '${(n / 1000).toStringAsFixed(n % 1000 == 0 ? 0 : 1)}K';
    return n.toString();
  }

  static String fileSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1073741824) return '${(bytes / 1048576).toStringAsFixed(1)}MB';
    return '${(bytes / 1073741824).toStringAsFixed(1)}GB';
  }

  static String dur(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) return '${h}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  static String date(String? ts) {
    if (ts == null) return '';
    try {
      final d = DateTime.parse(ts).toLocal();
      final now = DateTime.now();
      if (d.year == now.year && d.month == now.month && d.day == now.day) return DateFormat('h:mm a').format(d);
      if (d.year == now.year) return DateFormat('MMM d').format(d);
      return DateFormat('MMM d, y').format(d);
    } catch (_) { return ''; }
  }

  static String price(double? price, [String currency = 'USD']) {
    if (price == null) return 'Free';
    return '$currency ${NumberFormat('#,##0.00').format(price)}';
  }

  static String relativeTime(String? ts) {
    if (ts == null) return '';
    try {
      final d = DateTime.parse(ts).toLocal();
      final diff = DateTime.now().difference(d);
      if (diff.inSeconds < 60) return 'just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return DateFormat('MMM d').format(d);
    } catch (_) { return ''; }
  }
}
