import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:companion_ranchi/core/models/booking_model.dart';
import 'package:companion_ranchi/core/models/companion_model.dart';
import 'package:companion_ranchi/features/booking/data/booking_quote.dart';
import 'package:companion_ranchi/features/booking/data/booking_repository.dart';

/// The 3 grouped steps of the booking flow.
///
/// Each step bundles several decisions so the flow stays short:
///  * [when]    — duration + date + time slot
///  * [details] — activity + public meeting place + notes
///  * [review]  — server price breakdown + confirm & pay
enum BookingStep {
  when,
  details,
  review;

  // Note: Dart enums already provide a built-in zero-based `index` getter,
  // which is exactly the ordinal the flow needs — so we don't redeclare it.

  /// Number of steps in the flow.
  static int get count => values.length;
}

/// Immutable state of the in-progress booking flow.
@immutable
class BookingFlowState {
  const BookingFlowState({
    this.step = BookingStep.when,
    this.durationHours,
    this.bookingDate,
    this.selectedSlot,
    this.activity,
    this.categoryId,
    this.meetingLocation = '',
    this.meetingPlaceType,
    this.notes = '',
    this.quote,
    this.paymentMethod = 'razorpay',
    this.isSubmitting = false,
    this.submitError,
  });

  final BookingStep step;

  // Step 1 — duration (1 | 2 | 4 | 6).
  final int? durationHours;

  // Step 2 — date.
  final DateTime? bookingDate;

  // Step 3 — chosen slot.
  final TimeSlot? selectedSlot;

  // Step 4 — activity + (optional) mapped category id.
  final String? activity;
  final String? categoryId;

  // Step 5 — public meeting place.
  final String meetingLocation;
  final String? meetingPlaceType;
  final String notes;

  // Step 6 — server price breakdown.
  final BookingQuote? quote;

  // Step 6b — chosen payment method: 'razorpay' (online) | 'cash' (pay in person).
  final String paymentMethod;

  // Step 7 — submit.
  final bool isSubmitting;
  final Object? submitError;

  bool get canContinueFromDuration => durationHours != null;
  bool get canContinueFromDate => bookingDate != null;
  bool get canContinueFromSlot => selectedSlot != null;
  bool get canContinueFromActivity =>
      activity != null && activity!.trim().isNotEmpty;
  bool get canContinueFromLocation =>
      meetingLocation.trim().length >= 3 && meetingPlaceType != null;

  /// Whether the current [step] is satisfied and the user can advance.
  bool get canContinue {
    switch (step) {
      case BookingStep.when:
        return canContinueFromDuration &&
            canContinueFromDate &&
            canContinueFromSlot;
      case BookingStep.details:
        return canContinueFromActivity && canContinueFromLocation;
      case BookingStep.review:
        return quote != null && !isSubmitting;
    }
  }

  BookingFlowState copyWith({
    BookingStep? step,
    int? durationHours,
    DateTime? bookingDate,
    Object? selectedSlot = _sentinel,
    Object? activity = _sentinel,
    Object? categoryId = _sentinel,
    String? meetingLocation,
    Object? meetingPlaceType = _sentinel,
    String? notes,
    Object? quote = _sentinel,
    String? paymentMethod,
    bool? isSubmitting,
    Object? submitError = _sentinel,
  }) {
    return BookingFlowState(
      step: step ?? this.step,
      durationHours: durationHours ?? this.durationHours,
      bookingDate: bookingDate ?? this.bookingDate,
      selectedSlot: selectedSlot == _sentinel
          ? this.selectedSlot
          : selectedSlot as TimeSlot?,
      activity: activity == _sentinel ? this.activity : activity as String?,
      categoryId:
          categoryId == _sentinel ? this.categoryId : categoryId as String?,
      meetingLocation: meetingLocation ?? this.meetingLocation,
      meetingPlaceType: meetingPlaceType == _sentinel
          ? this.meetingPlaceType
          : meetingPlaceType as String?,
      notes: notes ?? this.notes,
      quote: quote == _sentinel ? this.quote : quote as BookingQuote?,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      submitError:
          submitError == _sentinel ? this.submitError : submitError,
    );
  }

  static const Object _sentinel = Object();
}

