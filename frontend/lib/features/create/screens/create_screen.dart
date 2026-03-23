import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:io';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/api_service.dart';
import 'package:dio/dio.dart';

class CreateScreen extends ConsumerStatefulWidget {
  const CreateScreen({super.key});
  @override ConsumerState<CreateScreen> createState() => _CS();
}
class _CS extends ConsumerState<CreateScreen> with SingleTickerProviderStateMixin {
  late TabController _tc;
  @override void initState() { super.initState(); _tc = TabController(length: 3, vsync: this); }
  @override void dispose() { _tc.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: const Text('Create', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
      leading: IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white), onPressed: () => context.go('/')),
      bottom: TabBar(controller: _tc, indicatorColor: AppTheme.orange, labelColor: Colors.white, unselectedLabelColor: Colors.white54, tabs: const [Tab(text: 'Post'), Tab(text: 'Reel'), Tab(text: 'Story')]),
    ),
    body: TabBarView(controller: _tc, children: const [
      _PostEditor(),
      _ReelEditor(),
      _StoryEditor(),
    ]),
  );
}

// ─────────────────────────────────────────
// POST EDITOR
// ─────────────────────────────────────────
class _PostEditor extends ConsumerStatefulWidget {
  const _PostEditor();
  @override ConsumerState<_PostEditor> createState() => _PE();
}
class _PE extends ConsumerState<_PostEditor> {
  List<File> _images = [];
  final _capCtrl   = TextEditingController();
  final _locCtrl   = TextEditingController();
  final _tagCtrl   = TextEditingController();
  String? _textOverlay; Color _overlayColor = Colors.white;
  double _textSize = 18;
  bool _isPublic = true, _allowComments = true;
  bool _uploading = false; double _progress = 0;
  List<String> _hashtags = [];
  List<Map<String,dynamic>> _taggedUsers = [];

  @override void dispose() { _capCtrl.dispose(); _locCtrl.dispose(); _tagCtrl.dispose(); super.dispose(); }

  Future<void> _pickImages() async {
    final imgs = await ImagePicker().pickMultiImage(imageQuality: 90);
    if (imgs.isNotEmpty) setState(() => _images = [..._images, ...imgs.map((x) => File(x.path))].take(10).toList());
  }

