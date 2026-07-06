import 'package:companion_ranchi/core/models/json_utils.dart';

/// The user who wrote a comment (embedded in [PostComment]).
class PostCommentUser {
  const PostCommentUser({required this.id, required this.name, this.photoUrl});

  final String id;
  final String name;
  final String? photoUrl;

  factory PostCommentUser.fromJson(Map<String, dynamic> json) =>
      PostCommentUser(
        id: J.asString(json['id']),
        name: J.asString(json['name'], 'User'),
        photoUrl: J.asStringOrNull(json['photoUrl']),
      );
}

/// A comment on a post (post_comments table).
class PostComment {
  const PostComment({
    required this.id,
    required this.postId,
    required this.body,
    this.createdAt,
    this.user,
  });

  final String id;
  final String postId;
  final String body;
  final DateTime? createdAt;
  final PostCommentUser? user;

  factory PostComment.fromJson(Map<String, dynamic> json) => PostComment(
        id: J.asString(json['id']),
        postId: J.asString(json['postId']),
        body: J.asString(json['body']),
        createdAt: J.asDate(json['createdAt']),
        user: json['user'] is Map
            ? PostCommentUser.fromJson(J.asMap(json['user']))
            : null,
      );
}
