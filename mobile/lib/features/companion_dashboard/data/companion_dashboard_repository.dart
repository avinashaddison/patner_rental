import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:companion_ranchi/core/models/booking_model.dart';
import 'package:companion_ranchi/core/models/companion_model.dart';
import 'package:companion_ranchi/core/models/json_utils.dart';
import 'package:companion_ranchi/core/network/api_client.dart';
import 'package:companion_ranchi/core/network/api_exception.dart';
import 'package:companion_ranchi/core/network/uploads_repository.dart';
import 'package:companion_ranchi/features/companion_dashboard/data/companion_dashboard_models.dart';
import 'package:companion_ranchi/features/companion_dashboard/data/kyc_models.dart';

/// Data access for the companion side of the app: the earnings dashboard, the
/// availability + online manager, incoming booking actions, and the
/// become-a-companion onboarding (profile, photos, KYC).
///
/// Every route here matches API.md exactly. All money is parsed defensively via
/// [J] because the backend serialises Decimals as strings.
class CompanionDashboardRepository {
  CompanionDashboardRepository(this._api, this._uploads);

  final ApiClient _api;
  final UploadsRepository _uploads;

  // ---------------------------------------------------------------------------
  // Dashboard  (/companion)
  // ---------------------------------------------------------------------------

  /// `GET /companion/dashboard` → earnings/ratings summary cards.
  Future<CompanionDashboard> fetchDashboard() async {
    final data = await _api.getJson('/companion/dashboard');
    if (data is Map<String, dynamic>) {
      return CompanionDashboard.fromJson(data);
    }
    return CompanionDashboard.empty;
  }

  /// `GET /companion/earnings` → earnings breakdown + recent transactions.
  Future<CompanionEarnings> fetchEarnings() async {
    final data = await _api.getJson('/companion/earnings');
    if (data is Map<String, dynamic>) {
      return CompanionEarnings.fromJson(data);
    }
    return CompanionEarnings.empty;
  }

  /// `GET /companion/bookings` → received bookings (optionally by status).
  Future<List<BookingModel>> fetchBookings({String? status}) async {
    final data = await _api.getJson(
      '/companion/bookings',
      query: {if (status != null && status.isNotEmpty) 'status': status},
    );
    return _mapBookings(data);
  }

  List<BookingModel> _mapBookings(dynamic data) {
    final list = data is List
        ? data
        : (data is Map && data['bookings'] is List
            ? data['bookings'] as List
            : const []);
    return J
        .asMapList(list)
        .map(BookingModel.fromJson)
        .toList(growable: false);
  }

  // ---------------------------------------------------------------------------
  // Incoming booking actions  (/bookings/:id/...)
  // ---------------------------------------------------------------------------

  /// `POST /bookings/:id/accept` → PENDING/CONFIRMED → CONFIRMED.
  Future<BookingModel> acceptBooking(String bookingId) =>
      _bookingAction(bookingId, 'accept');

  /// `POST /bookings/:id/reject` → CANCELLED (+ refund if paid).
  Future<BookingModel> rejectBooking(String bookingId) =>
      _bookingAction(bookingId, 'reject');

  /// `POST /bookings/:id/start` → CONFIRMED → IN_PROGRESS. Requires the
  /// customer's 6-digit start code, entered by the companion at the meeting.
  Future<BookingModel> startBooking(String bookingId, {required String code}) async {
    final data =
        await _api.postJson('/bookings/$bookingId/start', body: {'code': code});
    return BookingModel.fromJson(_asBookingMap(data));
  }

  /// `POST /bookings/:id/complete` → IN_PROGRESS → COMPLETED (payout credit).
  Future<BookingModel> completeBooking(String bookingId) =>
      _bookingAction(bookingId, 'complete');

  Future<BookingModel> _bookingAction(String bookingId, String action) async {
    final data = await _api.postJson('/bookings/$bookingId/$action');
    return BookingModel.fromJson(_asBookingMap(data));
  }

  // ---------------------------------------------------------------------------
  // Profile / availability / online  (/companions/me/...)
  // ---------------------------------------------------------------------------

  /// `GET /companions/me/profile` → the signed-in companion's own profile.
  /// Returns `null` when the user has not onboarded as a companion yet.
  Future<CompanionModel?> fetchMyProfile() async {
    try {
      final data = await _api.getJson('/companions/me/profile');
      if (data is Map<String, dynamic>) {
        return CompanionModel.fromJson(data);
      }
      return null;
    } on ApiException catch (e) {
      // No companion profile yet — surface as null so the UI can route to
      // onboarding rather than an error screen.
      if (e.isNotFound || e.isForbidden) return null;
      rethrow;
    }
  }

  /// `POST /companions/me` → create / onboard the companion profile.
  Future<CompanionModel> createProfile({
    required String aboutMe,
    required List<String> languages,
    required List<String> interests,
    required double hourlyRate,
    required String city,
    required List<String> categoryIds,
  }) async {
    final data = await _api.postJson(
      '/companions/me',
      body: {
        'aboutMe': aboutMe,
        'languages': languages,
        'interests': interests,
        'hourlyRate': hourlyRate,
        'city': city,
        'categoryIds': categoryIds,
      },
    );
    return CompanionModel.fromJson(_asCompanionMap(data));
  }

