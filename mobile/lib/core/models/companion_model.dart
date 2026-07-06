import 'package:companion_ranchi/core/models/json_utils.dart';
import 'package:companion_ranchi/core/models/review_model.dart';

/// A single companion photo (companion_photos).
class CompanionPhoto {
  const CompanionPhoto({
    required this.id,
    required this.photoUrl,
    this.isPrimary = false,
    this.sortOrder = 0,
  });

  final String id;
  final String photoUrl;
  final bool isPrimary;
  final int sortOrder;

  factory CompanionPhoto.fromJson(Map<String, dynamic> json) => CompanionPhoto(
        id: J.asString(json['id']),
        photoUrl: J.asString(json['photoUrl']),
        isPrimary: J.asBool(json['isPrimary']),
        sortOrder: J.asInt(json['sortOrder']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'photoUrl': photoUrl,
        'isPrimary': isPrimary,
        'sortOrder': sortOrder,
      };
}

/// A weekly availability window (companion_availability).
class AvailabilitySlot {
  const AvailabilitySlot({
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    this.isAvailable = true,
    this.id,
  });

  final String? id;

  /// 0 = Sunday ... 6 = Saturday.
  final int dayOfWeek;

  /// "HH:mm".
  final String startTime;
  final String endTime;
  final bool isAvailable;

  factory AvailabilitySlot.fromJson(Map<String, dynamic> json) =>
      AvailabilitySlot(
        id: J.asStringOrNull(json['id']),
        dayOfWeek: J.asInt(json['dayOfWeek']),
        startTime: J.asString(json['startTime']),
        endTime: J.asString(json['endTime']),
        isAvailable: J.asBool(json['isAvailable'], true),
      );

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'dayOfWeek': dayOfWeek,
        'startTime': startTime,
        'endTime': endTime,
        'isAvailable': isAvailable,
      };
}

/// Companion model — covers both the lightweight **card** shape (search/list)
/// and the **full profile** shape (`GET /companions/:id`). Optional fields are
/// only populated on the full profile.
///
/// Card shape (API.md):
/// ```json
/// { "id","name","age","city","photoUrl","rating","ratingCount","hourlyRate",
///   "isVerified","isOnline","isFeatured","categories":[...],"distanceKm" }
/// ```
class CompanionModel {
  const CompanionModel({
    required this.id,
    required this.name,
    required this.city,
    required this.hourlyRate,
    required this.rating,
    required this.ratingCount,
    required this.isVerified,
    required this.isOnline,
    required this.isFeatured,
    required this.categories,
    this.age,
    this.photoUrl,
    this.distanceKm,
    // Full-profile-only fields:
    this.userId,
    this.aboutMe,
    this.languages = const [],
    this.interests = const [],
    this.status,
    this.totalBookings = 0,
    this.photos = const [],
    this.availability = const [],
    this.reviews = const [],
    this.latitude,
    this.longitude,
    this.followerCount = 0,
    this.totalLikes = 0,
    this.postCount = 0,
    this.followingCount = 0,
    this.isFollowing = false,
  });

  final String id;
  final String name;
  final int? age;
  final String city;
  final String? photoUrl;
  final double rating;
  final int ratingCount;
  final double hourlyRate;
  final bool isVerified;
  final bool isOnline;
  final bool isFeatured;

  /// Category slugs, e.g. `["coffee-partner","city-guide"]`.
  final List<String> categories;

  /// Distance in km when a location query was supplied.
  final double? distanceKm;

  // ---- Full profile extras ----
  final String? userId;
  final String? aboutMe;
  final List<String> languages;
  final List<String> interests;

  /// `PENDING` | `APPROVED` | `REJECTED` | `SUSPENDED`.
  final String? status;
  final int totalBookings;
  final List<CompanionPhoto> photos;
  final List<AvailabilitySlot> availability;
  final List<ReviewModel> reviews;
  final double? latitude;
  final double? longitude;

  // ---- Social (posts + follow) ----
  final int followerCount;

  /// Total hearts across the companion's published posts.
  final int totalLikes;
  final int postCount;

  /// How many companions this user follows (own-profile endpoint only).
  final int followingCount;

  /// Whether the signed-in viewer follows this companion (profile endpoint only).
  final bool isFollowing;

