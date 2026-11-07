import 'package:day_raft/adaptive.dart';
import 'package:day_raft/main.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final platform in [
    TargetPlatform.iOS,
    TargetPlatform.android,
    TargetPlatform.windows,
  ]) {
    testWidgets('$platform adaptive button has a 44 logical-pixel target', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      tester.view.devicePixelRatio = 1;
      var taps = 0;
      try {
        await tester.pumpWidget(
          DayRaftApp(
            home: Center(
              child: AdaptiveButton(label: 'Save', onPressed: () => taps++),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final button = find.byType(AdaptiveButton);
        expect(tester.getSize(button).width, greaterThanOrEqualTo(44));
        expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
        final bounds = tester.getRect(button);
        await tester.tapAt(Offset(bounds.center.dx, bounds.top + 2));
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pumpAndSettle();
        expect(taps, 1, reason: 'Top edge must be inside actual tap target');
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
        tester.view.resetDevicePixelRatio();
      }
    });
  }
}