  Future<void> _pickCamera() async {
    final img = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 90);
    if (img != null) setState(() => _images = [..._images, File(img.path)].take(10).toList());
  }

  void _parseHashtags(String text) {
    final tags = RegExp(r'#(\w+)').allMatches(text).map((m) => m.group(1)!).toList();
    setState(() => _hashtags = tags);
  }

  Future<void> _post() async {
    if (_images.isEmpty) { _showSnack('Add at least one photo'); return; }
    setState(() { _uploading = true; _progress = 0; });
    try {
      final fd = FormData.fromMap({
        'caption': _capCtrl.text.trim(),
        'location': _locCtrl.text.trim(),
        'is_public': _isPublic ? '1' : '0',
        'allow_comments': _allowComments ? '1' : '0',
        'type': 'image',
        'post_media': await Future.wait(_images.map((f) => MultipartFile.fromFile(f.path, filename: f.path.split('/').last))),
      });
      final r = await ref.read(apiServiceProvider).upload('/posts', fd, onProgress: (s, t) => setState(() => _progress = s / t));
      if (r.data['success'] == true && mounted) {
        context.go('/');
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Posted successfully!')));
      }
    } catch (e) { _showSnack('Upload failed: ${e.toString().substring(0, 60)}'); }
    finally { if (mounted) setState(() => _uploading = false); }
  }

  void _showSnack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: SingleChildScrollView(child: Column(children: [
      // Image picker area
      GestureDetector(
        onTap: _images.isEmpty ? null : () {},
        child: Container(
          height: 340,
          color: const Color(0xFF111111),
          child: _images.isEmpty
            ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.add_photo_alternate_rounded, size: 64, color: Colors.white54),
                const SizedBox(height: 12), const Text('Add photos', style: TextStyle(color: Colors.white54, fontSize: 16)),
                const SizedBox(height: 20),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  _PickBtn(Icons.photo_library_rounded, 'Gallery', () => _pickImages()),
                  const SizedBox(width: 16),
                  _PickBtn(Icons.camera_alt_rounded, 'Camera', () => _pickCamera()),
                ]),
              ]))
            : Stack(children: [
                // Preview grid
                _images.length == 1
                  ? Image.file(_images[0], width: double.infinity, height: 340, fit: BoxFit.cover)
                  : GridView.builder(padding: EdgeInsets.zero, gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 2, mainAxisSpacing: 2),
                      itemCount: _images.length, itemBuilder: (_, i) => Stack(children: [
                        Positioned.fill(child: Image.file(_images[i], fit: BoxFit.cover)),
                        Positioned(top: 4, right: 4, child: GestureDetector(onTap: () => setState(() => _images.removeAt(i)), child: Container(width: 22, height: 22, decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle), child: const Icon(Icons.close_rounded, color: Colors.white, size: 14)))),
                        if (i == 0) Positioned(bottom: 4, left: 4, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: AppTheme.orange, borderRadius: BorderRadius.circular(8)), child: const Text('Cover', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)))),
                      ])),

                // Text overlay preview
                if (_textOverlay != null && _textOverlay!.isNotEmpty)
                  Center(child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(8)), child: Text(_textOverlay!, style: TextStyle(color: _overlayColor, fontSize: _textSize, fontWeight: FontWeight.w700)))),

                // Bottom toolbar
                Positioned(bottom: 8, right: 8, child: Row(children: [
                  _ImgBtn(Icons.add_rounded, () { _images.length < 10 ? _pickImages() : null; }),
                  const SizedBox(width: 8),
                  _ImgBtn(Icons.text_fields_rounded, () => _showTextOverlay()),
                ])),

                // Image count
                if (_images.length > 1) Positioned(top: 8, right: 8, child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)), child: Text('${_images.length}/10', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)))),
              ]),
        ),
      ),

      // Form
      Container(color: const Color(0xFF111111), padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Caption
        TextField(
          controller: _capCtrl,
          maxLines: 5, minLines: 2,
          maxLength: 2200,
          style: const TextStyle(color: Colors.white, fontSize: 15),
          onChanged: (v) => _parseHashtags(v),
          decoration: InputDecoration(
            hintText: 'Write a caption... #hashtag @mention',
            hintStyle: TextStyle(color: Colors.white38),
            border: InputBorder.none, filled: false, counterStyle: const TextStyle(color: Colors.white38),
          ),
        ),

        // Hashtag chips
        if (_hashtags.isNotEmpty) Wrap(spacing: 6, runSpacing: 4, children: _hashtags.map((h) => Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: AppTheme.orange.withOpacity(0.2), borderRadius: BorderRadius.circular(14)), child: Text('#$h', style: const TextStyle(color: AppTheme.orange, fontSize: 12)))).toList()),
        const SizedBox(height: 12),

        const Divider(color: Colors.white12),

        // Location
        ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.location_on_rounded, color: AppTheme.orange, size: 20), title: TextField(controller: _locCtrl, style: const TextStyle(color: Colors.white, fontSize: 14), decoration: const InputDecoration(hintText: 'Add location', hintStyle: TextStyle(color: Colors.white38), border: InputBorder.none, filled: false, isDense: true))),
        const Divider(color: Colors.white12),

        // Audience
        ListTile(contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.public_rounded, color: AppTheme.orange, size: 20),
          title: const Text('Audience', style: TextStyle(color: Colors.white, fontSize: 14)),
          trailing: DropdownButton<bool>(value: _isPublic, dropdownColor: const Color(0xFF1E1E1E), style: const TextStyle(color: Colors.white, fontSize: 13),
            items: const [DropdownMenuItem(value: true, child: Text('Public')), DropdownMenuItem(value: false, child: Text('Followers Only'))],
            onChanged: (v) => setState(() => _isPublic = v!),
          )),
        const Divider(color: Colors.white12),
        SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, title: const Text('Allow Comments', style: TextStyle(color: Colors.white, fontSize: 14)), secondary: const Icon(Icons.chat_bubble_outline_rounded, color: AppTheme.orange, size: 20), value: _allowComments, onChanged: (v) => setState(() => _allowComments = v), activeColor: AppTheme.orange),
        const Divider(color: Colors.white12),

        const SizedBox(height: 16),
        if (_uploading) Column(children: [
          LinearProgressIndicator(value: _progress, backgroundColor: Colors.white12, valueColor: const AlwaysStoppedAnimation(AppTheme.orange)),
          const SizedBox(height: 8), Text('Uploading ${(_progress * 100).toStringAsFixed(0)}%...', style: const TextStyle(color: AppTheme.orange, fontSize: 13)),
          const SizedBox(height: 12),
        ]),
        SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _uploading ? null : _post, child: Text(_uploading ? 'Posting...' : 'Share Post', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)))),
      ])),
    ])),
  );

  void _showTextOverlay() {
    final ctrl = TextEditingController(text: _textOverlay ?? '');
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.black, builder: (_) => Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom), child: Container(padding: const EdgeInsets.all(16), child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('Add Text Overlay', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
      const SizedBox(height: 12),
      TextField(controller: ctrl, style: const TextStyle(color: Colors.white, fontSize: 16), autofocus: true, decoration: const InputDecoration(hintText: 'Enter text...', hintStyle: TextStyle(color: Colors.white38), filled: true, fillColor: Color(0xFF222222), border: OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.all(Radius.circular(12))))),
      const SizedBox(height: 12),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('Text size:', style: TextStyle(color: Colors.white70)),
        Expanded(child: Slider(value: _textSize, min: 12, max: 48, divisions: 9, onChanged: (v) => setState(() => _textSize = v), activeColor: AppTheme.orange, inactiveColor: Colors.white24)),
        Text('${_textSize.toInt()}', style: const TextStyle(color: Colors.white70)),
      ]),
      const SizedBox(height: 8),
      Row(children: [const Text('Color:', style: TextStyle(color: Colors.white70)), const SizedBox(width: 10), ...[ Colors.white, AppTheme.orange, Colors.yellow, Colors.cyan, Colors.pink, Colors.green].map((c) => GestureDetector(onTap: () => setState(() => _overlayColor = c), child: Container(width: 28, height: 28, margin: const EdgeInsets.symmetric(horizontal: 3), decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: _overlayColor == c ? Colors.white : Colors.transparent, width: 2)))))]),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: OutlinedButton(onPressed: () { setState(() => _textOverlay = null); Navigator.pop(context); }, style: OutlinedButton.styleFrom(foregroundColor: Colors.white), child: const Text('Remove'))),
        const SizedBox(width: 10),
        Expanded(child: ElevatedButton(onPressed: () { setState(() => _textOverlay = ctrl.text.trim()); Navigator.pop(context); }, child: const Text('Apply'))),
      ]),
    ]))));
  }
}