/// Drives the multi-step booking flow for a single companion. Holds the user's
/// selections, fetches the quote when entering the review step, and creates the
/// booking on confirm.
class BookingFlowController extends StateNotifier<BookingFlowState> {
  BookingFlowController(this._repo, this.companionId, this.companion)
      : super(const BookingFlowState());

  final BookingRepository _repo;
  final String companionId;

  /// The companion being booked (rate, name). May be null until loaded.
  final CompanionModel? companion;

  void setDuration(int hours) {
    state = state.copyWith(durationHours: hours, quote: null);
  }

  void setDate(DateTime date) {
    // Changing the date invalidates the previously selected slot.
    final normalised = DateTime(date.year, date.month, date.day);
    state = state.copyWith(
      bookingDate: normalised,
      selectedSlot: null,
    );
  }

  void setSlot(TimeSlot slot) {
    state = state.copyWith(selectedSlot: slot);
  }

  void setActivity(String activity, {String? categoryId}) {
    state = state.copyWith(activity: activity, categoryId: categoryId);
  }

  void setMeetingLocation(String location) {
    state = state.copyWith(meetingLocation: location);
  }

  void setMeetingPlaceType(String type) {
    state = state.copyWith(meetingPlaceType: type);
  }

  void setNotes(String notes) {
    state = state.copyWith(notes: notes);
  }

  void goToStep(BookingStep step) {
    state = state.copyWith(step: step);
  }

  /// Advance to the next step. When moving into the review step it fetches a
  /// fresh price quote. Returns null on success, or the error that blocked
  /// the advance (e.g. the quote request failing) so the UI can announce it.
  Future<Object?> next() async {
    if (!state.canContinue) return null;
    const order = BookingStep.values;
    final currentIndex = state.step.index;
    if (currentIndex >= order.length - 1) return null;

    final nextStep = order[currentIndex + 1];

    // Fetch the quote when entering the review step.
    if (nextStep == BookingStep.review) {
      await _loadQuote();
      // If the quote failed, stay on the current step and report why.
      if (state.quote == null) {
        return state.submitError ?? Exception('Could not get a price');
      }
    }
    state = state.copyWith(step: nextStep);
    return null;
  }

  /// Step back one step (no-op on the first step).
  void back() {
    final currentIndex = state.step.index;
    if (currentIndex == 0) return;
    state = state.copyWith(step: BookingStep.values[currentIndex - 1]);
  }

  /// Choose the payment method on the review step ('razorpay' | 'cash').
  void setPaymentMethod(String method) {
    state = state.copyWith(paymentMethod: method == 'cash' ? 'cash' : 'razorpay');
  }

  Future<void> _loadQuote() async {
    final duration = state.durationHours;
    if (duration == null) return;
    state = state.copyWith(submitError: null);
    try {
      final quote = await _repo.quote(
        companionId: companionId,
        durationHours: duration,
      );
      state = state.copyWith(quote: quote);
    } catch (e) {
      state = state.copyWith(quote: null, submitError: e);
    }
  }

  /// Re-fetch the quote (used by a retry button on the review step).
  Future<void> refreshQuote() => _loadQuote();

  /// Final step — `POST /bookings`. On success returns the created booking so
  /// the screen can navigate to `/payment/:bookingId`; on failure stores the
  /// error in state and returns null.
  Future<BookingModel?> submit() async {
    final s = state;
    if (s.durationHours == null ||
        s.bookingDate == null ||
        s.selectedSlot == null ||
        s.activity == null ||
        s.meetingPlaceType == null ||
        s.meetingLocation.trim().isEmpty) {
      state = state.copyWith(
        submitError: 'Please complete every step before confirming.',
      );
      return null;
    }

    state = state.copyWith(isSubmitting: true, submitError: null);
    try {
      final booking = await _repo.create(
        companionId: companionId,
        categoryId: s.categoryId,
        activity: s.activity!,
        durationHours: s.durationHours!,
        bookingDate: s.bookingDate!,
        startTime: s.selectedSlot!.startTime,
        meetingLocation: s.meetingLocation.trim(),
        meetingPlaceType: s.meetingPlaceType!,
        notes: s.notes,
        paymentMethod: s.paymentMethod,
      );
      state = state.copyWith(isSubmitting: false);
      return booking;
    } catch (e) {
      state = state.copyWith(isSubmitting: false, submitError: e);
      return null;
    }
  }
}
