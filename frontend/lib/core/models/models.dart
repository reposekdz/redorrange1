// lib/core/models/models.dart

class UserModel {
  final String id, phoneNumber;
  final String? username, displayName, bio, avatarUrl, coverUrl, website, location, gender, statusText, lastSeen;
  final bool isVerified, isPrivate, isOnline, needsSetup;
  final int followersCount, followingCount, postsCount, reelsCount, unreadNotifications;
  final String? followStatus;
  final bool isBlocked, blockedMe;

  const UserModel({
    required this.id, required this.phoneNumber,
    this.username, this.displayName, this.bio, this.avatarUrl, this.coverUrl,
    this.website, this.location, this.gender, this.statusText, this.lastSeen,
    this.isVerified = false, this.isPrivate = false, this.isOnline = false, this.needsSetup = false,
    this.followersCount = 0, this.followingCount = 0, this.postsCount = 0, this.reelsCount = 0,
    this.unreadNotifications = 0, this.followStatus, this.isBlocked = false, this.blockedMe = false,
  });

  factory UserModel.fromJson(Map<String, dynamic> j) => UserModel(
    id: j['id'] ?? '', phoneNumber: j['phone_number'] ?? '',
    username: j['username'], displayName: j['display_name'], bio: j['bio'],
    avatarUrl: j['avatar_url'], coverUrl: j['cover_url'], website: j['website'],
    location: j['location'], gender: j['gender'], statusText: j['status_text'], lastSeen: j['last_seen'],
    isVerified: _b(j['is_verified']), isPrivate: _b(j['is_private']), isOnline: _b(j['is_online']),
    needsSetup: _b(j['needs_setup']),
    followersCount: _i(j['followers_count']), followingCount: _i(j['following_count']),
    postsCount: _i(j['posts_count']), reelsCount: _i(j['reels_count']),
    unreadNotifications: _i(j['unread_notifications']),
    followStatus: j['follow_status'], isBlocked: _b(j['is_blocked']), blockedMe: _b(j['blocked_me']),
  );

  UserModel copyWith({String? displayName, String? bio, String? avatarUrl, String? coverUrl,
    String? website, String? location, String? gender, String? statusText,
    bool? isPrivate, bool? isOnline, int? followersCount, int? followingCount, int? postsCount}) =>
    UserModel(
      id: id, phoneNumber: phoneNumber, username: username,
      displayName: displayName ?? this.displayName, bio: bio ?? this.bio,
      avatarUrl: avatarUrl ?? this.avatarUrl, coverUrl: coverUrl ?? this.coverUrl,
      website: website ?? this.website, location: location ?? this.location,
      gender: gender ?? this.gender, statusText: statusText ?? this.statusText,
      lastSeen: lastSeen, isVerified: isVerified,
      isPrivate: isPrivate ?? this.isPrivate, isOnline: isOnline ?? this.isOnline,
      followersCount: followersCount ?? this.followersCount,
      followingCount: followingCount ?? this.followingCount,
      postsCount: postsCount ?? this.postsCount, reelsCount: reelsCount,
      followStatus: followStatus, isBlocked: isBlocked,
    );
}

class PostModel {
  final String id, userId, createdAt;
  final String? caption, location, type;
  final bool isPublic, allowComments, isLiked, isSaved;
  final int likesCount, commentsCount, sharesCount, viewsCount;
  final List<MediaItem> media;
  final UserModel? user;

  const PostModel({
    required this.id, required this.userId, required this.createdAt,
    this.caption, this.location, this.type = 'image',
    this.isPublic = true, this.allowComments = true, this.isLiked = false, this.isSaved = false,
    this.likesCount = 0, this.commentsCount = 0, this.sharesCount = 0, this.viewsCount = 0,
    this.media = const [], this.user,
  });

  factory PostModel.fromJson(Map<String, dynamic> j) => PostModel(
    id: j['id'] ?? '', userId: j['user_id'] ?? '', createdAt: j['created_at'] ?? '',
    caption: j['caption'], location: j['location'], type: j['type'] ?? 'image',
    isPublic: _b(j['is_public']), allowComments: _b(j['allow_comments']),
    isLiked: _b(j['is_liked']), isSaved: _b(j['is_saved']),
    likesCount: _i(j['likes_count']), commentsCount: _i(j['comments_count']),
    sharesCount: _i(j['shares_count']), viewsCount: _i(j['views_count']),
    media: (j['media'] as List? ?? []).map((m) => MediaItem.fromJson(Map<String,dynamic>.from(m))).toList(),
    user: j['username'] != null ? UserModel.fromJson(j) : null,
  );

