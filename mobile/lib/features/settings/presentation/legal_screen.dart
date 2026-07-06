import 'package:flutter/material.dart';

import 'package:companion_ranchi/core/constants/app_constants.dart';
import 'package:companion_ranchi/core/theme/app_theme.dart';
import 'package:companion_ranchi/shared/widgets/safety_banner.dart';

/// The static legal / safety documents shown from Settings.
enum LegalDocument { safety, terms, privacy, refund }

/// Renders one of the bundled legal / safety documents. Content reinforces the
/// platform's hard rules: 18+ only, companionship activities only (no escort or
/// adult services), and public-place meetings only.
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.document});

  final LegalDocument document;

  @override
  Widget build(BuildContext context) {
    final spec = _specFor(document);
    return Scaffold(
      appBar: AppBar(title: Text(spec.title)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          const SafetyBanner(),
          const SizedBox(height: AppSpacing.lg),
          Text(
            spec.title,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'Last updated 29 June 2026',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.inkMuted),
          ),
          const SizedBox(height: AppSpacing.lg),
          for (final section in spec.sections) ...[
            Text(
              section.heading,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              section.body,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(height: 1.5, color: AppColors.inkMuted),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  _LegalSpec _specFor(LegalDocument doc) {
    switch (doc) {
      case LegalDocument.safety:
        return const _LegalSpec(
          title: 'Community & Safety Guidelines',
          sections: [
            _LegalSection(
              '1. 18+ only',
              'All users must be at least ${AppConstants.minAge} years old. We '
                  'verify date of birth at sign up and during companion KYC. '
                  'Misrepresenting your age leads to a permanent ban.',
            ),
            _LegalSection(
              '2. Companionship only',
              '${AppConstants.appName} is a companionship marketplace for social '
                  'activities such as coffee, movies, shopping, events, city '
                  'tours, networking and conversation. It is NOT an escort, '
                  'dating or adult service. Any solicitation of sexual or adult '
                  'services is strictly prohibited and will be reported.',
            ),
            _LegalSection(
              '3. Public places only',
              'Meetings must take place in public venues — malls, cafes, '
                  'restaurants, parks, public events, co-working spaces, hotel '
                  'lobbies and tourist spots. Private residences and hotel rooms '
                  'are not permitted.',
            ),
            _LegalSection(
              '4. Respect & consent',
              'Treat every companion and customer with respect. Harassment, '
                  'abuse, coercion or unwanted contact is grounds for an '
                  'immediate ban. Use the Report and SOS tools if you ever feel '
                  'unsafe.',
            ),
            _LegalSection(
              '5. Payments stay on-platform',
              'Pay only through the in-app wallet and Razorpay checkout. Cash or '
                  'off-platform payments are not protected and may indicate a '
                  'scam or prohibited activity.',
            ),
          ],
        );
      case LegalDocument.terms:
        return const _LegalSpec(
          title: 'Terms of Service',
          sections: [
            _LegalSection(
              '1. Acceptance',
              'By using ${AppConstants.appName} you agree to these Terms and to '
                  'our Community & Safety Guidelines. If you do not agree, do not '
                  'use the app.',
            ),
            _LegalSection(
              '2. Eligibility',
              'You must be ${AppConstants.minAge} or older and legally able to '
                  'enter contracts in India to use this service.',
            ),
            _LegalSection(
              '3. Bookings & payments',
              'Bookings are confirmed once payment is captured. The platform '
                  'charges a commission on each completed booking; the companion '
                  'receives the remaining payout to their wallet. Cancellations '
                  'and refunds follow the policy shown at checkout.',
            ),
            _LegalSection(
              '4. Prohibited conduct',
              'You may not use the service for escort, sexual, dating or any '
                  'illegal purpose, nor request meetings in non-public places. '
                  'Violations result in suspension or a permanent ban and may be '
                  'reported to authorities.',
            ),
            _LegalSection(
              '5. Liability',
              'Companions are independent individuals, not employees. We verify '
                  'identity but you are responsible for your own safety. Always '
                  'meet in public and use the SOS feature if needed.',
            ),
          ],
        );
      case LegalDocument.privacy:
        return const _LegalSpec(
          title: 'Privacy Policy',
          sections: [
            _LegalSection(
              '1. What we collect',
              'We collect your mobile number, name, gender, date of birth, city, '
                  'optional email and profile photo, plus booking, payment and '
                  'chat data needed to run the service.',
            ),
            _LegalSection(
              '2. How we use it',
              'Your data is used to verify eligibility, match you with '
                  'companions, process payments and payouts, keep the community '
                  'safe and send you booking and account notifications.',
            ),
            _LegalSection(
              '3. Sharing',
              'We share the minimum necessary information with companions or '
                  'customers you book, our payment provider (Razorpay) and, when '
                  'legally required, the authorities. We never sell your data.',
            ),
            _LegalSection(
              '4. Your controls',
              'You can edit your profile, block users, adjust notification '
                  'preferences and request account deletion via Support at any '
                  'time.',
            ),
            _LegalSection(
              '5. Security',
              'Access tokens are stored securely on your device and media is '
                  'served over encrypted connections. Report any concern through '
                  'the in-app Support section.',
            ),
          ],
        );
      case LegalDocument.refund:
        return const _LegalSpec(
          title: 'Refund & Cancellation Policy',
          sections: [
            _LegalSection(
              '1. How payments work',
              'You pay for a booking up front through Razorpay. The amount is '
                  'held against the booking and released to the companion only '
                  'after the meeting is completed. ${AppConstants.appName} keeps '
                  'a commission on each completed booking; the rest is the '
                  'companion\'s payout.',
            ),
            _LegalSection(
              '2. Cancelling before the meeting',
              'You can cancel from the booking screen. Unless a different '
                  'policy is shown at checkout, the following applies:\n\n'
                  '• More than 24 hours before the start time — full refund.\n'
                  '• Between 6 and 24 hours before — 50% refund (the remainder '
                  'compensates the companion for the reserved time).\n'
                  '• Less than 6 hours before, or a no-show — no refund.',
            ),
            _LegalSection(
              '3. If the companion cancels',
              'If a companion cancels or does not show up, you receive a full '
                  'refund to your original payment method. You can also report '
                  'the companion so our team can review their account.',
            ),
            _LegalSection(
              '4. Safety cancellations',
              'If a booking is cancelled because a safety rule was broken — for '
                  'example a request to meet in a private place or for a '
                  'prohibited activity — the user at fault may not be refunded '
                  'and their account may be suspended. If you ever feel unsafe, '
                  'use the SOS or Report tools.',
            ),
            _LegalSection(
              '5. How refunds are paid',
              'Approved refunds are returned to your original Razorpay payment '
                  'method. Banks and card networks usually take 5–7 business '
                  'days to credit the amount. Our Support team can confirm the '
                  'status at any time.',
            ),
            _LegalSection(
              '6. Disputes',
              'If something went wrong with a booking, contact us through '
                  'in-app Support within 48 hours. Our team can review the '
                  'booking and, where fair, issue a full or partial refund — '
                  'all payments are reversible by ${AppConstants.appName} admin.',
            ),
          ],
        );
    }
  }
}

class _LegalSpec {
  const _LegalSpec({required this.title, required this.sections});
  final String title;
  final List<_LegalSection> sections;
}

class _LegalSection {
  const _LegalSection(this.heading, this.body);
  final String heading;
  final String body;
}
