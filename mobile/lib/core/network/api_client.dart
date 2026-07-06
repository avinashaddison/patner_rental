import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:companion_ranchi/core/env/env.dart';
import 'package:companion_ranchi/core/network/api_exception.dart';
import 'package:companion_ranchi/core/storage/token_storage.dart';

/// Thin wrapper around [Dio] that:
///  * targets `${Env.apiBaseUrl}`
///  * injects the JWT access token on every request
///  * transparently refreshes the access token on a 401 using the refresh
///    token (`POST /auth/refresh`), retrying the original request once
///  * unwraps the `{ success, data, meta }` envelope from API.md
///  * converts every failure into an [ApiException]
///
/// Returned values are the **`data`** field of the envelope (a Map or List).
class ApiClient {
  ApiClient({
    required TokenStorage tokenStorage,
    Dio? dio,
    this.onUnauthorized,
  }) : _tokens = tokenStorage {
    _dio = dio ??
        Dio(
          BaseOptions(
            baseUrl: Env.apiBaseUrl,
            connectTimeout: const Duration(seconds: 20),
            receiveTimeout: const Duration(seconds: 30),
            sendTimeout: const Duration(seconds: 30),
            contentType: 'application/json',
            headers: {'Accept': 'application/json'},
            // We validate status ourselves to read the error envelope. 401 is
            // excluded so it raises a DioException and activates the refresh +
            // auto-recover interceptor below; other 4xx pass through so their
            // error envelopes can be read in _ensureSuccess.
            validateStatus: (status) =>
                status != null && status < 500 && status != 401,
          ),
        );
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: _onRequest,
        onError: _onError,
      ),
    );
  }

  late final Dio _dio;
  final TokenStorage _tokens;

  /// Called after a refresh attempt fails (session truly expired) so the auth
  /// layer can sign the user out and route to /login.
  final FutureOr<void> Function()? onUnauthorized;

  /// Exposes the underlying Dio for advanced uses (e.g. file PUT to R2).
  Dio get raw => _dio;

  Completer<bool>? _refreshing;

  Future<void> _onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // Allow callers to opt out of auth (OTP/refresh endpoints) via extra flag.
    final skipAuth = options.extra['skipAuth'] == true;
    if (!skipAuth) {
      final token = options.extra['useTempToken'] == true
          ? await _tokens.readTempToken()
          : await _tokens.readAccessToken();
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }
    handler.next(options);
  }

  Future<void> _onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final response = err.response;
    final isAuthEndpoint =
        err.requestOptions.path.contains('/auth/refresh') ||
            err.requestOptions.path.contains('/auth/otp');

    if (response?.statusCode == 401 &&
        !isAuthEndpoint &&
        err.requestOptions.extra['retried'] != true) {
      final refreshed = await _refreshToken();
      if (refreshed) {
        try {
          final clone = await _retry(err.requestOptions);
          return handler.resolve(clone);
        } on DioException catch (e) {
          return handler.next(e);
        }
      } else {
        await onUnauthorized?.call();
      }
    }
    handler.next(err);
  }

  /// Refreshes the access token. Multiple concurrent 401s share one refresh.
  ///
  /// First tries the standard refresh-token rotation (`POST /auth/refresh`).
  /// In debug/test builds, if that fails — e.g. the stored session was a
  /// poisoned offline mock with no valid refresh token — it transparently
  /// re-mints a REAL session via `POST /auth/dev-login` so authenticated
  /// screens self-heal instead of surfacing "Invalid or expired token". This
  /// recovery is compiled out of release builds via [kDebugMode].
  Future<bool> _refreshToken() {
    final existing = _refreshing;
    if (existing != null) return existing.future;

    final completer = Completer<bool>();
    _refreshing = completer;

    () async {
      try {
        if (await _tryStandardRefresh()) {
          completer.complete(true);
          return;
        }
        if (kDebugMode && await _tryDevLoginRecovery()) {
          completer.complete(true);
          return;
        }
        completer.complete(false);
      } catch (_) {
        completer.complete(false);
      } finally {
        _refreshing = null;
      }
    }();

    return completer.future;
  }

  /// Standard refresh-token rotation. Returns true if a new pair was saved.
  /// A 401 (invalid/expired refresh token) now raises a DioException because of
  /// our validateStatus, so we swallow it and return false — letting the caller
  /// fall through to auto-recovery instead of aborting the whole refresh.
  Future<bool> _tryStandardRefresh() async {
    final refreshToken = await _tokens.readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) return false;
    try {
      final res = await _dio.post(
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
        options: Options(extra: {'skipAuth': true}),
      );
      return _saveTokenPair(_extractData(res));
    } on DioException {
      return false;
    }
  }

  /// DEBUG/TEST ONLY recovery: mint a fresh real session via dev-login when the
  /// stored session can't be refreshed. The backend falls back to the seeded
  /// demo customer and disables this entirely when NODE_ENV=production.
  Future<bool> _tryDevLoginRecovery() async {
    try {
      final res = await _dio.post(
        '/auth/dev-login',
        data: <String, dynamic>{},
        options: Options(extra: {'skipAuth': true}),
      );
      return _saveTokenPair(_extractData(res));
    } catch (_) {
      return false;
    }
  }

  /// Persist an access+refresh pair from a parsed envelope `data`. Returns
  /// whether a valid pair was found and saved.
  Future<bool> _saveTokenPair(dynamic data) async {
    if (data is Map &&
        data['accessToken'] is String &&
        data['refreshToken'] is String) {
      await _tokens.saveTokens(
        accessToken: data['accessToken'] as String,
        refreshToken: data['refreshToken'] as String,
      );
      return true;
    }
    return false;
  }

  Future<Response<dynamic>> _retry(RequestOptions requestOptions) {
    // Drop the stale Authorization header; _onRequest re-injects the freshly
    // refreshed access token. `retried` guards against an infinite loop.
    final options = Options(
      method: requestOptions.method,
      headers: Map<String, dynamic>.from(requestOptions.headers)
        ..remove('Authorization'),
      extra: {...requestOptions.extra, 'retried': true},
      contentType: requestOptions.contentType,
      responseType: requestOptions.responseType,
    );
    return _dio.request<dynamic>(
      requestOptions.path,
      data: requestOptions.data,
      queryParameters: requestOptions.queryParameters,
      options: options,
    );
  }

  // --------------------------------------------------------------------------
  // Public verbs. All return the unwrapped `data` payload.
  // --------------------------------------------------------------------------

  Future<dynamic> getJson(
    String path, {
    Map<String, dynamic>? query,
    bool skipAuth = false,
    bool useTempToken = false,
  }) =>
      _request(
        'GET',
        path,
        query: query,
        skipAuth: skipAuth,
        useTempToken: useTempToken,
      );

  Future<dynamic> postJson(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    bool skipAuth = false,
    bool useTempToken = false,
  }) =>
      _request(
        'POST',
        path,
        body: body,
        query: query,
        skipAuth: skipAuth,
        useTempToken: useTempToken,
      );

  Future<dynamic> patchJson(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    bool skipAuth = false,
    bool useTempToken = false,
  }) =>
      _request(
        'PATCH',
        path,
        body: body,
        query: query,
        skipAuth: skipAuth,
        useTempToken: useTempToken,
      );

  Future<dynamic> putJson(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    bool skipAuth = false,
    bool useTempToken = false,
  }) =>
      _request(
        'PUT',
        path,
        body: body,
        query: query,
        skipAuth: skipAuth,
        useTempToken: useTempToken,
      );

  Future<dynamic> delete(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    bool skipAuth = false,
  }) =>
      _request(
        'DELETE',
        path,
        body: body,
        query: query,
        skipAuth: skipAuth,
      );

  /// Returns the full envelope `{ success, data, meta }` for paginated calls
  /// that need `meta`.
  Future<Map<String, dynamic>> getEnvelope(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    const maxAttempts = 4;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final res = await _dio.get<dynamic>(
          path,
          queryParameters: query,
        );
        _ensureSuccess(res);
        final body = res.data;
        if (body is Map<String, dynamic>) return body;
        return {'success': true, 'data': body};
      } on DioException catch (e) {
        if (_isTransient(e) && attempt < maxAttempts) {
          await Future<void>.delayed(Duration(milliseconds: 350 * attempt));
          continue;
        }
        throw ApiException.fromDio(e);
      }
    }
    throw ApiException(message: 'Request failed.', code: 'INTERNAL');
  }

  /// Whether a Dio failure is a transient connectivity blip worth retrying
  /// (e.g. the dev USB tunnel re-establishing, brief network drop).
  static bool _isTransient(DioException e) =>
      e.type == DioExceptionType.connectionError ||
      e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.receiveTimeout ||
      e.type == DioExceptionType.sendTimeout;

  Future<dynamic> _request(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    bool skipAuth = false,
    bool useTempToken = false,
  }) async {
    const maxAttempts = 4;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final res = await _dio.request<dynamic>(
          path,
          data: body,
          queryParameters: query,
          options: Options(
            method: method,
            extra: {
              if (skipAuth) 'skipAuth': true,
              if (useTempToken) 'useTempToken': true,
            },
          ),
        );
        _ensureSuccess(res);
        return _extractData(res);
      } on DioException catch (e) {
        // Auto-retry transient connection failures with a short backoff so a
        // brief drop doesn't surface as "Couldn't load".
        if (_isTransient(e) && attempt < maxAttempts) {
          await Future<void>.delayed(Duration(milliseconds: 350 * attempt));
          continue;
        }
        throw ApiException.fromDio(e);
      }
    }
    // Unreachable, but satisfies the analyzer.
    throw ApiException(message: 'Request failed.', code: 'INTERNAL');
  }

  /// Throws an [ApiException] for 4xx envelopes (our validateStatus lets them
  /// through so we can read the error body here).
  void _ensureSuccess(Response<dynamic> res) {
    final status = res.statusCode ?? 0;
    if (status >= 200 && status < 300) return;
    final data = res.data;
    if (data is Map && data['error'] is Map) {
      final err = data['error'] as Map;
      throw ApiException(
        message: err['message'] as String? ?? 'Request failed.',
        code: err['code'] as String? ?? 'INTERNAL',
        statusCode: status,
        details: err['details'] is List ? err['details'] as List : const [],
      );
    }
    throw ApiException(
      message: 'Request failed ($status).',
      code: 'INTERNAL',
      statusCode: status,
    );
  }

  dynamic _extractData(Response<dynamic> res) {
    final body = res.data;
    if (body is Map<String, dynamic> && body.containsKey('data')) {
      return body['data'];
    }
    return body;
  }
}

/// App-wide [ApiClient] provider. The auth controller wires [onUnauthorized]
/// by listening; here we keep a no-op default and let auth override via a ref.
final apiClientProvider = Provider<ApiClient>((ref) {
  final tokens = ref.watch(tokenStorageProvider);
  return ApiClient(
    tokenStorage: tokens,
    onUnauthorized: () async {
      // Session expired: clear tokens. The router's auth redirect will then
      // send the user back to /login on the next navigation.
      await tokens.clear();
    },
  );
});