  PostModel copyWith({bool? isLiked, bool? isSaved, int? likesCount, int? commentsCount}) => PostModel(
    id: id, userId: userId, createdAt: createdAt, caption: caption, location: location, type: type,
    isPublic: isPublic, allowComments: allowComments,
    isLiked: isLiked ?? this.isLiked, isSaved: isSaved ?? this.isSaved,
    likesCount: likesCount ?? this.likesCount, commentsCount: commentsCount ?? this.commentsCount,
    sharesCount: sharesCount, viewsCount: viewsCount, media: media, user: user,
  );
}

class MediaItem {
  final String mediaUrl, mediaType;
  final String? thumbnailUrl;
  final int? width, height, duration, orderIndex;
  const MediaItem({required this.mediaUrl, required this.mediaType, this.thumbnailUrl, this.width, this.height, this.duration, this.orderIndex});
  factory MediaItem.fromJson(Map<String, dynamic> j) => MediaItem(
    mediaUrl: j['media_url'] ?? '', mediaType: j['media_type'] ?? 'image',
    thumbnailUrl: j['thumbnail_url'], width: j['width'], height: j['height'],
    duration: j['duration'], orderIndex: j['order_index'],
  );
}

class StoryModel {
  final String id, userId, mediaUrl, mediaType, createdAt, expiresAt;
  final String? caption, textOverlay, bgColor, musicTitle, musicArtist, musicUrl;
  final int viewsCount, duration;
  final UserModel? user;

  const StoryModel({
    required this.id, required this.userId, required this.mediaUrl,
    required this.mediaType, required this.createdAt, required this.expiresAt,
    this.caption, this.textOverlay, this.bgColor, this.musicTitle, this.musicArtist, this.musicUrl,
    this.viewsCount = 0, this.duration = 5, this.user,
  });

  factory StoryModel.fromJson(Map<String, dynamic> j) => StoryModel(
    id: j['id'] ?? '', userId: j['user_id'] ?? '',
    mediaUrl: j['media_url'] ?? '', mediaType: j['media_type'] ?? 'image',
    createdAt: j['created_at'] ?? '', expiresAt: j['expires_at'] ?? '',
    caption: j['caption'], textOverlay: j['text_overlay'], bgColor: j['bg_color'],
    musicTitle: j['music_title'], musicArtist: j['music_artist'], musicUrl: j['music_url'],
    viewsCount: _i(j['views_count']), duration: _i(j['duration'], 5),
    user: j['username'] != null ? UserModel.fromJson(j) : null,
  );
}

class ReelModel {
  final String id, userId, videoUrl, createdAt;
  final String? caption, thumbnailUrl, musicTitle, musicArtist, musicUrl;
  final bool isLiked, isSaved;
  final int likesCount, commentsCount, viewsCount, sharesCount;
  final UserModel? user;

  const ReelModel({
    required this.id, required this.userId, required this.videoUrl, required this.createdAt,
    this.caption, this.thumbnailUrl, this.musicTitle, this.musicArtist, this.musicUrl,
    this.isLiked = false, this.isSaved = false,
    this.likesCount = 0, this.commentsCount = 0, this.viewsCount = 0, this.sharesCount = 0,
    this.user,
  });

  factory ReelModel.fromJson(Map<String, dynamic> j) => ReelModel(
    id: j['id'] ?? '', userId: j['user_id'] ?? '',
    videoUrl: j['video_url'] ?? '', createdAt: j['created_at'] ?? '',
    caption: j['caption'], thumbnailUrl: j['thumbnail_url'],
    musicTitle: j['music_title'], musicArtist: j['music_artist'], musicUrl: j['music_url'],
    isLiked: _b(j['is_liked']), isSaved: _b(j['is_saved']),
    likesCount: _i(j['likes_count']), commentsCount: _i(j['comments_count']),
    viewsCount: _i(j['views_count']), sharesCount: _i(j['shares_count']),
    user: j['username'] != null ? UserModel.fromJson(j) : null,
  );
}

class ConversationModel {
  final String id, type;
  final String? name, avatarUrl, description;
  final String? lmContent, lmType, lmSenderId, lmSenderName, lmAt;
  final int unreadCount, membersCount;
  final String? otherId, otherUsername, otherDisplayName, otherAvatarUrl, otherLastSeen, otherStatusText;
  final bool otherIsOnline, otherIsVerified;
  final List<Map<String, dynamic>> membersPreview;
  final bool isMuted;

