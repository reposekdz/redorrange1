import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:camera/camera.dart';
import 'dart:io';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/api_service.dart';
import 'package:dio/dio.dart';

class CreateStoryScreen extends ConsumerStatefulWidget {
  const CreateStoryScreen({super.key});
  @override ConsumerState<CreateStoryScreen> createState() => _S();
}
class _S extends ConsumerState<CreateStoryScreen> {
  File? _media;
  String _mediaType = 'image'; // image or video
  String? _caption;
  String _audience = 'everyone'; // everyone, close_friends, custom
  Color _bgColor = AppTheme.orange;
  String _textOverlay = '';
  double _textSize   = 18;
  Color _textColor   = Colors.white;
  bool _uploading    = false;
  bool _showTextTool = false;

  final _textCtrl = TextEditingController();
  final _captionCtrl = TextEditingController();

  static const _bgColors = [
    AppTheme.orange, Color(0xFF9C27B0), Color(0xFF2196F3), Color(0xFF4CAF50),
    Color(0xFFFF5722), Color(0xFF607D8B), Color(0xFF795548), Color(0xFF000000),
    Color(0xFFFFFFFF), Color(0xFFE91E63), Color(0xFF00BCD4), Color(0xFF8BC34A),
  ];

  @override void dispose() { _textCtrl.dispose(); _captionCtrl.dispose(); super.dispose(); }

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final f = await picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (f != null && mounted) setState(() { _media = File(f.path); _mediaType = 'image'; });
  }

  Future<void> _pickVideoFromGallery() async {
    final f = await ImagePicker().pickVideo(source: ImageSource.gallery, maxDuration: const Duration(seconds: 60));
    if (f != null && mounted) setState(() { _media = File(f.path); _mediaType = 'video'; });
  }

  Future<void> _publish() async {
    setState(() => _uploading = true);
    try {
      final me = ref.read(currentUserProvider);
      final fd = FormData.fromMap({
        if (_media != null) 'media': await MultipartFile.fromFile(_media!.path, filename: _mediaType == 'video' ? 'story.mp4' : 'story.jpg'),
        if (_mediaType == 'image' && _media == null) 'bg_color': '#${_bgColor.value.toRadixString(16).substring(2).toUpperCase()}',
        if (_textOverlay.isNotEmpty) 'text_overlay': _textOverlay,
        if (_captionCtrl.text.isNotEmpty) 'caption': _captionCtrl.text.trim(),
        'audience': _audience,
        'media_type': _mediaType,
        'duration': '5',
      });
      await ref.read(apiServiceProvider).upload('/stories', fd);
      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Story published! 🎉'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
    if (mounted) setState(() => _uploading = false);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final h    = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        // ── PREVIEW
        Positioned.fill(child: _media != null
          ? _mediaType == 'video'
            ? Container(color: Colors.black, child: const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white38, size: 72)))
            : Image.file(_media!, fit: BoxFit.cover, width: double.infinity, height: double.infinity)
          : Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [_bgColor, _bgColor.withOpacity(0.7)], begin: Alignment.topLeft, end: Alignment.bottomRight)), child: Center(child: _textOverlay.isNotEmpty ? Text(_textOverlay, style: TextStyle(color: _textColor, fontSize: _textSize, fontWeight: FontWeight.w800, shadows: const [Shadow(blurRadius: 8)]), textAlign: TextAlign.center) : const Icon(Icons.add_photo_alternate_rounded, color: Colors.white24, size: 72)))),

        // ── TOP BAR
        SafeArea(child: Column(children: [
          Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), child: Row(children: [
            GestureDetector(onTap: () => context.pop(), child: Container(width: 38, height: 38, decoration: const BoxDecoration(color: Colors.black38, shape: BoxShape.circle), child: const Icon(Icons.close_rounded, color: Colors.white, size: 22))),
            const Spacer(),
            // Audience selector
            GestureDetector(onTap: _showAudienceSheet, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7), decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(20)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(_audienceIcon, color: Colors.white, size: 14), const SizedBox(width: 5), Text(_audienceLabel, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)), const SizedBox(width: 3), const Icon(Icons.arrow_drop_down_rounded, color: Colors.white, size: 18)]))),
            const SizedBox(width: 8),
            // Text tool
            GestureDetector(onTap: () => setState(() => _showTextTool = !_showTextTool), child: Container(width: 38, height: 38, decoration: BoxDecoration(color: _showTextTool ? AppTheme.orange : Colors.black38, shape: BoxShape.circle), child: const Icon(Icons.title_rounded, color: Colors.white, size: 20))),
          ])),

          // ── TEXT OVERLAY TOOL
          if (_showTextTool) _TextTool(ctrl: _textCtrl, textColor: _textColor, textSize: _textSize, onDone: (text) { setState(() { _textOverlay = text; _showTextTool = false; }); }, onColorChange: (c) => setState(() => _textColor = c), onSizeChange: (s) => setState(() => _textSize = s)),
        ])),

        // ── BOTTOM CONTROLS
        Positioned(bottom: 0, left: 0, right: 0, child: SafeArea(child: Column(children: [
          // Background color picker (only when no media)
          if (_media == null) SingleChildScrollView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), child: Row(children: _bgColors.map((c) => GestureDetector(onTap: () => setState(() => _bgColor = c), child: AnimatedContainer(duration: const Duration(milliseconds: 150), width: _bgColor == c ? 36 : 30, height: _bgColor == c ? 36 : 30, margin: const EdgeInsets.only(right: 8), decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: _bgColor == c ? Colors.white : Colors.transparent, width: 2))))).toList())),

          // Caption input
          Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 10), child: Container(decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(24)), child: TextField(controller: _captionCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: 'Add a caption...', hintStyle: TextStyle(color: Colors.white38), contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10), border: InputBorder.none, isDense: true)))),

          // Action buttons
          Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 20), child: Row(children: [
            // Gallery
            _ActionBtn(Icons.photo_library_rounded, 'Gallery', () => _pickFromGallery()),
            const SizedBox(width: 12),
            // Video
            _ActionBtn(Icons.videocam_rounded, 'Video', () => _pickVideoFromGallery()),
            const SizedBox(width: 12),
            // Camera
            _ActionBtn(Icons.camera_alt_rounded, 'Camera', () async {
              final cameras = await availableCameras().catchError((_) => <CameraDescription>[]);
              if (cameras.isEmpty) return;
              final f = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 90);
              if (f != null && mounted) setState(() { _media = File(f.path); _mediaType = 'image'; });
            }),

            const Spacer(),

            // PUBLISH button
            GestureDetector(
              onTap: _uploading ? null : _publish,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                decoration: BoxDecoration(color: AppTheme.orange, borderRadius: BorderRadius.circular(30), boxShadow: [BoxShadow(color: AppTheme.orange.withOpacity(0.4), blurRadius: 16, spreadRadius: 2)]),
                child: _uploading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Row(mainAxisSize: MainAxisSize.min, children: [Text('Share', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)), SizedBox(width: 6), Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 14)]),
              ),
            ),
          ])),
        ]))),

        // ── REMOVE MEDIA BUTTON
        if (_media != null) Positioned(top: 80, right: 14, child: SafeArea(child: GestureDetector(onTap: () => setState(() => _media = null), child: Container(padding: const EdgeInsets.all(6), decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle), child: const Icon(Icons.close_rounded, color: Colors.white, size: 18))))),
      ]),
    );
  }

  IconData get _audienceIcon {
    switch (_audience) {
      case 'close_friends': return Icons.people_rounded;
      case 'custom':        return Icons.tune_rounded;
      default:              return Icons.public_rounded;
    }
  }
  String get _audienceLabel {
    switch (_audience) {
      case 'close_friends': return 'Close Friends';
      case 'custom':        return 'Custom';
      default:              return 'Everyone';
    }
  }

  void _showAudienceSheet() {
    showModalBottomSheet(context: context, backgroundColor: Colors.black87, builder: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
      const Padding(padding: EdgeInsets.all(16), child: Text('Story Audience', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16))),
      ListTile(leading: const Icon(Icons.public_rounded, color: Colors.white), title: const Text('Everyone', style: TextStyle(color: Colors.white)), subtitle: const Text('All your followers', style: TextStyle(color: Colors.grey)), trailing: _audience == 'everyone' ? const Icon(Icons.check_circle_rounded, color: AppTheme.orange) : null, onTap: () { setState(() => _audience = 'everyone'); Navigator.pop(context); }),
      ListTile(leading: const Icon(Icons.people_rounded, color: Color(0xFF4CAF50)), title: const Text('Close Friends', style: TextStyle(color: Colors.white)), subtitle: const Text('Only people on your close friends list', style: TextStyle(color: Colors.grey)), trailing: _audience == 'close_friends' ? const Icon(Icons.check_circle_rounded, color: AppTheme.orange) : null, onTap: () { setState(() => _audience = 'close_friends'); Navigator.pop(context); }),
      const SizedBox(height: 20),
    ]));
  }
}

