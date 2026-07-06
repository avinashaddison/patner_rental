import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Securely persists the JWT access + refresh tokens (and an optional short
/// lived temp token used between OTP verify and profile registration).
///
/// Backed by `flutter_secure_storage` (Keychain on iOS, EncryptedSharedPrefs
/// on Android).
class TokenStorage {
  TokenStorage([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;

  static const _kAccess = 'cr_access_token';
  static const _kRefresh = 'cr_refresh_token';
  static const _kTemp = 'cr_temp_token';

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(key: _kAccess, value: accessToken);
    await _storage.write(key: _kRefresh, value: refreshToken);
  }

  Future<void> saveAccessToken(String accessToken) =>
      _storage.write(key: _kAccess, value: accessToken);

  Future<void> saveRefreshToken(String refreshToken) =>
      _storage.write(key: _kRefresh, value: refreshToken);

  Future<String?> readAccessToken() => _storage.read(key: _kAccess);

  Future<String?> readRefreshToken() => _storage.read(key: _kRefresh);

  /// Temp token issued by `/auth/otp/verify` when `isNewUser == true`; used to
  /// authorise `/auth/register`.
  Future<void> saveTempToken(String token) =>
      _storage.write(key: _kTemp, value: token);

  Future<String?> readTempToken() => _storage.read(key: _kTemp);

  Future<void> clearTempToken() => _storage.delete(key: _kTemp);

  Future<bool> hasTokens() async {
    final access = await readAccessToken();
    return access != null && access.isNotEmpty;
  }

  /// Wipe all stored credentials (logout / forced sign-out).
  Future<void> clear() async {
    await _storage.delete(key: _kAccess);
    await _storage.delete(key: _kRefresh);
    await _storage.delete(key: _kTemp);
  }
}

/// App-wide singleton provider for [TokenStorage].
final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());
