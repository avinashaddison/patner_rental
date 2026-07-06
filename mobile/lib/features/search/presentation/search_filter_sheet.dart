import 'package:flutter/material.dart';

import 'package:companion_ranchi/core/constants/app_constants.dart';
import 'package:companion_ranchi/core/theme/app_theme.dart';
import 'package:companion_ranchi/core/utils/formatters.dart';
import 'package:companion_ranchi/features/search/data/search_repository.dart';
import 'package:companion_ranchi/shared/widgets/widgets.dart';

/// Bottom sheet that edits the advanced [CompanionSearchFilters] (city, rate
/// range, minimum rating, online-only, featured-only and sort). Returns the new
/// filters via `Navigator.pop`, or `null` if dismissed.
class SearchFilterSheet extends StatefulWidget {
  const SearchFilterSheet({super.key, required this.initial});

  final CompanionSearchFilters initial;

  @override
  State<SearchFilterSheet> createState() => _SearchFilterSheetState();
}

class _SearchFilterSheetState extends State<SearchFilterSheet> {
  static const double _rateFloor = 0;
  static const double _rateCeil = 5000;

  late RangeValues _rate;
  late double _minRating;
  late bool _onlineOnly;
  late bool _featuredOnly;
  String? _city;
  String? _sort;

  static const _sortOptions = <String, String>{
    'rating:desc': 'Top rated',
    'hourlyRate:asc': 'Price: low to high',
    'hourlyRate:desc': 'Price: high to low',
    'totalBookings:desc': 'Most booked',
  };

  @override
  void initState() {
    super.initState();
    final f = widget.initial;
    _rate = RangeValues(
      (f.minRate ?? _rateFloor).clamp(_rateFloor, _rateCeil).toDouble(),
      (f.maxRate ?? _rateCeil).clamp(_rateFloor, _rateCeil).toDouble(),
    );
    _minRating = f.minRating ?? 0;
    _onlineOnly = f.onlineOnly;
    _featuredOnly = f.featuredOnly;
    _city = f.city;
    _sort = f.sort;
  }

  void _reset() {
    setState(() {
      _rate = const RangeValues(_rateFloor, _rateCeil);
      _minRating = 0;
      _onlineOnly = false;
      _featuredOnly = false;
      _city = null;
      _sort = null;
    });
  }

  void _apply() {
    final result = widget.initial.copyWith(
      city: _city,
      minRate: _rate.start <= _rateFloor ? null : _rate.start,
      maxRate: _rate.end >= _rateCeil ? null : _rate.end,
      minRating: _minRating <= 0 ? null : _minRating,
      onlineOnly: _onlineOnly,
      featuredOnly: _featuredOnly,
      sort: _sort,
    );
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: AppColors.line,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                  ),
                ),
              ),
              Row(
                children: [
                  Text(
                    'Filters',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  TextButton(onPressed: _reset, child: const Text('Reset')),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),

              // ---- City ----
              _label(theme, 'City'),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  CategoryChip(
                    label: 'Any',
                    selected: _city == null,
                    onTap: () => setState(() => _city = null),
                  ),
                  for (final city in AppConstants.cities)
                    CategoryChip(
                      label: city,
                      selected: _city == city,
                      onTap: () => setState(() => _city = city),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              // ---- Rate range ----
              Row(
                children: [
                  _label(theme, 'Hourly rate'),
                  const Spacer(),
                  Text(
                    '${Formatters.money(_rate.start)} – '
                    '${_rate.end >= _rateCeil ? '${Formatters.money(_rateCeil)}+' : Formatters.money(_rate.end)}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              RangeSlider(
                values: _rate,
                min: _rateFloor,
                max: _rateCeil,
                divisions: 50,
                activeColor: AppColors.primary,
                labels: RangeLabels(
                  Formatters.money(_rate.start),
                  Formatters.money(_rate.end),
                ),
                onChanged: (v) => setState(() => _rate = v),
              ),
              const SizedBox(height: AppSpacing.sm),

              // ---- Minimum rating ----
              Row(
                children: [
                  _label(theme, 'Minimum rating'),
                  const Spacer(),
                  Text(
                    _minRating <= 0
                        ? 'Any'
                        : '${_minRating.toStringAsFixed(1)}+',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final r in const [0.0, 3.0, 3.5, 4.0, 4.5])
                    CategoryChip(
                      label: r == 0 ? 'Any' : r.toStringAsFixed(1),
                      icon: r == 0 ? null : Icons.star_rounded,
                      selected: _minRating == r,
                      onTap: () => setState(() => _minRating = r),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              // ---- Sort ----
              _label(theme, 'Sort by'),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  CategoryChip(
                    label: 'Relevance',
                    selected: _sort == null,
                    onTap: () => setState(() => _sort = null),
                  ),
                  for (final entry in _sortOptions.entries)
                    CategoryChip(
                      label: entry.value,
                      selected: _sort == entry.key,
                      onTap: () => setState(() => _sort = entry.key),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              // ---- Toggles ----
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: AppColors.primary,
                title: const Text('Online now'),
                subtitle: const Text('Only companions currently online'),
                value: _onlineOnly,
                onChanged: (v) => setState(() => _onlineOnly = v),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: AppColors.primary,
                title: const Text('Featured only'),
                subtitle: const Text('Hand-picked, top profiles'),
                value: _featuredOnly,
                onChanged: (v) => setState(() => _featuredOnly = v),
              ),
              const SizedBox(height: AppSpacing.md),
              GradientButton(
                label: 'Show results',
                icon: Icons.check_rounded,
                onPressed: _apply,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(ThemeData theme, String text) => Text(
        text,
        style:
            theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      );
}