// ─────────────────────────────────────────
// REEL EDITOR
// ─────────────────────────────────────────
class _ReelEditor extends ConsumerStatefulWidget {
  const _ReelEditor();
  @override ConsumerState<_ReelEditor> createState() => _RE();
}
class _RE extends ConsumerState<_ReelEditor> {
  File? _video;
  VideoPlayerController? _vc;
  final _capCtrl = TextEditingController();
  String? _musicTitle, _musicArtist, _textOverlay;
  Color _textColor = Colors.white;
  double _textSize = 22;
  bool _uploading = false; double _progress = 0;
  @override void dispose() { _vc?.dispose(); _capCtrl.dispose(); super.dispose(); }

  Future<void> _pickVideo() async {
    final v = await ImagePicker().pickVideo(source: ImageSource.gallery, maxDuration: const Duration(seconds: 90));
    if (v != null) {
      _vc?.dispose();
      final vc = VideoPlayerController.file(File(v.path));
      await vc.initialize();
      setState(() { _video = File(v.path); _vc = vc; });
      vc.play(); vc.setLooping(true);
    }
  }

  Future<void> _pickMusic() async {
    // Show music picker dialog
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title: const Text('Add Music', style: TextStyle(color: Colors.white)),
      content: const Text('Music integration coming soon.\nYou can add audio files directly.', style: TextStyle(color: Colors.white70)),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK', style: TextStyle(color: AppTheme.orange)))],
    ));
  }

  Future<void> _postReel() async {
    if (_video == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a video first'))); return; }
    setState(() { _uploading = true; _progress = 0; });
    try {
      final fd = FormData.fromMap({
        'caption': _capCtrl.text.trim(),
        'type': 'reel',
        if (_musicTitle != null) 'music_title': _musicTitle,
        if (_musicArtist != null) 'music_artist': _musicArtist,
        'reel': await MultipartFile.fromFile(_video!.path, filename: 'reel.mp4'),
      });
      final r = await ref.read(apiServiceProvider).upload('/reels', fd, onProgress: (s, t) => setState(() => _progress = s / t));
      if (r.data['success'] == true && mounted) {
        context.go('/reels');
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Reel posted!')));
      }
    } catch (e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'))); }
    finally { if (mounted) setState(() => _uploading = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: Column(children: [
      // Video preview
      Expanded(child: _video == null
        ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.video_library_rounded, size: 80, color: Colors.white24),
            const SizedBox(height: 16), const Text('Select a video', style: TextStyle(color: Colors.white54, fontSize: 18)),
            const SizedBox(height: 24),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _PickBtn(Icons.video_library_rounded, 'Gallery', _pickVideo),
              const SizedBox(width: 16),
              _PickBtn(Icons.camera_alt_rounded, 'Record', () async { final v = await ImagePicker().pickVideo(source: ImageSource.camera); if (v != null) { _vc?.dispose(); final vc = VideoPlayerController.file(File(v.path)); await vc.initialize(); setState(() { _video = File(v.path); _vc = vc; }); vc.play(); vc.setLooping(true); } }),
            ]),
          ]))
        : Stack(fit: StackFit.expand, children: [
            // Video player
            _vc != null && _vc!.value.isInitialized
              ? GestureDetector(onTap: () { if (_vc!.value.isPlaying) _vc!.pause(); else _vc!.play(); setState(() {}); },
                  child: FittedBox(fit: BoxFit.cover, child: SizedBox(width: _vc!.value.size.width, height: _vc!.value.size.height, child: VideoPlayer(_vc!))))
              : Container(color: Colors.black54),

            // Text overlay
            if (_textOverlay != null && _textOverlay!.isNotEmpty)
              Center(child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(10)), child: Text(_textOverlay!, style: TextStyle(color: _textColor, fontSize: _textSize, fontWeight: FontWeight.w800), textAlign: TextAlign.center))),

            // Right toolbar
            Positioned(right: 12, top: 60, child: Column(children: [
              _RTool(Icons.text_fields_rounded, 'Text', () => _addTextOverlay()),
              const SizedBox(height: 16),
              _RTool(Icons.music_note_rounded, 'Music', _pickMusic),
              const SizedBox(height: 16),
              _RTool(Icons.flip_camera_ios_rounded, 'Flip', () {}),
              const SizedBox(height: 16),
              _RTool(Icons.speed_rounded, 'Speed', () {}),
            ])),

            // Bottom music strip
            if (_musicTitle != null) Positioned(bottom: 8, left: 8, right: 60, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)), child: Row(children: [const Icon(Icons.music_note_rounded, color: Colors.white, size: 16), const SizedBox(width: 6), Expanded(child: Text('$_musicTitle – ${_musicArtist ?? ''}', style: const TextStyle(color: Colors.white, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis))]))),

            // Change video button
            Positioned(top: 12, left: 12, child: IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white, size: 26), onPressed: () { _vc?.dispose(); setState(() { _video = null; _vc = null; }); })),

            // Play/Pause indicator
            if (_vc != null && !_vc!.value.isPlaying)
              const Center(child: Icon(Icons.play_arrow_rounded, color: Colors.white54, size: 72)),
          ])),

      // Bottom panel
      Container(color: const Color(0xFF111111), padding: const EdgeInsets.all(14), child: Column(children: [
        TextField(controller: _capCtrl, maxLines: 2, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: 'Write a caption... #hashtag', hintStyle: TextStyle(color: Colors.white38), border: InputBorder.none, filled: false)),
        const Divider(color: Colors.white12),
        Row(children: [
          _BottomAction(Icons.music_note_rounded, _musicTitle ?? 'Add sound', () => _pickMusic()),
          const SizedBox(width: 8),
          _BottomAction(Icons.text_fields_rounded, 'Text', () => _addTextOverlay()),
          const Spacer(),
          if (_uploading) Padding(padding: const EdgeInsets.only(right: 12), child: Row(children: [
            SizedBox(width: 60, child: LinearProgressIndicator(value: _progress, backgroundColor: Colors.white12, valueColor: const AlwaysStoppedAnimation(AppTheme.orange))),
            const SizedBox(width: 6),
            Text('${(_progress * 100).toStringAsFixed(0)}%', style: const TextStyle(color: AppTheme.orange, fontSize: 12)),
          ])),
          ElevatedButton(onPressed: _uploading ? null : _postReel, child: Text(_uploading ? 'Uploading...' : 'Share', style: const TextStyle(fontWeight: FontWeight.w700))),
        ]),
      ])),
    ]),
  );

  void _addTextOverlay() {
    final ctrl = TextEditingController(text: _textOverlay ?? '');
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.black, builder: (_) => Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom), child: Container(padding: const EdgeInsets.all(16), child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('Text Overlay', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
      const SizedBox(height: 12),
      TextField(controller: ctrl, style: TextStyle(color: _textColor, fontSize: _textSize), autofocus: true, textAlign: TextAlign.center, decoration: InputDecoration(hintText: 'Add text...', hintStyle: const TextStyle(color: Colors.white38), filled: true, fillColor: const Color(0xFF222222), border: OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.circular(12)))),
      const SizedBox(height: 12),
      Row(children: [const Text('Size:', style: TextStyle(color: Colors.white70)), Expanded(child: Slider(value: _textSize, min: 14, max: 56, divisions: 7, onChanged: (v) => setState(() => _textSize = v), activeColor: AppTheme.orange, inactiveColor: Colors.white24)), Text('${_textSize.toInt()}', style: const TextStyle(color: Colors.white70))]),
      Row(children: [const Text('Color:', style: TextStyle(color: Colors.white70)), const SizedBox(width: 8), ...[Colors.white, AppTheme.orange, Colors.yellow, Colors.cyan, Colors.pink, Colors.greenAccent, Colors.red].map((c) => GestureDetector(onTap: () => setState(() => _textColor = c), child: Container(width: 28, height: 28, margin: const EdgeInsets.symmetric(horizontal: 3), decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: _textColor == c ? Colors.white : Colors.transparent, width: 2)))))]),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: OutlinedButton(onPressed: () { setState(() => _textOverlay = null); Navigator.pop(context); }, style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white24)), child: const Text('Remove'))),
        const SizedBox(width: 10),
        Expanded(child: ElevatedButton(onPressed: () { setState(() => _textOverlay = ctrl.text.trim()); Navigator.pop(context); }, child: const Text('Apply'))),
      ]),
    ]))));
  }
}

