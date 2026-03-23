import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'dart:io';
import 'dart:async';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/models/models.dart';
import '../../../shared/widgets/app_avatar.dart';
import '../../../shared/utils/format_utils.dart';
import 'package:dio/dio.dart';

// ── Message state notifier
final _msgsProvider = StateNotifierProvider.family<_MN, List<MessageModel>, String>((ref, cid) => _MN(ref, cid));

class _MN extends StateNotifier<List<MessageModel>> {
  final Ref _ref; final String _cid; bool _hasMore = true; bool _busy = false;
  _MN(this._ref, this._cid) : super([]) { load(); _listenSocket(); }

  void _listenSocket() {
    final s = _ref.read(socketServiceProvider);
    s.on('new_message', (d) {
      if (d is! Map || d['conversation_id'] != _cid) return;
      final m = MessageModel.fromJson(Map<String,dynamic>.from(d['message'] as Map));
      state = [...state, m];
      // Deliver receipt back to sender
      _ref.read(socketServiceProvider).messageDelivered(m.id, m.senderId);
    });
    s.on('message_deleted', (d) {
      if (d is! Map || d['conversation_id'] != _cid) return;
      final mid = d['message_id'] as String;
      state = state.map((m) => m.id == mid ? _deletedMsg(m) : m).toList();
    });
    s.on('message_edited', (d) {
      if (d is! Map || d['conversation_id'] != _cid) return;
      final mid = d['message_id'] as String;
      state = state.map((m) => m.id == mid ? MessageModel(id: m.id, conversationId: m.conversationId, senderId: m.senderId, type: m.type, createdAt: m.createdAt, content: d['content'] as String?, isEdited: true, username: m.username, displayName: m.displayName, avatarUrl: m.avatarUrl, reactions: m.reactions, readBy: m.readBy, deliveredTo: m.deliveredTo, status: m.status) : m).toList();
    });
    s.on('message_reaction', (d) {
      if (d is! Map) return;
      final mid = d['message_id'] as String;
      final rxns = List<Map<String,dynamic>>.from(d['reactions'] ?? []);
      state = state.map((m) => m.id == mid ? _withReactions(m, rxns) : m).toList();
    });
    s.on('messages_read', (d) {
      if (d is! Map || d['conversation_id'] != _cid) return;
      final readerId = d['reader_id'] as String;
      // Mark all sent messages as seen
      state = state.map((m) {
        if (!m.readBy.contains(readerId)) {
          final newReadBy = [...m.readBy, readerId];
          return MessageModel(id: m.id, conversationId: m.conversationId, senderId: m.senderId, type: m.type, createdAt: m.createdAt, content: m.content, mediaUrl: m.mediaUrl, mediaThumbnail: m.mediaThumbnail, mediaName: m.mediaName, mediaMime: m.mediaMime, mediaDuration: m.mediaDuration, mediaSize: m.mediaSize, latitude: m.latitude, longitude: m.longitude, contactName: m.contactName, contactPhone: m.contactPhone, replyToId: m.replyToId, replyContent: m.replyContent, replyType: m.replyType, replySenderName: m.replySenderName, replySenderUsername: m.replySenderUsername, isEdited: m.isEdited, isDeleted: m.isDeleted, deletedForAll: m.deletedForAll, reactions: m.reactions, username: m.username, displayName: m.displayName, avatarUrl: m.avatarUrl, status: MessageStatus.seen, readBy: newReadBy, deliveredTo: m.deliveredTo);
        }
        return m;
      }).toList();
    });
    s.on('message_status_update', (d) {
      if (d is! Map) return;
      final mid = d['message_id'] as String;
      final st = d['status'] == 'delivered' ? MessageStatus.delivered : MessageStatus.seen;
      final uid = d['user_id'] as String? ?? '';
      state = state.map((m) {
        if (m.id != mid) return m;
        final newDelivered = st == MessageStatus.delivered && !m.deliveredTo.contains(uid) ? [...m.deliveredTo, uid] : m.deliveredTo;
        return MessageModel(id: m.id, conversationId: m.conversationId, senderId: m.senderId, type: m.type, createdAt: m.createdAt, content: m.content, mediaUrl: m.mediaUrl, mediaThumbnail: m.mediaThumbnail, mediaName: m.mediaName, mediaMime: m.mediaMime, mediaDuration: m.mediaDuration, mediaSize: m.mediaSize, latitude: m.latitude, longitude: m.longitude, contactName: m.contactName, contactPhone: m.contactPhone, replyToId: m.replyToId, replyContent: m.replyContent, replyType: m.replyType, replySenderName: m.replySenderName, replySenderUsername: m.replySenderUsername, isEdited: m.isEdited, isDeleted: m.isDeleted, deletedForAll: m.deletedForAll, reactions: m.reactions, username: m.username, displayName: m.displayName, avatarUrl: m.avatarUrl, status: st, readBy: m.readBy, deliveredTo: newDelivered);
      }).toList();
    });
  }

