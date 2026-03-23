import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/models/models.dart';
import '../../../shared/widgets/app_avatar.dart';
import '../../../shared/utils/format_utils.dart';

class PostDetailScreen extends ConsumerStatefulWidget {
  final String postId;
  const PostDetailScreen({super.key, required this.postId});
  @override ConsumerState<PostDetailScreen> createState() => _S();
}
class _S extends ConsumerState<PostDetailScreen> {
  PostModel? _post;
  List<Map<String,dynamic>> _comments = [];
  bool _loading = true, _sendingComment = false;
  final _commentCtrl = TextEditingController();
  final _focusNode    = FocusNode();
  final _pageCtrl     = PageController();
  int _page = 0;
  String? _replyToId, _replyToName;
  bool _showAllCaption = false;
  int _commentPage = 1;
  bool _hasMoreComments = true, _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _load();
    _listenSocket();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    _focusNode.dispose();
    _pageCtrl.dispose();
    ref.read(socketServiceProvider).leavePost(widget.postId);
    super.dispose();
  }

  void _listenSocket() {
    final s = ref.read(socketServiceProvider);
    s.joinPost(widget.postId);
    s.on('new_comment', (d) {
      if (d is! Map || d['post_id'] != widget.postId) return;
      final c = Map<String,dynamic>.from(d['comment'] as Map? ?? {});
      if (mounted) setState(() { _comments.insert(0, c); if (_post != null) _post = _post!.copyWith(commentsCount: _post!.commentsCount + 1); });
    });
    s.on('post_liked', (d) {
      if (d is! Map || d['post_id'] != widget.postId) return;
      if (mounted && _post != null) setState(() => _post = _post!.copyWith(likesCount: _post!.likesCount + 1));
    });
  }

  Future<void> _load() async {
    try {
      final api = ref.read(apiServiceProvider);
      final [pr, cr] = await Future.wait([
        api.get('/posts/${widget.postId}'),
        api.get('/posts/${widget.postId}/comments', q: {'page': '1', 'limit': '20'}),
      ]);
      if (mounted) setState(() {
        _post     = PostModel.fromJson(Map<String,dynamic>.from(pr.data['post'] ?? {}));
        _comments = List<Map<String,dynamic>>.from(cr.data['comments'] ?? []);
        _hasMoreComments = cr.data['has_more'] == true;
        _loading  = false;
      });
    } catch (e) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _loadMoreComments() async {
    if (_loadingMore || !_hasMoreComments) return;
    setState(() => _loadingMore = true);
    try {
      final r = await ref.read(apiServiceProvider).get('/posts/${widget.postId}/comments', q: {'page': '${_commentPage + 1}', 'limit': '20'});
      final more = List<Map<String,dynamic>>.from(r.data['comments'] ?? []);
      setState(() { _comments.addAll(more); _commentPage++; _hasMoreComments = r.data['has_more'] == true; });
    } catch (_) {}
    if (mounted) setState(() => _loadingMore = false);
  }

  Future<void> _toggleLike() async {
    if (_post == null) return;
    final prev = _post!.isLiked;
    setState(() => _post = _post!.copyWith(isLiked: !prev, likesCount: _post!.likesCount + (prev ? -1 : 1)));
    try {
      await ref.read(apiServiceProvider).post('/posts/${widget.postId}/like');
    } catch (_) {
      if (mounted) setState(() => _post = _post!.copyWith(isLiked: prev, likesCount: _post!.likesCount + (prev ? 1 : -1)));
    }
  }

  Future<void> _toggleSave() async {
    if (_post == null) return;
    final prev = _post!.isSaved;
    setState(() => _post = _post!.copyWith(isSaved: !prev));
    await ref.read(apiServiceProvider).post('/posts/${widget.postId}/save').catchError((_){});
  }

  Future<void> _sendComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty || _sendingComment) return;
    setState(() => _sendingComment = true);
    try {
      await ref.read(apiServiceProvider).post('/posts/${widget.postId}/comments', data: {
        'content': text,
        if (_replyToId != null) 'parent_id': _replyToId,
      });
      _commentCtrl.clear();
      setState(() { _replyToId = null; _replyToName = null; });
    } catch (_) {}
    if (mounted) setState(() => _sendingComment = false);
  }

  Future<void> _deleteComment(String id) async {
    await ref.read(apiServiceProvider).delete('/comments/$id').catchError((_){});
    setState(() {
      _comments.removeWhere((c) => c['id'] == id);
      if (_post != null) _post = _post!.copyWith(commentsCount: _post!.commentsCount - 1);
    });
  }

  void _showShareSheet() {
    showModalBottomSheet(context: context, backgroundColor: Colors.transparent, builder: (_) {
      final dark = Theme.of(context).brightness == Brightness.dark;
      return Container(
        margin: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: dark ? AppTheme.dCard : Colors.white, borderRadius: BorderRadius.circular(20)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, margin: const EdgeInsets.only(top: 10, bottom: 14), decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          const Text('Share', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _ShareOpt(Icons.message_rounded,      'Message',    AppTheme.orange,          () { Navigator.pop(context); context.push('/new-chat'); }),
            _ShareOpt(Icons.auto_stories_rounded, 'Story',      const Color(0xFF9C27B0),  () { Navigator.pop(context); }),
            _ShareOpt(Icons.copy_rounded,         'Copy Link',  const Color(0xFF2196F3),  () { Navigator.pop(context); Clipboard.setData(const ClipboardData(text: 'https://redorrange.app/post/')); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copied!'))); }),
            _ShareOpt(Icons.more_horiz_rounded,   'More',       Colors.grey,              () { Navigator.pop(context); }),
          ]),
          const SizedBox(height: 20),
        ]),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator(color: AppTheme.orange)));
    if (_post == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Post not found')));

    final post = _post!;
    final me   = ref.watch(currentUserProvider);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final isMe = post.userId == me?.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Post', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          if (isMe) ...[
            IconButton(icon: const Icon(Icons.insights_rounded, color: AppTheme.orange), onPressed: () => context.push('/post/${widget.postId}/insights'), tooltip: 'Insights'),
            IconButton(icon: const Icon(Icons.rocket_launch_rounded, color: AppTheme.orange), onPressed: () => context.push('/post/${widget.postId}/boost', extra: {'caption': post.caption ?? ''}), tooltip: 'Boost'),
          ],
          PopupMenuButton<String>(onSelected: (v) {
            if (v == 'report') context.push('/report/post/${widget.postId}');
            if (v == 'delete' && isMe) _deletePost();
            if (v == 'insights' && isMe) context.push('/post/${widget.postId}/insights');
          }, itemBuilder: (_) => [
            const PopupMenuItem(value: 'share', child: Row(children: [Icon(Icons.share_rounded, size: 18), SizedBox(width: 10), Text('Share')])),
            if (isMe) const PopupMenuItem(value: 'insights', child: Row(children: [Icon(Icons.analytics_rounded, size: 18, color: AppTheme.orange), SizedBox(width: 10), Text('View Insights')])),
            if (isMe) const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red), SizedBox(width: 10), Text('Delete', style: TextStyle(color: Colors.red))])),
            if (!isMe) const PopupMenuItem(value: 'report', child: Row(children: [Icon(Icons.flag_rounded, size: 18, color: Colors.red), SizedBox(width: 10), Text('Report', style: TextStyle(color: Colors.red))])),
          ]),
        ],
      ),
      body: Column(children: [
        Expanded(child: CustomScrollView(slivers: [
          // User header
          SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(12, 10, 12, 8), child: Row(children: [
            GestureDetector(onTap: () => context.push('/profile/${post.userId}'), child: AppAvatar(url: post.user?.avatarUrl, size: 44, username: post.user?.username)),
            const SizedBox(width: 10),
            Expanded(child: GestureDetector(onTap: () => context.push('/profile/${post.userId}'), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Flexible(child: Text(post.user?.displayName ?? post.user?.username ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15), overflow: TextOverflow.ellipsis)), if (post.user?.isVerified == true) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.verified_rounded, color: AppTheme.orange, size: 14))]),
              Text(timeago.format(DateTime.tryParse(post.createdAt) ?? DateTime.now()), style: TextStyle(fontSize: 12, color: dark ? AppTheme.dSub : AppTheme.lSub)),
            ]))),
            if (!isMe) ElevatedButton(onPressed: () async { await ref.read(apiServiceProvider).post('/users/${post.userId}/follow').catchError((_){}); }, style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), textStyle: const TextStyle(fontSize: 12)), child: const Text('Follow')),
          ]))),

          // Media carousel
          SliverToBoxAdapter(child: GestureDetector(
            onDoubleTap: _toggleLike,
            child: Stack(children: [
              post.media.isEmpty
                ? Container(height: 300, color: AppTheme.orangeSurf, child: const Center(child: Icon(Icons.image_outlined, size: 64, color: AppTheme.orange)))
                : SizedBox(height: post.media.length == 1 ? null : 400, child: PageView.builder(
                    controller: _pageCtrl,
                    itemCount: post.media.length,
                    onPageChanged: (i) => setState(() => _page = i),
                    itemBuilder: (_, i) {
                      final m = post.media[i];
                      return GestureDetector(
                        onTap: () => context.push('/media-viewer', extra: {'media': post.media.map((m) => {'media_url': m.mediaUrl, 'media_type': m.mediaType}).toList(), 'index': i}),
                        child: m.mediaType == 'video'
                          ? Container(color: Colors.black, height: 400, child: const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 72)))
                          : CachedNetworkImage(imageUrl: m.mediaUrl, fit: BoxFit.cover, width: double.infinity, errorWidget: (_, __, ___) => Container(height: 300, color: AppTheme.orangeSurf)),
                      );
                    })),
              if (post.media.length > 1) Positioned(top: 12, right: 12, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)), child: Text('${_page + 1}/${post.media.length}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)))),
            ]),
          )),

          // Page indicator
          if (post.media.length > 1) SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Center(child: SmoothPageIndicator(controller: _pageCtrl, count: post.media.length, effect: const ExpandingDotsEffect(activeDotColor: AppTheme.orange, dotColor: Colors.grey, dotHeight: 6, dotWidth: 6, expansionFactor: 3))))),

          // Actions row
          SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), child: Row(children: [
            // Like with count
            GestureDetector(onTap: _toggleLike, child: Row(children: [
              Icon(post.isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: post.isLiked ? Colors.red : null, size: 28),
              const SizedBox(width: 4),
              Text(FormatUtils.count(post.likesCount), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            ])),
            const SizedBox(width: 16),
            // Comment
            GestureDetector(onTap: () => _focusNode.requestFocus(), child: Row(children: [
              const Icon(Icons.chat_bubble_outline_rounded, size: 26),
              const SizedBox(width: 4),
              Text(FormatUtils.count(post.commentsCount), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            ])),
            const SizedBox(width: 16),
            // Share
            GestureDetector(onTap: _showShareSheet, child: const Icon(Icons.send_outlined, size: 26)),
            const SizedBox(width: 16),
            // Views
            Row(children: [Icon(Icons.remove_red_eye_rounded, size: 20, color: dark ? AppTheme.dSub : AppTheme.lSub), const SizedBox(width: 4), Text(FormatUtils.count(post.viewsCount), style: TextStyle(fontSize: 13, color: dark ? AppTheme.dSub : AppTheme.lSub))]),
            const Spacer(),
            // Save
            GestureDetector(onTap: _toggleSave, child: Icon(post.isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, color: post.isSaved ? AppTheme.orange : null, size: 28)),
          ]))),

          // Likes link
          if (post.likesCount > 0) SliverToBoxAdapter(child: GestureDetector(onTap: () => context.push('/post/${widget.postId}/likes'), child: Padding(padding: const EdgeInsets.fromLTRB(14, 2, 14, 6), child: Text('${FormatUtils.count(post.likesCount)} likes', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))))),

          // Caption
          if (post.caption != null && post.caption!.isNotEmpty) SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(14, 2, 14, 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            GestureDetector(onTap: () => setState(() => _showAllCaption = !_showAllCaption), child: RichText(text: TextSpan(style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14, height: 1.5), children: [TextSpan(text: '${post.user?.username ?? ''} ', style: const TextStyle(fontWeight: FontWeight.w700)), TextSpan(text: post.caption!)]), maxLines: _showAllCaption ? null : 3, overflow: _showAllCaption ? TextOverflow.visible : TextOverflow.ellipsis)),
            if (!_showAllCaption && (post.caption!.length > 100)) GestureDetector(onTap: () => setState(() => _showAllCaption = true), child: Text('more', style: TextStyle(color: dark ? AppTheme.dSub : AppTheme.lSub, fontSize: 13))),
          ]))),

          // Location
          if (post.location != null) SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 8), child: Row(children: [const Icon(Icons.location_on_rounded, size: 14, color: AppTheme.orange), const SizedBox(width: 4), Text(post.location!, style: const TextStyle(fontSize: 13, color: AppTheme.orange))]))),

          // Creator stats (if my post)
          if (isMe) SliverToBoxAdapter(child: _CreatorStats(post: post, postId: widget.postId)),

          // Comments header
          SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(14, 8, 14, 8), child: Row(children: [
            Text('${post.commentsCount} Comments', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const Spacer(),
            TextButton(onPressed: () {}, child: const Text('Newest', style: TextStyle(color: AppTheme.orange, fontSize: 13))),
          ]))),

          // Comments list
          _comments.isEmpty
            ? SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(24), child: Center(child: Column(children: [const Icon(Icons.chat_bubble_outline_rounded, size: 48, color: Colors.grey), const SizedBox(height: 8), Text('No comments yet. Be first!', style: TextStyle(color: dark ? AppTheme.dSub : AppTheme.lSub))]))))
            : SliverList(delegate: SliverChildBuilderDelegate((_, i) {
                if (i == _comments.length) return _loadingMore
                  ? const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.orange)))
                  : _hasMoreComments ? TextButton(onPressed: _loadMoreComments, child: const Text('Load more comments', style: TextStyle(color: AppTheme.orange))) : const SizedBox.shrink();
                final c = _comments[i];
                return _CommentTile(comment: c, dark: dark, myId: me?.id ?? '', onReply: () { setState(() { _replyToId = c['id']; _replyToName = c['username']; }); _focusNode.requestFocus(); }, onDelete: () => _deleteComment(c['id'] as String? ?? ''), onLike: () async { await ref.read(apiServiceProvider).post('/posts/${widget.postId}/comments/${c['id']}/like').catchError((_){}); });
              }, childCount: _comments.length + 1)),
        ])),

        // Reply banner
        if (_replyToName != null) Container(color: dark ? AppTheme.dCard : AppTheme.orangeSurf, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), child: Row(children: [const Icon(Icons.reply_rounded, color: AppTheme.orange, size: 16), const SizedBox(width: 6), Expanded(child: Text('Replying to @$_replyToName', style: const TextStyle(color: AppTheme.orange, fontSize: 12, fontWeight: FontWeight.w600))), IconButton(icon: const Icon(Icons.close_rounded, size: 18), onPressed: () => setState(() { _replyToId = null; _replyToName = null; }))]),),

        // Comment input
        Container(
          decoration: BoxDecoration(color: dark ? AppTheme.dSurf : Colors.white, border: Border(top: BorderSide(color: dark ? AppTheme.dDiv : AppTheme.lDiv, width: 0.5))),
          padding: EdgeInsets.only(left: 12, right: 8, top: 8, bottom: MediaQuery.of(context).viewInsets.bottom + 10),
          child: Row(children: [
            AppAvatar(url: me?.avatarUrl, size: 34, username: me?.username),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: _commentCtrl, focusNode: _focusNode, textInputAction: TextInputAction.send, onSubmitted: (_) => _sendComment(), decoration: InputDecoration(hintText: _replyToName != null ? 'Reply to @$_replyToName...' : 'Add a comment...', border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none), fillColor: dark ? AppTheme.dCard : const Color(0xFFF2F2F2), filled: true, contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), isDense: true))),
            const SizedBox(width: 8),
            GestureDetector(onTap: _sendComment, child: Container(width: 40, height: 40, decoration: const BoxDecoration(gradient: LinearGradient(colors: [AppTheme.orange, AppTheme.orangeDark]), shape: BoxShape.circle), child: _sendingComment ? const Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send_rounded, color: Colors.white, size: 20))),
          ]),
        ),
      ]),
    );
  }

  Future<void> _deletePost() async {
    final confirmed = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('Delete Post?'), content: const Text('This cannot be undone.'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: Colors.red)))]));
    if (confirmed != true) return;
    await ref.read(apiServiceProvider).delete('/posts/${widget.postId}').catchError((_){});
    if (mounted) context.pop();
  }
}

