import 'package:companion_ranchi/core/models/json_utils.dart';

/// The companion who authored a post (embedded in [PostModel]).
class PostAuthor {
  const PostAuthor({
    required this.companionId,
    required this.name,
    this.userId,
    this.photoUrl,
    this.followerCount = 0,
    this.isVerified = false,
    this.isFollowing = false,
  });

  final String companionId;
  final String? userId;
  final String name;
  final String? photoUrl;
  final int followerCount;
  final bool isVerified;
  final bool isFollowing;

  factory PostAuthor.fromJson(Map<String, dynamic> json) => PostAuthor(
        companionId: J.asString(json['companionId']),
        userId: J.asStringOrNull(json['userId']),
        name: J.asString(json['name'], 'Companion'),
        photoUrl: J.asStringOrNull(json['photoUrl']),
        followerCount: J.asInt(json['followerCount']),
        isVerified: J.asBool(json['isVerified']),
        isFollowing: J.asBool(json['isFollowing']),
      );
}

/// An Instagram-style companion photo post (posts table).
class PostModel {
  const PostModel({
    required this.id,
    required this.companionId,
    required this.images,
    required this.likeCount,
    required this.commentCount,
    required this.status,
    required this.isLikedByMe,
    required this.isMine,
    this.caption,
    this.createdAt,
    this.author,
  });

  final String id;
  final String companionId;
  final String? caption;
  final List<String> images;
  final int likeCount;
  final int commentCount;
  final String status; // PUBLISHED | REMOVED
  final DateTime? createdAt;
  final bool isLikedByMe;
  final bool isMine;
  final PostAuthor? author;

  factory PostModel.fromJson(Map<String, dynamic> json) => PostModel(
        id: J.asString(json['id']),
        companionId: J.asString(json['companionId']),
        caption: J.asStringOrNull(json['caption']),
        images: J.asStringList(json['images']),
        likeCount: J.asInt(json['likeCount']),
        commentCount: J.asInt(json['commentCount']),
        status: J.asString(json['status'], 'PUBLISHED'),
        createdAt: J.asDate(json['createdAt']),
        isLikedByMe: J.asBool(json['isLikedByMe']),
        isMine: J.asBool(json['isMine']),
        author: json['author'] is Map
            ? PostAuthor.fromJson(J.asMap(json['author']))
            : null,
      );

  /// Optimistic local update for the like toggle + comment count.
  PostModel copyWith({
    bool? isLikedByMe,
    int? likeCount,
    int? commentCount,
  }) {
    return PostModel(
      id: id,
      companionId: companionId,
      images: images,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      status: status,
      isLikedByMe: isLikedByMe ?? this.isLikedByMe,
      isMine: isMine,
      caption: caption,
      createdAt: createdAt,
      author: author,
    );
  }
}
