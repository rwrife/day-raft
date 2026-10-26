import 'dart:io';

import 'package:day_raft/domain/schedule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const engine = ScheduleEngine();
  DateTime at(int day, int hour, [int minute = 0]) =>
      DateTime(2026, 10, day, hour, minute);

  test('empty trip and one stop need no travel leg', () {
    final empty = engine.calculate(
      Trip(start: at(21, 9), end: at(21, 17), stops: []),
    );
    expect(empty.stops, isEmpty);
    expect(empty.slackMinutes, 480);
    expect(empty.verdict, Verdict.onTrack);
    final one = engine.calculate(
      Trip(
        start: at(21, 9),
        end: at(21, 10),
        stops: [const Stop(name: 'Museum', dwellMinutes: 60)],
      ),
    );
    expect(one.stops.single.arrival, at(21, 9));
    expect(one.verdict, Verdict.tight);
    expect(one.overrunMinutes, 0);
  });

  test('overnight schedule records per-stop slack and overrun', () {
    final result = engine.calculate(
      Trip(
        start: at(21, 23),
        end: at(22, 1),
        stops: [
          const Stop(name: 'Dinner', dwellMinutes: 60),
          const Stop(
            name: 'Walk',
            dwellMinutes: 45,
            leg: Leg(mode: TravelMode.walk, minutes: 30),
          ),
        ],
      ),
    );
    expect(result.stops.last.arrival, at(22, 0, 30));
    expect(result.end, at(22, 1, 15));
    expect(result.stops.last.slackMinutes, -15);
    expect(result.verdict, Verdict.overrun);
    expect(result.overrunMinutes, 15);
  });

  test('missed anchor does not rewind time; early arrival waits', () {
    final result = engine.calculate(
      Trip(
        start: at(21, 9),
        end: at(21, 12),
        stops: [
          Stop(name: 'Show', dwellMinutes: 30, anchor: at(21, 10)),
          Stop(
            name: 'Train',
            dwellMinutes: 20,
            anchor: at(21, 10, 45),
            leg: const Leg(mode: TravelMode.transit, minutes: 30),
          ),
        ],
      ),
    );
    expect(result.stops.first.arrival, at(21, 10));
    expect(result.stops.last.arrival, at(21, 11));
    expect(result.conflicts.map((c) => c.kind), [ConflictKind.missedAnchor]);
    expect(result.conflicts.single.stopIndex, 1);
  });

  test('user opening notes flag weekday closure and time outside window', () {
    final result = engine.calculate(
      Trip(
        start: at(21, 9),
        end: at(21, 12),
        stops: [
          const Stop(
            name: 'Gallery',
            dwellMinutes: 60,
            opening: OpeningNote(
              opensAt: 10 * 60,
              closesAt: 11 * 60,
              closedWeekdays: {DateTime.wednesday},
            ),
          ),
        ],
      ),
    );
    expect(result.conflicts.map((c) => c.kind), [
      ConflictKind.closedDay,
      ConflictKind.outsideOpeningHours,
    ]);
  });

  test('opening at boundary valid; departure after close conflicts', () {
    final trip = Trip(
      start: at(21, 10),
      end: at(21, 12),
      stops: [
        const Stop(
          name: 'Gallery',
          dwellMinutes: 60,
          opening: OpeningNote(opensAt: 600, closesAt: 660),
        ),
      ],
    );
    expect(engine.calculate(trip).conflicts, isEmpty);
    expect(
      engine
          .calculate(
            Trip(
              start: trip.start,
              end: trip.end,
              stops: [
                const Stop(
                  name: 'Gallery',
                  dwellMinutes: 61,
                  opening: OpeningNote(opensAt: 600, closesAt: 660),
                ),
              ],
            ),
          )
          .conflicts
          .single
          .kind,
      ConflictKind.outsideOpeningHours,
    );
  });

  test('day-of actual recalculates remaining day without mutating estimate', () {
    final trip = Trip(
      start: at(21, 9),
      end: at(21, 13),
      stops: [
        Stop(
          name: 'Breakfast',
          dwellMinutes: 60,
          actual: StopActual(
            status: StopStatus.done,
            arrival: at(21, 9, 30),
            departure: at(21, 10, 45),
          ),
        ),
        const Stop(
          name: 'Museum',
          dwellMinutes: 60,
          leg: Leg(mode: TravelMode.walk, minutes: 15),
        ),
      ],
    );
    final tl = planTimeline(trip);
    // Original estimate: 9:00 -> 10:00, 10:15 -> 11:15, ends 11:15, slack 105m.
    expect(tl.estimate.stops[0].departure, at(21, 10));
    expect(tl.estimate.stops[1].arrival, at(21, 10, 15));
    expect(tl.estimate.stops[1].departure, at(21, 11, 15));
    expect(tl.estimate.slackMinutes, 105);
    expect(tl.estimate.verdict, Verdict.onTrack);

    // Remaining with actuals: stop 1 finished 10:45. Stop 2 starts 10:45 + 15m leg = 11:00.
    expect(tl.remaining.stops[0].departure, at(21, 10, 45));
    expect(tl.remaining.stops[1].arrival, at(21, 11));
    expect(tl.remaining.stops[1].departure, at(21, 12));
    expect(tl.remaining.slackMinutes, 60);
    expect(tl.remaining.verdict, Verdict.onTrack);
  });

  test('skipped stop uses recorded departure time with no arrival', () {
    final trip = Trip(
      start: at(21, 9),
      end: at(21, 12),
      stops: [
        Stop(
          name: 'Crowded cafe',
          dwellMinutes: 45,
          actual: StopActual(
            status: StopStatus.skipped,
            departure: at(21, 9, 10),
          ),
        ),
        const Stop(
          name: 'Park',
          dwellMinutes: 60,
          leg: Leg(mode: TravelMode.walk, minutes: 20),
        ),
      ],
    );
    final tl = planTimeline(trip);
    expect(tl.remaining.stops[0].departure, at(21, 9, 10));
    expect(tl.remaining.stops[1].arrival, at(21, 9, 30));
    expect(tl.remaining.stops[1].departure, at(21, 10, 30));
  });

  test('late actual flags fixed anchor at risk or missed', () {
    final trip = Trip(
      start: at(21, 9),
      end: at(21, 13),
      stops: [
        Stop(
          name: 'Stop 1',
          dwellMinutes: 30,
          actual: StopActual(
            status: StopStatus.late,
            arrival: at(21, 9, 15),
            departure: at(21, 11),
          ),
        ),
        Stop(
          name: 'Show',
          dwellMinutes: 60,
          anchor: at(21, 10, 30),
          leg: const Leg(mode: TravelMode.transit, minutes: 15),
        ),
      ],
    );
    final tl = planTimeline(trip);
    // Show was reachable in estimate (9:00 + 30m = 9:30 + 15m = 9:45 < 10:30 anchor).
    expect(tl.estimate.conflicts, isEmpty);
    // With late actual, arrival at show is 11:00 + 15m = 11:15 > 10:30 anchor.
    expect(tl.remaining.conflicts.map((c) => c.kind), [
      ConflictKind.missedAnchor,
    ]);
  });

  test('sub-minute overrun still reports one minute', () {
    final result = engine.calculate(
      Trip(
        start: at(21, 9, 0).add(const Duration(seconds: 1)),
        end: at(21, 10),
        stops: [const Stop(name: 'Park', dwellMinutes: 60)],
      ),
    );
    expect(result.verdict, Verdict.overrun);
    expect(result.overrunMinutes, 1);
    expect(result.stops.single.slackMinutes, -1);
  });

  test('opening note does not extend across midnight', () {
    final result = engine.calculate(
      Trip(
        start: at(21, 23, 30),
        end: at(22, 1),
        stops: [
          const Stop(
            name: 'Late venue',
            dwellMinutes: 60,
            opening: OpeningNote(opensAt: 0, closesAt: 1440),
          ),
        ],
      ),
    );
    expect(result.conflicts.single.kind, ConflictKind.outsideOpeningHours);
  });

  test('editing duration recalculates without changing previous result', () {
    Trip trip(int dwell) => Trip(
      start: at(21, 9),
      end: at(21, 10),
      stops: [Stop(name: 'Park', dwellMinutes: dwell)],
    );
    final before = engine.calculate(trip(20));
    final after = engine.calculate(trip(70));
    expect(before.verdict, Verdict.onTrack);
    expect(after.overrunMinutes, 10);
    expect(before.end, at(21, 9, 20));
  });

  test(
    'invalid trust-boundary inputs fail rather than yield misleading time',
    () {
      void invalid(Trip trip) =>
          expect(() => engine.calculate(trip), throwsArgumentError);
      invalid(Trip(start: at(21, 10), end: at(21, 9), stops: []));
      invalid(
        Trip(
          start: at(21, 9),
          end: at(21, 10),
          stops: [const Stop(name: '', dwellMinutes: 1)],
        ),
      );
      invalid(
        Trip(
          start: at(21, 9),
          end: at(21, 10),
          stops: [const Stop(name: 'X', dwellMinutes: 0)],
        ),
      );
      invalid(
        Trip(
          start: at(21, 9),
          end: at(21, 10),
          stops: [
            const Stop(
              name: 'X',
              dwellMinutes: 1,
              leg: Leg(mode: TravelMode.car, minutes: -1),
            ),
          ],
        ),
      );
      invalid(
        Trip(
          start: at(21, 9),
          end: at(21, 10),
          stops: [Stop(name: 'X', dwellMinutes: 1, anchor: at(21, 8))],
        ),
      );
      invalid(
        Trip(
          start: at(21, 9),
          end: at(21, 10),
          stops: [
            const Stop(
              name: 'X',
              dwellMinutes: 1,
              opening: OpeningNote(opensAt: 900),
            ),
          ],
        ),
      );
    },
  );

  test('DST boundary uses elapsed minutes, not wall-clock subtraction', () {
    // UTC offset changes cannot be manufactured on UTC or the CI runner's
    // unspecified local timezone. The same instant represented at -05:00 and
    // -04:00 must have a 30-minute elapsed budget despite a 90-minute clock gap.
    final start = DateTime.parse('2026-03-08T01:30:00-05:00');
    final end = DateTime.parse('2026-03-08T03:00:00-04:00');
    final result = engine.calculate(
      Trip(
        start: start,
        end: end,
        stops: [const Stop(name: 'Ride', dwellMinutes: 30)],
      ),
    );
    expect(result.slackMinutes, 0);
    expect(result.end.isAtSameMomentAs(end), isTrue);
  });

  test('domain files import no Flutter packages', () {
    // PLAN gate: lib/domain stays pure Dart (this test file may use flutter_test).
    for (final file in Directory(
      'lib/domain',
    ).listSync(recursive: true).whereType<File>()) {
      for (final line in file.readAsStringSync().split('\n')) {
        final uri = RegExp(
          r'''^\s*import\s+['"]([^'"]+)['"]''',
        ).firstMatch(line)?.group(1);
        if (uri == null) continue;
        expect(uri, isNot(startsWith('package:flutter')), reason: file.path);
        expect(uri, isNot(startsWith('dart:ui')), reason: file.path);
      }
    }
  });
}
