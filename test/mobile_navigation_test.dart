import 'package:day_raft/data/trip_store.dart';
import 'package:day_raft/trip_screen.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// ponytail: in-memory snapshot skips SQLite transaction timers under fake async;
// use integration tests when testing database-backed navigation.
class _NavigationStore extends TripStore {
  _NavigationStore(super.db);
  @override
  Future<TripSnapshot> snapshot() async => TripSnapshot({}, {});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Database db;
  setUp(
    () async =>
        db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath),
  );
  tearDown(() async => db.close());

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('$platform back navigation discards unsaved trip edits', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        platform == TargetPlatform.iOS
            ? CupertinoApp(home: TripScreen(store: _NavigationStore(db)))
            : MaterialApp(home: TripScreen(store: _NavigationStore(db))),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('new-trip')));
      await tester.pumpAndSettle();
      expect(find.byType(TripEditor), findsOneWidget);
      await tester.enterText(find.byKey(const Key('trip-title')), 'Unsaved');
      tester.testTextInput.hide();
      await tester.pump();
      if (platform == TargetPlatform.iOS) {
        // CupertinoPageRoute owns edge swipe; Android uses system back.
        await tester.dragFrom(const Offset(2, 420), const Offset(350, 0));
        await tester.pumpAndSettle();
      } else {
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
      }
      expect(find.byType(TripEditor), findsNothing);
      await tester.tap(find.byKey(const Key('new-trip')));
      await tester.pumpAndSettle();
      expect(find.text('Unsaved'), findsNothing);
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
