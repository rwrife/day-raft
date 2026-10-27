import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../adaptive.dart';
import '../main.dart' show AdaptiveShell;
import 'backup_files.dart';
import 'trip_store.dart';

/// User-initiated backup controls. No automatic network or location access.
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  TripStore? store;
  String? error;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    TripStore.open()
        .then((value) {
          if (mounted) {
            setState(() => store = value);
          } else {
            value.close();
          }
        })
        .catchError((Object e) {
          if (mounted) setState(() => error = '$e');
        });
  }

  @override
  void dispose() {
    store?.close();
    super.dispose();
  }

  bool get ios => defaultTargetPlatform == TargetPlatform.iOS;
  bool get mobile =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;

  Future<bool?> _ask(String title, String details, {String yes = 'Continue'}) =>
      showAdaptivePrompt<bool>(
        context,
        (context) => AdaptiveDialog(
          title: title,
          content: Text(details),
          actions: [
            AdaptiveButton(
              label: 'Cancel',
              onPressed: () => Navigator.pop(context, false),
            ),
            AdaptiveButton(
              label: yes,
              destructive: yes == 'Wipe' || yes == 'Replace',
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        ),
      );

  Future<void> _run(Future<void> Function() operation) async {
    if (busy || store == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await operation();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<bool?> _chooseImport(String details) => showAdaptivePrompt<bool>(
    context,
    (context) => AdaptiveDialog(
      title: 'Preview import',
      content: Text(details),
      actions: [
        AdaptiveButton(
          label: 'Cancel',
          onPressed: () => Navigator.pop(context),
        ),
        AdaptiveButton(
          label: 'Merge',
          onPressed: () => Navigator.pop(context, true),
        ),
        AdaptiveButton(
          label: 'Replace…',
          destructive: true,
          onPressed: () => Navigator.pop(context, false),
        ),
      ],
    ),
  );

  Future<void> _import() async {
    final incoming = await pickBackup();
    if (incoming == null || !mounted) return;
    final existing = await store!.snapshot();
    if (!mounted) return;
    final details =
        '${incoming.trips.length} trips, ${incoming.places.length} places in backup. '
        'Current: ${existing.trips.length} trips, ${existing.places.length} places. '
        'Merge keeps current entries when IDs match.';
    final merge = await _chooseImport('$details\n\nChoose merge or replace.');
    if (!mounted || merge == null) return;
    if (merge) {
      await store!.import(incoming, replace: false);
    } else if (await _ask(
          'Replace all local data?',
          '$details\n\nThis deletes all current trips and places before import. Export a backup first.',
          yes: 'Replace',
        ) ==
        true) {
      await store!.import(incoming, replace: true);
    }
  }

  Widget _button(String label, VoidCallback onPressed) => AdaptiveButton(
    label: label,
    onPressed: busy || store == null ? null : onPressed,
  );

  @override
  Widget build(BuildContext context) => AdaptiveShell(
    title: 'Local backups',
    body: Center(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Trips and places stay on this device. JSON backups are saved only when you choose a file.',
              ),
              if (store == null && error == null)
                const Text('Opening local database…'),
              if (error != null)
                Text('Error: $error', key: const Key('backup-error')),
              _button(
                'Export JSON backup',
                () => _run(() async {
                  await exportBackup(store!, mobile: mobile);
                }),
              ),
              _button('Import JSON backup', () => _run(_import)),
              _button(
                'Wipe local data',
                () => _run(() async {
                  if (await _ask(
                        'Wipe local data?',
                        'All trips and places on this device will be deleted. Export a backup first.',
                        yes: 'Wipe',
                      ) ==
                      true) {
                    await store!.wipe();
                  }
                }),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
