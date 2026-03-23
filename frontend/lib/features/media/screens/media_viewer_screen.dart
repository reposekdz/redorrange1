import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/models.dart';
import '../../../shared/utils/format_utils.dart';

class MediaViewerScreen extends StatefulWidget {
  final List<MediaItem> media;
  final int initialIndex;
  const MediaViewerScreen({super.key, required this.media, this.initialIndex = 0});
  @override State<MediaViewerScreen> createState() => _S();
}
class _S extends State<MediaViewerScreen> {
  late int _idx;
  late PageController _pc;
  bool _showUi = true;

  @override
  void initState() {
    super.initState();
    _idx = widget.initialIndex;
    _pc  = PageController(initialPage: _idx);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _pc.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.media;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => setState(() => _showUi = !_showUi),
        child: Stack(children: [
          // Gallery
          PhotoViewGallery.builder(
            pageController: _pc,
            itemCount: m.length,
            onPageChanged: (i) => setState(() => _idx = i),
            scrollPhysics: const BouncingScrollPhysics(),
            builder: (_, i) {
              final item = m[i];
              if (item.mediaType == 'video') {
                return PhotoViewGalleryPageOptions.customChild(
                  child: Container(color: Colors.black, child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.play_circle_fill_rounded, color: Colors.white54, size: 80),
                    const SizedBox(height: 12),
                    const Text('Video', style: TextStyle(color: Colors.white38, fontSize: 16)),
                    if (item.duration != null) Text(FormatUtils.dur(item.duration!), style: const TextStyle(color: Colors.white38, fontSize: 13)),
                  ]))),
                  minScale: PhotoViewComputedScale.contained,
                  maxScale: PhotoViewComputedScale.covered * 2,
                );
              }
              return PhotoViewGalleryPageOptions(
                imageProvider: CachedNetworkImageProvider(item.mediaUrl),
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 3,
                heroAttributes: PhotoViewHeroAttributes(tag: item.mediaUrl),
              );
            },
            loadingBuilder: (_, event) => const Center(child: CircularProgressIndicator(color: AppTheme.orange)),
          ),

          // Top bar
          AnimatedOpacity(
            opacity: _showUi ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 250),
            child: SafeArea(child: Row(children: [
              IconButton(icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 26), onPressed: () => Navigator.pop(context)),
              const Spacer(),
              if (m.length > 1) Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(14)), child: Text('${_idx + 1} / ${m.length}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
              const SizedBox(width: 8),
              IconButton(icon: const Icon(Icons.download_rounded, color: Colors.white, size: 24), onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Downloading...')))),
              IconButton(icon: const Icon(Icons.more_vert_rounded, color: Colors.white, size: 24), onPressed: () => _showOptions(context)),
            ])),
          ),

          // Bottom dots
          if (m.length > 1) AnimatedOpacity(
            opacity: _showUi ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 250),
            child: Positioned(bottom: 40, left: 0, right: 0, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(m.length, (i) => AnimatedContainer(duration: const Duration(milliseconds: 200), width: _idx == i ? 18 : 7, height: 7, margin: const EdgeInsets.symmetric(horizontal: 3), decoration: BoxDecoration(color: _idx == i ? AppTheme.orange : Colors.white38, borderRadius: BorderRadius.circular(4)))))),
          ),

          // Media info
          if (m[_idx].width != null && m[_idx].height != null) AnimatedOpacity(
            opacity: _showUi ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 250),
            child: Positioned(bottom: 20, right: 16, child: Text('${m[_idx].width} × ${m[_idx].height}', style: const TextStyle(color: Colors.white38, fontSize: 11))),
          ),
        ]),
      ),
    );
  }

  void _showOptions(BuildContext context) {
    showModalBottomSheet(context: context, backgroundColor: Colors.black87, builder: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
      const SizedBox(height: 8),
      ListTile(leading: const Icon(Icons.download_rounded, color: AppTheme.orange), title: const Text('Download', style: TextStyle(color: Colors.white)), onTap: () { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Downloading...'))); }),
      ListTile(leading: const Icon(Icons.share_rounded, color: AppTheme.orange), title: const Text('Share', style: TextStyle(color: Colors.white)), onTap: () => Navigator.pop(context)),
      ListTile(leading: const Icon(Icons.copy_rounded, color: AppTheme.orange), title: const Text('Copy URL', style: TextStyle(color: Colors.white)), onTap: () { Clipboard.setData(ClipboardData(text: widget.media[_idx].mediaUrl)); Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('URL copied'))); }),
      const SizedBox(height: 14),
    ]));
  }
}
