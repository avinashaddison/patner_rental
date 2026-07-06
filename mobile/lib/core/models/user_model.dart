import 'package:companion_ranchi/core/models/json_utils.dart';

/// A human account (customer or companion). Mirrors `users` in DATA_MODEL.md
/// and the `user` object returned by `/auth/me`, `/auth/otp/verify`, etc.
class UserModel {
  const UserModel({
    required this.id,
    required this.mobileNumber,
    required this.fullName,
    required this.role,
    required this.isMobileVerified,
    this.gender,
    this.dateOfBirth,
    this.city,
    this.email,
    this.username,
    this.profilePhotoUrl,
    this.referralCode,
    this.referredById,
    this.isBlocked = false,
    this.blockedReason,
    this.lastActiveAt,
    this.createdAt,
    this.updatedAt,
    this.hasCompanionProfile = false,
  });

  final String id;
  final String mobileNumber;
  final String fullName;

  /// `CUSTOMER` | `COMPANION` | `ADMIN`.
  final String role;
  final bool isMobileVerified;

  /// `MALE` | `FEMALE` | `OTHER`.
  final String? gender;
  final DateTime? dateOfBirth;
  final String? city;
  final String? email;

  /// Public @handle chosen at profile creation (null for legacy accounts).
  final String? username;
  final String? profilePhotoUrl;
  final String? referralCode;
  final String? referredById;
  final bool isBlocked;
  final String? blockedReason;
  final DateTime? lastActiveAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// True when the API response embedded a `companion` object.
  final bool hasCompanionProfile;

  bool get isCompanion => role == 'COMPANION';
  bool get isCustomer => role == 'CUSTOMER';
  bool get isAdmin => role == 'ADMIN';

  /// Age derived from [dateOfBirth] (server is authoritative; this is display).
  int? get age {
    final dob = dateOfBirth;
    if (dob == null) return null;
    final now = DateTime.now();
    var years = now.year - dob.year;
    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) {
      years--;
    }
    return years;
  }

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: J.asString(json['id']),
      mobileNumber: J.asString(json['mobileNumber']),
      fullName: J.asString(json['fullName']),
      role: J.asString(json['role'], 'CUSTOMER'),
      isMobileVerified: J.asBool(json['isMobileVerified']),
      gender: J.asStringOrNull(json['gender']),
      dateOfBirth: J.asDate(json['dateOfBirth']),
      city: J.asStringOrNull(json['city']),
      email: J.asStringOrNull(json['email']),
      username: J.asStringOrNull(json['username']),
      profilePhotoUrl: J.asStringOrNull(json['profilePhotoUrl']),
      referralCode: J.asStringOrNull(json['referralCode']),
      referredById: J.asStringOrNull(json['referredById']),
      isBlocked: J.asBool(json['isBlocked']),
      blockedReason: J.asStringOrNull(json['blockedReason']),
      lastActiveAt: J.asDate(json['lastActiveAt']),
      createdAt: J.asDate(json['createdAt']),
      updatedAt: J.asDate(json['updatedAt']),
      hasCompanionProfile: json['companion'] != null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'mobileNumber': mobileNumber,
        'fullName': fullName,
        'role': role,
        'isMobileVerified': isMobileVerified,
        'gender': gender,
        'dateOfBirth': dateOfBirth?.toIso8601String(),
        'city': city,
        'email': email,
        'username': username,
        'profilePhotoUrl': profilePhotoUrl,
        'referralCode': referralCode,
        'referredById': referredById,
        'isBlocked': isBlocked,
        'blockedReason': blockedReason,
        'lastActiveAt': lastActiveAt?.toIso8601String(),
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
      };

  UserModel copyWith({
    String? fullName,
    String? city,
    String? email,
    String? username,
    String? profilePhotoUrl,
    String? role,
    bool? isMobileVerified,
    bool? hasCompanionProfile,
  }) {
    return UserModel(
      id: id,
      mobileNumber: mobileNumber,
      fullName: fullName ?? this.fullName,
      role: role ?? this.role,
      isMobileVerified: isMobileVerified ?? this.isMobileVerified,
      gender: gender,
      dateOfBirth: dateOfBirth,
      city: city ?? this.city,
      email: email ?? this.email,
      username: username ?? this.username,
      profilePhotoUrl: profilePhotoUrl ?? this.profilePhotoUrl,
      referralCode: referralCode,
      referredById: referredById,
      isBlocked: isBlocked,
      blockedReason: blockedReason,
      lastActiveAt: lastActiveAt,
      createdAt: createdAt,
      updatedAt: updatedAt,
      hasCompanionProfile: hasCompanionProfile ?? this.hasCompanionProfile,
    );
  }
}
