import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:companion_ranchi/core/constants/app_constants.dart';
import 'package:companion_ranchi/core/network/api_exception.dart';
import 'package:companion_ranchi/core/theme/app_theme.dart';
import 'package:companion_ranchi/features/support/application/support_providers.dart';
import 'package:companion_ranchi/features/support/data/support_repository.dart';
import 'package:companion_ranchi/shared/widgets/widgets.dart';

/// Bottom sheet to raise a new support ticket (`POST /support/tickets`).
class CreateTicketSheet extends ConsumerStatefulWidget {
  const CreateTicketSheet({super.key});

  @override
  ConsumerState<CreateTicketSheet> createState() => _CreateTicketSheetState();
}

class _CreateTicketSheetState extends ConsumerState<CreateTicketSheet> {
  final _formKey = GlobalKey<FormState>();
  final _subjectController = TextEditingController();
  final _descriptionController = TextEditingController();
  String _priority = 'MEDIUM';

  @override
  void dispose() {
    _subjectController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final ticket =
        await ref.read(createTicketControllerProvider.notifier).submit(
              subject: _subjectController.text.trim(),
              description: _descriptionController.text.trim(),
              priority: _priority,
            );
    if (!mounted) return;
    if (ticket != null) {
      Navigator.of(context).pop(ticket);
    }
  }

  @override
  Widget build(BuildContext context) {
    final createState = ref.watch(createTicketControllerProvider);
    final isSubmitting = createState.isLoading;
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg + viewInsets,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
              const SizedBox(height: AppSpacing.lg),
              Text(
                'New support ticket',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppTextField(
                controller: _subjectController,
                label: 'Subject',
                hint: 'Brief summary of your issue',
                textInputAction: TextInputAction.next,
                maxLength: 120,
                validator: (v) {
                  final value = v?.trim() ?? '';
                  if (value.length < 4) return 'Enter a short subject';
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                controller: _descriptionController,
                label: 'Description',
                hint: 'Tell us what happened, with any booking ID',
                maxLines: 5,
                maxLength: 1000,
                validator: (v) {
                  final value = v?.trim() ?? '';
                  if (value.length < 10) {
                    return 'Please describe your issue in a little more detail';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Priority',
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: TicketPriorities.all.map((p) {
                  final selected = _priority == p;
                  return ChoiceChip(
                    label: Text(SupportTicket.priorityLabel(p)),
                    selected: selected,
                    onSelected: (_) => setState(() => _priority = p),
                  );
                }).toList(),
              ),
              if (createState.hasError) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  createState.error is ApiException
                      ? (createState.error as ApiException).message
                      : 'Could not create the ticket. Please try again.',
                  style: const TextStyle(color: AppColors.danger, fontSize: 13),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              GradientButton(
                label: 'Submit ticket',
                icon: Icons.send_rounded,
                isLoading: isSubmitting,
                onPressed: isSubmitting ? null : _submit,
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        ),
      ),
    );
  }
}