  static MessageModel _deletedMsg(MessageModel m) => MessageModel(id: m.id, conversationId: m.conversationId, senderId: m.senderId, type: m.type, createdAt: m.createdAt, isDeleted: true, username: m.username, displayName: m.displayName, avatarUrl: m.avatarUrl);
  static MessageModel _withReactions(MessageModel m, List<Map<String,dynamic>> rxns) => MessageModel(id: m.id, conversationId: m.conversationId, senderId: m.senderId, type: m.type, createdAt: m.createdAt, content: m.content, mediaUrl: m.mediaUrl, mediaThumbnail: m.mediaThumbnail, mediaName: m.mediaName, mediaMime: m.mediaMime, mediaDuration: m.mediaDuration, mediaSize: m.mediaSize, replyToId: m.replyToId, replyContent: m.replyContent, replyType: m.replyType, replySenderName: m.replySenderName, isEdited: m.isEdited, reactions: rxns, username: m.username, displayName: m.displayName, avatarUrl: m.avatarUrl, status: m.status, readBy: m.readBy, deliveredTo: m.deliveredTo);

  Future<void> load({bool more = false}) async {
    if (_busy || (more && !_hasMore)) return;
    _busy = true;
    try {
      final params = <String,dynamic>{'limit': '40'};
      if (more && state.isNotEmpty) params['before_id'] = state.first.id;
      final r = await _ref.read(apiServiceProvider).get('/messages/conversations/$_cid/messages', q: params);
      final msgs = (r.data['messages'] as List).map((m) => MessageModel.fromJson(Map<String,dynamic>.from(m))).toList();
      _hasMore = r.data['has_more'] == true;
      state = more ? [...msgs, ...state] : msgs;
    } catch (_) {}
    _busy = false;
  }
}

// ── Chat Screen
class ChatScreen extends ConsumerStatefulWidget {
  final String convId;
  final Map<String,dynamic>? extra;
  const ChatScreen({super.key, required this.convId, this.extra});
  @override ConsumerState<ChatScreen> createState() => _CS();
}

class _CS extends ConsumerState<ChatScreen> {
  final _msgCtrl  = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _focus    = FocusNode();
  bool _showEmoji = false, _sending = false, _typing = false;
  String? _typingUser;
  MessageModel? _replyTo, _editingMsg;
  ConversationModel? _conv;
  final _recorder = AudioRecorder();
  bool _isRecording = false;
  String? _recPath;
  Timer? _recTimer;
  int _recSecs = 0;

