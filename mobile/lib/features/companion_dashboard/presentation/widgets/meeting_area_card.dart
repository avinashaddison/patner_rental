import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import 'package:companion_ranchi/core/models/companion_model.dart';
import 'package:companion_ranchi/core/theme/app_theme.dart';
import 'package:companion_ranchi/features/companion_dashboard/application/companion_dashboard_providers.dart';
import 'package:companion_ranchi/features/tracking/data/tracking_repository.dart';

/// Lets a companion set their base coordinates from the device GPS. Powers
/// "near me" / distance sorting for guests. Uses free device GPS to sense the
/// location and the Geocoding proxy only to show a friendly area label.
class MeetingAreaCard extends ConsumerStatefulWidget {
  const MeetingAreaCard({super.key, required this.profile});

  final CompanionModel profile;

  @override
  ConsumerState<MeetingAreaCard> createState() => _MeetingAreaCardState();
}

class _MeetingAreaCardState extends ConsumerState<MeetingAreaCard> {
  bool _saving = false;
  String? _label; // reverse-geocoded label after a successful set
  String? _error;

  bool get _hasLocation =>
      widget.profile.latitude != null && widget.profile.longitude != null;

  Future<void> _setLocation() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _fail('Turn on location services to set your area.');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _fail('Location permission is needed to set your area.');
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      );

      final repo = ref.read(trackingRepositoryProvider);
      await repo.updateCompanionLocation(pos.latitude, pos.longitude);
      final label = await repo.reverseGeocode(pos.latitude, pos.longitude);

      if (!mounted) return;
      setState(() {
        _saving = false;
        _label = label;
      });
      ref.invalidate(myCompanionProfileProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            label == null ? 'Meeting area updated.' : 'Meeting area set: $label',
          ),
        ),
      );
    } catch (_) {
      _fail('Could not set your location. Please try again.');
    }
  }

  void _fail(String msg) {
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = msg;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isSet = _label != null || _hasLocation;
    final subtitle = _label ??
        (_hasLocation
            ? 'Your base area is set. Update it if you have moved.'
            : 'Set your base area so guests nearby can find you.');

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.map_outlined, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Meeting area',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: AppColors.ink,
                ),
              ),
              const Spacer(),
              if (isSet)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                  ),
                  child: const Text(
                    'Set',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.success,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 13, color: AppColors.inkMuted),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(fontSize: 12.5, color: AppColors.danger),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _saving ? null : _setLocation,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location_rounded, size: 18),
              label: Text(
                isSet ? 'Update my location' : 'Use my current location',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radius),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
