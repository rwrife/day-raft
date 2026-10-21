# Day Raft

**Pitch:** Day Raft helps people planning a day out with others turn a messy group-chat list of places into one offline, stop-by-stop itinerary with time budgets, opening-hour warnings, and travel legs — on phone, tablet, and Windows, with no account, no cloud, and no location tracking.

Day Raft is a local-first Flutter app in the Tool Lab fleet. It is a planning aid, not a navigation, booking, or ticketing product.

## Motivation

Group day trips usually die in a chat thread. Each person suggests a café, a trailhead, a museum, a brewery. Some are closed on Mondays. Some are 40 minutes apart. Nobody can tell whether the plan physically fits between "leave at 9" and "kids asleep by 8". Existing trip planners are cloud accounts, booking funnels, subscription upsells, and multi-week itinerary machinery that a single Saturday does not need.

Day Raft keeps one trip a day-trip: a short ordered list of stops, a rough travel leg between each pair, per-stop dwell time, and an honest "this plan runs 47 minutes past your end time" verdict — entirely on device.

## Target users

- Friends and families coordinating a day out over chat, then wanting one shared plan.
- Solo day-trippers who want a time-budgeted loop without opening three map apps.
- Caregivers and outing planners who need visible buffers (feeding naps, medication windows, mobility rest stops) without sharing anyone's health data.
- People on metered, rural, or privacy-sensitive connections who need planning to work fully offline.

## Use cases

1. Saturday plan: drop in a bakery, a trailhead, a lunch spot, and a movie; set dwell times; see whether dinner at 6:30 is realistic.
2. Opening-hours sanity: note that the museum is closed Mondays and the plan flags the conflict on the chosen date.
3. Rain fallback: keep a second plan on the same trip and compare total times side by side.
4. Accessibility-first outing: attach rest-seat and step-free notes per stop so nobody has to re-ask in the group chat.
5. Airplane-mode planning: build or edit a full day plan with no network at all.

## How to use

1. Create a trip, set the start time, end time, and any fixed anchors (show ticket at 19:00).
2. Add stops with name, notes, planned dwell time, and optional rough cost or opening-hour notes.
3. Add the travel leg before each stop by rough mode (walk/transit/car/bike) and rough minutes, or pick from locally saved places.
4. Read the timeline view: arrival/departure per stop, total time, and over/under the end time.
5. On the day, mark stops done, skipped, or running late, then save the actual durations for next time.
6. Export/import trip JSON for backup or sharing across devices by file.

## MVP

- Trips, ordered stops, and rough travel legs with a pure-Dart schedule engine.
- Time-budget verdict: on track, tight, or overruns the end time, with the overflow shown per stop.
- Fixed anchors, per-stop dwell time, and simple opening-hour/day-of-week notes.
- Alternative plan compare on one screen (no per-stop diff required in MVP).
- Local saved places and recents; local per-leg travel-time memory (user-entered, not map APIs).
- JSON export/import of trips and places.
- Adaptive UI (UX strategy A) for phone, tablet, and Windows: touch plus full keyboard control on desktop.
- Per-platform visual and behavioral checks.

## Non-goals

- No routes, turn-by-turn, traffic, transit schedules, or map tiles.
- No real-time location access or background tracking.
- No accounts, cloud sync, collaborative editing, or push services.
- No bookings, payments, or ticketing integrations.
- No restaurant/menu or ticket price APIs in MVP. Costs are user notes only.
- No full multi-day itinerary product — anything past one day is out of scope.
- No navigation, geofencing, or location access; the app performs no network requests.
- Day Raft is a planning aid, not a scheduling or time-management system and makes no medical, dietary, or accessibility claims.
- No advertising, analytics, tracking, accounts, cloud sync, or telemetry.

## Privacy and data

Day Raft is local-first and performs no network requests. Trips, stops, places, travel-time memories, notes, settings, and exports remain on device. The app does not request location permission, background access, camera access, microphone access, contacts, calendar, or notifications. Users can delete a trip or wipe all app data at any time.

Travel legs are user-entered approximations. They do not come from map services and Day Raft makes no claim that they reflect live traffic, transit schedules, or walking conditions. Opening-hour notes are user-maintained; the app never validates them online.

## Architecture

```text
lib/
  domain/           trip, stop, leg, anchors, schedule engine, verdict, time helpers
  data/             JSON repository, migration, atomic write, export/import
  adaptive/         platform-adaptive widgets and layout (UX strategy A)
  ui/               trips, plan editor, timeline, actuals, settings
test/               pure unit tests, widget and adaptive layout tests
AppStore/           listing copy and app icon
toolchain.json      pinned framework and app identifier contract
```

The schedule engine is pure Dart: ordered stops, leg durations, dwell times, anchors, and a start time go in; arrival/departure times, slack, and the over/under verdict come out. Repository and UI layers stay thin.

## Technology

- Flutter stable 3.47.7 / Dart 3.13.5; Windows, Android, iOS.
- Material 3 on Android, Cupertino on iOS, Fluent (`fluent_ui`) on Windows, behind an adaptive widget layer.
- `sqflite` for local structured storage; `share_plus` and file pickers for export/import.
- `flutter_test`, golden tests, and Dart unit tests.

## Identifier

`com.infinityball.dayraft` is used for the Android application ID, iOS bundle identifier, and Windows/MSIX identity. App Store Connect registration status: see `toolchain.json`; if registration failed, see Manual setup below.

## App Store Connect secrets

The repository has four GitHub Actions secrets configured (names only): `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `ASC_TEAM_ID`. They enable later TestFlight/App Store packaging. Store submission is an opt-in milestone; the MVP release is a zipped Windows build on a `v*` GitHub release. No secret values are ever committed, logged, printed, or placed in issues or reports.

## Manual setup required

None at scaffold time.

## Status

Scaffold only. No runnable application yet.

Next milestones:

1. Flutter skeleton (Windows + Android + iOS), CI, schedule engine, local persistence.
2. Trip list and plan editor.
3. Timeline view and time-budget verdicts.
4. Actuals log, alternative-plan compare, saved places and travel-time memory.
5. Adaptive UI polish and per-platform golden tests.
6. Import/export, privacy review, Windows release workflow.

## Development quickstart

Requires Flutter stable `3.47.7` (Dart `3.13.5`).

```bash
flutter pub get
flutter test
flutter run -d windows
flutter build windows --release
```

Android and iOS use `com.infinityball.dayraft`. Store submission is not required for MVP.

## License

MIT