  /// Primary display photo: explicit `photoUrl`, else the primary in [photos].
  String? get primaryPhotoUrl {
    if (photoUrl != null && photoUrl!.isNotEmpty) return photoUrl;
    if (photos.isEmpty) return null;
    final primary = photos.where((p) => p.isPrimary);
    return primary.isNotEmpty ? primary.first.photoUrl : photos.first.photoUrl;
  }

  factory CompanionModel.fromJson(Map<String, dynamic> json) {
    return CompanionModel(
      id: J.asString(json['id']),
      name: J.asString(json['name'], 'Companion'),
      age: J.asIntOrNull(json['age']),
      city: J.asString(json['city'], 'Ranchi'),
      photoUrl: J.asStringOrNull(json['photoUrl']),
      rating: J.asDouble(json['rating'] ?? json['ratingAvg']),
      ratingCount: J.asInt(json['ratingCount']),
      hourlyRate: J.asDouble(json['hourlyRate']),
      isVerified: J.asBool(json['isVerified']),
      isOnline: J.asBool(json['isOnline']),
      isFeatured: J.asBool(json['isFeatured']),
      categories: J.asStringList(json['categories']),
      distanceKm: J.asDoubleOrNull(json['distanceKm']),
      userId: J.asStringOrNull(json['userId']),
      aboutMe: J.asStringOrNull(json['aboutMe']),
      languages: J.asStringList(json['languages']),
      interests: J.asStringList(json['interests']),
      status: J.asStringOrNull(json['status']),
      totalBookings: J.asInt(json['totalBookings']),
      photos: J
          .asMapList(json['photos'])
          .map(CompanionPhoto.fromJson)
          .toList(growable: false),
      availability: J
          .asMapList(json['availability'])
          .map(AvailabilitySlot.fromJson)
          .toList(growable: false),
      reviews: J
          .asMapList(json['reviews'])
          .map(ReviewModel.fromJson)
          .toList(growable: false),
      latitude: J.asDoubleOrNull(json['latitude']),
      longitude: J.asDoubleOrNull(json['longitude']),
      followerCount: J.asInt(json['followerCount']),
      totalLikes: J.asInt(json['totalLikes']),
      postCount: J.asInt(json['postCount']),
      followingCount: J.asInt(json['followingCount']),
      isFollowing: J.asBool(json['isFollowing']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'age': age,
        'city': city,
        'photoUrl': photoUrl,
        'rating': rating,
        'ratingCount': ratingCount,
        'hourlyRate': hourlyRate,
        'isVerified': isVerified,
        'isOnline': isOnline,
        'isFeatured': isFeatured,
        'categories': categories,
        'distanceKm': distanceKm,
        'userId': userId,
        'aboutMe': aboutMe,
        'languages': languages,
        'interests': interests,
        'status': status,
        'totalBookings': totalBookings,
        'photos': photos.map((p) => p.toJson()).toList(),
        'availability': availability.map((a) => a.toJson()).toList(),
        'reviews': reviews.map((r) => r.toJson()).toList(),
        'latitude': latitude,
        'longitude': longitude,
        'followerCount': followerCount,
        'totalLikes': totalLikes,
        'postCount': postCount,
        'followingCount': followingCount,
        'isFollowing': isFollowing,
      };

  CompanionModel copyWith({
    bool? isOnline,
    int? followerCount,
    int? totalLikes,
    bool? isFollowing,
  }) {
    return CompanionModel(
      id: id,
      name: name,
      city: city,
      hourlyRate: hourlyRate,
      rating: rating,
      ratingCount: ratingCount,
      isVerified: isVerified,
      isOnline: isOnline ?? this.isOnline,
      isFeatured: isFeatured,
      categories: categories,
      age: age,
      photoUrl: photoUrl,
      distanceKm: distanceKm,
      userId: userId,
      aboutMe: aboutMe,
      languages: languages,
      interests: interests,
      status: status,
      totalBookings: totalBookings,
      photos: photos,
      availability: availability,
      reviews: reviews,
      latitude: latitude,
      longitude: longitude,
      followerCount: followerCount ?? this.followerCount,
      totalLikes: totalLikes ?? this.totalLikes,
      postCount: postCount,
      followingCount: followingCount,
      isFollowing: isFollowing ?? this.isFollowing,
    );
  }
}
