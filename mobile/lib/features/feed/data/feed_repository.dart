import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:companion_ranchi/core/models/json_utils.dart';
import 'package:companion_ranchi/core/models/post_model.dart';
import 'package:companion_ranchi/core/models/post_comment_model.dart';
import 'package:companion_ranchi/core/network/api_client.dart';
import 'package:companion_ranchi/core/network/uploads_repository.dart';

/// Data access for the social feed: companion photo posts, likes, comments and
/// follows. Image bytes upload to R2 via the presign flow (same as companion
/// photos); only the resulting public URL is sent to the API.
class FeedRepository {
  FeedRepository(this._api, this._uploads);

  final ApiClient _api;
  final UploadsRepository _uploads;

  // ---- Posts ----------------------------------------------------------------

  /// `GET /posts/feed` — posts from companions the user follows.
  Future<List<PostModel>> feed({int page = 1, int limit = 20}) =>
      _listPosts('/posts/feed', page: page, limit: limit);

  /// `GET /posts` — explore / discovery feed.
  Future<List<PostModel>> explore({int page = 1, int limit = 20}) =>
      _listPosts('/posts', page: page, limit: limit);

  /// `GET /companions/:id/posts` — a companion's posts grid.
  Future<List<PostModel>> companionPosts(
    String companionId, {
    int page = 1,
    int limit = 30,
  }) =>
      _listPosts('/companions/$companionId/posts', page: page, limit: limit);

  Future<List<PostModel>> _listPosts(
    String path, {
    required int page,
    required int limit,
  }) async {
    final env = await _api.getEnvelope(
      path,
      query: {'page': page, 'limit': limit, 'sort': 'createdAt:desc'},
    );
    return J
        .asMapList(env['data'])
        .map(PostModel.fromJson)
        .toList(growable: false);
  }

  /// `GET /posts/:id` — single post detail.
  Future<PostModel> detail(String id) async {
    final data = await _api.getJson('/posts/$id');
    return PostModel.fromJson(J.asMap(data));
  }

  /// `POST /posts` — companion publishes a post. Uploads [images] to R2 first.
  Future<PostModel> createPost({
    String? caption,
    required List<File> images,
  }) async {
    final urls = <String>[];
    for (final file in images) {
      urls.add(await _uploads.uploadFile(file, folder: 'posts'));
    }
    final data = await _api.postJson('/posts', body: {
      if (caption != null && caption.trim().isNotEmpty) 'caption': caption.trim(),
      'images': urls,
    });
    return PostModel.fromJson(J.asMap(data));
  }

  /// `DELETE /posts/:id` — owner companion deletes their post.
  Future<void> deletePost(String id) => _api.delete('/posts/$id');

  // ---- Likes ----------------------------------------------------------------

  Future<({bool liked, int likeCount})> like(String postId) async {
    final data = await _api.postJson('/posts/$postId/like');
    final m = J.asMap(data);
    return (liked: J.asBool(m['liked'], true), likeCount: J.asInt(m['likeCount']));
  }

  Future<({bool liked, int likeCount})> unlike(String postId) async {
    final data = await _api.delete('/posts/$postId/like');
    final m = J.asMap(data);
    return (liked: J.asBool(m['liked']), likeCount: J.asInt(m['likeCount']));
  }

  // ---- Comments -------------------------------------------------------------

  /// `GET /posts/:id/comments` — newest first.
  Future<List<PostComment>> comments(
    String postId, {
    int page = 1,
    int limit = 30,
  }) async {
    final env = await _api.getEnvelope(
      '/posts/$postId/comments',
      query: {'page': page, 'limit': limit},
    );
    return J
        .asMapList(env['data'])
        .map(PostComment.fromJson)
        .toList(growable: false);
  }

  /// `POST /posts/:id/comments`.
  Future<PostComment> addComment(String postId, String body) async {
    final data = await _api.postJson('/posts/$postId/comments', body: {'body': body});
    return PostComment.fromJson(J.asMap(data));
  }

  /// `DELETE /posts/comments/:commentId`.
  Future<void> deleteComment(String commentId) =>
      _api.delete('/posts/comments/$commentId');

  // ---- Follows --------------------------------------------------------------

  Future<({bool following, int followerCount})> follow(String companionId) async {
    final data = await _api.postJson('/companions/$companionId/follow');
    final m = J.asMap(data);
    return (
      following: J.asBool(m['following'], true),
      followerCount: J.asInt(m['followerCount']),
    );
  }

  Future<({bool following, int followerCount})> unfollow(String companionId) async {
    final data = await _api.delete('/companions/$companionId/follow');
    final m = J.asMap(data);
    return (
      following: J.asBool(m['following']),
      followerCount: J.asInt(m['followerCount']),
    );
  }

}

/// Provider for [FeedRepository].
final feedRepositoryProvider = Provider<FeedRepository>((ref) {
  return FeedRepository(
    ref.watch(apiClientProvider),
    ref.watch(uploadsRepositoryProvider),
  );
});
