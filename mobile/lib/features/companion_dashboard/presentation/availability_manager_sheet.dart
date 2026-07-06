import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:companion_ranchi/core/models/companion_model.dart';
import 'package:companion_ranchi/core/theme/app_theme.dart';
import 'package:companion_ranchi/core/utils/formatters.dart';
import 'package:companion_ranchi/features/companion_dashboard/application/availability_controller.dart';
import 'package:companion_ranchi/features/companion_dashboard/application/companion_dashboard_providers.dart';
import 'package:companion_ranchi/shared/widgets/widgets.dart';

/// Bottom sheet to manage the companion's weekly recurring availability
/// (`PUT /companions/me/availability`). Lets the companion add/remove
/// time windows per weekday and save the whole set.
class AvailabilityManagerSheet extends ConsumerStatefulWidget {
  const AvailabilityManagerSheet({super.key, required this.initial});

  /// The companion's current weekly slots (from the profile).
  final List<AvailabilitySlot> initial;

  /// Opens the sheet, seeding it with [initial] slots.
  static Future<void> show(
    BuildContext context, {
    required List<AvailabilitySlot> initial,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AvailabilityManagerSheet(initial: initial),
    );
  }

  @override
  ConsumerState<AvailabilityManagerSheet> createState() =>
      _AvailabilityManagerSheetState();
}

class _AvailabilityManagerSheetState
    extends ConsumerState<AvailabilityManagerSheet> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(availabilityControllerProvider.notifier).hydrate(widget.initial);
    });
  }

  Future<void> _addSlot(int dayOfWeek) async {
    final start = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 10, minute: 0),
      helpText: 'Start time',
    );
    if (start == null || !mounted) return;
    final end = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: (start.hour + 2).clamp(0, 23), minute: 0),
      helpText: 'End time',
    );
    if (end == null || !mounted) return;

    final startStr = _fmt(start);
    final endStr = _fmt(end);
    if (_toMinutes(end) <= _toMinutes(start)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End time must be after start time.')),
      );
      return;
    }
    ref.read(availabilityControllerProvider.notifier).addSlot(
          dayOfWeek: dayOfWeek,
          startTime: startStr,
          endTime: endStr,
        );
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  int _toMinutes(TimeOfDay t) => t.hour * 60 + t.minute;

  Future<void> _save() async {
    try {
      await ref.read(availabilityControllerProvider.notifier).save();
      ref.invalidate(myCompanionProfileProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Availability updated.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_msg(e))),
      );
    }
  }

  String _msg(Object e) {
    final s = e.toString();
    final i = s.indexOf(': ');
    return i >= 0 && i < s.length - 2 ? s.substring(i + 2) : s;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(availabilityControllerProvider);
    final byDay = state.byDay;
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (context, scrollController) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Weekly availability',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              const Text(
                'Set the times you are open to meet each day. Customers can only '
                'book within these windows.',
                style: TextStyle(color: AppColors.inkMuted, fontSize: 13),
              ),
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: kWeekdayLabels.length,
                  itemBuilder: (context, day) {
                    final slots = byDay[day] ?? const [];
                    return _DaySection(
                      day: day,
                      slots: slots,
                      onAdd: () => _addSlot(day),
                      onRemove: (slot) => ref
                          .read(availabilityControllerProvider.notifier)
                          .removeSlot(slot),
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              GradientButton(
                label: 'Save availability',
                isLoading: state.isSaving,
                onPressed: state.isSaving ? null : _save,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DaySection extends StatelessWidget {
  const _DaySection({
    required this.day,
    required this.slots,
    required this.onAdd,
    required this.onRemove,
  });

  final int day;
  final List<AvailabilitySlot> slots;
  final VoidCallback onAdd;
  final ValueChanged<AvailabilitySlot> onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  kWeekdayLabels[day],
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              TextButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          if (slots.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Text(
                'Unavailable',
                style: TextStyle(color: AppColors.inkMuted, fontSize: 12.5),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final slot in slots)
                  InputChip(
                    label: Text(
                      '${Formatters.time12(slot.startTime)} – '
                      '${Formatters.time12(slot.endTime)}',
                    ),
                    onDeleted: () => onRemove(slot),
                    deleteIcon: const Icon(Icons.close_rounded, size: 16),
                  ),
              ],
            ),
          const Divider(height: AppSpacing.lg),
        ],
      ),
    );
  }
}
