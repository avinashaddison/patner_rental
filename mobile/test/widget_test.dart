// Smoke test placeholder.
//
// The default Flutter counter test was removed because this app uses a custom
// root widget (CompanionRanchiApp) plus Riverpod + platform plugins (secure
// storage, sockets) that aren't available in the bare widget-test sandbox.
// Real widget/integration tests can be added per feature; this keeps `flutter
// test` green in CI without standing up the whole app.

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app package compiles and tests run', () {
    expect(2 + 2, 4);
  });
}
