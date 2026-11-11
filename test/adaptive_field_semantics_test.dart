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
    testWidgets('$platform field announces its label on the editable node', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      final semantics = tester.ensureSemantics();
      final controller = TextEditingController();
      try {
        await tester.pumpWidget(
          DayRaftApp(
            home: AdaptiveShell(
              title: 'Day Raft',
              body: AdaptiveField(
                inputKey: const Key('name-input'),
                label: 'Place name',
                controller: controller,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('name-input')), findsOneWidget);
        expect(
          find.semantics.byPredicate((node) {
            final data = node.getSemanticsData();
            return data.flagsCollection.isTextField &&
                data.label.contains('Place name');
          }),
          findsOneWidget,
        );
        await tester.enterText(find.byKey(const Key('name-input')), 'Library');
        expect(controller.text, 'Library');
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
        controller.dispose();
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
