import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:companion_ranchi/core/constants/app_constants.dart';
import 'package:companion_ranchi/core/theme/app_theme.dart';
import 'package:companion_ranchi/features/settings/presentation/legal_screen.dart';

/// A short consent sentence with tappable links to the Terms of Service,
/// Privacy Policy and Community & Safety Guidelines.
///
/// Used on the login and registration screens so users can actually read what
/// they are agreeing to before they continue. Owns its [TapGestureRecognizer]s
/// and disposes them, which is why it is a [StatefulWidget].
class LegalConsentText extends StatefulWidget {
  const LegalConsentText({
    super.key,
    this.prefix = 'By continuing you agree to our ',
    this.confirmAge = true,
    this.textAlign = TextAlign.center,
  });

  /// Sentence shown before the document links.
  final String prefix;

  /// When true, appends ", and confirm you are 18+." after the links.
  final bool confirmAge;

  final TextAlign textAlign;

  @override
  State<LegalConsentText> createState() => _LegalConsentTextState();
}

class _LegalConsentTextState extends State<LegalConsentText> {
  late final TapGestureRecognizer _terms;
  late final TapGestureRecognizer _privacy;
  late final TapGestureRecognizer _guidelines;

  @override
  void initState() {
    super.initState();
    _terms = TapGestureRecognizer()..onTap = () => _open(LegalDocument.terms);
    _privacy = TapGestureRecognizer()
      ..onTap = () => _open(LegalDocument.privacy);
    _guidelines = TapGestureRecognizer()
      ..onTap = () => _open(LegalDocument.safety);
  }

  @override
  void dispose() {
    _terms.dispose();
    _privacy.dispose();
    _guidelines.dispose();
    super.dispose();
  }

  void _open(LegalDocument doc) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LegalScreen(document: doc)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodySmall?.copyWith(
      color: AppColors.inkMuted,
      height: 1.4,
    );
    final link = base?.copyWith(
      color: AppColors.primary,
      fontWeight: FontWeight.w700,
    );
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(text: widget.prefix),
          TextSpan(text: 'Terms of Service', style: link, recognizer: _terms),
          const TextSpan(text: ', '),
          TextSpan(text: 'Privacy Policy', style: link, recognizer: _privacy),
          const TextSpan(text: ' and '),
          TextSpan(
            text: 'Community Guidelines',
            style: link,
            recognizer: _guidelines,
          ),
          if (widget.confirmAge)
            const TextSpan(
              text: ', and confirm you are ${AppConstants.minAge}+.',
            )
          else
            const TextSpan(text: '.'),
        ],
      ),
      textAlign: widget.textAlign,
    );
  }
}
