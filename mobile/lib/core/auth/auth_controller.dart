import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'package:companion_ranchi/core/env/env.dart';
import 'package:companion_ranchi/core/models/user_model.dart';
import 'package:companion_ranchi/core/network/api_client.dart';
import 'package:companion_ranchi/core/network/api_exception.dart';
import 'package:companion_ranchi/core/storage/token_storage.dart';

/// Result of an OTP verification: whether the profile still needs to be
/// completed via [AuthController.register].
class OtpVerifyResult {
  const OtpVerifyResult({required this.isNewUser, this.user});
  final bool isNewUser;
  final UserModel? user;
}

/// Owns the authenticated session. Exposes the current [UserModel] (or null)
/// as `AsyncValue` and drives the OTP -> verify -> register flow.
///
/// Restored on startup by reading the stored access token and calling
/// `GET /auth/me`.
class AuthController extends AsyncNotifier<UserModel?> {
  ApiClient get _api => ref.read(apiClientProvider);
  TokenStorage get _tokens => ref.read(tokenStorageProvider);

  // Firebase Phone Auth state: set during requestOtp (codeSent), consumed by
  // verifyOtp. Only used when Firebase initialised (google-services.json present).
  String? _fbVerificationId;
  int? _fbResendToken;

  bool get _firebaseAvailable => Firebase.apps.isNotEmpty;

  // Verified profile pulled from the last Google sign-in, used to PREFILL the
  // registration screen for brand-new users (name + email come from Google).
  String? _pendingFullName;
  String? _pendingEmail;
  String? get pendingFullName => _pendingFullName;
  String? get pendingEmail => _pendingEmail;

  // ---- Offline test login -------------------------------------------------
  // Enter mobile number 2222222222 and OTP 222222 on the login screen to sign
  // in as a demo CUSTOMER without any backend. The login screen whitelists this
  // number past its Indian-number validation. Remove this block for production.
  static const String _devNumber = '2222222222';
  static const String _devAccessToken = 'dev-offline-access-token';
  static const String _devRefreshToken = 'dev-offline-refresh-token';

  bool _isDevNumber(String mobileNumber) {
    final digits = mobileNumber.replaceAll(RegExp(r'\D'), '');
    return digits == _devNumber || digits == '91$_devNumber';
  }

  UserModel _devUser([String? mobileNumber]) => UserModel(
        id: 'dev-customer',
        mobileNumber: (mobileNumber == null || mobileNumber.trim().isEmpty)
            ? '+91$_devNumber'
            : mobileNumber.trim(),
        fullName: 'Test User',
        role: 'CUSTOMER',
        isMobileVerified: true,
        gender: 'OTHER',
        dateOfBirth: DateTime(2000, 1, 1),
        city: 'Ranchi',
        referralCode: 'TESTCR',
        createdAt: DateTime(2026, 1, 1),
      );
  // -------------------------------------------------------------------------

  @override
  Future<UserModel?> build() async {
    final access = await _tokens.readAccessToken();
    // Restore the offline test session without contacting the backend.
    if (access == _devAccessToken) return _devUser();
    if (access == null || access.isEmpty) return null;
    try {
      return await _fetchMe();
    } catch (_) {
      // Token invalid/expired and refresh failed: treat as signed out.
      await _tokens.clear();
      return null;
    }
  }

  Future<UserModel?> _fetchMe() async {
    final data = await _api.getJson('/auth/me');
    if (data is Map<String, dynamic>) {
      // `/auth/me` may return `{ user, companion }` or the user directly.
      final userJson = data['user'] is Map
          ? Map<String, dynamic>.from(data['user'] as Map)
          : data;
      if (data['companion'] != null) {
        userJson['companion'] = data['companion'];
      }
      return UserModel.fromJson(userJson);
    }
    return null;
  }