  const ConversationModel({
    required this.id, required this.type,
    this.name, this.avatarUrl, this.description,
    this.lmContent, this.lmType, this.lmSenderId, this.lmSenderName, this.lmAt,
    this.unreadCount = 0, this.membersCount = 0,
    this.otherId, this.otherUsername, this.otherDisplayName, this.otherAvatarUrl,
    this.otherLastSeen, this.otherStatusText,
    this.otherIsOnline = false, this.otherIsVerified = false,
    this.membersPreview = const [],
    this.isMuted = false,
  });

  String get displayName => type == 'group' ? (name ?? 'Group') : (otherDisplayName ?? otherUsername ?? 'Unknown');
  String? get displayAvatar => type == 'group' ? avatarUrl : otherAvatarUrl;

  factory ConversationModel.fromJson(Map<String, dynamic> j) => ConversationModel(
    id: j['id'] ?? '', type: j['type'] ?? 'direct',
    name: j['name'], avatarUrl: j['avatar_url'], description: j['description'],
    lmContent: j['lm_content'], lmType: j['lm_type'], lmSenderId: j['lm_sender'],
    lmSenderName: j['lm_sender_name'], lmAt: j['lm_at'] ?? j['last_message_at'],
    unreadCount: _i(j['unread_count']), membersCount: _i(j['members_count']),
    otherId: j['other_id'], otherUsername: j['other_username'],
    otherDisplayName: j['other_display_name'], otherAvatarUrl: j['other_avatar_url'],
    otherLastSeen: j['other_last_seen'], otherStatusText: j['other_status_text'],
    otherIsOnline: _b(j['other_is_online']), otherIsVerified: _b(j['other_is_verified']),
    membersPreview: List<Map<String, dynamic>>.from(j['members'] ?? j['members_preview'] ?? []),
    isMuted: _b(j['muted_until']),
  );
}

// ── Message read/delivery status
enum MessageStatus { sending, sent, delivered, seen }

class MessageModel {
  final String id, conversationId, senderId, type, createdAt;
  final String? content, mediaUrl, mediaThumbnail, mediaName, mediaMime;
  final int? mediaDuration, mediaSize;
  final double? latitude, longitude;
  final String? contactName, contactPhone;
  final String? replyToId, replyContent, replyType, replySenderName, replySenderUsername;
  final bool isEdited, isDeleted, deletedForAll;
  final List<Map<String, dynamic>> reactions;
  final String? username, displayName, avatarUrl;
  // Read/delivery status
  final MessageStatus status;
  final List<String> readBy;       // list of user IDs who have read this message
  final List<String> deliveredTo;  // list of user IDs message was delivered to

  const MessageModel({
    required this.id, required this.conversationId, required this.senderId,
    required this.type, required this.createdAt,
    this.content, this.mediaUrl, this.mediaThumbnail, this.mediaName, this.mediaMime,
    this.mediaDuration, this.mediaSize, this.latitude, this.longitude,
    this.contactName, this.contactPhone,
    this.replyToId, this.replyContent, this.replyType, this.replySenderName, this.replySenderUsername,
    this.isEdited = false, this.isDeleted = false, this.deletedForAll = false,
    this.reactions = const [],
    this.username, this.displayName, this.avatarUrl,
    this.status = MessageStatus.sent,
    this.readBy = const [],
    this.deliveredTo = const [],
  });

  factory MessageModel.fromJson(Map<String, dynamic> j) => MessageModel(
    id: j['id'] ?? '', conversationId: j['conversation_id'] ?? '',
    senderId: j['sender_id'] ?? '', type: j['type'] ?? 'text', createdAt: j['created_at'] ?? '',
    content: j['content'], mediaUrl: j['media_url'], mediaThumbnail: j['media_thumbnail'],
    mediaName: j['media_name'], mediaMime: j['media_mime'],
    mediaDuration: j['media_duration'], mediaSize: j['media_size'],
    latitude: j['latitude'] != null ? double.tryParse(j['latitude'].toString()) : null,
    longitude: j['longitude'] != null ? double.tryParse(j['longitude'].toString()) : null,
    contactName: j['contact_name'], contactPhone: j['contact_phone'],
    replyToId: j['reply_to_id'], replyContent: j['reply_content'],
    replyType: j['reply_type'], replySenderName: j['reply_sender_name'],
    replySenderUsername: j['reply_sender_username'],
    isEdited: _b(j['is_edited']), isDeleted: _b(j['is_deleted']), deletedForAll: _b(j['deleted_for_all']),
    reactions: List<Map<String, dynamic>>.from(j['reactions'] ?? []),
    username: j['username'], displayName: j['display_name'], avatarUrl: j['avatar_url'],
    status: _parseStatus(j['status'], j['read_by'], j['delivered_to']),
    readBy: List<String>.from(j['read_by'] ?? []),
    deliveredTo: List<String>.from(j['delivered_to'] ?? []),
  );

