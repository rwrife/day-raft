import 'dart:io';

import 'package:day_raft/data/backup_files.dart';
import 'package:day_raft/data/trip_store.dart';
import 'package:day_raft/domain/schedule.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Database db;
  late TripStore store;
  late Directory tempDir;

  Trip sampleTrip() => Trip(
    start: DateTime.utc(2026, 10, 24, 9, 0),
    end: DateTime.utc(2026, 10, 24, 17, 0),
    stops: [
      Stop(
        name: 'Pike Place',
        dwellMinutes: 60,
        leg: const Leg(mode: TravelMode.walk, minutes: 15),
        anchor: DateTime.utc(2026, 10, 24, 10, 0),
        opening: const OpeningNote(
          opensAt: 9 * 60,
          closesAt: 18 * 60,
          closedWeekdays: {DateTime.monday},
        ),
        notes: 'Try the chowder',
      ),
      const Stop(name: 'Space Needle', dwellMinutes: 90),
    ],
  );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('day-raft-test-');
    final dbPath = '${tempDir.path}${Platform.pathSeparator}test.db';
    db = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: TripStore.schemaVersion,
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE trips (id TEXT PRIMARY KEY, payload TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE places (id TEXT PRIMARY KEY, name TEXT NOT NULL)',
          );
        },
      ),
    );
    store = TripStore(db);
  });

  tearDown(() async {
    await store.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('trips and places CRUD persists and queries correctly', () async {
    expect((await store.snapshot()).trips, isEmpty);
    expect((await store.snapshot()).places, isEmpty);

    final trip = sampleTrip();
    await store.saveTrip('trip-1', trip);
    await store.savePlace('place-1', 'Seattle Center');

    final snap = await store.snapshot();
    expect(snap.trips.length, 1);
    expect(snap.places.length, 1);
    expect(snap.places['place-1'], 'Seattle Center');

    final storedTrip = snap.trips['trip-1']!;
    expect(storedTrip.start, trip.start);
    expect(storedTrip.end, trip.end);
    expect(storedTrip.stops.length, 2);
    expect(storedTrip.stops.first.name, 'Pike Place');
    expect(storedTrip.stops.first.leg?.mode, TravelMode.walk);
    expect(storedTrip.stops.first.leg?.minutes, 15);
    expect(storedTrip.stops.first.anchor, trip.stops.first.anchor);
    expect(storedTrip.stops.first.opening?.opensAt, 9 * 60);
    expect(storedTrip.stops.first.opening?.closedWeekdays, {DateTime.monday});
    expect(storedTrip.stops.first.notes, 'Try the chowder');

    await store.deleteTrip('trip-1');
    await store.deletePlace('place-1');
    expect((await store.snapshot()).trips, isEmpty);
    expect((await store.snapshot()).places, isEmpty);
  });

  test('mutations keep every permitted state exportable', () async {
    final path = '${tempDir.path}${Platform.pathSeparator}small.db';
    final small = await TripStore.openAt(
      databaseFactoryFfi,
      path,
      maxEntries: 2,
    );
    await small.savePlace('p1', 'One');
    await small.savePlace('p2', 'Two');
    await expectLater(small.savePlace('p3', 'Three'), throwsFormatException);
    expect((await small.snapshot()).places.length, 2);

    // Replace import at cap succeeds and replaces everything.
    await small.import(TripSnapshot({}, {'p9': 'Nine'}), replace: true);
    expect((await small.snapshot()).places, {'p9': 'Nine'});
    // Replace import beyond cap aborts before deleting anything.
    await expectLater(
      small.import(
        TripSnapshot({}, {'a': 'A', 'b': 'B', 'c': 'C'}),
        replace: true,
      ),
      throwsFormatException,
    );
    expect((await small.snapshot()).places, {'p9': 'Nine'});
    await small.close();
  });

  test('wipe removes both trips and places atomically', () async {
    await store.saveTrip('t1', sampleTrip());
    await store.savePlace('p1', 'Library');
    await store.wipe();

    final snap = await store.snapshot();
    expect(snap.trips, isEmpty);
    expect(snap.places, isEmpty);
  });

  test('invalid trip fails before database mutation', () async {
    // End before start is invalid in schedule engine.
    final broken = Trip(
      start: DateTime.utc(2026, 10, 24, 18, 0),
      end: DateTime.utc(2026, 10, 24, 9, 0),
      stops: [],
    );
    expect(() => store.saveTrip('bad', broken), throwsArgumentError);
    expect((await store.snapshot()).trips, isEmpty);
  });

  test('export refuses existing file and preserves its contents', () async {
    final path = '${tempDir.path}${Platform.pathSeparator}backup.json';
    final file = File(path);
    await file.writeAsString('existing');
    await expectLater(
      writeBackup(path, TripSnapshot({}, {})),
      throwsA(isA<FileSystemException>()),
    );
    expect(await file.readAsString(), 'existing');
    await file.delete();
    final snapshot = TripSnapshot({'t': sampleTrip()}, {'p': 'Place'});
    await writeBackup(path, snapshot);
    expect(
      TripSnapshot.parse(await file.readAsString()).exportJson(),
      snapshot.exportJson(),
    );
  });

  test('actuals persist across reopen and JSON export/import', () async {
    final trip = Trip(
      start: DateTime.utc(2026, 10, 24, 9),
      end: DateTime.utc(2026, 10, 24, 12),
      stops: [
        Stop(
          name: 'Stop',
          dwellMinutes: 30,
          actual: StopActual(
            status: StopStatus.late,
            arrival: DateTime.utc(2026, 10, 24, 9, 20),
            departure: DateTime.utc(2026, 10, 24, 10),
          ),
        ),
      ],
    );
    await store.saveTrip('day', trip);
    final reopened = await TripStore.openAt(
      databaseFactoryFfi,
      '${tempDir.path}${Platform.pathSeparator}test.db',
    );
    final restored = (await reopened.snapshot()).trips['day']!;
    expect(restored.stops.single.actual!.status, StopStatus.late);
    expect(
      restored.stops.single.actual!.arrival,
      DateTime.utc(2026, 10, 24, 9, 20),
    );
    final backup = (await reopened.snapshot()).exportJson();
    final parsed = TripSnapshot.parse(backup).trips['day']!;
    expect(
      parsed.stops.single.actual!.departure,
      DateTime.utc(2026, 10, 24, 10),
    );
    await reopened.close();
  });

  test('JSON backup roundtrips exact contents', () async {
    await store.saveTrip('t1', sampleTrip());
    await store.savePlace('p1', 'Harbor');

    final snap = await store.snapshot();
    final json = snap.exportJson();
    final parsed = TripSnapshot.parse(json);

    expect(parsed.trips.length, 1);
    expect(parsed.places.length, 1);
    expect(parsed.places['p1'], 'Harbor');
    expect(parsed.trips['t1']!.stops.first.name, 'Pike Place');
  });

  test('corrupt or truncated backup never alters existing data', () async {
    await store.savePlace('local-place', 'Original Harbor');
    final before = await store.snapshot();

    expect(
      () => TripSnapshot.parse('{"schemaVersion": 1, "trips":'),
      throwsFormatException,
    );
    expect(
      () => TripSnapshot.parse('{"schemaVersion": 999}'),
      throwsFormatException,
    );
    expect(
      () => TripSnapshot.parse(
        '{"schemaVersion": 1, "trips": {}, "places": {"p": 123}}',
      ),
      throwsFormatException,
    );

    // Existing store left untouched
    final after = await store.snapshot();
    expect(after.places['local-place'], 'Original Harbor');
    expect(after.places.length, before.places.length);
  });

  test(
    'import replace clears prior state; import merge preserves local on collision',
    () async {
      await store.saveTrip('shared-id', sampleTrip());
      await store.savePlace('shared-p', 'Old Place');
      await store.savePlace('local-only', 'Stays On Merge');

      final incomingTrip = Trip(
        start: DateTime.utc(2026, 10, 25, 8, 0),
        end: DateTime.utc(2026, 10, 25, 12, 0),
        stops: [const Stop(name: 'New Destination', dwellMinutes: 45)],
      );
      final incoming = TripSnapshot(
        {'shared-id': incomingTrip, 'new-id': incomingTrip},
        {'shared-p': 'Incoming Place', 'incoming-only': 'New Place'},
      );

      // Merge: preserve local collisions
      await store.import(incoming, replace: false);
      var current = await store.snapshot();
      expect(current.places['shared-p'], 'Old Place'); // collision preserved
      expect(current.places['local-only'], 'Stays On Merge');
      expect(
        current.places['incoming-only'],
        'New Place',
      ); // new place inserted
      expect(
        current.trips['shared-id']!.stops.first.name,
        'Pike Place',
      ); // kept
      expect(
        current.trips['new-id']!.stops.first.name,
        'New Destination',
      ); // added

      // Replace: wipes previous local data completely
      await store.import(incoming, replace: true);
      current = await store.snapshot();
      expect(current.places['local-only'], isNull); // wiped
      expect(current.places['shared-p'], 'Incoming Place'); // replaced
      expect(current.places['incoming-only'], 'New Place');
      expect(current.trips['shared-id']!.stops.first.name, 'New Destination');
    },
  );

  test('v1 fixture migrates forward without losing rows', () async {
    final path = '${tempDir.path}${Platform.pathSeparator}fixture.db';
    final v1 = await TripStore.openAt(databaseFactoryFfi, path);
    await v1.savePlace('p1', 'Kept');
    await v1.saveTrip('t1', sampleTrip());
    await v1.close();

    final v2 = await TripStore.openAt(
      databaseFactoryFfi,
      path,
      version: 2,
      steps: {2: (db) => db.execute('ALTER TABLE places ADD COLUMN note TEXT')},
    );
    final snap = await v2.snapshot();
    expect(snap.places['p1'], 'Kept');
    expect(snap.trips['t1']!.stops.length, 2);
    expect(await v2.db.getVersion(), 2);
    await v2.close();

    // Missing step fails and leaves the file untouched at v2.
    await expectLater(
      TripStore.openAt(databaseFactoryFfi, path, version: 3, steps: {}),
      throwsStateError,
    );
    final again = await TripStore.openAt(
      databaseFactoryFfi,
      path,
      version: 2,
      steps: {},
    );
    expect((await again.snapshot()).places['p1'], 'Kept');
    await again.close();
  });

  test('schema v1 refuses to open a database from a newer schema', () async {
    final path = '${tempDir.path}${Platform.pathSeparator}future.db';
    final newer = await TripStore.openAt(
      databaseFactoryFfi,
      path,
      version: 2,
      steps: {2: (db) => db.execute('ALTER TABLE places ADD COLUMN note TEXT')},
    );
    await newer.savePlace('p1', 'Kept');
    await newer.close();

    // Production open (schema v1) must abort instead of downgrading or wiping.
    await expectLater(
      TripStore.openAt(databaseFactoryFfi, path),
      throwsStateError,
    );
    final data = await TripStore.openAt(
      databaseFactoryFfi,
      path,
      version: 2,
      steps: {2: (db) => db.execute('ALTER TABLE places ADD COLUMN note TEXT')},
    );
    expect((await data.snapshot()).places['p1'], 'Kept');
    await data.close();
  });
}