  /// Step 1 — request an OTP for [mobileNumber]. Returns the expiry (seconds).
  Future<int> requestOtp(String mobileNumber) async {
    // TEST BUILD: never block login on the network. The demo number skips the
    // backend; any other number still tries the real API but falls through to
    // the OTP screen within 3s if it is unreachable, so the test OTP (222222)
    // can sign in offline. Revert this fallback for production.
    if (_isDevNumber(mobileNumber)) return 300;

    // Firebase Phone Auth (real SMS) when configured; this sends the OTP.
    if (_firebaseAvailable) {
      return _startFirebasePhoneAuth(mobileNumber);
    }

    // Fallback: backend OTP (console in dev / MSG91 in prod).
    try {
      final data = await _api.postJson(
        '/auth/otp/request',
        body: {'mobileNumber': mobileNumber},
        skipAuth: true,
      ).timeout(const Duration(seconds: 3));
      if (data is Map && data['expiresIn'] != null) {
        return int.tryParse(data['expiresIn'].toString()) ?? 300;
      }
      return 300;
    } catch (_) {
      // Offline / backend unreachable: proceed so 222222 can sign in.
      return 300;
    }
  }

  /// Step 2 — verify the OTP. On success stores tokens (access+refresh for
  /// returning users, or a temp token for new users) and updates [state].
  Future<OtpVerifyResult> verifyOtp({
    required String mobileNumber,
    required String otp,
  }) async {
    // TEST BUILD: OTP 222222 (with ANY mobile number) — or the demo number —
    // signs straight in as a demo CUSTOMER so the app can be explored without a
    // running backend. Remove this block for production.
    if (otp.trim() == '222222' || _isDevNumber(mobileNumber)) {
      // First try to obtain a REAL backend session (demo account) so that
      // authenticated screens (bookings, wallet, chat, profile) work end-to-end.
      try {
        final data = await _api
            .postJson('/auth/dev-login',
                body: {'mobileNumber': mobileNumber}, skipAuth: true)
            .timeout(const Duration(seconds: 6));
        final map = data is Map<String, dynamic> ? data : <String, dynamic>{};
        final accessToken = map['accessToken'] as String?;
        final refreshToken = map['refreshToken'] as String?;
        if (accessToken != null && refreshToken != null) {
          await _tokens
              .saveTokens(accessToken: accessToken, refreshToken: refreshToken)
              .timeout(const Duration(seconds: 4), onTimeout: () {});
          UserModel? user;
          if (map['user'] is Map) {
            user = UserModel.fromJson(
                Map<String, dynamic>.from(map['user'] as Map));
          }
          user ??= _devUser(mobileNumber);
          state = AsyncData(user);
          return OtpVerifyResult(isNewUser: false, user: user);
        }
      } catch (_) {
        // Backend unreachable — fall through to a fully-offline mock session.
      }
      final user = _devUser(mobileNumber);
      state = AsyncData(user);
      _tokens
          .saveTokens(
            accessToken: _devAccessToken,
            refreshToken: _devRefreshToken,
          )
          .catchError((_) {});
      return OtpVerifyResult(isNewUser: false, user: user);
    }

    // Firebase Phone Auth: complete the SMS code → Firebase ID token →
    // POST /auth/firebase (verified server-side) → our session.
    if (_firebaseAvailable && _fbVerificationId != null) {
      try {
        final credential = PhoneAuthProvider.credential(
          verificationId: _fbVerificationId!,
          smsCode: otp.trim(),
        );
        final result = await _completeFirebaseSignIn(credential);
        _fbVerificationId = null;
        return result;
      } on FirebaseAuthException catch (e) {
        throw ApiException(
          message: _friendlyFirebaseError(e),
          code: 'AUTH_ERROR',
        );
      }
    }

    final data = await _api.postJson(
      '/auth/otp/verify',
      body: {'mobileNumber': mobileNumber, 'otp': otp},
      skipAuth: true,
    );
    final map = data is Map<String, dynamic>
        ? data
        : <String, dynamic>{};

    final isNewUser = map['isNewUser'] == true;
    final accessToken = map['accessToken'] as String?;
    final refreshToken = map['refreshToken'] as String?;

    if (isNewUser) {
      // New users get a temp token to authorise /auth/register.
      if (accessToken != null) {
        await _tokens.saveTempToken(accessToken);
      }
      return const OtpVerifyResult(isNewUser: true);
    }

    if (accessToken != null && refreshToken != null) {
      await _tokens.saveTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
      );
    }
    UserModel? user;
    if (map['user'] is Map) {
      user = UserModel.fromJson(Map<String, dynamic>.from(map['user'] as Map));
      state = AsyncData(user);
    } else {
      await refreshUser();
    }
    return OtpVerifyResult(isNewUser: false, user: user ?? state.value);
  }

  // -- Google Sign-In --------------------------------------------------------

  /// Sign in with Google (via Supabase Auth). Opens the NATIVE Google account
  /// picker, exchanges the Google ID token for a Supabase session, then trades
  /// the Supabase access token with our backend (`POST /auth/supabase`) for our
  /// own JWTs. For a brand-new user the backend returns isNewUser=true + a
  /// registration token; the name/email are stashed to prefill the profile
  /// screen. Supabase is only the identity source — the rest of the app runs on
  /// our own tokens as usual.
  ///
  /// Returns `null` if the user dismisses the account chooser (not an error).
  Future<OtpVerifyResult?> signInWithGoogle() async {
    _pendingFullName = null;
    _pendingEmail = null;

    // 1) Native Google account picker → Google ID token. serverClientId must be
    // the Google WEB client id (the one configured in Supabase → Google) so the
    // token's audience is what Supabase expects.
    final googleSignIn = GoogleSignIn(
      serverClientId: Env.googleServerClientId,
      scopes: const ['email', 'profile'],
    );
    // Sign out first so the account chooser always appears (avoids silently
    // reusing a stale account).
    await googleSignIn.signOut();
    final googleUser = await googleSignIn.signIn();
    if (googleUser == null) return null; // dismissed the picker

    final googleAuth = await googleUser.authentication;
    final idToken = googleAuth.idToken;
    if (idToken == null) {
      throw ApiException(
        message: 'Google sign-in did not return an ID token.',
        code: 'AUTH_ERROR',
      );
    }

    // 2) Exchange the Google token for a Supabase session.
    final supabase = sb.Supabase.instance.client;
    final res = await supabase.auth.signInWithIdToken(
      provider: sb.OAuthProvider.google,
      idToken: idToken,
      accessToken: googleAuth.accessToken,
    );
    final supabaseToken = res.session?.accessToken;
    if (supabaseToken == null) {
      throw ApiException(
        message: 'Could not complete Google sign-in. Please try again.',
        code: 'AUTH_ERROR',
      );
    }

    // 3) Trade the Supabase token with our backend for app tokens.
    final data = await _api.postJson(
      '/auth/supabase',
      body: {'supabaseToken': supabaseToken},
      skipAuth: true,
    );
    final map = data is Map<String, dynamic> ? data : <String, dynamic>{};

    // /auth/supabase nests prefill for new users: { prefill: { fullName, email } }.
    // Flatten it so _applySessionEnvelope can stash the register prefill.
    if (map['prefill'] is Map) {
      final prefill = Map<String, dynamic>.from(map['prefill'] as Map);
      map['fullName'] ??= prefill['fullName'];
      map['email'] ??= prefill['email'];
    }
    return _applySessionEnvelope(map);
  }

  /// DEV/TEST ONLY: sign in as the seeded demo customer without Google, so the
  /// app can be tested before Google Sign-In is configured for a build. Triggered
  /// by a hidden long-press on the login logo. Remove for production.
  Future<void> devSignIn() async {
    final data = await _api.postJson(
      '/auth/dev-login',
      body: const <String, dynamic>{},
      skipAuth: true,
    );
    final map = data is Map<String, dynamic> ? data : <String, dynamic>{};
    final accessToken = map['accessToken'] as String?;
    final refreshToken = map['refreshToken'] as String?;
    if (accessToken != null && refreshToken != null) {
      await _tokens.saveTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
      );
    }
    UserModel? user;
    if (map['user'] is Map) {
      user = UserModel.fromJson(Map<String, dynamic>.from(map['user'] as Map));
      state = AsyncData(user);
    } else {
      await refreshUser();
    }
  }

  // -- Firebase Phone Auth ---------------------------------------------------

  /// Start Firebase phone verification (sends the SMS). Resolves with a TTL
  /// (seconds) once the code is sent; throws [ApiException] on failure. The
  /// resulting `verificationId` is stashed for [verifyOtp].
  Future<int> _startFirebasePhoneAuth(String e164, {int? resendToken}) async {
    final completer = Completer<int>();
    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: e164,
      timeout: const Duration(seconds: 60),
      forceResendingToken: resendToken ?? _fbResendToken,
      verificationCompleted: (PhoneAuthCredential credential) async {
        // Android SMS auto-retrieval: sign in straight away.
        try {
          await _completeFirebaseSignIn(credential);
        } catch (_) {}
        if (!completer.isCompleted) completer.complete(0);
      },
      verificationFailed: (FirebaseAuthException e) {
        if (!completer.isCompleted) {
          completer.completeError(
            ApiException(message: _friendlyFirebaseError(e), code: 'AUTH_ERROR'),
          );
        }
      },
      codeSent: (String verificationId, int? token) {
        _fbVerificationId = verificationId;
        _fbResendToken = token;
        if (!completer.isCompleted) completer.complete(60);
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        _fbVerificationId = verificationId;
        if (!completer.isCompleted) completer.complete(60);
      },
    );
    return completer.future;
  }

  /// Sign in with a phone credential, then exchange the Firebase ID token for
  /// our session via POST /auth/firebase.
  Future<OtpVerifyResult> _completeFirebaseSignIn(
    PhoneAuthCredential credential,
  ) async {
    final cred = await FirebaseAuth.instance.signInWithCredential(credential);
    final idToken = await cred.user?.getIdToken();
    if (idToken == null || idToken.isEmpty) {
      throw ApiException(
        message: 'Could not complete sign-in. Please try again.',
        code: 'AUTH_ERROR',
      );
    }
    return _exchangeFirebaseToken(idToken);
  }

  /// POST /auth/firebase — turn a verified Firebase ID token into our JWTs (or a
  /// registration temp token for brand-new users). Mirrors the OTP-verify path.
  Future<OtpVerifyResult> _exchangeFirebaseToken(String idToken) async {
    final data = await _api.postJson(
      '/auth/firebase',
      body: {'idToken': idToken},
      skipAuth: true,
    );
    return _applySessionEnvelope(
      data is Map<String, dynamic> ? data : <String, dynamic>{},
    );
  }

  /// Apply a sign-in envelope (from the Firebase OR Google exchange). For a
  /// brand-new user, stash the registration token + prefill data and report
  /// isNewUser; for a returning user, persist the JWT pair and load the profile.
  Future<OtpVerifyResult> _applySessionEnvelope(Map<String, dynamic> map) async {
    if (map['isNewUser'] == true) {
      // The Google browser flow returns name/email here for register prefill;
      // the Firebase path already set them from the account, so don't overwrite.
      _pendingFullName ??= map['fullName'] as String?;
      _pendingEmail ??= map['email'] as String?;
      final registerToken =
          (map['registerToken'] ?? map['accessToken']) as String?;
      if (registerToken != null) await _tokens.saveTempToken(registerToken);
      return const OtpVerifyResult(isNewUser: true);
    }

    final accessToken = map['accessToken'] as String?;
    final refreshToken = map['refreshToken'] as String?;
    if (accessToken != null && refreshToken != null) {
      await _tokens.saveTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
      );
    }
    UserModel? user;
    if (map['user'] is Map) {
      user = UserModel.fromJson(Map<String, dynamic>.from(map['user'] as Map));
      state = AsyncData(user);
    } else {
      await refreshUser();
    }
    return OtpVerifyResult(isNewUser: false, user: user ?? state.value);
  }

  String _friendlyFirebaseError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-verification-code':
        return 'Incorrect OTP. Please try again.';
      case 'session-expired':
      case 'code-expired':
        return 'The code has expired. Please resend a new one.';
      case 'invalid-phone-number':
        return 'Enter a valid mobile number.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'quota-exceeded':
        return 'SMS limit reached. Please try again later.';
      default:
        return e.message ?? 'Phone verification failed. Please try again.';
    }
  }

  /// Live @username availability check for the registration screen. Returns
  /// whether the handle is free (and a `reason` — 'taken' / 'invalid_format' —
  /// when it isn't). Never throws for a normal "taken" answer.
  Future<({bool available, String? reason})> checkUsernameAvailable(
    String username,
  ) async {
    final data = await _api.getJson(
      '/auth/username-available',
      query: {'username': username},
      skipAuth: true,
    );
    final map = data is Map<String, dynamic> ? data : <String, dynamic>{};
    return (
      available: map['available'] == true,
      reason: map['reason'] as String?,
    );
  }

  /// Step 3 (new users) — complete the profile. Age >= 18 is enforced
  /// server-side; the client passes the chosen [role].
  Future<UserModel> register({
    required String fullName,
    required String username,
    required String gender,
    required String dateOfBirth, // ISO date "YYYY-MM-DD"
    required String city,
    required String role,
    String? referralCode,
  }) async {
    final data = await _api.postJson(
      '/auth/register',
      useTempToken: true,
      body: {
        'fullName': fullName,
        'username': username,
        'gender': gender,
        'dateOfBirth': dateOfBirth,
        'city': city,
        'role': role,
        if (referralCode != null && referralCode.isNotEmpty)
          'referralCode': referralCode,
      },
    );
    final map = data is Map<String, dynamic>
        ? data
        : <String, dynamic>{};

    final accessToken = map['accessToken'] as String?;
    final refreshToken = map['refreshToken'] as String?;
    if (accessToken != null && refreshToken != null) {
      await _tokens.saveTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
      );
    }
    await _tokens.clearTempToken();

    UserModel user;
    if (map['user'] is Map) {
      user = UserModel.fromJson(Map<String, dynamic>.from(map['user'] as Map));
    } else {
      user = (await _fetchMe())!;
    }
    state = AsyncData(user);
    return user;
  }

  /// Re-fetch the current user from `/auth/me`.
  Future<void> refreshUser() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async => _fetchMe());
  }

  /// Register the device FCM token with the backend.
  Future<void> registerFcmToken(String fcmToken) async {
    try {
      await _api.postJson('/auth/fcm-token', body: {'fcmToken': fcmToken});
    } catch (_) {
      // Non-fatal.
    }
  }

  /// Sign out: invalidate refresh token server-side, then wipe local state.
  Future<void> logout() async {
    try {
      await _api.postJson('/auth/logout');
    } catch (_) {
      // Ignore network errors on logout.
    }
    await _tokens.clear();
    state = const AsyncData(null);
  }

  /// Locally apply a profile mutation (e.g. after PATCH /users/me).
  void setUser(UserModel user) => state = AsyncData(user);
}

/// The auth session provider.
final authControllerProvider =
    AsyncNotifierProvider<AuthController, UserModel?>(AuthController.new);

/// Convenience: the current user (or null), ignoring loading/error states.
final currentUserProvider = Provider<UserModel?>((ref) {
  return ref.watch(authControllerProvider).valueOrNull;
});

/// Whether a user is currently authenticated.
final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(currentUserProvider) != null;
});