  @override
  void initState() {
    super.initState();
    _loadConv();
    _setupSocket();
    _msgCtrl.addListener(_onTextChange);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void dispose() {
    _msgCtrl.removeListener(_onTextChange);
    _msgCtrl.dispose(); _scrollCtrl.dispose(); _focus.dispose();
    _recorder.dispose(); _recTimer?.cancel();
    final s = ref.read(socketServiceProvider);
    s.leaveConversation(widget.convId);
    s.off('new_message'); s.off('user_typing'); s.off('user_stopped_typing');
    s.off('message_deleted'); s.off('message_edited'); s.off('message_reaction');
    s.off('messages_read'); s.off('message_status_update');
    super.dispose();
  }

  void _onTextChange() {
    final s = ref.read(socketServiceProvider);
    if (_msgCtrl.text.isNotEmpty && !_typing) { _typing = true; s.startTyping(widget.convId); }
    else if (_msgCtrl.text.isEmpty && _typing) { _typing = false; s.stopTyping(widget.convId); }
    setState(() {});
  }

  void _setupSocket() {
    final s = ref.read(socketServiceProvider);
    s.joinConversation(widget.convId);
    s.on('user_typing', (d) { if (d is Map && d['conversation_id'] == widget.convId && mounted) setState(() => _typingUser = d['display_name'] as String?); });
    s.on('user_stopped_typing', (d) { if (d is Map && d['conversation_id'] == widget.convId && mounted) setState(() => _typingUser = null); });
    s.on('new_message', (_) { Future.delayed(const Duration(milliseconds: 100), _scrollToBottom); s.markRead(widget.convId); });
    s.markRead(widget.convId);
  }

  Future<void> _loadConv() async {
    try {
      final r = await ref.read(apiServiceProvider).get('/messages/conversations');
      final list = (r.data['conversations'] as List).map((c) => ConversationModel.fromJson(Map<String,dynamic>.from(c))).toList();
      final conv = list.firstWhere((c) => c.id == widget.convId, orElse: () => _fallback());
      if (mounted) setState(() => _conv = conv);
    } catch (_) { if (mounted) setState(() => _conv = _fallback()); }
  }

  ConversationModel _fallback() {
    final e = widget.extra ?? {};
    return ConversationModel(id: widget.convId, type: 'direct', otherId: e['other_user_id'] as String?, otherDisplayName: e['other_display_name'] as String?, otherAvatarUrl: e['other_avatar_url'] as String?, otherIsOnline: e['other_is_online'] == true);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  Future<void> _send({String type = 'text', File? file, String? forceContent}) async {
    final text = forceContent ?? _msgCtrl.text.trim();
    if (text.isEmpty && file == null) return;
    setState(() => _sending = true);
    try {
      dynamic data;
      if (file != null) {
        data = FormData.fromMap({'type': type, if (text.isNotEmpty) 'content': text, if (_replyTo != null) 'reply_to_id': _replyTo!.id, 'message_file': await MultipartFile.fromFile(file.path, filename: file.path.split(Platform.pathSeparator).last)});
      } else {
        data = {'type': 'text', 'content': text, if (_replyTo != null) 'reply_to_id': _replyTo!.id};
      }
      await ref.read(apiServiceProvider).post('/messages/conversations/${widget.convId}/messages', data: data);
      _msgCtrl.clear();
      setState(() { _replyTo = null; _editingMsg = null; _sending = false; });
      ref.read(socketServiceProvider).stopTyping(widget.convId);
      _typing = false;
    } catch (_) { setState(() => _sending = false); }
  }

  Future<void> _saveEdit() async {
    if (_editingMsg == null || _msgCtrl.text.trim().isEmpty) return;
    await ref.read(apiServiceProvider).put('/messages/${_editingMsg!.id}', data: {'content': _msgCtrl.text.trim()});
    _msgCtrl.clear(); setState(() => _editingMsg = null);
  }

  Future<void> _startRec() async {
    if (!await _recorder.hasPermission()) return;
    final dir = await getTemporaryDirectory();
    _recPath = '${dir.path}/vn_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: _recPath!);
    setState(() { _isRecording = true; _recSecs = 0; });
    _recTimer = Timer.periodic(const Duration(seconds: 1), (_) { if (mounted) setState(() => _recSecs++); });
  }

  Future<void> _stopRec({bool cancel = false}) async {
    _recTimer?.cancel(); await _recorder.stop();
    setState(() => _isRecording = false);
    if (!cancel && _recPath != null && _recSecs >= 1) await _send(type: 'voice_note', file: File(_recPath!));
    _recPath = null; _recSecs = 0;
  }

  String _recDur() { final m = _recSecs ~/ 60; final s = _recSecs % 60; return '${m.toString().padLeft(2,'0')}:${s.toString().padLeft(2,'0')}'; }

  void _showAttach() {
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (_) {
      final dark = Theme.of(context).brightness == Brightness.dark;
      return Container(margin: const EdgeInsets.all(12), decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(20)), child: Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16), decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _AI(Icons.photo_library_rounded, 'Gallery', const Color(0xFF9C27B0), () async { Navigator.pop(context); final imgs = await ImagePicker().pickMultiImage(); for (final i in imgs) await _send(type: 'image', file: File(i.path)); }),
          _AI(Icons.camera_alt_rounded, 'Camera', const Color(0xFF2196F3), () async { Navigator.pop(context); final img = await ImagePicker().pickImage(source: ImageSource.camera); if (img != null) await _send(type: 'image', file: File(img.path)); }),
          _AI(Icons.videocam_rounded, 'Video', const Color(0xFFE91E63), () async { Navigator.pop(context); final v = await ImagePicker().pickVideo(source: ImageSource.gallery); if (v != null) await _send(type: 'video', file: File(v.path)); }),
          _AI(Icons.insert_drive_file_rounded, 'File', const Color(0xFFFF9800), () async { Navigator.pop(context); final r = await FilePicker.platform.pickFiles(); if (r?.files.single.path != null) await _send(type: 'file', file: File(r!.files.single.path!)); }),
        ]),
        const SizedBox(height: 14),
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _AI(Icons.headphones_rounded, 'Audio', const Color(0xFF00BCD4), () async { Navigator.pop(context); final r = await FilePicker.platform.pickFiles(type: FileType.audio); if (r?.files.single.path != null) await _send(type: 'audio', file: File(r!.files.single.path!)); }),
          _AI(Icons.location_on_rounded, 'Location', const Color(0xFF4CAF50), () { Navigator.pop(context); }),
          _AI(Icons.gif_box_rounded, 'GIF', const Color(0xFFFF5722), () { Navigator.pop(context); }),
          _AI(Icons.contacts_rounded, 'Contact', const Color(0xFF607D8B), () { Navigator.pop(context); }),
        ]),
        const SizedBox(height: 8),
      ])));
    });
  }

  Future<void> _deleteMsg(MessageModel msg) async {
    final choice = await showDialog<String>(context: context, builder: (_) => AlertDialog(
      title: const Text('Delete Message'),
      content: const Text('Who should this be deleted for?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, 'cancel'), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, 'me'), child: const Text('For me')),
        TextButton(onPressed: () => Navigator.pop(context, 'all'), child: const Text('For everyone', style: TextStyle(color: Colors.red))),
      ],
    ));
    if (choice == null || choice == 'cancel') return;
    await ref.read(apiServiceProvider).delete('/messages/${msg.id}', data: {'for_all': choice == 'all'});
  }

  bool _sameDay(String a, String b) {
    try { final da = DateTime.parse(a).toLocal(); final db = DateTime.parse(b).toLocal(); return da.year == db.year && da.month == db.month && da.day == db.day; } catch (_) { return false; }
  }

  @override
  Widget build(BuildContext context) {
    final msgs = ref.watch(_msgsProvider(widget.convId));
    final me   = ref.watch(currentUserProvider);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final conv = _conv;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => context.pop()),
        title: GestureDetector(
          onTap: () => context.push('/chat-info/${widget.convId}'),
          child: Row(children: [
            Stack(children: [
              AppAvatar(url: conv?.displayAvatar, size: 38, username: conv?.displayName),
              if (conv?.otherIsOnline == true)
                Positioned(bottom: 0, right: 0, child: Container(width: 11, height: 11, decoration: BoxDecoration(color: AppTheme.orange, shape: BoxShape.circle, border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2)))),
            ]),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(conv?.displayName ?? 'Chat', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16), overflow: TextOverflow.ellipsis)),
                if (conv?.otherIsVerified == true) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.verified_rounded, color: AppTheme.orange, size: 14)),
              ]),
              Text(
                _typingUser != null ? 'typing...'
                  : conv?.otherIsOnline == true ? '● Online'
                  : conv?.otherLastSeen != null ? 'last seen ${timeago.format(DateTime.tryParse(conv!.otherLastSeen!) ?? DateTime.now())}'
                  : conv?.otherStatusText ?? 'tap for info',
                style: TextStyle(fontSize: 12, fontWeight: _typingUser != null ? FontWeight.w600 : FontWeight.w400,
                  color: _typingUser != null ? AppTheme.orange : conv?.otherIsOnline == true ? AppTheme.orange : (dark ? AppTheme.dSub : AppTheme.lSub)),
                overflow: TextOverflow.ellipsis,
              ),
            ])),
          ]),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.videocam_rounded), onPressed: () { if (conv?.otherId != null) context.push('/call/video', extra: {'user_id': conv!.otherId, 'user_name': conv.displayName, 'avatar': conv.displayAvatar, 'is_incoming': false}); }),
          IconButton(icon: const Icon(Icons.call_rounded), onPressed: () { if (conv?.otherId != null) context.push('/call/audio', extra: {'user_id': conv!.otherId, 'user_name': conv.displayName, 'avatar': conv.displayAvatar, 'is_incoming': false}); }),
          IconButton(icon: const Icon(Icons.more_vert_rounded), onPressed: () => context.push('/chat-info/${widget.convId}')),
        ],
      ),

      body: Column(children: [
        // Messages
        Expanded(child: msgs.isEmpty
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.chat_bubble_outline_rounded, size: 64, color: dark ? AppTheme.dSub : AppTheme.lSub),
              const SizedBox(height: 14),
              Text('No messages yet', style: TextStyle(color: dark ? AppTheme.dSub : AppTheme.lSub, fontSize: 16)),
              const SizedBox(height: 6), Text('Say hello 👋', style: TextStyle(color: dark ? AppTheme.dSub : AppTheme.lSub, fontSize: 13)),
            ]))
          : NotificationListener<ScrollNotification>(
              onNotification: (n) { if (n is ScrollStartNotification && _scrollCtrl.position.pixels <= 80) ref.read(_msgsProvider(widget.convId).notifier).load(more: true); return false; },
              child: ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                itemCount: msgs.length,
                itemBuilder: (_, i) {
                  final msg = msgs[i];
                  final isMe = msg.senderId == me?.id;
                  final showDate = i == 0 || !_sameDay(msgs[i-1].createdAt, msg.createdAt);
                  final showAvatar = !isMe && (i == msgs.length - 1 || msgs[i+1].senderId != msg.senderId);
                  return Column(mainAxisSize: MainAxisSize.min, children: [
                    if (showDate) _DateLabel(msg.createdAt),
                    _Bubble(
                      msg: msg, isMe: isMe, dark: dark, myId: me?.id ?? '',
                      showAvatar: showAvatar, conv: conv,
                      onReply: () => setState(() { _replyTo = msg; _editingMsg = null; _focus.requestFocus(); }),
                      onEdit:  () { setState(() { _editingMsg = msg; _replyTo = null; _msgCtrl.text = msg.content ?? ''; _focus.requestFocus(); }); },
                      onDelete: () => _deleteMsg(msg),
                      onReact: (e) { ref.read(socketServiceProvider).reactToMessage(msg.id, e, widget.convId); },
                      onCopy: () { Clipboard.setData(ClipboardData(text: msg.content ?? '')); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied'))); },
                      onStar: () { ref.read(socketServiceProvider).starMessage(msg.id); },
                      onInfo: () {},
                    ),
                  ]);
                },
              ),
            )),

        // Typing indicator
        if (_typingUser != null) Padding(padding: const EdgeInsets.only(left: 16, bottom: 4), child: Row(children: [
          _TypingBubble(dark: dark),
          const SizedBox(width: 8),
          Text('$_typingUser is typing...', style: TextStyle(fontSize: 12, color: dark ? AppTheme.dSub : AppTheme.lSub, fontStyle: FontStyle.italic)),
        ])),

        // Reply/Edit banner
        if (_replyTo != null || _editingMsg != null) _ReplyBanner(msg: _editingMsg ?? _replyTo!, isEdit: _editingMsg != null, dark: dark, onClose: () => setState(() { _replyTo = null; _editingMsg = null; _msgCtrl.clear(); })),

        // Input bar
        Container(
          decoration: BoxDecoration(color: dark ? AppTheme.dSurf : Colors.white, border: Border(top: BorderSide(color: dark ? AppTheme.dDiv : AppTheme.lDiv, width: 0.5))),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: SafeArea(top: false, child: _isRecording
            ? _RecBar(secs: _recSecs, dur: _recDur, onCancel: () => _stopRec(cancel: true), onSend: () => _stopRec())
            : Row(children: [
                IconButton(icon: Icon(_showEmoji ? Icons.keyboard_rounded : Icons.emoji_emotions_outlined, color: AppTheme.orange), onPressed: () { setState(() => _showEmoji = !_showEmoji); if (_showEmoji) FocusScope.of(context).unfocus(); else _focus.requestFocus(); }),
                Expanded(child: ConstrainedBox(constraints: const BoxConstraints(maxHeight: 120), child: TextField(
                  controller: _msgCtrl, focusNode: _focus, minLines: 1, maxLines: 6,
                  textCapitalization: TextCapitalization.sentences,
                  onTap: () { if (_showEmoji) setState(() => _showEmoji = false); },
                  decoration: InputDecoration(
                    hintText: _editingMsg != null ? 'Edit message...' : 'Message...',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                    fillColor: dark ? AppTheme.dCard : const Color(0xFFF2F2F2), filled: true,
                    suffixIcon: IconButton(icon: const Icon(Icons.attach_file_rounded, size: 20), onPressed: _showAttach),
                  ),
                ))),
                const SizedBox(width: 6),
                _msgCtrl.text.isEmpty && _editingMsg == null
                  ? GestureDetector(onLongPressStart: (_) => _startRec(), onLongPressEnd: (_) => _stopRec(), child: Container(width: 46, height: 46, decoration: const BoxDecoration(gradient: LinearGradient(colors: [AppTheme.orange, AppTheme.orangeDark]), shape: BoxShape.circle), child: const Icon(Icons.mic_rounded, color: Colors.white, size: 24)))
                  : GestureDetector(onTap: _editingMsg != null ? _saveEdit : () => _send(), child: Container(width: 46, height: 46, decoration: const BoxDecoration(gradient: LinearGradient(colors: [AppTheme.orange, AppTheme.orangeDark]), shape: BoxShape.circle),
                      child: _sending ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Icon(_editingMsg != null ? Icons.check_rounded : Icons.send_rounded, color: Colors.white, size: 22))),
              ])),
        ),

        if (_showEmoji) SizedBox(height: 280, child: EmojiPicker(onEmojiSelected: (_, e) => _msgCtrl.text += e.emoji, config: Config(height: 280, emojiViewConfig: const EmojiViewConfig(columns: 8, emojiSizeMax: 28), categoryViewConfig: const CategoryViewConfig(indicatorColor: AppTheme.orange, iconColorSelected: AppTheme.orange)))),
      ]),
    );
  }
}