  /// `PATCH /companions/me` → update the companion profile.
  Future<CompanionModel> updateProfile({
    String? aboutMe,
    List<String>? languages,
    List<String>? interests,
    double? hourlyRate,
    String? city,
    List<String>? categoryIds,
  }) async {
    final data = await _api.patchJson(
      '/companions/me',
      body: {
        if (aboutMe != null) 'aboutMe': aboutMe,
        if (languages != null) 'languages': languages,
        if (interests != null) 'interests': interests,
        if (hourlyRate != null) 'hourlyRate': hourlyRate,
        if (city != null) 'city': city,
        if (categoryIds != null) 'categoryIds': categoryIds,
      },
    );
    return CompanionModel.fromJson(_asCompanionMap(data));
  }

  /// `PATCH /companions/me/online` → toggle realtime online presence.
  Future<bool> setOnline(bool isOnline) async {
    final data = await _api.patchJson(
      '/companions/me/online',
      body: {'isOnline': isOnline},
    );
    if (data is Map && data['isOnline'] != null) {
      return J.asBool(data['isOnline']);
    }
    return isOnline;
  }

  /// `PUT /companions/me/availability` → replace the weekly availability.
  /// Body shape per API.md: `{ slots: [{ dayOfWeek, startTime, endTime }] }`.
  Future<List<AvailabilitySlot>> saveAvailability(
    List<AvailabilitySlot> slots,
  ) async {
    final data = await _api.putJson(
      '/companions/me/availability',
      body: {
        'slots': slots
            .map((s) => {
                  'dayOfWeek': s.dayOfWeek,
                  'startTime': s.startTime,
                  'endTime': s.endTime,
                })
            .toList(),
      },
    );
    return _mapAvailability(data);
  }

  List<AvailabilitySlot> _mapAvailability(dynamic data) {
    final list = data is List
        ? data
        : (data is Map && data['slots'] is List
            ? data['slots'] as List
            : (data is Map && data['availability'] is List
                ? data['availability'] as List
                : const []));
    return J
        .asMapList(list)
        .map(AvailabilitySlot.fromJson)
        .toList(growable: false);
  }

  // ---------------------------------------------------------------------------
  // Photos  (/uploads/presign + /companions/me/photos)
  // ---------------------------------------------------------------------------

  /// Uploads [file] to R2 via a presigned PUT, then registers the public URL
  /// against the companion profile via `POST /companions/me/photos`.
  /// Returns the new [CompanionPhoto].
  Future<CompanionPhoto> uploadPhoto(
    File file, {
    bool isPrimary = false,
  }) async {
    final publicUrl = await _uploads.uploadFile(file, folder: 'companion-photos');
    final data = await _api.postJson(
      '/companions/me/photos',
      body: {'photoUrl': publicUrl, 'isPrimary': isPrimary},
    );
    if (data is Map<String, dynamic>) {
      return CompanionPhoto.fromJson(data);
    }
    return CompanionPhoto(id: '', photoUrl: publicUrl, isPrimary: isPrimary);
  }

  /// `DELETE /companions/me/photos/:photoId`.
  Future<void> deletePhoto(String photoId) async {
    await _api.delete('/companions/me/photos/$photoId');
  }

  // ---------------------------------------------------------------------------
  // KYC  (/kyc)
  // ---------------------------------------------------------------------------

  /// Uploads a KYC document image to R2 then submits it via `POST /kyc/submit`.
  Future<KycDocument> submitKyc({
    required String documentType, // GOVERNMENT_ID | SELFIE
    required File file,
    String? documentNumber,
  }) async {
    final publicUrl = await _uploads.uploadFile(file, folder: 'kyc');
    final data = await _api.postJson(
      '/kyc/submit',
      body: {
        'documentType': documentType,
        'documentUrl': publicUrl,
        if (documentNumber != null && documentNumber.isNotEmpty)
          'documentNumber': documentNumber,
      },
    );
    if (data is Map<String, dynamic>) {
      return KycDocument.fromJson(data);
    }
    return KycDocument(
      id: '',
      docType: documentType,
      documentUrl: publicUrl,
      status: KycStatusValue.submitted,
      documentNumber: documentNumber,
    );
  }

  /// `GET /kyc/status` → overall KYC status + documents.
  Future<KycStatus> fetchKycStatus() async {
    final data = await _api.getJson('/kyc/status');
    if (data is Map<String, dynamic>) {
      return KycStatus.fromJson(data);
    }
    return KycStatus.empty;
  }

  Map<String, dynamic> _asBookingMap(dynamic data) {
    if (data is Map<String, dynamic>) {
      if (data['booking'] is Map) {
        return Map<String, dynamic>.from(data['booking'] as Map);
      }
      return data;
    }
    return const {};
  }

  Map<String, dynamic> _asCompanionMap(dynamic data) {
    if (data is Map<String, dynamic>) {
      if (data['companion'] is Map) {
        return Map<String, dynamic>.from(data['companion'] as Map);
      }
      return data;
    }
    return const {};
  }
}

/// Provider for [CompanionDashboardRepository], wired to [apiClientProvider].
final companionDashboardRepositoryProvider =
    Provider<CompanionDashboardRepository>((ref) {
  return CompanionDashboardRepository(
    ref.watch(apiClientProvider),
    ref.watch(uploadsRepositoryProvider),
  );
});
