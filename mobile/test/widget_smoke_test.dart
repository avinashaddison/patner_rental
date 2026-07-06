import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:companion_ranchi/core/models/companion_model.dart';
import 'package:companion_ranchi/core/theme/app_theme.dart';
import 'package:companion_ranchi/core/utils/formatters.dart';
import 'package:companion_ranchi/shared/widgets/widgets.dart';

void main() {
  group('Formatters', () {
    test('money formats INR without paise', () {
      expect(Formatters.money(600), contains('600'));
    });

    test('ratePerHour', () {
      expect(Formatters.ratePerHour(600), '₹600/hr');
    });

    test('time12 converts 24h to 12h', () {
      expect(Formatters.time12('15:30'), '3:30 PM');
      expect(Formatters.time12('09:05'), '9:05 AM');
    });

    test('durationHours pluralises', () {
      expect(Formatters.durationHours(1), '1 hr');
      expect(Formatters.durationHours(2), '2 hrs');
    });
  });

  group('Models', () {
    test('CompanionModel.fromJson parses card shape', () {
      final c = CompanionModel.fromJson(const {
        'id': 'c1',
        'name': 'Aisha',
        'age': 24,
        'city': 'Ranchi',
        'photoUrl': 'https://example.com/a.jpg',
        'rating': 4.8,
        'ratingCount': 42,
        'hourlyRate': 600,
        'isVerified': true,
        'isOnline': true,
        'isFeatured': true,
        'categories': ['coffee-partner', 'city-guide'],
        'distanceKm': 2.4,
      });
      expect(c.name, 'Aisha');
      expect(c.age, 24);
      expect(c.hourlyRate, 600);
      expect(c.isVerified, true);
      expect(c.categories.length, 2);
      expect(c.distanceKm, 2.4);
    });

    test('CompanionModel tolerates string decimals', () {
      final c = CompanionModel.fromJson(const {
        'id': 'c2',
        'name': 'Riya',
        'hourlyRate': '750.00',
        'rating': '4.5',
      });
      expect(c.hourlyRate, 750.0);
      expect(c.rating, 4.5);
    });
  });

  testWidgets('Shared widgets render under the app theme', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Column(
            children: [
              const VerifiedBadge(),
              const OnlineDot(isOnline: true, showLabel: true),
              const RatingStars(rating: 4.6, count: 12),
              const CategoryChip(label: 'Coffee', emoji: '☕'),
              GradientButton(label: 'Continue', onPressed: () {}),
              AppButton(label: 'Book', onPressed: () {}),
              const EmptyView(title: 'Nothing here'),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Verified'), findsOneWidget);
    expect(find.text('Online'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Book'), findsOneWidget);
    expect(find.text('Nothing here'), findsOneWidget);
  });
}
