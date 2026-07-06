import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:companion_ranchi/core/models/companion_model.dart';
import 'package:companion_ranchi/features/companion_dashboard/data/companion_dashboard_repository.dart';

/// Day-of-week labels (0 = Sunday .. 6 = Saturday), matching DATA_MODEL.md.
const List<String> kWeekdayLabels = [
  'Sunday',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
];

const List<String> kWeekdayShort = [
  'Sun',
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
];

/// Editable availability state: the working set of weekly slots plus save flags.
class AvailabilityState {
  const AvailabilityState({
    this.slots = const [],
    this.isSaving = false,
    this.loaded = false,
  });

  final List<AvailabilitySlot> slots;
  final bool isSaving;
  final bool loaded;

  AvailabilityState copyWith({
    List<AvailabilitySlot>? slots,
    bool? isSaving,
    bool? loaded,
  }) =>
      AvailabilityState(
        slots: slots ?? this.slots,
        isSaving: isSaving ?? this.isSaving,
        loaded: loaded ?? this.loaded,
      );

  /// Slots grouped by day-of-week (0..6), each list sorted by start time.
  Map<int, List<AvailabilitySlot>> get byDay {
    final map = <int, List<AvailabilitySlot>>{};
    for (final s in slots) {
      map.putIfAbsent(s.dayOfWeek, () => []).add(s);
    }
    for (final list in map.values) {
      list.sort((a, b) => a.startTime.compareTo(b.startTime));
    }
    return map;
  }
}

/// Manages the companion's weekly availability windows. Loaded from the
/// profile, edited locally (add/remove slots), then persisted via
/// `PUT /companions/me/availability`.
///
/// AutoDispose so the working set is discarded when the editor sheet closes,
/// guaranteeing a fresh seed (from the latest profile) on the next open.
class AvailabilityController extends AutoDisposeNotifier<AvailabilityState> {
  CompanionDashboardRepository get _repo =>
      ref.read(companionDashboardRepositoryProvider);

  @override
  AvailabilityState build() => const AvailabilityState();

  /// Seed the working set from the loaded profile (only once).
  void hydrate(List<AvailabilitySlot> slots) {
    if (state.loaded) return;
    state = state.copyWith(slots: List.of(slots), loaded: true);
  }

  /// Add a [startTime]–[endTime] window for [dayOfWeek]. Ignores duplicates and
  /// invalid ranges (end must be after start).
  void addSlot({
    required int dayOfWeek,
    required String startTime,
    required String endTime,
  }) {
    if (!_isValidRange(startTime, endTime)) return;
    final exists = state.slots.any((s) =>
        s.dayOfWeek == dayOfWeek &&
        s.startTime == startTime &&
        s.endTime == endTime);
    if (exists) return;
    state = state.copyWith(
      slots: [
        ...state.slots,
        AvailabilitySlot(
          dayOfWeek: dayOfWeek,
          startTime: startTime,
          endTime: endTime,
        ),
      ],
    );
  }

  /// Remove a specific slot.
  void removeSlot(AvailabilitySlot slot) {
    state = state.copyWith(
      slots: state.slots
          .where((s) => !(s.dayOfWeek == slot.dayOfWeek &&
              s.startTime == slot.startTime &&
              s.endTime == slot.endTime))
          .toList(),
    );
  }

  /// Remove every slot for a given day.
  void clearDay(int dayOfWeek) {
    state = state.copyWith(
      slots: state.slots.where((s) => s.dayOfWeek != dayOfWeek).toList(),
    );
  }

  /// Persist the working set. Returns the canonical slots from the server.
  Future<void> save() async {
    state = state.copyWith(isSaving: true);
    try {
      final saved = await _repo.saveAvailability(state.slots);
      state = state.copyWith(
        slots: saved.isNotEmpty ? saved : state.slots,
        isSaving: false,
      );
    } catch (e) {
      state = state.copyWith(isSaving: false);
      rethrow;
    }
  }

  bool _isValidRange(String start, String end) {
    final s = _minutes(start);
    final e = _minutes(end);
    if (s == null || e == null) return false;
    return e > s;
  }

  int? _minutes(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    if (h < 0 || h > 23 || m < 0 || m > 59) return null;
    return h * 60 + m;
  }
}

final availabilityControllerProvider =
    NotifierProvider.autoDispose<AvailabilityController, AvailabilityState>(
  AvailabilityController.new,
);
