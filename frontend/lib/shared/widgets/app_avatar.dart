import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/theme/app_theme.dart';

class AppAvatar extends StatelessWidget {
  final String? url;
  final double size;
  final String? username;
  final bool showOnline;
  final bool isOnline;
  final bool showBorder;
  final Color? borderColor;
  final double borderWidth;

  const AppAvatar({
    super.key,
    this.url,
    this.size = 44,
    this.username,
    this.showOnline = false,
    this.isOnline = false,
    this.showBorder = false,
    this.borderColor,
    this.borderWidth = 2,
  });

  String get _initials {
    if (username == null || username!.isEmpty) return '?';
    return username![0].toUpperCase();
  }

  Color get _bgColor {
    if (username == null || username!.isEmpty) return AppTheme.orange;
    final colors = [AppTheme.orange, const Color(0xFF2196F3), const Color(0xFF4CAF50), const Color(0xFF9C27B0), const Color(0xFFE91E63), const Color(0xFFFF9800)];
    return colors[username!.codeUnitAt(0) % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final avatar = _buildAvatar();
    if (!showOnline) return avatar;
    return Stack(children: [
      avatar,
      Positioned(
        bottom: 0, right: 0,
        child: Container(
          width: size * 0.28,
          height: size * 0.28,
          decoration: BoxDecoration(
            color: isOnline ? AppTheme.orange : Colors.grey,
            shape: BoxShape.circle,
            border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 1.5),
          ),
        ),
      ),
    ]);
  }

  Widget _buildAvatar() {
    Widget child;
    if (url != null && url!.isNotEmpty) {
      child = CachedNetworkImage(
        imageUrl: url!,
        width: size, height: size,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(color: _bgColor, child: Center(child: Text(_initials, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: size * 0.4)))),
        errorWidget: (_, __, ___) => Container(color: _bgColor, child: Center(child: Text(_initials, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: size * 0.4)))),
      );
    } else {
      child = Container(color: _bgColor, child: Center(child: Text(_initials, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: size * 0.4))));
    }
    return ClipOval(
      child: showBorder ? Container(
        width: size, height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: borderColor ?? AppTheme.orange, width: borderWidth)),
        child: child,
      ) : SizedBox(width: size, height: size, child: child),
    );
  }
}

class StoryRing extends StatelessWidget {
  final Widget child;
  final bool hasStory;
  final bool isCloseFriend;
  final bool isViewed;
  final double size;

  const StoryRing({super.key, required this.child, this.hasStory = false, this.isCloseFriend = false, this.isViewed = false, this.size = 64});

  @override
  Widget build(BuildContext context) {
    if (!hasStory) return child;
    final color = isViewed ? Colors.grey : (isCloseFriend ? const Color(0xFF4CAF50) : AppTheme.orange);
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, gradient: isViewed ? null : LinearGradient(colors: isCloseFriend ? [const Color(0xFF4CAF50), const Color(0xFF2E7D32)] : [AppTheme.orange, AppTheme.orangeDark, const Color(0xFFFF1744)], begin: Alignment.topLeft, end: Alignment.bottomRight)),
      child: Padding(padding: const EdgeInsets.all(2.5), child: Container(decoration: BoxDecoration(shape: BoxShape.circle, color: Theme.of(context).scaffoldBackgroundColor), child: Padding(padding: const EdgeInsets.all(2), child: child))),
    );
  }
}

class OrangeButton extends StatelessWidget {
  final String label; final VoidCallback? onPressed; final bool loading; final IconData? icon;
  const OrangeButton({super.key, required this.label, this.onPressed, this.loading = false, this.icon});
  @override Widget build(BuildContext _) => ElevatedButton(
    onPressed: loading ? null : onPressed,
    child: loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
      : (icon != null ? Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon!, size: 18), const SizedBox(width: 6), Text(label, style: const TextStyle(fontWeight: FontWeight.w700))]) : Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
  );
}

class SkeletonBox extends StatefulWidget {
  final double width, height, radius;
  const SkeletonBox({super.key, required this.width, required this.height, this.radius = 8});
  @override State<SkeletonBox> createState() => _SKS();
}
class _SKS extends State<SkeletonBox> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _a;
  @override void initState() { super.initState(); _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true); _a = CurvedAnimation(parent: _c, curve: Curves.easeInOut); }
  @override void dispose() { _c.dispose(); super.dispose(); }
  @override Widget build(BuildContext ctx) {
    final dark = Theme.of(ctx).brightness == Brightness.dark;
    return AnimatedBuilder(animation: _a, builder: (_, __) => Container(width: widget.width, height: widget.height,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(widget.radius),
        color: Color.lerp(dark ? const Color(0xFF2A2A2A) : const Color(0xFFE0E0E0), dark ? const Color(0xFF383838) : const Color(0xFFF5F5F5), _a.value))));
  }
}