// ─── Date label
class _DateLabel extends StatelessWidget {
  final String ts;
  const _DateLabel(this.ts);
  @override
  Widget build(BuildContext context) {
    String label;
    try { final d = DateTime.parse(ts).toLocal(); final now = DateTime.now(); if (d.year == now.year && d.month == now.month && d.day == now.day) label = 'Today'; else if (d.year == now.year && d.month == now.month && d.day == now.day - 1) label = 'Yesterday'; else label = '${d.day}/${d.month}/${d.year}'; } catch (_) { label = ''; }
    return Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Row(children: [
      const Expanded(child: Divider()),
      Container(margin: const EdgeInsets.symmetric(horizontal: 12), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5), decoration: BoxDecoration(color: AppTheme.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(14)), child: Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.orange, fontWeight: FontWeight.w500))),
      const Expanded(child: Divider()),
    ]));
  }
}

// ─── Reply banner
class _ReplyBanner extends StatelessWidget {
  final MessageModel msg; final bool isEdit, dark; final VoidCallback onClose;
  const _ReplyBanner({required this.msg, required this.isEdit, required this.dark, required this.onClose});
  @override
  Widget build(BuildContext _) => Container(color: dark ? AppTheme.dCard : AppTheme.orangeSurf, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), child: Row(children: [
    Container(width: 3, height: 40, color: AppTheme.orange),
    const SizedBox(width: 10),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(isEdit ? '✏️  Edit Message' : '↩️  Reply to ${msg.displayName ?? msg.username ?? 'User'}', style: const TextStyle(color: AppTheme.orange, fontWeight: FontWeight.w600, fontSize: 12)),
      const SizedBox(height: 2),
      Text(msg.content ?? msg.type, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: dark ? AppTheme.dSub : AppTheme.lSub)),
    ])),
    IconButton(icon: const Icon(Icons.close_rounded, size: 20), onPressed: onClose),
  ]));
}