class _TextTool extends StatefulWidget {
  final TextEditingController ctrl;
  final Color textColor; final double textSize;
  final void Function(String) onDone;
  final void Function(Color) onColorChange;
  final void Function(double) onSizeChange;
  const _TextTool({required this.ctrl, required this.textColor, required this.textSize, required this.onDone, required this.onColorChange, required this.onSizeChange});
  @override State<_TextTool> createState() => _TTS();
}
class _TTS extends State<_TextTool> {
  static const _colors = [Colors.white, Colors.black, AppTheme.orange, Colors.yellow, Color(0xFF00BCD4), Colors.pink, Color(0xFF9C27B0), Colors.green, Colors.red];
  @override Widget build(BuildContext _) => Container(color: Colors.black38, padding: const EdgeInsets.all(12), child: Column(children: [
    Row(children: [
      Expanded(child: Slider(value: widget.textSize, min: 12, max: 48, activeColor: AppTheme.orange, inactiveColor: Colors.white24, onChanged: widget.onSizeChange)),
      GestureDetector(onTap: () => widget.onDone(widget.ctrl.text), child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), decoration: BoxDecoration(color: AppTheme.orange, borderRadius: BorderRadius.circular(10)), child: const Text('Done', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)))),
    ]),
    TextField(controller: widget.ctrl, autofocus: true, textAlign: TextAlign.center, style: TextStyle(color: widget.textColor, fontSize: widget.textSize, fontWeight: FontWeight.w800), decoration: const InputDecoration(border: InputBorder.none, hintText: 'Type something...', hintStyle: TextStyle(color: Colors.white24))),
    SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: _colors.map((c) => GestureDetector(onTap: () => widget.onColorChange(c), child: Container(width: 28, height: 28, margin: const EdgeInsets.only(right: 8), decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: widget.textColor == c ? Colors.white : Colors.transparent, width: 2))))).toList())),
  ]));
}

class _ActionBtn extends StatelessWidget {
  final IconData icon; final String label; final VoidCallback onTap;
  const _ActionBtn(this.icon, this.label, this.onTap);
  @override Widget build(BuildContext _) => GestureDetector(onTap: onTap, child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(20)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: Colors.white, size: 18), const SizedBox(width: 5), Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13))])));
}