  MessageModel copyWithStatus(MessageStatus s) => MessageModel(
    id: id, conversationId: conversationId, senderId: senderId, type: type, createdAt: createdAt,
    content: content, mediaUrl: mediaUrl, mediaThumbnail: mediaThumbnail, mediaName: mediaName,
    mediaMime: mediaMime, mediaDuration: mediaDuration, mediaSize: mediaSize,
    latitude: latitude, longitude: longitude, contactName: contactName, contactPhone: contactPhone,
    replyToId: replyToId, replyContent: replyContent, replyType: replyType,
    replySenderName: replySenderName, replySenderUsername: replySenderUsername,
    isEdited: isEdited, isDeleted: isDeleted, deletedForAll: deletedForAll,
    reactions: reactions, username: username, displayName: displayName, avatarUrl: avatarUrl,
    status: s, readBy: readBy, deliveredTo: deliveredTo,
  );

  static MessageStatus _parseStatus(dynamic statusStr, dynamic readBy, dynamic deliveredTo) {
    if (statusStr == 'seen' || (readBy is List && readBy.isNotEmpty)) return MessageStatus.seen;
    if (statusStr == 'delivered' || (deliveredTo is List && deliveredTo.isNotEmpty)) return MessageStatus.delivered;
    if (statusStr == 'sent') return MessageStatus.sent;
    return MessageStatus.sent;
  }
}

class EventModel {
  final String id, creatorId, title, startDatetime, createdAt;
  final String? description, coverUrl, eventType, endDatetime, location, onlineLink, myStatus;
  final int goingCount, interestedCount;
  final UserModel? creator;
  const EventModel({
    required this.id, required this.creatorId, required this.title,
    required this.startDatetime, required this.createdAt,
    this.description, this.coverUrl, this.eventType = 'public',
    this.endDatetime, this.location, this.onlineLink, this.myStatus,
    this.goingCount = 0, this.interestedCount = 0, this.creator,
  });
  factory EventModel.fromJson(Map<String, dynamic> j) => EventModel(
    id: j['id'] ?? '', creatorId: j['creator_id'] ?? '', title: j['title'] ?? '',
    startDatetime: j['start_datetime'] ?? '', createdAt: j['created_at'] ?? '',
    description: j['description'], coverUrl: j['cover_url'], eventType: j['event_type'] ?? 'public',
    endDatetime: j['end_datetime'], location: j['location'], onlineLink: j['online_link'],
    myStatus: j['my_status'], goingCount: _i(j['going_count']), interestedCount: _i(j['interested_count']),
    creator: j['username'] != null ? UserModel.fromJson(j) : null,
  );
}

class NotificationModel {
  final String id, type, createdAt;
  final String? actorId, actorUsername, actorName, actorAvatar, targetType, targetId, message;
  final bool isRead;
  const NotificationModel({
    required this.id, required this.type, required this.createdAt,
    this.actorId, this.actorUsername, this.actorName, this.actorAvatar,
    this.targetType, this.targetId, this.message, this.isRead = false,
  });
  factory NotificationModel.fromJson(Map<String, dynamic> j) => NotificationModel(
    id: j['id'] ?? '', type: j['type'] ?? '', createdAt: j['created_at'] ?? '',
    actorId: j['actor_id'], actorUsername: j['actor_username'],
    actorName: j['actor_name'], actorAvatar: j['actor_avatar'],
    targetType: j['target_type'], targetId: j['target_id'], message: j['message'],
    isRead: _b(j['is_read']),
  );
}

class ContactModel {
  final String id;
  final String? username, displayName, avatarUrl, statusText, nickname;
  final bool isOnline, isVerified, isBlocked;
  final String? lastSeen;
  const ContactModel({
    required this.id, this.username, this.displayName, this.avatarUrl,
    this.statusText, this.nickname, this.lastSeen,
    this.isOnline = false, this.isVerified = false, this.isBlocked = false,
  });
  factory ContactModel.fromJson(Map<String, dynamic> j) => ContactModel(
    id: j['id'] ?? '', username: j['username'], displayName: j['display_name'],
    avatarUrl: j['avatar_url'], statusText: j['status_text'], nickname: j['nickname'],
    lastSeen: j['last_seen'], isOnline: _b(j['is_online']),
    isVerified: _b(j['is_verified']), isBlocked: _b(j['is_blocked']),
  );
  String get nameToDisplay => nickname ?? displayName ?? username ?? 'Unknown';
}

// ── Helpers
bool _b(dynamic v) => v == true || v == 1;
int  _i(dynamic v, [int d = 0]) => v == null ? d : (v is int ? v : int.tryParse(v.toString()) ?? d);