// ─── Message bubble
class _Bubble extends StatelessWidget {
  final MessageModel msg; final bool isMe, dark; final String myId;
  final bool showAvatar; final ConversationModel? conv;
  final VoidCallback onReply, onEdit, onDelete, onCopy, onStar, onInfo;
  final void Function(String) onReact;
  const _Bubble({required this.msg, required this.isMe, required this.dark, required this.myId, required this.showAvatar, required this.conv, required this.onReply, required this.onEdit, required this.onDelete, required this.onCopy, required this.onStar, required this.onInfo, required this.onReact});

  @override
  Widget build(BuildContext context) {
    if (msg.isDeleted) return Align(alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(margin: const EdgeInsets.symmetric(vertical: 2), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: dark ? AppTheme.dCard : const Color(0xFFEEEEEE), borderRadius: BorderRadius.circular(16)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.block_rounded, size: 14, color: dark ? AppTheme.dSub : AppTheme.lSub), const SizedBox(width: 6), Text('This message was deleted', style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: dark ? AppTheme.dSub : AppTheme.lSub))])));

    final bgColor  = isMe ? AppTheme.orange : (dark ? AppTheme.dCard : const Color(0xFFF0F0F0));
    final txtColor = isMe ? Colors.white : (dark ? AppTheme.dText : AppTheme.lText);
    final isGroup  = conv?.type == 'group';

    return GestureDetector(
      onLongPress: () => _showOpts(context),
      child: Padding(
        padding: EdgeInsets.only(top: 2, bottom: 2, left: isMe ? 56 : 0, right: isMe ? 0 : 56),
        child: Row(
          mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Avatar for group chat
            if (!isMe && isGroup)
              showAvatar ? Padding(padding: const EdgeInsets.only(right: 6, bottom: 4), child: AppAvatar(url: msg.avatarUrl, size: 28, username: msg.username)) : const SizedBox(width: 34),

            ConstrainedBox(constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72), child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                // Group sender name
                if (!isMe && isGroup && showAvatar)
                  Padding(padding: const EdgeInsets.only(left: 4, bottom: 2), child: Text(msg.displayName ?? msg.username ?? '', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.orange))),

                // Reply preview
                if (msg.replyToId != null) Container(
                  margin: const EdgeInsets.only(bottom: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(color: isMe ? Colors.white.withOpacity(0.2) : (dark ? AppTheme.dDiv : const Color(0xFFE8E8E8)), borderRadius: BorderRadius.circular(10), border: const Border(left: BorderSide(color: AppTheme.orange, width: 3))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(msg.replySenderName ?? 'User', style: const TextStyle(color: AppTheme.orange, fontWeight: FontWeight.w700, fontSize: 11)),
                    const SizedBox(height: 2),
                    Text(msg.replyContent ?? msg.replyType ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                  ])),

                // Bubble
                Container(
                  padding: _pad(msg.type),
                  decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18), topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(isMe ? 18 : 4),
                    bottomRight: Radius.circular(isMe ? 4 : 18),
                  )),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    _buildBody(context, txtColor),
                    Padding(
                      padding: _isMedia(msg.type) ? const EdgeInsets.fromLTRB(8, 4, 8, 6) : const EdgeInsets.only(top: 4),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(_fmtTime(msg.createdAt), style: TextStyle(fontSize: 10, color: _isMedia(msg.type) ? Colors.white70 : txtColor.withOpacity(0.65))),
                        if (msg.isEdited) Padding(padding: const EdgeInsets.only(left: 4), child: Text('edited', style: TextStyle(fontSize: 10, color: txtColor.withOpacity(0.6), fontStyle: FontStyle.italic))),
                        if (isMe) Padding(padding: const EdgeInsets.only(left: 3), child: _StatusTick(status: msg.status)),
                      ]),
                    ),
                  ]),
                ),

                // Reactions
                if (msg.reactions.isNotEmpty)
                  Container(margin: const EdgeInsets.only(top: 3), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: dark ? AppTheme.dSurf : Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 6)]),
                    child: Row(mainAxisSize: MainAxisSize.min, children: msg.reactions.map((r) {
                      final cnt = r['count'] as int? ?? 1;
                      return Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: Text('${r['emoji']}${cnt > 1 ? " $cnt" : ""}', style: const TextStyle(fontSize: 14)));
                    }).toList())),
              ],
            )),
          ],
        ),
      ),
    );
  }

  bool _isMedia(String t) => ['image','video'].contains(t);
  EdgeInsets _pad(String t) => _isMedia(t) ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 14, vertical: 10);
  String _fmtTime(String ts) { try { final d = DateTime.parse(ts).toLocal(); return '${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}'; } catch (_) { return ''; } }
  String _fmtSize(int b) { if (b < 1024) return '${b}B'; if (b < 1048576) return '${(b/1024).toStringAsFixed(1)}KB'; return '${(b/1048576).toStringAsFixed(1)}MB'; }

  Widget _buildBody(BuildContext ctx, Color tc) {
    switch (msg.type) {
      case 'image':
        return ClipRRect(borderRadius: BorderRadius.circular(14), child: msg.mediaUrl != null
          ? CachedNetworkImage(imageUrl: msg.mediaUrl!, width: 220, height: 220, fit: BoxFit.cover, placeholder: (_, __) => Container(width: 220, height: 220, color: AppTheme.orangeSurf), errorWidget: (_, __, ___) => Container(width: 220, height: 220, color: AppTheme.orangeSurf, child: const Icon(Icons.broken_image_rounded, color: AppTheme.orange, size: 48)))
          : Container(width: 220, height: 220, color: AppTheme.orangeSurf));
      case 'video':
        return Stack(children: [
          ClipRRect(borderRadius: BorderRadius.circular(14), child: msg.mediaThumbnail != null ? CachedNetworkImage(imageUrl: msg.mediaThumbnail!, width: 220, height: 160, fit: BoxFit.cover) : Container(width: 220, height: 160, color: Colors.black87)),
          const Positioned.fill(child: Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 52))),
          if (msg.mediaDuration != null) Positioned(bottom: 8, right: 8, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)), child: Text(FormatUtils.dur(msg.mediaDuration!), style: const TextStyle(color: Colors.white, fontSize: 11)))),
        ]);
      case 'voice_note':
        return _VoicePlayer(url: msg.mediaUrl, dur: msg.mediaDuration, tc: tc);
      case 'file':
        return Row(mainAxisSize: MainAxisSize.min, children: [
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: tc.withOpacity(0.12), borderRadius: BorderRadius.circular(10)), child: Icon(Icons.insert_drive_file_rounded, color: tc, size: 28)),
          const SizedBox(width: 10),
          Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(msg.mediaName ?? 'File', style: TextStyle(color: tc, fontWeight: FontWeight.w600, fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
            if (msg.mediaSize != null) Text(_fmtSize(msg.mediaSize!), style: TextStyle(color: tc.withOpacity(0.7), fontSize: 11)),
          ])),
          const SizedBox(width: 8), Icon(Icons.download_rounded, color: tc, size: 22),
        ]);
      case 'audio':
        return Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.music_note_rounded, color: tc, size: 20), const SizedBox(width: 8),
          Flexible(child: Text(msg.mediaName ?? 'Audio', style: TextStyle(color: tc, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]);
      default:
        return Text(msg.content ?? '', style: TextStyle(color: tc, fontSize: 15, height: 1.4));
    }
  }

  void _showOpts(BuildContext ctx) {
    showModalBottomSheet(context: ctx, backgroundColor: Colors.transparent, builder: (_) {
      final dark = Theme.of(ctx).brightness == Brightness.dark;
      return Container(margin: const EdgeInsets.all(12), decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(20)), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4, margin: const EdgeInsets.only(top: 10, bottom: 6), decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: ['❤️','😂','😮','😢','😡','👍','🙏','🔥'].map((e) => GestureDetector(onTap: () { Navigator.pop(ctx); onReact(e); }, child: Text(e, style: const TextStyle(fontSize: 28)))).toList())),
        const Divider(height: 1),
        ListTile(leading: const Icon(Icons.reply_rounded), title: const Text('Reply'), onTap: () { Navigator.pop(ctx); onReply(); }),
        if (msg.type == 'text') ListTile(leading: const Icon(Icons.copy_rounded), title: const Text('Copy'), onTap: () { Navigator.pop(ctx); onCopy(); }),
        ListTile(leading: const Icon(Icons.star_outline_rounded), title: const Text('Star'), onTap: () { Navigator.pop(ctx); onStar(); }),
        ListTile(leading: const Icon(Icons.forward_rounded), title: const Text('Forward'), onTap: () => Navigator.pop(ctx)),
        if (isMe && msg.type == 'text') ListTile(leading: const Icon(Icons.edit_rounded, color: AppTheme.orange), title: const Text('Edit'), onTap: () { Navigator.pop(ctx); onEdit(); }),
        ListTile(leading: const Icon(Icons.info_outline_rounded), title: const Text('Message info'), onTap: () { Navigator.pop(ctx); onInfo(); }),
        if (isMe) ListTile(leading: const Icon(Icons.delete_outline_rounded, color: Colors.red), title: const Text('Delete', style: TextStyle(color: Colors.red)), onTap: () { Navigator.pop(ctx); onDelete(); }),
        const SizedBox(height: 14),
      ]));
    });
  }
}

