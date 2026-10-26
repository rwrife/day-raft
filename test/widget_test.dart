import 'dart:io';

import 'package:day_raft/data/trip_store.dart';
import 'package:day_raft/domain/schedule.dart';
import 'package:day_raft/trip_screen.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show MaterialApp, TextField;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Database db;
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  });
  tearDown(() async {
    await db.close();
  });

  testWidgets('adaptive editor reorders stops with accessible buttons', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final trip = Trip(
      title: 'Saturday',
      start: DateTime(2026, 10, 25, 9),
      end: DateTime(2026, 10, 25, 12),
      stops: const [
        Stop(name: 'Bakery', dwellMinutes: 30),
        Stop(name: 'Museum', dwellMinutes: 30),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TripEditor(store: TripStore(db), id: '1', trip: trip),
      ),
    );
    await tester.pump();
    expect(
      find.textContaining('Opening hours are your notes, not live venue data.'),
      findsNWidgets(2),
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('stop-name-0')))
          .controller!
          .text,
      'Bakery',
    );
    await tester.ensureVisible(find.text('Move down stop 1'));
    await tester.pump();
    await tester.tap(find.text('Move down stop 1'));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('stop-name-0')))
          .controller!
          .text,
      'Museum',
    );
  });

  testWidgets('timeline shows overrun and per-stop conflicts', (tester) async {
    final store = TripStore(db);
    await store.saveTrip(
      'late',
      Trip(
        title: 'Rain day',
        start: DateTime(2026, 10, 21, 9),
        end: DateTime(2026, 10, 21, 10),
        stops: [
          Stop(
            name: 'Show',
            dwellMinutes: 90,
            anchor: DateTime(2026, 10, 21, 9, 10),
            opening: const OpeningNote(opensAt: 10 * 60, closesAt: 11 * 60),
          ),
        ],
      ),
    );
    await tester.pumpWidget(MaterialApp(home: TripScreen(store: store)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Overrun (40m late)'), findsOneWidget);
    expect(find.textContaining('outsideOpeningHours'), findsOneWidget);
    expect(find.byKey(const Key('timeline-stop-0')), findsOneWidget);
  });

  testWidgets('invalid local date stays in editor without writing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: TripEditor(store: TripStore(db))),
    );
    await tester.pump();
    await tester.enterText(find.byKey(const Key('trip-title')), 'Bad date');
    await tester.enterText(
      find.byKey(const Key('trip-start')),
      '2026-13-40 09:00',
    );
    await tester.ensureVisible(find.byKey(const Key('save-trip')));
    await tester.tap(find.byKey(const Key('save-trip')));
    await tester.pump();
    expect(find.textContaining('Invalid local date or time'), findsOneWidget);
    expect(find.byKey(const Key('trip-title')), findsOneWidget);
  });

  testWidgets('phone and desktop widths keep editor controls accessible', (
    tester,
  ) async {
    for (final width in [360.0, 1200.0]) {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(home: TripEditor(store: TripStore(db))),
      );
      await tester.pump();
      expect(find.byKey(const Key('trip-title')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('save-trip')));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('iOS editor uses Cupertino navigation and editable fields', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.pumpWidget(
      CupertinoApp(home: TripEditor(store: TripStore(db))),
    );
    await tester.pump();
    expect(find.byType(CupertinoNavigationBar), findsOneWidget);
    expect(find.byType(CupertinoTextField), findsNWidgets(3));
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'trip CRUD persists across reopen, JSON title and cost survive',
    () async {
      final dir = await Directory.systemTemp.createTemp('day-raft');
      final path = '${dir.path}/db.sqlite';
      var store = await TripStore.openAt(databaseFactoryFfi, path);
      final trip = Trip(
        title: 'Trip',
        start: DateTime(2026, 1, 1, 9),
        end: DateTime(2026, 1, 1, 12),
        stops: [const Stop(name: 'Stop', dwellMinutes: 10, roughCost: 7)],
      );
      await store.saveTrip('a', trip);
      await store.close();
      store = await TripStore.openAt(databaseFactoryFfi, path);
      final restored = (await store.snapshot()).trips['a']!;
      expect(restored.title, 'Trip');
      expect(restored.stops.single.roughCost, 7);
      expect(
        TripSnapshot.parse(
          (await store.snapshot()).exportJson(),
        ).trips['a']!.title,
        'Trip',
      );
      await store.deleteTrip('a');
      expect((await store.snapshot()).trips, isEmpty);
      await store.close();
      await dir.delete(recursive: true);
    },
  );
}
