import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:companion_ranchi/core/env/env.dart';
import 'package:companion_ranchi/core/theme/app_theme.dart';
import 'package:companion_ranchi/features/tracking/data/tracking_repository.dart';
import 'package:companion_ranchi/shared/widgets/widgets.dart';

/// A meeting-location field with Google Places (New) autocomplete. As the user
/// types it shows Ranchi-biased suggestions; picking one fills the field with a
/// verified place name and (optionally) resolves its coordinates.
///
/// Degrades to a plain text field when no Maps key is configured — it never
/// blocks typing, so bookings still work without Google.
class PlaceAutocompleteField extends ConsumerStatefulWidget {
  const PlaceAutocompleteField({
    super.key,
    this.initialValue,
    this.label,
    this.hint,
    required this.onChanged,
    this.onPlaceSelected,
  });

  final String? initialValue;
  final String? label;
  final String? hint;
  final ValueChanged<String> onChanged;
  final ValueChanged<PlaceDetail>? onPlaceSelected;

  @override
  ConsumerState<PlaceAutocompleteField> createState() =>
      _PlaceAutocompleteFieldState();
}

class _PlaceAutocompleteFieldState
    extends ConsumerState<PlaceAutocompleteField> {
  late final TextEditingController _ctrl;
  Timer? _debounce;
  List<PlaceSuggestion> _suggestions = const [];
  bool _loading = false;
  bool _resolving = false;
  String _session = _newSession();

  static String _newSession() =>
      'cr_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 31)}';

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialValue ?? '');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    widget.onChanged(value);
    if (!Env.hasMapboxToken) return; // no suggestions without a token — plain field
    _debounce?.cancel();
    if (value.trim().length < 2) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _fetch(value));
  }

  Future<void> _fetch(String value) async {
    setState(() => _loading = true);
    try {
      final results = await ref
          .read(trackingRepositoryProvider)
          .autocomplete(value, sessionToken: _session);
      if (!mounted) return;
      setState(() {
        _suggestions = results;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _suggestions = const [];
          _loading = false;
        });
      }
    }
  }

  Future<void> _select(PlaceSuggestion s) async {
    final label = s.label;
    _ctrl.text = label;
    _ctrl.selection = TextSelection.collapsed(offset: label.length);
    widget.onChanged(label);
    setState(() {
      _suggestions = const [];
      _resolving = widget.onPlaceSelected != null;
    });
    FocusScope.of(context).unfocus();

    // Resolve coordinates (this also closes the Places session for billing).
    if (widget.onPlaceSelected != null) {
      final detail = await ref
          .read(trackingRepositoryProvider)
          .placeDetails(s.placeId, sessionToken: _session);
      if (mounted) {
        setState(() => _resolving = false);
        if (detail != null) widget.onPlaceSelected!(detail);
      }
    }
    _session = _newSession(); // next search starts a fresh session
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppTextField(
          controller: _ctrl,
          label: widget.label,
          hint: widget.hint,
          prefixIcon: const Icon(Icons.location_on_rounded),
          suffixIcon: (_loading || _resolving)
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : null,
          textInputAction: TextInputAction.next,
          onChanged: _onChanged,
        ),
        if (_suggestions.isNotEmpty) ...[
          const SizedBox(height: 6),
          _SuggestionList(suggestions: _suggestions, onTap: _select),
        ],
      ],
    );
  }
}

class _SuggestionList extends StatelessWidget {
  const _SuggestionList({required this.suggestions, required this.onTap});

  final List<PlaceSuggestion> suggestions;
  final ValueChanged<PlaceSuggestion> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          for (var i = 0; i < suggestions.length && i < 5; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.line),
            ListTile(
              dense: true,
              leading: const Icon(
                Icons.place_outlined,
                color: AppColors.primary,
                size: 20,
              ),
              title: Text(
                suggestions[i].primary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: AppColors.ink,
                ),
              ),
              subtitle: suggestions[i].secondary.isEmpty
                  ? null
                  : Text(
                      suggestions[i].secondary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.inkMuted,
                      ),
                    ),
              onTap: () => onTap(suggestions[i]),
            ),
          ],
        ],
      ),
    );
  }
}
