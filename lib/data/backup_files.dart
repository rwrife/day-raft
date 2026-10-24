import 'dart:io';

import 'package:file_selector/file_selector.dart';

import 'trip_store.dart';

const backupType = XTypeGroup(label: 'Day Raft JSON', extensions: ['json']);

/// User chooses destination. Never overwrite an existing file silently.
Future<String?> exportBackup(TripStore store) async {
  final target = await getSaveLocation(
    suggestedName: 'day-raft-backup.json',
    acceptedTypeGroups: [backupType],
  );
  if (target == null) return null;
  return writeBackup(target.path, await store.snapshot());
}

/// Exclusive create so a file selected in the save dialog is never clobbered.
/// A failed write removes the partial file rather than leaving truncated JSON.
Future<String> writeBackup(String path, TripSnapshot snapshot) async {
  final file = File(path);
  final backup = snapshot.exportJson();
  await file.create(exclusive: true);
  try {
    await file.writeAsString(backup, flush: true);
  } catch (_) {
    await file.delete();
    rethrow;
  }
  return file.path;
}

/// Parse and validate entire document before offering merge or replace.
Future<TripSnapshot?> pickBackup() async {
  final file = await openFile(acceptedTypeGroups: [backupType]);
  if (file == null) return null;
  if (await file.length() > 10 * 1024 * 1024) {
    throw const FormatException('Backup exceeds 10 MB');
  }
  return TripSnapshot.parse(await file.readAsString());
}
