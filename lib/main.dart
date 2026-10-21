import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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
  const DayRaftApp({super.key});

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return const CupertinoApp(
        title: 'Day Raft',
        debugShowCheckedModeBanner: false,
        home: HomeScreen(),
      );
    }
    return MaterialApp(
      title: 'Day Raft',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AdaptiveShell(
      title: 'Day Raft',
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Lay out stops, travel legs, and time budgets. '
                'See whether the day fits before you leave.',
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 16),
              Text(
                'Travel times are user-entered planning estimates, not live '
                'traffic, transit, or routing data.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Platform-native application shell.
///
/// Screens supply [title] and [body] once; this widget decides the idiom.
/// Keep new behavior here (dialogs, buttons, navigation) instead of
/// scattering [defaultTargetPlatform] checks through the screens.
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
    final theme = Theme.of(context)
        .copyWith(visualDensity: desktop ? VisualDensity.compact : null);
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
