import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:share_plus/share_plus.dart';

import 'trip_store.dart';

const backupType = XTypeGroup(
  label: 'Day Raft JSON',
  extensions: ['json'],
  uniformTypeIdentifiers: ['public.json'],
);

/// Desktop: user chooses a destination; mobile: the OS share sheet offers
/// Save to Files. No network call is made by this app.
Future<void> exportBackup(TripStore store, {required bool mobile}) async {
  final snapshot = await store.snapshot();
  if (mobile) {
    await shareBackupText(snapshot.exportJson());
    return;
  }
  final target = await getSaveLocation(
    suggestedName: 'day-raft-backup.json',
    acceptedTypeGroups: [backupType],
  );
  if (target == null) return;
  await writeBackup(target.path, snapshot);
}

Future<void> shareBackupText(String backupJson) async {
  final dir = await Directory.systemTemp.createTemp('day-raft-backup-');
  final file = File('${dir.path}${Platform.pathSeparator}day-raft-backup.json');
  try {
    await file.writeAsString(backupJson, flush: true);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path, mimeType: 'application/json')]),
    );
  } finally {
    if (await file.exists()) await file.delete();
    if (await dir.exists()) await dir.delete(recursive: true);
  }
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
  if (await file.length() > TripSnapshot.maxBytes) {
    throw const FormatException('Backup exceeds 10 MB');
  }
  return TripSnapshot.parse(await file.readAsString());
}
