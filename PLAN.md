# Day Raft — PLAN

## Scope

Day Raft plans a single day out: an ordered list of stops with dwell times, rough user-entered travel legs, fixed anchors, and opening-hour notes, checked against a start/end window by a pure-Dart schedule engine. It runs on phone, tablet, and Windows (Windows is the primary CI/release target). Everything is stored on device; the app performs no network requests.

Out of scope for MVP: maps/routing/traffic/transit data, live location, accounts, sync, collaboration, bookings, multi-week itineraries.

## Architecture

```
lib/
  domain/        # pure Dart: Trip, Stop, Leg, Anchor, ScheduleEngine, Verdict
  data/          # sqflite repository, JSON export/import, atomic writes, migrations
  adaptive/      # AdaptiveScaffold, AdaptiveButton, AdaptiveList, AdaptiveDialog
                 # (Cupertino on iOS, Material 3 on Android, fluent_ui on Windows)
  ui/            # trips list, plan editor, timeline, day-of actuals, settings
AppStore/        # description.txt + icon.png
toolchain.json   # pinned toolchain + identifier contract
```

- `ScheduleEngine` (pure): inputs = start time, ordered stops (dwell minutes, optional open/close window, optional fixed anchor), legs (mode + rough minutes); outputs = arrival/departure per stop, cumulative slack, `Verdict { onTrack | tight | overrun(minutes) }`, and per-anchor feasibility. No Flutter imports in `lib/domain` — enforced by a test that scans imports.
- Persistence: sqflite database in app documents; export/import is a versioned JSON document (`schemaVersion` field, forward-migrating reader). Atomic write via temp file + rename.
- Travel-time memory: user-entered minutes per (place A, place B, mode) triple, suggested on repeat legs. Never derived from network sources.

## Technology choices

- **Flutter stable 3.47.7 (Dart 3.13.5)** — one codebase for Windows, Android, iOS incl. tablets, per the fleet build shape. React Native, Expo, Kotlin Multiplatform, .NET MAUI, Unity, and native Swift/Xcode-only projects are not used.
- **UX strategy A — platform-native adaptive.** Rationale: Day Raft is a utility/productivity app; users expect the host OS's idioms (iOS navigation + swipe-back, Android back handling + Material 3, Windows command bar + keyboard shortcuts + Fluent look). All screens render through an adaptive-widget layer (`AdaptiveScaffold`, `AdaptiveButton`, `AdaptiveDialog`, `AdaptiveList`) so no Material look ships on iOS, no Cupertino look ships on Android, and no phone-style UI ships on Windows. Golden tests per `TargetPlatform` (iOS, android, windows) gate this.
- **sqflite** for local storage (relational trips/stops/legs fit naturally, offline by construction); JSON export/import for portability.
- **fluent_ui** on Windows for title bar/command bar/NavigationView behavior; `flutter_platform_widgets` or in-repo equivalent behind the adaptive layer.

## Identifiers

- Android applicationId, iOS bundle identifier, MSIX identity root: `com.infinityball.dayraft` (prefix `com.infinityball.` is mandatory fleet-wide; never introduce another prefix).
- App Store Connect bundle ID registration is recorded in `toolchain.json` and README.
- iOS/Android packaging uses the four repo secrets by name only: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `ASC_TEAM_ID`. Never log or commit values.

## Milestones (dependency order)

1. **Skeleton + CI** — `flutter create` with windows/android/ios enabled, pinned `toolchain.json`, CI: `windows-latest` (format, analyze, test, `flutter build windows --release`) + Android debug APK lane; identifiers set to `com.infinityball.dayraft`.
2. **Domain + persistence** — `ScheduleEngine` + repository with unit tests (pure Dart, no UI).
3. **Core workflow** — trip list, plan editor, timeline with verdict; keyboard-complete on Windows.
4. **Art/branding** — `AppStore/icon.png` (generated via spark-media OpenAI Images, already committed) wired into Windows `.ico` runner resource, Android launcher icons, iOS asset catalog via flutter_launcher_icons; `AppStore/description.txt` kept accurate.
5. **Adaptive UI pass** — adaptive-widget layer everywhere + per-platform golden tests + accessibility pass.
6. **Day-of actuals + travel-time memory + plan compare**.
7. **Export/import + privacy controls**.
8. **Release** — `.github/workflows/release.yml` on `v*` tag or manual dispatch: `windows-latest`, `flutter build windows --release`, zipped portable build attached to the GitHub release. iOS TestFlight via the ASC secrets and Play upload are later opt-in milestones, not MVP.

## Testing strategy

- Pure unit tests for `ScheduleEngine` (overnight spans, anchor conflicts, zero-leg trips, opening-window edge cases) and repository migrations.
- Widget tests with `debugDefaultTargetPlatformOverride` for iOS/android/windows idioms.
- Golden/screenshot tests of key screens per `TargetPlatform` to prove platform-authentic look.
- Accessibility:Semantics labels, scalable text up to AX sizes, full-keyboard navigation test on the Windows shell, contrast checks.
- CI gates: `dart format --set-exit-if-changed`, `flutter analyze`, `flutter test`, Windows release build, Android debug APK.

## Packaging / distribution

- Primary: GitHub release on `v*` with zipped Windows portable build (MSIX later if wanted).
- Mobile: keep `flutter build apk --debug` green in CI; TestFlight via ASC secrets and Play are opt-in milestones. Store copy lives in `AppStore/description.txt` and must match implemented features before any submission.

## Privacy and data

Local-only: trips, stops, notes, saved places, travel-time memory. No network requests, no location permission, no accounts, no analytics, no tracking. Export is user-initiated JSON; import merges with explicit confirmation. Deletion of a trip or full data wipe is one action from Settings.

## Accessibility

Scalable text, screen-reader labels on all controls, high-contrast-safe palette, touch targets ≥ 44 pt, full keyboard navigation and shortcuts on Windows, VoiceOver/TalkBack pass on mobile.

## Risks

- Naive `ScheduleEngine` time math is a bug farm (midnight wraps, anchors before start, open-window edge inclusivity) — attack it with table-driven tests first.
- Adaptive layer drift: someone hardcodes a Material widget in a shared screen — golden tests per platform plus a lint/test that scans `lib/ui` for direct platform widget imports.
- Windows Fluent widget gaps: fall back to a custom-styled desktop layout that still honors Windows behaviors (command bar, shortcuts, hover, context menus) rather than shipping a phone layout.
- Scope creep toward maps: legs stay user-entered minutes; reject any dependency on routing/map SDKs in review.

## Non-goals

No maps/routing/traffic, no live location, no accounts/sync/collaboration, no bookings/payments, no multi-week planning, no ads/analytics, no network calls. Day Raft is a planning aid, not a scheduling system, and makes no medical, dietary, or accessibility-certification claims.
