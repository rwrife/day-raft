import 'dart:convert';
import 'dart:io';

import 'package:day_raft/domain/schedule.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart' as mobile;
import 'package:flutter/foundation.dart';

/// One SQLite transaction replaces a complete validated snapshot. The domain
/// has no trip IDs yet; IDs here remain stable across exports and imports.
class TripStore {
  TripStore(this.db, {this.maxEntries = TripSnapshot.maxEntries});
  final Database db;
  static const schemaVersion = 1;

  /// Per-collection cap shared by import, mutation and export so any stored
  /// state is guaranteed to have a parseable export. Lowerable in tests.
  final int maxEntries;

  static Future<TripStore> open() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = '${dir.path}${Platform.pathSeparator}day-raft.sqlite';
    final factory =
        defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux
        ? databaseFactoryFfi
        : mobile.databaseFactory;
    if (identical(factory, databaseFactoryFfi)) sqfliteFfiInit();
    return openAt(factory, file);
  }

  /// Forward migrations keyed by the version they produce. Step N runs when
  /// upgrading from N-1; a missing step aborts the open without changing data.
  // ponytail: no steps yet (schema v1); add `2: (db) async {...}` when bumping.
  static const Map<int, Future<void> Function(Database)> migrations = {};

  static Future<TripStore> openAt(
    DatabaseFactory factory,
    String path, {
    int version = schemaVersion,
    Map<int, Future<void> Function(Database)> steps = migrations,
    int maxEntries = TripSnapshot.maxEntries,
  }) async {
    return TripStore(
      await factory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: version,
          onCreate: (db, v) async {
            await db.execute(
              'CREATE TABLE trips (id TEXT PRIMARY KEY, payload TEXT NOT NULL)',
            );
            await db.execute(
              'CREATE TABLE places (id TEXT PRIMARY KEY, name TEXT NOT NULL)',
            );
          },
          onUpgrade: (db, from, to) async {
            for (var next = from + 1; next <= to; next++) {
              final step = steps[next];
              if (step == null) {
                throw StateError('Missing database migration to $next');
              }
              await step(db);
            }
          },
          onDowngrade: (db, from, to) =>
              throw StateError('Database is newer ($from) than app ($to)'),
        ),
      ),
      maxEntries: maxEntries,
    );
  }

  Future<void> close() => db.close();

  Future<TripSnapshot> snapshot() => db.transaction(_snapshot);

  Future<TripSnapshot> _snapshot(DatabaseExecutor executor) async {
    final trips = <String, Trip>{};
    for (final row in await executor.query('trips')) {
      trips[row['id']! as String] = decodeTrip(
        jsonDecode(row['payload']! as String),
      );
    }
    final places = <String, String>{};
    for (final row in await executor.query('places')) {
      places[row['id']! as String] = row['name']! as String;
    }
    return TripSnapshot(trips, places);
  }

  Future<void> _assertExportable(DatabaseExecutor txn) async {
    (await _snapshot(txn)).exportJson(maxEntries: maxEntries);
  }

  Future<void> saveTrip(String id, Trip trip) async {
    _id(id);
    // Validate at trust boundary before touching disk.
    const ScheduleEngine().calculate(trip);
    await db.transaction((txn) async {
      await txn.insert('trips', {
        'id': id,
        'payload': jsonEncode(encodeTrip(trip)),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await _assertExportable(txn);
    });
  }

  Future<void> deleteTrip(String id) async {
    await db.transaction(
      (txn) async => txn.delete('trips', where: 'id = ?', whereArgs: [id]),
    );
  }

  Future<void> savePlace(String id, String name) async {
    _id(id);
    if (name.trim().isEmpty) throw const FormatException('Empty place name');
    await db.transaction((txn) async {
      await txn.insert('places', {
        'id': id,
        'name': name,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await _assertExportable(txn);
    });
  }

  Future<void> deletePlace(String id) async {
    await db.transaction(
      (txn) async => txn.delete('places', where: 'id = ?', whereArgs: [id]),
    );
  }

  Future<void> wipe() async {
    await db.transaction((txn) async {
      await txn.delete('trips');
      await txn.delete('places');
    });
  }

  Future<void> import(TripSnapshot incoming, {required bool replace}) async {
    // Merge keeps local entries on ID collision; never silently overwrites.
    await db.transaction((txn) async {
      if (replace) {
        if (incoming.trips.length > maxEntries ||
            incoming.places.length > maxEntries) {
          throw const FormatException('Import exceeds entry limit');
        }
        await txn.delete('trips');
        await txn.delete('places');
      }
      for (final entry in incoming.trips.entries) {
        await txn.insert(
          'trips',
          {'id': entry.key, 'payload': jsonEncode(encodeTrip(entry.value))},
          conflictAlgorithm: replace
              ? ConflictAlgorithm.replace
              : ConflictAlgorithm.ignore,
        );
      }
      for (final entry in incoming.places.entries) {
        await txn.insert(
          'places',
          {'id': entry.key, 'name': entry.value},
          conflictAlgorithm: replace
              ? ConflictAlgorithm.replace
              : ConflictAlgorithm.ignore,
        );
      }
      await _assertExportable(txn);
    });
  }
}

class TripSnapshot {
  TripSnapshot(Map<String, Trip> trips, Map<String, String> places)
    : trips = Map.unmodifiable(trips),
      places = Map.unmodifiable(places) {
    for (final entry in trips.entries) {
      _id(entry.key);
      const ScheduleEngine().calculate(entry.value);
    }
    for (final entry in places.entries) {
      _id(entry.key);
      if (entry.value.trim().isEmpty) {
        throw const FormatException('Empty place name');
      }
    }
  }
  final Map<String, Trip> trips;
  final Map<String, String> places;

  static const maxEntries = 10000;
  static const maxBytes = 10 * 1024 * 1024;

  /// Export refuses a payload that [parse] callers (10 MB picker limit) could
  /// not restore, so a backup is never silently unrestorable.
  String exportJson({int maxEntries = TripSnapshot.maxEntries}) {
    if (trips.length > maxEntries || places.length > maxEntries) {
      throw const FormatException('Backup exceeds entry limit');
    }
    final json = jsonEncode({
      'schemaVersion': TripStore.schemaVersion,
      'trips': {for (final e in trips.entries) e.key: encodeTrip(e.value)},
      'places': places,
    });
    if (utf8.encode(json).length > maxBytes) {
      throw const FormatException('Backup exceeds 10 MB; delete entries first');
    }
    return json;
  }

  static TripSnapshot parse(String text) {
    final value = jsonDecode(text);
    final root = _object(value);
    if (root['schemaVersion'] != TripStore.schemaVersion) {
      throw const FormatException('Unsupported backup schemaVersion');
    }
    final rawTrips = _object(root['trips']);
    final rawPlaces = _object(root['places']);
    if (rawTrips.length > maxEntries || rawPlaces.length > maxEntries) {
      throw const FormatException('Backup exceeds entry limit');
    }
    return TripSnapshot(
      {for (final e in rawTrips.entries) e.key: decodeTrip(e.value)},
      {for (final e in rawPlaces.entries) e.key: _string(e.value)},
    );
  }
}

void _id(String id) {
  if (id.trim().isEmpty || id.length > 128) {
    throw const FormatException('Invalid ID');
  }
}

Map<String, dynamic> _object(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Expected object');
  }
  return value;
}

String _string(Object? value) {
  if (value is! String) throw const FormatException('Expected string');
  return value;
}

int _int(Object? value) {
  if (value is! int) throw const FormatException('Expected integer');
  return value;
}

DateTime _date(Object? value) {
  final raw = _string(value);
  final date = DateTime.tryParse(raw);
  if (date == null || date.toIso8601String() != raw) {
    throw const FormatException('Invalid ISO date');
  }
  return date;
}

Map<String, dynamic> encodeTrip(Trip trip) => {
  'title': trip.title,
  'start': trip.start.toIso8601String(),
  'end': trip.end.toIso8601String(),
  'stops': [
    for (final stop in trip.stops)
      {
        'name': stop.name,
        'dwellMinutes': stop.dwellMinutes,
        'notes': stop.notes,
        'roughCost': stop.roughCost,
        'anchor': stop.anchor?.toIso8601String(),
        'actual': stop.actual == null
            ? null
            : {
                'status': stop.actual!.status.name,
                'arrival': stop.actual!.arrival?.toIso8601String(),
                'departure': stop.actual!.departure.toIso8601String(),
              },
        'leg': stop.leg == null
            ? null
            : {'mode': stop.leg!.mode.name, 'minutes': stop.leg!.minutes},
        'opening': stop.opening == null
            ? null
            : {
                'opensAt': stop.opening!.opensAt,
                'closesAt': stop.opening!.closesAt,
                'closedWeekdays': stop.opening!.closedWeekdays.toList()..sort(),
              },
      },
  ],
};

Trip decodeTrip(Object? value) {
  final root = _object(value);
  final rawStops = root['stops'];
  if (rawStops is! List || rawStops.length > 1000) {
    throw const FormatException('Invalid stops');
  }
  final trip = Trip(
    title: root['title'] == null ? '' : _string(root['title']),
    start: _date(root['start']),
    end: _date(root['end']),
    stops: [for (final raw in rawStops) _decodeStop(_object(raw))],
  );
  try {
    const ScheduleEngine().calculate(trip);
  } on ArgumentError catch (error) {
    throw FormatException('Invalid trip: $error');
  }
  return trip;
}

Stop _decodeStop(Map<String, dynamic> row) {
  final leg = row['leg'] == null ? null : _object(row['leg']);
  final actual = row['actual'] == null ? null : _object(row['actual']);
  final opening = row['opening'] == null ? null : _object(row['opening']);
  final days = opening?['closedWeekdays'];
  if (days != null && days is! List) {
    throw const FormatException('Invalid weekdays');
  }
  final modeName = leg?['mode'];
  final mode = leg == null
      ? null
      : TravelMode.values.where((v) => v.name == modeName).firstOrNull;
  if (leg != null && mode == null) {
    throw const FormatException('Invalid travel mode');
  }
  final actualStatusName = actual?['status'];
  final actualStatus = actual == null
      ? null
      : StopStatus.values.where((v) => v.name == actualStatusName).firstOrNull;
  if (actual != null && actualStatus == null) {
    throw const FormatException('Invalid stop status');
  }
  final stopActual = actual == null
      ? null
      : StopActual(
          status: actualStatus!,
          arrival: actual['arrival'] == null ? null : _date(actual['arrival']),
          departure: _date(actual['departure']),
        );
  return Stop(
    name: _string(row['name']),
    dwellMinutes: _int(row['dwellMinutes']),
    notes: _string(row['notes']),
    roughCost: row['roughCost'] == null ? 0 : _int(row['roughCost']),
    anchor: row['anchor'] == null ? null : _date(row['anchor']),
    actual: stopActual,
    leg: leg == null ? null : Leg(mode: mode!, minutes: _int(leg['minutes'])),
    opening: opening == null
        ? null
        : OpeningNote(
            opensAt: opening['opensAt'] == null
                ? null
                : _int(opening['opensAt']),
            closesAt: opening['closesAt'] == null
                ? null
                : _int(opening['closesAt']),
            closedWeekdays: {for (final day in days as List? ?? []) _int(day)},
          ),
  );
}