// ── Creator stats bar for own posts
class _CreatorStats extends StatelessWidget {
  final PostModel post; final String postId;
  const _CreatorStats({required this.post, required this.postId});
  @override Widget build(BuildContext context) => GestureDetector(
    onTap: () => context.push('/post/$postId/insights'),
    child: Container(margin: const EdgeInsets.fromLTRB(12, 4, 12, 8), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), decoration: BoxDecoration(color: AppTheme.orangeSurf, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.orange.withOpacity(0.2))), child: Row(children: [
      _MStat(Icons.remove_red_eye_rounded, FormatUtils.count(post.viewsCount), 'Views', const Color(0xFF2196F3)),
      _Divider(), _MStat(Icons.favorite_rounded, FormatUtils.count(post.likesCount), 'Likes', Colors.red),
      _Divider(), _MStat(Icons.chat_bubble_rounded, FormatUtils.count(post.commentsCount), 'Comments', const Color(0xFF9C27B0)),
      _Divider(), _MStat(Icons.send_rounded, FormatUtils.count(post.sharesCount), 'Shares', AppTheme.orange),
      const Spacer(), const Icon(Icons.analytics_rounded, color: AppTheme.orange, size: 16), const SizedBox(width: 4), const Text('Insights', style: TextStyle(color: AppTheme.orange, fontSize: 12, fontWeight: FontWeight.w600)),
    ])),
  );
}
class _MStat extends StatelessWidget {
  final IconData icon; final String value, label; final Color color;
  const _MStat(this.icon, this.value, this.label, this.color);
  @override Widget build(BuildContext _) => Column(children: [Row(children: [Icon(icon, size: 13, color: color), const SizedBox(width: 3), Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: color))]), Text(label, style: const TextStyle(fontSize: 9, color: Colors.grey))]);
}
class _Divider extends StatelessWidget {
  @override Widget build(BuildContext _) => Container(width: 1, height: 28, margin: const EdgeInsets.symmetric(horizontal: 10), color: AppTheme.orange.withOpacity(0.2));
}

