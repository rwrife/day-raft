/// Local-only schedule estimates. Callers provide dated [DateTime] values.
/// Durations are elapsed minutes (including across DST changes); opening hours
/// and weekdays are wall-clock notes for the stop's arrival date. An overnight
/// day needs an explicit next-day [Trip.end], not a same-day earlier clock time.
/// Opening windows belong to one calendar day; overnight venues need separate
/// notes or a later model revision.
enum TravelMode { walk, transit, car, bike, other }

enum Verdict { onTrack, tight, overrun }

class Leg {
  const Leg({required this.mode, required this.minutes});
  final TravelMode mode;
  final int minutes;
}

class OpeningNote {
  const OpeningNote({
    this.opensAt,
    this.closesAt,
    this.closedWeekdays = const {},
  });

  /// Minutes after local midnight. Both bounds together or neither.
  final int? opensAt;
  final int? closesAt;

  /// [DateTime.monday] through [DateTime.sunday]. User-maintained, not live.
  final Set<int> closedWeekdays;
}

class Stop {
  const Stop({
    required this.name,
    required this.dwellMinutes,
    this.leg,
    this.anchor,
    this.opening,
    this.notes = '',
    this.roughCost = 0,
  });

  final String name;
  final int dwellMinutes;

  /// User-entered rough cost in whole currency units, no exchange conversion.
  final int roughCost;

  /// User-entered travel from previous position to this stop; null means zero.
  final Leg? leg;

  /// Fixed arrival deadline. Early arrival waits until this time.
  final DateTime? anchor;
  final OpeningNote? opening;
  final String notes;
}

class Trip {
  const Trip({
    required this.start,
    required this.end,
    required this.stops,
    this.title = '',
  });
  final String title;
  final DateTime start;
  final DateTime end;
  final List<Stop> stops;
}

enum ConflictKind { missedAnchor, closedDay, outsideOpeningHours }

class Conflict {
  const Conflict(this.stopIndex, this.kind);
  final int stopIndex;
  final ConflictKind kind;
}

class ScheduledStop {
  const ScheduledStop({
    required this.stop,
    required this.arrival,
    required this.departure,
    required this.slackMinutes,
  });
  final Stop stop;
  final DateTime arrival;
  final DateTime departure;

  /// Minutes remaining until end after this stop; negative means overrun.
  final int slackMinutes;
}

class Schedule {
  const Schedule({
    required this.stops,
    required this.conflicts,
    required this.end,
    required this.slackMinutes,
    required this.verdict,
  });
  final List<ScheduledStop> stops;
  final List<Conflict> conflicts;
  final DateTime end;
  final int slackMinutes;
  final Verdict verdict;
  int get overrunMinutes => slackMinutes < 0 ? -slackMinutes : 0;
}

class ScheduleEngine {
  const ScheduleEngine();

  Schedule calculate(Trip trip) {
    if (trip.start.isUtc != trip.end.isUtc || !trip.end.isAfter(trip.start)) {
      throw ArgumentError('End must be after start in the same time basis');
    }
    var current = trip.start;
    final rows = <ScheduledStop>[];
    final conflicts = <Conflict>[];
    for (var i = 0; i < trip.stops.length; i++) {
      final stop = trip.stops[i];
      if (stop.name.trim().isEmpty ||
          stop.dwellMinutes <= 0 ||
          stop.roughCost < 0 ||
          (stop.leg != null && stop.leg!.minutes < 0)) {
        throw ArgumentError(
          'Stop needs a name, positive dwell, nonnegative leg and cost',
        );
      }
      final opening = stop.opening;
      if (opening != null) {
        final opens = opening.opensAt;
        final closes = opening.closesAt;
        if ((opens == null) != (closes == null) ||
            (opens != null &&
                (opens < 0 || closes! > 1440 || opens >= closes)) ||
            opening.closedWeekdays.any((day) => day < 1 || day > 7)) {
          throw ArgumentError('Invalid opening-hour note');
        }
      }
      final anchor = stop.anchor;
      if (anchor != null &&
          (anchor.isUtc != trip.start.isUtc ||
              anchor.isBefore(trip.start) ||
              anchor.isAfter(trip.end))) {
        throw ArgumentError(
          'Anchor must be within the trip in the same time basis',
        );
      }
      current = current.add(Duration(minutes: stop.leg?.minutes ?? 0));
      if (anchor != null) {
        if (current.isAfter(anchor)) {
          conflicts.add(Conflict(i, ConflictKind.missedAnchor));
        } else {
          current = anchor;
        }
      }
      final arrival = current;
      current = current.add(Duration(minutes: stop.dwellMinutes));
      if (opening != null) {
        if (opening.closedWeekdays.contains(arrival.weekday) ||
            opening.closedWeekdays.contains(current.weekday)) {
          conflicts.add(Conflict(i, ConflictKind.closedDay));
        }
        if (opening.opensAt != null) {
          // A stop must arrive and depart on the same calendar date to stay
          // within a single-day opening window, and fit inside the bounds.
          final spansMultipleDays =
              arrival.year != current.year ||
              arrival.month != current.month ||
              arrival.day != current.day;
          if (spansMultipleDays ||
              !_withinHours(arrival, opening) ||
              !_withinHours(current, opening)) {
            conflicts.add(Conflict(i, ConflictKind.outsideOpeningHours));
          }
        }
      }
      final remainingMs = trip.end.difference(current).inMilliseconds;
      final stopSlackMinutes = remainingMs < 0
          ? -((-remainingMs + 59999) ~/ 60000)
          : remainingMs ~/ 60000;
      rows.add(
        ScheduledStop(
          stop: stop,
          arrival: arrival,
          departure: current,
          slackMinutes: stopSlackMinutes,
        ),
      );
    }
    final endRemainingMs = trip.end.difference(current).inMilliseconds;
    final slack = endRemainingMs < 0
        ? -((-endRemainingMs + 59999) ~/ 60000)
        : endRemainingMs ~/ 60000;
    final isOverrun = current.isAfter(trip.end);
    return Schedule(
      stops: List.unmodifiable(rows),
      conflicts: List.unmodifiable(conflicts),
      end: current,
      slackMinutes: slack,
      verdict: isOverrun
          ? Verdict.overrun
          : slack <= 15
          ? Verdict.tight
          : Verdict.onTrack,
    );
  }

  bool _withinHours(DateTime time, OpeningNote note) {
    final microsecondOfDay =
        ((time.hour * 60 + time.minute) * 60 + time.second) * 1000000 +
        time.millisecond * 1000 +
        time.microsecond;
    // Closing time is inclusive. A fractional second after closing conflicts.
    return microsecondOfDay >= note.opensAt! * 60000000 &&
        microsecondOfDay <= note.closesAt! * 60000000;
  }
}
