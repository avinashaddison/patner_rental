import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:companion_ranchi/core/network/api_client.dart';
import 'package:companion_ranchi/core/network/api_exception.dart';

/// The single source of truth for uploading files to Cloudflare R2.
///
/// Every feature uploads through here — avatar, post images, companion gallery
/// photos, KYC documents and chat attachments — so the flow stays correct and
/// consistent. The flow (API.md §15) is:
///   1. `POST /uploads/presign` → `{ uploadUrl, publicUrl }`
///   2. `PUT` the raw bytes to `uploadUrl`
///   3. store / return `publicUrl`
///
/// Two rules the presigned PUT MUST follow — the reason this lives in ONE place
/// instead of being re-implemented per repository:
///   * `extra: {'skipAuth': true}` — the R2 URL carries its own query-string
///     signature; attaching our JWT `Authorization` header makes R2 reject the
///     PUT with *"only one auth mechanism allowed"*.
///   * validate the response status — a non-2xx PUT must surface as an error,
///     never be silently treated as success.
///
/// [folder] must be one of the backend `UPLOAD_FOLDERS`:
/// `profile | companion-photos | kyc | chat | reports | posts | misc`.
class UploadsRepository {
  UploadsRepository(this._api);

  final ApiClient _api;

  /// Uploads raw [bytes] to R2 under [folder] and returns the public URL.
  Future<String> uploadBytes({
    required List<int> bytes,
    required String fileName,
    required String contentType,
    required String folder,
  }) async {
    final presign = await _api.postJson(
      '/uploads/presign',
      body: {
        'fileName': fileName,
        'contentType': contentType,
        'folder': folder,
      },
    );
    if (presign is! Map ||
        presign['uploadUrl'] is! String ||
        presign['publicUrl'] is! String) {
      throw ApiException(
        message: 'Could not prepare the upload. Please try again.',
        code: 'INTERNAL',
      );
    }
    final uploadUrl = presign['uploadUrl'] as String;
    final publicUrl = presign['publicUrl'] as String;

    // Raw PUT straight to the presigned (absolute) URL. `skipAuth` keeps the
    // interceptor from prepending the API base or attaching our JWT — both of
    // which would break the R2 upload. A generous validateStatus lets us raise
    // a precise error below instead of a generic DioException.
    final Response<dynamic> putRes = await _api.raw.put<dynamic>(
      uploadUrl,
      data: Stream.fromIterable([bytes]),
      options: Options(
        headers: {
          Headers.contentTypeHeader: contentType,
          Headers.contentLengthHeader: bytes.length,
        },
        extra: const {'skipAuth': true},
        validateStatus: (status) => status != null && status < 500,
      ),
    );
    final status = putRes.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      throw ApiException(
        message: 'Upload failed ($status). Please try again.',
        code: 'INTERNAL',
        statusCode: status,
      );
    }
    return publicUrl;
  }

  /// Reads [file] from disk and uploads it under [folder], deriving the file
  /// name and content type from the path.
  Future<String> uploadFile(File file, {required String folder}) async {
    final fileName = _basename(file.path);
    final bytes = await file.readAsBytes();
    return uploadBytes(
      bytes: bytes,
      fileName: fileName,
      contentType: contentTypeFor(fileName),
      folder: folder,
    );
  }

  /// Last path segment of [path] (handles both `/` and `\` separators).
  static String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    final slash = normalized.lastIndexOf('/');
    return slash < 0 ? normalized : normalized.substring(slash + 1);
  }

  /// Best-effort image content type from a file name's extension; defaults to
  /// JPEG. Stays within the backend's allowed content types.
  static String contentTypeFor(String fileName) {
    final dot = fileName.lastIndexOf('.');
    final ext = (dot <= 0 || dot == fileName.length - 1)
        ? ''
        : fileName.substring(dot).toLowerCase();
    switch (ext) {
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      case '.heic':
        return 'image/heic';
      case '.jpg':
      case '.jpeg':
      default:
        return 'image/jpeg';
    }
  }
}

/// App-wide [UploadsRepository], wired to the shared [ApiClient].
final uploadsRepositoryProvider = Provider<UploadsRepository>((ref) {
  return UploadsRepository(ref.watch(apiClientProvider));
});