// ─── Orange read ticks (like WhatsApp green but orange)
class _StatusTick extends StatelessWidget {
  final MessageStatus status;
  const _StatusTick({required this.status});
  @override
  Widget build(BuildContext _) {
    switch (status) {
      case MessageStatus.sending:
        return const Icon(Icons.access_time_rounded, size: 13, color: Colors.white70);
      case MessageStatus.sent:
        return const Icon(Icons.check_rounded, size: 14, color: Colors.white70);
      case MessageStatus.delivered:
        return const Icon(Icons.done_all_rounded, size: 14, color: Colors.white70);
      case MessageStatus.seen:
        return const Icon(Icons.done_all_rounded, size: 14, color: AppTheme.orange);
    }
  }
}

// ─── Voice note player
class _VoicePlayer extends StatefulWidget {
  final String? url; final int? dur; final Color tc;
  const _VoicePlayer({this.url, this.dur, required this.tc});
  @override State<_VoicePlayer> createState() => _VPS();
}
class _VPS extends State<_VoicePlayer> {
  final _player = AudioPlayer(); bool _playing = false; Duration _pos = Duration.zero; Duration _total = Duration.zero;
  @override void initState() { super.initState(); if (widget.dur != null) _total = Duration(seconds: widget.dur!); _player.onPositionChanged.listen((p) { if (mounted) setState(() => _pos = p); }); _player.onDurationChanged.listen((d) { if (mounted) setState(() => _total = d); }); _player.onPlayerComplete.listen((_) { if (mounted) setState(() { _playing = false; _pos = Duration.zero; }); }); }
  @override void dispose() { _player.dispose(); super.dispose(); }
  String _fmt(Duration d) { final m = d.inMinutes; final s = d.inSeconds % 60; return '${m.toString().padLeft(2,'0')}:${s.toString().padLeft(2,'0')}'; }
  @override
  Widget build(BuildContext _) => SizedBox(width: 200, child: Row(children: [
    GestureDetector(onTap: () async { if (_playing) { await _player.pause(); setState(() => _playing = false); } else if (widget.url != null) { await _player.play(UrlSource(widget.url!)); setState(() => _playing = true); } },
      child: Container(width: 38, height: 38, decoration: BoxDecoration(color: widget.tc.withOpacity(0.2), shape: BoxShape.circle), child: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: widget.tc, size: 22))),
    const SizedBox(width: 8),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SliderTheme(data: SliderThemeData(thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5), trackHeight: 3, overlayShape: SliderComponentShape.noOverlay),
        child: Slider(value: _total.inMilliseconds > 0 ? (_pos.inMilliseconds / _total.inMilliseconds).clamp(0.0, 1.0) : 0.0, onChanged: (v) async { await _player.seek(Duration(milliseconds: (v * _total.inMilliseconds).round())); }, activeColor: widget.tc, inactiveColor: widget.tc.withOpacity(0.3))),
      Padding(padding: const EdgeInsets.only(left: 6), child: Text(_playing ? _fmt(_pos) : _fmt(_total), style: TextStyle(fontSize: 10, color: widget.tc.withOpacity(0.7)))),
    ])),
  ]));
}