// ── Comment tile
class _CommentTile extends StatefulWidget {
  final Map<String,dynamic> comment; final bool dark; final String myId;
  final VoidCallback onReply, onDelete, onLike;
  const _CommentTile({required this.comment, required this.dark, required this.myId, required this.onReply, required this.onDelete, required this.onLike});
  @override State<_CommentTile> createState() => _CTS();
}
class _CTS extends State<_CommentTile> {
  bool _liked = false; int _likes = 0;
  @override void initState() { super.initState(); _liked = widget.comment['is_liked'] == 1 || widget.comment['is_liked'] == true; _likes = widget.comment['likes_count'] as int? ?? 0; }
  @override Widget build(BuildContext context) {
    final c = widget.comment;
    final isMe = c['user_id'] == widget.myId;
    return Padding(padding: const EdgeInsets.fromLTRB(14, 8, 14, 4), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      GestureDetector(onTap: () => context.push('/profile/${c['user_id']}'), child: AppAvatar(url: c['avatar_url'], size: 36, username: c['username'])),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(color: widget.dark ? AppTheme.dCard : const Color(0xFFF4F4F4), borderRadius: BorderRadius.circular(14)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Text(c['username'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)), if (c['is_verified'] == 1) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.verified_rounded, color: AppTheme.orange, size: 12))]),
          const SizedBox(height: 3),
          Text(c['content'] ?? '', style: const TextStyle(fontSize: 14, height: 1.4)),
        ])),
        Padding(padding: const EdgeInsets.only(left: 4, top: 4), child: Row(children: [
          Text(timeago.format(DateTime.tryParse(c['created_at'] ?? '') ?? DateTime.now()), style: TextStyle(fontSize: 11, color: widget.dark ? AppTheme.dSub : AppTheme.lSub)),
          const SizedBox(width: 14),
          GestureDetector(onTap: widget.onReply, child: const Text('Reply', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.orange))),
          const SizedBox(width: 14),
          GestureDetector(onTap: () { setState(() { _liked = !_liked; _likes += _liked ? 1 : -1; }); widget.onLike(); }, child: Row(children: [Icon(_liked ? Icons.favorite_rounded : Icons.favorite_border_rounded, size: 13, color: _liked ? Colors.red : Colors.grey), const SizedBox(width: 3), Text('$_likes', style: const TextStyle(fontSize: 11, color: Colors.grey))])),
          if (isMe) ...[const SizedBox(width: 14), GestureDetector(onTap: widget.onDelete, child: const Text('Delete', style: TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.w600)))],
        ])),
      ])),
    ]));
  }
}

class _ShareOpt extends StatelessWidget {
  final IconData icon; final String label; final Color color; final VoidCallback onTap;
  const _ShareOpt(this.icon, this.label, this.color, this.onTap);
  @override Widget build(BuildContext _) => GestureDetector(onTap: onTap, child: Column(children: [Container(width: 56, height: 56, decoration: BoxDecoration(color: color.withOpacity(0.12), shape: BoxShape.circle), child: Icon(icon, color: color, size: 26)), const SizedBox(height: 6), Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))]));
}
