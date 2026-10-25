import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'trip_screen.dart';
export 'trip_screen.dart' show TripScreen;

void main() {
  runApp(const DayRaftApp());
}

/// Root of Day Raft.
///
/// UX strategy A: every screen renders through [AdaptiveShell], choosing the
/// host platform's idiom: Cupertino on iOS, Material 3 on Android, and a
/// compact desktop layout on Windows. Fluent widgets land with the release
/// issue; until then, avoid using one phone look on every platform.
class DayRaftApp extends StatelessWidget {
  const DayRaftApp({super.key, this.home});
  final Widget? home;

  @override
  Widget build(BuildContext context) {
    final root = home ?? const TripScreen();
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return CupertinoApp(
        title: 'Day Raft',
        debugShowCheckedModeBanner: false,
        home: root,
      );
    }
    return MaterialApp(
      title: 'Day Raft',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: root,
    );
  }
}

class AdaptiveShell extends StatelessWidget {
  const AdaptiveShell({super.key, required this.title, required this.body});

  final String title;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final platform = defaultTargetPlatform;
    if (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS) {
      return CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(middle: Text(title)),
        child: SafeArea(child: body),
      );
    }
    final desktop =
        platform == TargetPlatform.windows || platform == TargetPlatform.linux;
    // Desktop pointer input wants compact density; touch keeps the default.
    final theme = Theme.of(
      context,
    ).copyWith(visualDensity: desktop ? VisualDensity.compact : null);
    return Theme(
      data: theme,
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          // Windows convention: leading actions, no up-button on the root page.
          automaticallyImplyLeading: !desktop,
        ),
        body: SafeArea(
          child: desktop
              ? Padding(padding: const EdgeInsets.all(24), child: body)
              : body,
        ),
      ),
    );
  }
}