// ─── Typing animation
class _TypingBubble extends StatefulWidget {
  final bool dark;
  const _TypingBubble({required this.dark});
  @override State<_TypingBubble> createState() => _TBS();
}
class _TBS extends State<_TypingBubble> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  @override void initState() { super.initState(); _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(); }
  @override void dispose() { _c.dispose(); super.dispose(); }
  @override Widget build(BuildContext _) => Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), decoration: BoxDecoration(color: widget.dark ? AppTheme.dCard : const Color(0xFFF0F0F0), borderRadius: BorderRadius.circular(18)),
    child: Row(mainAxisSize: MainAxisSize.min, children: List.generate(3, (i) => AnimatedBuilder(animation: _c, builder: (_, __) {
      final phase = ((_c.value * 3) - i).clamp(0.0, 1.0);
      return Container(width: 7, height: 7, margin: const EdgeInsets.symmetric(horizontal: 2), decoration: BoxDecoration(color: AppTheme.orange.withOpacity(0.4 + phase * 0.6), shape: BoxShape.circle));
    }))));
}

// ─── Recording bar
class _RecBar extends StatelessWidget {
  final int secs; final String Function() dur; final VoidCallback onCancel, onSend;
  const _RecBar({required this.secs, required this.dur, required this.onCancel, required this.onSend});
  @override Widget build(BuildContext _) => Row(children: [
    GestureDetector(onTap: onCancel, child: const Padding(padding: EdgeInsets.all(10), child: Icon(Icons.delete_outline_rounded, color: Colors.red, size: 28))),
    Expanded(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(width: 10, height: 10, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
      const SizedBox(width: 8), Text(dur(), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: Colors.red)),
      const SizedBox(width: 8), const Text('Recording...', style: TextStyle(color: Colors.grey, fontSize: 12)),
    ])),
    GestureDetector(onTap: onSend, child: Container(width: 46, height: 46, decoration: const BoxDecoration(gradient: LinearGradient(colors: [AppTheme.orange, AppTheme.orangeDark]), shape: BoxShape.circle), child: const Icon(Icons.send_rounded, color: Colors.white, size: 22))),
  ]);
}

class _AI extends StatelessWidget {
  final IconData icon; final String label; final Color color; final VoidCallback onTap;
  const _AI(this.icon, this.label, this.color, this.onTap);
  @override Widget build(BuildContext _) => GestureDetector(onTap: onTap, child: Column(children: [
    Container(width: 60, height: 60, decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(18)), child: Icon(icon, color: color, size: 28)),
    const SizedBox(height: 6), Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
  ]));
}