// ─────────────────────────────────────────
// STORY EDITOR
// ─────────────────────────────────────────
class _StoryEditor extends ConsumerStatefulWidget {
  const _StoryEditor();
  @override ConsumerState<_StoryEditor> createState() => _SE();
}
class _SE extends ConsumerState<_StoryEditor> {
  File? _media; String? _mediaType;
  String? _textOverlay, _bgColor;
  Color _textColor = Colors.white; double _textSize = 24;
  String? _musicTitle; String? _musicArtist;
  bool _isTextStory = false;
  String _storyText = '';
  final _textBgs = ['#FF6B35', '#2196F3', '#4CAF50', '#9C27B0', '#E91E63', '#FF9800', '#000000', '#FFFFFF'];
  int _bgIdx = 0;
  bool _uploading = false;

  Future<void> _pickMedia() async {
    showModalBottomSheet(context: context, builder: (_) => Container(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(leading: const Icon(Icons.photo_library_rounded, color: AppTheme.orange), title: const Text('Photo from Gallery'), onTap: () async { Navigator.pop(context); final img = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90); if (img != null) setState(() { _media = File(img.path); _mediaType = 'image'; _isTextStory = false; }); }),
      ListTile(leading: const Icon(Icons.camera_alt_rounded, color: AppTheme.orange), title: const Text('Take Photo'), onTap: () async { Navigator.pop(context); final img = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 90); if (img != null) setState(() { _media = File(img.path); _mediaType = 'image'; _isTextStory = false; }); }),
      ListTile(leading: const Icon(Icons.videocam_rounded, color: AppTheme.orange), title: const Text('Video'), onTap: () async { Navigator.pop(context); final v = await ImagePicker().pickVideo(source: ImageSource.gallery, maxDuration: const Duration(seconds: 30)); if (v != null) setState(() { _media = File(v.path); _mediaType = 'video'; _isTextStory = false; }); }),
      ListTile(leading: const Icon(Icons.text_fields_rounded, color: AppTheme.orange), title: const Text('Text Story'), onTap: () { Navigator.pop(context); setState(() { _isTextStory = true; _media = null; }); }),
    ])));
  }

  Future<void> _postStory() async {
    setState(() => _uploading = true);
    try {
      final fd = FormData.fromMap({
        'type': _isTextStory ? 'text' : _mediaType ?? 'image',
        if (_textOverlay != null && _textOverlay!.isNotEmpty) 'text_overlay': _textOverlay,
        if (_isTextStory) 'text_overlay': _storyText,
        if (_bgColor != null) 'bg_color': _bgColor,
        if (_musicTitle != null) 'music_title': _musicTitle,
        if (_musicArtist != null) 'music_artist': _musicArtist,
        if (_media != null) 'story': await MultipartFile.fromFile(_media!.path, filename: _media!.path.split('/').last),
      });
      final r = await ref.read(apiServiceProvider).upload('/stories', fd);
      if (r.data['success'] == true && mounted) {
        context.go('/');
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Story shared!')));
      }
    } catch (e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'))); }
    finally { if (mounted) setState(() => _uploading = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        // Content area
        Positioned.fill(child: _isTextStory
          ? GestureDetector(onTap: () => _editText(), child: Container(
              decoration: BoxDecoration(color: Color(int.parse('0xFF${_textBgs[_bgIdx].replaceFirst('#', '')}'))),
              child: Center(child: _storyText.isEmpty
                ? const Text('Tap to add text', style: TextStyle(color: Colors.white38, fontSize: 22))
                : Text(_storyText, style: TextStyle(color: _textColor, fontSize: _textSize, fontWeight: FontWeight.w700), textAlign: TextAlign.center))))
          : (_media != null
              ? Stack(fit: StackFit.expand, children: [
                  if (_mediaType == 'image') Image.file(_media!, fit: BoxFit.cover) else Container(color: Colors.black87, child: const Center(child: Icon(Icons.videocam_rounded, color: Colors.white54, size: 80))),
                  if (_textOverlay != null && _textOverlay!.isNotEmpty)
                    Center(child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(10)), child: Text(_textOverlay!, style: TextStyle(color: _textColor, fontSize: _textSize, fontWeight: FontWeight.w700), textAlign: TextAlign.center))),
                  if (_musicTitle != null) Positioned(bottom: 120, left: 0, right: 0, child: Center(child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)), child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.music_note_rounded, color: Colors.white, size: 14), const SizedBox(width: 6), Text('$_musicTitle', style: const TextStyle(color: Colors.white, fontSize: 12))])))),
                ])
              : Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.add_circle_outline_rounded, size: 80, color: Colors.white24),
                  const SizedBox(height: 16), const Text('Create a story', style: TextStyle(color: Colors.white54, fontSize: 20)),
                ])))),

        // Top controls
        SafeArea(child: Row(children: [
          IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28), onPressed: () => context.go('/')),
          const Spacer(),
          if (_isTextStory) ...[
            for (int i = 0; i < _textBgs.length; i++)
              GestureDetector(onTap: () => setState(() => _bgIdx = i), child: Container(width: 24, height: 24, margin: const EdgeInsets.symmetric(horizontal: 3), decoration: BoxDecoration(color: Color(int.parse('0xFF${_textBgs[i].replaceFirst('#', '')}')), shape: BoxShape.circle, border: Border.all(color: _bgIdx == i ? Colors.white : Colors.transparent, width: 2)))),
            const SizedBox(width: 8),
          ],
        ])),

        // Right tools
        Positioned(right: 12, top: 80, child: Column(children: [
          _RTool(Icons.text_fields_rounded, 'Text', () => _addText()),
          const SizedBox(height: 14),
          _RTool(Icons.music_note_rounded, 'Music', () => _addMusic()),
          const SizedBox(height: 14),
          _RTool(Icons.add_photo_alternate_rounded, 'Media', _pickMedia),
        ])),

        // Bottom buttons
        Positioned(bottom: 0, left: 0, right: 0, child: SafeArea(top: false, child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black.withOpacity(0.8), Colors.transparent])),
          child: Row(children: [
            if (_media == null && !_isTextStory) Expanded(child: OutlinedButton.icon(onPressed: _pickMedia, style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white38), padding: const EdgeInsets.symmetric(vertical: 14)), icon: const Icon(Icons.add_rounded), label: const Text('Add Content'))),
            if (_media != null || _isTextStory) ...[
              Expanded(child: OutlinedButton(onPressed: _pickMedia, style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white38), padding: const EdgeInsets.symmetric(vertical: 14)), child: const Text('Change'))),
              const SizedBox(width: 12),
              Expanded(child: ElevatedButton(onPressed: _uploading ? null : _postStory, child: _uploading ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)), SizedBox(width: 8), Text('Sharing...')]) : const Text('Share Story', style: TextStyle(fontWeight: FontWeight.w700)))),
            ],
          ]),
        ))),
      ]),
    );
  }

  void _editText() { _addText(); }
  void _addText() {
    final ctrl = TextEditingController(text: _isTextStory ? _storyText : (_textOverlay ?? ''));
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.black, builder: (_) => Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom), child: Container(padding: const EdgeInsets.all(16), child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('Add Text', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
      const SizedBox(height: 12),
      TextField(controller: ctrl, style: TextStyle(color: _textColor, fontSize: _textSize), autofocus: true, maxLines: 4, textAlign: TextAlign.center, decoration: InputDecoration(hintText: 'Write something...', hintStyle: const TextStyle(color: Colors.white38), filled: true, fillColor: const Color(0xFF222222), border: OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.circular(12)))),
      const SizedBox(height: 10),
      Row(children: [const Text('Size:', style: TextStyle(color: Colors.white70)), Expanded(child: Slider(value: _textSize, min: 14, max: 52, divisions: 8, onChanged: (v) => setState(() => _textSize = v), activeColor: AppTheme.orange, inactiveColor: Colors.white24)), Text('${_textSize.toInt()}', style: const TextStyle(color: Colors.white70))]),
      Row(children: [const Text('Color:', style: TextStyle(color: Colors.white70, fontSize: 12)), const SizedBox(width: 6), ...[Colors.white, AppTheme.orange, Colors.yellow, Colors.cyan, Colors.pink, Colors.greenAccent, Colors.red, Colors.black].map((c) => GestureDetector(onTap: () => setState(() => _textColor = c), child: Container(width: 26, height: 26, margin: const EdgeInsets.symmetric(horizontal: 3), decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: _textColor == c ? Colors.white : Colors.transparent, width: 2)))))]),
      const SizedBox(height: 14),
      ElevatedButton(onPressed: () { setState(() { if (_isTextStory) _storyText = ctrl.text.trim(); else _textOverlay = ctrl.text.trim(); }); Navigator.pop(context); }, child: const Text('Apply Text')),
    ]))));
  }

  void _addMusic() {
    showModalBottomSheet(context: context, backgroundColor: const Color(0xFF1E1E1E), builder: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
      const Padding(padding: EdgeInsets.all(16), child: Text('Add Music', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16))),
      const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Search and add music to your story.', style: TextStyle(color: Colors.white54))),
      const SizedBox(height: 16),
      ...['Afrobeats Mix', 'Trap Nation', 'Chill Vibes', 'Summer Hits'].map((s) => ListTile(leading: const Icon(Icons.music_note_rounded, color: AppTheme.orange), title: Text(s, style: const TextStyle(color: Colors.white)), onTap: () { setState(() { _musicTitle = s; _musicArtist = 'Various'; }); Navigator.pop(context); })),
      const SizedBox(height: 16),
    ]));
  }
}

