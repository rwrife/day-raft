import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' as material;
import 'package:fluent_ui/fluent_ui.dart' as fluent;

import 'adaptive.dart';
import 'data/backup_screen.dart';
import 'trip_screen.dart';
export 'trip_screen.dart' show TripScreen;

void main() => runApp(const DayRaftApp());

class DayRaftApp extends StatelessWidget {
  const DayRaftApp({super.key, this.home});
  final Widget? home;

  @override
  Widget build(BuildContext context) {
    final root = home ?? const TripScreen();
    if (isIOS || defaultTargetPlatform == TargetPlatform.macOS) {
      return CupertinoApp(title: 'Day Raft', home: root);
    }
    if (isWindows) {
      return fluent.FluentApp(
        title: 'Day Raft',
        home: home ?? const DesktopHome(),
      );
    }
    return material.MaterialApp(
      title: 'Day Raft',
      theme: material.ThemeData(useMaterial3: true),
      home: root,
    );
  }
}

class DesktopHome extends StatefulWidget {
  const DesktopHome({super.key});
  @override
  State<DesktopHome> createState() => _DesktopHomeState();
}

class _DesktopHomeState extends State<DesktopHome> {
  int selected = 0;

  @override
  Widget build(BuildContext context) => fluent.NavigationView(
    pane: fluent.NavigationPane(
      selected: selected,
      onChanged: (index) => setState(() => selected = index),
      items: [
        fluent.PaneItem(
          icon: const Icon(fluent.FluentIcons.calendar),
          title: const Text('Trips'),
          body: const TripScreen(),
        ),
        fluent.PaneItem(
          icon: const Icon(fluent.FluentIcons.save),
          title: const Text('Local backups'),
          body: const BackupScreen(),
        ),
      ],
    ),
  );
}

class AdaptiveShell extends StatelessWidget {
  const AdaptiveShell({super.key, required this.title, required this.body});
  final String title;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    if (isIOS) {
      return CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(middle: Text(title)),
        child: SafeArea(child: body),
      );
    }
    if (isWindows) {
      return fluent.ScaffoldPage(
        header: fluent.PageHeader(title: Text(title)),
        content: SafeArea(child: body),
      );
    }
    return material.Scaffold(
      appBar: material.AppBar(title: Text(title)),
      body: SafeArea(child: body),
    );
  }
}
