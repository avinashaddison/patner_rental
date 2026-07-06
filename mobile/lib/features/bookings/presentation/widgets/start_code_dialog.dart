import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:companion_ranchi/core/theme/app_theme.dart';
import 'package:companion_ranchi/core/utils/app_sounds.dart';

/// Shows the companion-facing "enter the customer's start code" dialog and
/// returns `true` if the meeting was successfully started.
///
/// [onSubmit] performs the start call and returns `null` on success (the dialog
/// closes) or an error message to display inline (the dialog stays open so the
/// companion can re-enter the code).
Future<bool> showStartCodeDialog(
  BuildContext context, {
  required Future<String?> Function(String code) onSubmit,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => StartCodeDialog(onSubmit: onSubmit),
  );
  return result == true;
}

/// Companion-facing dialog to enter the customer's 6-digit start code. Stays
/// open on an incorrect code, showing the server's message inline.
class StartCodeDialog extends StatefulWidget {
  const StartCodeDialog({super.key, required this.onSubmit});

  /// Returns null on success (dialog pops with `true`), or an error message.
  final Future<String?> Function(String code) onSubmit;

  @override
  State<StartCodeDialog> createState() => _StartCodeDialogState();
}

class _StartCodeDialogState extends State<StartCodeDialog> {
  final _controller = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _controller.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code from the customer.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final err = await widget.onSubmit(code);
    if (!mounted) return;
    if (err == null) {
      AppSounds.success();
      Navigator.pop(context, true);
    } else {
      setState(() {
        _submitting = false;
        _error = err;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Start the meeting'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ask the customer for their 6-digit start code and enter it here to '
            'begin the booking.',
            style: TextStyle(color: AppColors.inkMuted, fontSize: 13.5),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _controller,
            autofocus: true,
            enabled: !_submitting,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 6,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: 8,
            ),
            decoration: InputDecoration(
              counterText: '',
              hintText: '••••••',
              errorText: _error,
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                )
              : const Text('Start meeting'),
        ),
      ],
    );
  }
}