// ─── Shared widgets
class _PickBtn extends StatelessWidget {
  final IconData icon; final String label; final VoidCallback onTap;
  const _PickBtn(this.icon, this.label, this.onTap);
  @override Widget build(BuildContext _) => GestureDetector(onTap: onTap, child: Column(children: [
    Container(width: 64, height: 64, decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(18)), child: Icon(icon, color: Colors.white, size: 30)),
    const SizedBox(height: 8), Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
  ]));
}

class _ImgBtn extends StatelessWidget {
  final IconData icon; final VoidCallback onTap;
  const _ImgBtn(this.icon, this.onTap);
  @override Widget build(BuildContext _) => GestureDetector(onTap: onTap, child: Container(width: 36, height: 36, decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: Colors.white, size: 20)));
}

class _RTool extends StatelessWidget {
  final IconData icon; final String label; final VoidCallback onTap;
  const _RTool(this.icon, this.label, this.onTap);
  @override Widget build(BuildContext _) => GestureDetector(onTap: onTap, child: Column(children: [
    Container(width: 44, height: 44, decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle), child: Icon(icon, color: Colors.white, size: 22)),
    const SizedBox(height: 3), Text(label, style: const TextStyle(color: Colors.white, fontSize: 10)),
  ]));
}

class _BottomAction extends StatelessWidget {
  final IconData icon; final String label; final VoidCallback onTap;
  const _BottomAction(this.icon, this.label, this.onTap);
  @override Widget build(BuildContext _) => GestureDetector(onTap: onTap, child: Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, color: Colors.white70, size: 18), const SizedBox(width: 4),
    Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
  ]));
}
