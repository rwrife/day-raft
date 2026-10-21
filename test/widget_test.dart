import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:day_raft/main.dart';

void main() {
  testWidgets('root shell renders offline home copy', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await tester.pumpWidget(const DayRaftApp());

    expect(find.text('Day Raft'), findsOneWidget);
    expect(
      find.textContaining('See whether the day fits before you leave.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('user-entered planning estimates'),
      findsOneWidget,
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('iOS renders the Cupertino navigation idiom', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.pumpWidget(const DayRaftApp());

    expect(find.byType(CupertinoNavigationBar), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Windows and Android shell resolve through AdaptiveShell', (
    tester,
  ) async {
    for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
      debugDefaultTargetPlatformOverride = platform;
      await tester.pumpWidget(const DayRaftApp());

      // Both idiom families can coexist (Cupertino widgets sit inside a
      // MaterialApp), so identity here is the shell, not any single widget.
      expect(find.byType(AdaptiveShell), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
