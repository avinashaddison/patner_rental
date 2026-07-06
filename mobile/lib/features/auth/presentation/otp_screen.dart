import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:companion_ranchi/core/auth/auth_controller.dart';
import 'package:companion_ranchi/core/network/api_exception.dart';
import 'package:companion_ranchi/core/router/routes.dart';
import 'package:companion_ranchi/core/theme/app_theme.dart';
import 'package:companion_ranchi/shared/widgets/gradient_button.dart';

/// 6-digit OTP verification.
///
/// Receives the full mobile number via go_router's `extra`. Calls
/// [AuthController.verifyOtp] (`POST /auth/otp/verify`). On success:
///  * new user  → push `/register` (temp token already stored by the
///    controller) so they can complete their profile;
///  * returning → the controller sets the session, the router auth-redirect
///    sends them to `/home`.
class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key});

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  static const int _otpLength = 6;
  static const int _resendSeconds = 30;

  final List<TextEditingController> _controllers =
      List.generate(_otpLength, (_) => TextEditingController());
  final List<FocusNode> _focusNodes =
      List.generate(_otpLength, (_) => FocusNode());

  Timer? _timer;
  int _secondsLeft = _resendSeconds;
  bool _verifying = false;
  bool _resending = false;
  String? _error;

  String? _mobileNumber;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The login screen passes the full +91 number via `extra`.
    final extra = GoRouterState.of(context).extra;
    if (_mobileNumber == null && extra is String && extra.isNotEmpty) {
      _mobileNumber = extra;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _code => _controllers.map((c) => c.text).join();

  String get _maskedNumber {
    final number = _mobileNumber ?? '';
    if (number.length < 4) return number;
    final tail = number.substring(number.length - 4);
    return '${'•' * (number.length - 4)}$tail';
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _secondsLeft = _resendSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsLeft <= 1) {
        timer.cancel();
        setState(() => _secondsLeft = 0);
      } else {
        setState(() => _secondsLeft -= 1);
      }
    });
  }

  void _onChanged(int index, String value) {
    if (_error != null) setState(() => _error = null);

    // Handle paste of the full code into the first box.
    if (value.length > 1) {
      final digits = value.replaceAll(RegExp(r'\D'), '');
      for (var i = 0; i < _otpLength; i++) {
        _controllers[i].text = i < digits.length ? digits[i] : '';
      }
      final next = digits.length.clamp(0, _otpLength - 1);
      _focusNodes[next].requestFocus();
      setState(() {});
      if (_code.length == _otpLength) _verify();
      return;
    }

    if (value.isNotEmpty && index < _otpLength - 1) {
      _focusNodes[index + 1].requestFocus();
    }
    setState(() {});
    if (_code.length == _otpLength) _verify();
  }

  KeyEventResult _onKey(int index, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _controllers[index].text.isEmpty &&
        index > 0) {
      _controllers[index - 1].clear();
      _focusNodes[index - 1].requestFocus();
      setState(() {});
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _verify() async {
    final number = _mobileNumber;
    if (number == null) {
      setState(() => _error = 'Missing mobile number. Please go back and retry.');
      return;
    }
    if (_code.length != _otpLength) {
      setState(() => _error = 'Enter the full $_otpLength-digit code.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(authControllerProvider.notifier)
          .verifyOtp(mobileNumber: number, otp: _code);
      if (!mounted) return;
      if (result.isNewUser) {
        // Temp token is stored by the controller; complete the profile.
        context.pushReplacement(Routes.register, extra: number);
      } else {
        // Returning/test user — navigate to Home explicitly so we never depend
        // solely on the router's auth-redirect timing.
        context.go(Routes.home);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _verifying = false;
      });
      _clearCode();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Verification failed. Please try again.';
        _verifying = false;
      });
      _clearCode();
    }
  }

  void _clearCode() {
    for (final c in _controllers) {
      c.clear();
    }
    _focusNodes.first.requestFocus();
  }

  Future<void> _resend() async {
    final number = _mobileNumber;
    if (number == null || _secondsLeft > 0 || _resending) return;
    setState(() {
      _resending = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).requestOtp(number);
      if (!mounted) return;
      _clearCode();
      _startTimer();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A new OTP has been sent.')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not resend OTP. Please try again.');
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.canPop()
              ? context.pop()
              : context.go(Routes.login),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.lg),
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppSpacing.radius),
                ),
                child: const Icon(
                  Icons.sms_rounded,
                  color: AppColors.primary,
                  size: 32,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                'Verify your number',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text.rich(
                TextSpan(
                  text: 'Enter the 6-digit code sent to ',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: AppColors.inkMuted,
                  ),
                  children: [
                    TextSpan(
                      text: _maskedNumber,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.brightness == Brightness.dark
                            ? AppColors.darkInk
                            : AppColors.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              _OtpBoxes(
                length: _otpLength,
                controllers: _controllers,
                focusNodes: _focusNodes,
                enabled: !_verifying,
                hasError: _error != null,
                onChanged: _onChanged,
                onKey: _onKey,
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        color: AppColors.danger, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: AppColors.danger,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              GradientButton(
                label: 'Verify & continue',
                isLoading: _verifying,
                onPressed: _verifying ? null : _verify,
              ),
              const SizedBox(height: AppSpacing.xl),
              Center(
                child: _secondsLeft > 0
                    ? Text(
                        'Resend code in 0:${_secondsLeft.toString().padLeft(2, '0')}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.inkMuted,
                        ),
                      )
                    : TextButton.icon(
                        onPressed: _resending ? null : _resend,
                        icon: _resending
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Resend OTP'),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A row of [length] single-digit OTP input boxes.
class _OtpBoxes extends StatelessWidget {
  const _OtpBoxes({
    required this.length,
    required this.controllers,
    required this.focusNodes,
    required this.enabled,
    required this.hasError,
    required this.onChanged,
    required this.onKey,
  });

  final int length;
  final List<TextEditingController> controllers;
  final List<FocusNode> focusNodes;
  final bool enabled;
  final bool hasError;
  final void Function(int index, String value) onChanged;
  final KeyEventResult Function(int index, KeyEvent event) onKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(length, (index) {
        final filled = controllers[index].text.isNotEmpty;
        return Flexible(
          child: Padding(
            padding: EdgeInsets.only(right: index == length - 1 ? 0 : 8),
            child: AspectRatio(
              aspectRatio: 0.82,
              child: Focus(
                canRequestFocus: false,
                onKeyEvent: (_, event) => onKey(index, event),
                child: TextField(
                  controller: controllers[index],
                  focusNode: focusNodes[index],
                  enabled: enabled,
                  autofocus: index == 0,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  // Only the first box accepts multi-char input (paste).
                  maxLength: index == 0 ? null : 1,
                  showCursor: true,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: isDark ? AppColors.darkInk : AppColors.ink,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: InputDecoration(
                    counterText: '',
                    contentPadding: EdgeInsets.zero,
                    filled: true,
                    fillColor: filled
                        ? AppColors.primary.withValues(alpha: 0.06)
                        : (isDark ? AppColors.darkField : AppColors.field),
                    enabledBorder: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusSm),
                      borderSide: BorderSide(
                        color: hasError
                            ? AppColors.danger
                            : (filled
                                ? AppColors.primary
                                : (isDark
                                    ? AppColors.darkLine
                                    : AppColors.line)),
                        width: filled ? 1.6 : 1,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusSm),
                      borderSide: BorderSide(
                        color: hasError
                            ? AppColors.danger
                            : AppColors.primary,
                        width: 1.8,
                      ),
                    ),
                  ),
                  onChanged: (value) => onChanged(index, value),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
