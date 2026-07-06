import 'package:flutter/material.dart';

/// App-wide constants mirrored from the backend contracts (DATA_MODEL.md,
/// SAFETY.md, API.md). These are sensible defaults for offline rendering;
/// the authoritative copy is fetched from `GET /meta/config`.
class AppConstants {
  AppConstants._();

  static const String appName = 'Companion Ranchi';
  static const String tagline = 'Verified companions for real-life social moments';
  static const String defaultCity = 'Ranchi';
  static const List<String> cities = ['Ranchi'];

  /// Minimum legal age. Enforced server-side; surfaced in the UI too.
  static const int minAge = 18;

  /// Platform commission percent (default; runtime value via /meta/config).
  static const double defaultCommissionRate = 20;

  /// Referral reward credited to the referrer (INR).
  static const double referralReward = 100;

  /// Minimum payout amount a companion can withdraw (INR).
  static const double minPayout = 500;

  /// Allowed booking durations (hours) — DATA_MODEL: durationHours 1|2|4|6.
  static const List<int> bookingDurations = [1, 2, 4, 6];

  static const String currencySymbol = '₹'; // Rupee sign
  static const String currencyCode = 'INR';
}

/// A fixed activity category (mirrors `categories` seed slugs).
class CategoryDef {
  const CategoryDef({
    required this.slug,
    required this.name,
    required this.emoji,
    required this.description,
    this.icon,
  });

  final String slug;
  final String name;
  final String emoji;
  final String description;

  /// Material icon for chips/forms — consistent weight across devices,
  /// unlike emoji (which render differently per OEM).
  final IconData? icon;
}

/// Seeded activity categories (SAFETY.md: companionship only — fixed list).
class AppCategories {
  AppCategories._();

  static const List<CategoryDef> all = [
    CategoryDef(
      slug: 'coffee-partner',
      icon: Icons.local_cafe_rounded,
      name: 'Coffee Partner',
      emoji: '☕', // coffee
      description: 'Casual conversation over coffee at a cafe.',
    ),
    CategoryDef(
      slug: 'movie-partner',
      icon: Icons.movie_rounded,
      name: 'Movie Partner',
      emoji: '🎬', // clapper
      description: 'Catch the latest release together.',
    ),
    CategoryDef(
      slug: 'shopping-partner',
      icon: Icons.shopping_bag_rounded,
      name: 'Shopping Partner',
      emoji: '🛒', // cart
      description: 'A second opinion while you shop at the mall.',
    ),
    CategoryDef(
      slug: 'event-companion',
      icon: Icons.celebration_rounded,
      name: 'Event Companion',
      emoji: '🎉', // party popper
      description: 'A friendly plus-one for public events.',
    ),
    CategoryDef(
      slug: 'city-guide',
      icon: Icons.map_rounded,
      name: 'City Guide',
      emoji: '🗺', // map
      description: 'Explore Ranchi with a local guide.',
    ),
    CategoryDef(
      slug: 'travel-companion',
      icon: Icons.flight_takeoff_rounded,
      name: 'Travel Companion',
      emoji: '✈', // airplane
      description: 'Company for a day trip to nearby spots.',
    ),
    CategoryDef(
      slug: 'networking-partner',
      icon: Icons.handshake_rounded,
      name: 'Networking Partner',
      emoji: '🤝', // handshake
      description: 'Professional company for meetups and networking.',
    ),
  ];

  static CategoryDef? bySlug(String slug) {
    for (final c in all) {
      if (c.slug == slug) return c;
    }
    return null;
  }

  static String nameFor(String slug) => bySlug(slug)?.name ?? slug;
}

/// Allowed PUBLIC meeting place types (SAFETY.md hard rule #3).
/// Private residences / hotel rooms are intentionally excluded.
class MeetingPlaceTypes {
  MeetingPlaceTypes._();

  static const List<String> all = [
    'Mall',
    'Cafe',
    'Restaurant',
    'Public Event',
    'Park',
    'Co-working',
    'Hotel Lobby',
    'Tourist Spot',
  ];
}

/// Allowed free-text activities (validated server-side against this list).
class Activities {
  Activities._();

  static const List<String> all = [
    'Coffee',
    'Movie',
    'Shopping',
    'Dinner',
    'Lunch',
    'City Tour',
    'Event',
    'Networking',
    'Conversation',
    'Walk in the Park',
    'Sightseeing',
  ];
}

/// Common languages spoken in Ranchi (for companion onboarding chips).
class AppLanguages {
  AppLanguages._();

  static const List<String> all = [
    'Hindi',
    'English',
    'Nagpuri',
    'Bengali',
    'Maithili',
    'Bhojpuri',
    'Urdu',
    'Santhali',
    'Odia',
  ];
}

/// Common interests for companion profiles / search filtering.
class AppInterests {
  AppInterests._();

  static const List<String> all = [
    'Music',
    'Movies',
    'Food',
    'Travel',
    'Fitness',
    'Reading',
    'Photography',
    'Art',
    'Sports',
    'Gaming',
    'Fashion',
    'Technology',
    'Cooking',
    'Dancing',
  ];
}

/// Report categories (mirrors `ReportCategory` enum).
class ReportCategories {
  ReportCategories._();

  static const List<String> all = [
    'HARASSMENT',
    'FAKE_PROFILE',
    'ABUSE',
    'SPAM',
    'OTHER',
  ];

  static String label(String value) {
    switch (value) {
      case 'HARASSMENT':
        return 'Harassment';
      case 'FAKE_PROFILE':
        return 'Fake Profile';
      case 'ABUSE':
        return 'Abuse';
      case 'SPAM':
        return 'Spam';
      default:
        return 'Other';
    }
  }
}

/// Support ticket priorities (mirrors `TicketPriority`).
class TicketPriorities {
  TicketPriorities._();

  static const List<String> all = ['LOW', 'MEDIUM', 'HIGH', 'URGENT'];
}

/// Gender options (mirrors `Gender` enum).
class Genders {
  Genders._();

  static const List<String> all = ['MALE', 'FEMALE', 'OTHER'];

  static String label(String value) {
    switch (value) {
      case 'MALE':
        return 'Male';
      case 'FEMALE':
        return 'Female';
      default:
        return 'Other';
    }
  }
}

/// Roles a registering user can pick (mirrors `Role`; ADMIN excluded).
class UserRoles {
  UserRoles._();

  static const String customer = 'CUSTOMER';
  static const String companion = 'COMPANION';
  static const String admin = 'ADMIN';
}
