import 'dart:io';

import 'package:day_raft/adaptive.dart';
import 'package:day_raft/data/trip_store.dart';
import 'package:day_raft/domain/schedule.dart';
import 'package:day_raft/main.dart';
import 'package:day_raft/trip_screen.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show MaterialApp, TextField;
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:fluent_ui/fluent_ui.dart' show CommandBar, PageHeader, TextBox;
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

  testWidgets('Windows uses Fluent NavigationView, PageHeader, and TextBox', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await tester.pumpWidget(DayRaftApp(home: TripEditor(store: TripStore(db))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(TextBox), findsWidgets);
    expect(find.byType(PageHeader), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Android uses Material Scaffold and TextField', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(DayRaftApp(home: TripEditor(store: TripStore(db))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(TextField), findsWidgets);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'DesktopHome renders Fluent NavigationView with navigation items',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      await tester.pumpWidget(const DayRaftApp());
      await tester.pumpAndSettle();
      expect(find.text('Trips'), findsWidgets);
      expect(find.text('Local backups'), findsWidgets);
      expect(find.byType(CommandBar), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('trip editor exposes scaled controls to screen readers', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    tester.view.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.platformDispatcher.clearTextScaleFactorTestValue);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(
      MaterialApp(home: TripEditor(store: TripStore(db))),
    );
    await tester.pump();
    expect(find.byKey(const Key('trip-title')), findsOneWidget);
    expect(find.bySemanticsLabel('Trip title'), findsWidgets);
    expect(tester.takeException(), isNull);
    semantics.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Windows editor Escape returns to prior page', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await tester.pumpWidget(
      fluent.FluentApp(
        home: fluent.NavigationView(
          content: Builder(
            builder: (context) => fluent.Button(
              child: const Text('Open editor'),
              onPressed: () => Navigator.of(context).push(
                fluent.FluentPageRoute<void>(
                  builder: (_) => TripEditor(store: TripStore(db)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    expect(find.byType(TripEditor), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(TripEditor), findsNothing);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Windows trip menu works with right-click and keyboard', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    var edited = 0;
    var deleted = 0;
    await tester.pumpWidget(
      DayRaftApp(
        home: DesktopTripMenu(
          id: 'one',
          onEdit: () => edited++,
          onDelete: () => deleted++,
          child: const Text('Outing'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final menu = find.byKey(const Key('trip-menu-one'));
    expect(menu, findsOneWidget);
    final point = tester.getCenter(find.text('Outing'));
    await tester.sendEventToBinding(
      PointerAddedEvent(
        pointer: 1,
        kind: PointerDeviceKind.mouse,
        position: point,
      ),
    );
    await tester.sendEventToBinding(
      PointerDownEvent(
        pointer: 1,
        kind: PointerDeviceKind.mouse,
        position: point,
        buttons: kSecondaryMouseButton,
      ),
    );
    await tester.sendEventToBinding(
      PointerUpEvent(
        pointer: 1,
        kind: PointerDeviceKind.mouse,
        position: point,
        buttons: kSecondaryMouseButton,
      ),
    );
    await tester.sendEventToBinding(
      PointerRemovedEvent(
        pointer: 1,
        kind: PointerDeviceKind.mouse,
        position: point,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Edit trip'), findsOneWidget);
    expect(find.text('Delete trip'), findsOneWidget);
    await tester.tap(find.text('Edit trip'));
    await tester.pumpAndSettle();
    expect(edited, 1);
    expect(deleted, 0);
    await tester.tap(menu);
    await tester.pumpAndSettle();
    expect(find.text('Edit trip'), findsOneWidget);
    expect(find.text('Delete trip'), findsOneWidget);
    await tester.tap(find.text('Delete trip'));
    await tester.pumpAndSettle();
    expect(deleted, 1);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('adaptive buttons use host platform idiom', (tester) async {
    for (final platform in [
      TargetPlatform.iOS,
      TargetPlatform.android,
      TargetPlatform.windows,
    ]) {
      debugDefaultTargetPlatformOverride = platform;
      await tester.pumpWidget(
        DayRaftApp(
          home: const AdaptiveButton(label: 'Action', onPressed: null),
        ),
      );
      await tester.pumpAndSettle();
      if (platform == TargetPlatform.iOS) {
        expect(find.byType(CupertinoButton), findsOneWidget);
      } else if (platform == TargetPlatform.android) {
        expect(find.byType(CupertinoButton), findsNothing);
        expect(find.byType(TextField), findsNothing);
      } else {
        expect(find.byType(CupertinoButton), findsNothing);
      }
      expect(tester.takeException(), isNull);
    }
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
