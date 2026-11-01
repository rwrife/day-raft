import 'package:day_raft/adaptive.dart';
import 'package:day_raft/main.dart';
import 'package:flutter/cupertino.dart' show CupertinoButton;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TextButton;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_ui/fluent_ui.dart' show Button;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final (platform, width, height) in [
    (TargetPlatform.iOS, 390.0, 844.0),
    (TargetPlatform.android, 390.0, 844.0),
    (TargetPlatform.windows, 1200.0, 800.0),
  ]) {
    testWidgets('$platform adaptive shell golden', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      tester.view.physicalSize = Size(width, height);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        DayRaftApp(
          home: AdaptiveShell(
            title: 'Day Raft',
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Saturday outing'),
                    Text('Travel legs are your estimates, not live data.'),
                    AdaptiveButton(label: 'New trip', onPressed: null),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (platform == TargetPlatform.iOS) {
        expect(find.byType(CupertinoButton), findsOneWidget);
        expect(find.byType(TextButton), findsNothing);
      } else if (platform == TargetPlatform.android) {
        expect(find.byType(TextButton), findsOneWidget);
        expect(find.byType(CupertinoButton), findsNothing);
      } else {
        expect(find.byType(Button), findsOneWidget);
        expect(find.byType(TextButton), findsNothing);
      }
      await expectLater(
        find.byType(AdaptiveShell),
        matchesGoldenFile('goldens/adaptive_shell_${platform.name}.png'),
      );
      debugDefaultTargetPlatformOverride = null;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }
}
