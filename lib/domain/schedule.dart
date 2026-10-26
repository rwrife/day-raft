/// Local-only schedule estimates. Callers provide dated [DateTime] values.
/// Durations are elapsed minutes (including across DST changes); opening hours
/// and weekdays are wall-clock notes for the stop's arrival date. An overnight
/// day needs an explicit next-day [Trip.end], not a same-day earlier clock time.
/// Opening windows belong to one calendar day; overnight venues need separate
/// notes or a later model revision.
enum TravelMode { walk, transit, car, bike, other }

enum Verdict { onTrack, tight, overrun }

enum StopStatus { done, skipped, late }

/// User-entered day-of timestamp, not location-derived. Skipped stops use
/// [departure] as time skip was recorded and have no arrival.
class StopActual {
  const StopActual({
    required this.status,
    required this.departure,
    this.arrival,
  });
  final StopStatus status;
  final DateTime departure;
  final DateTime? arrival;
}

class Timeline {
  const Timeline({required this.estimate, required this.remaining});
  final Schedule estimate;
  final Schedule remaining;
}

Timeline planTimeline(Trip trip) => Timeline(
  estimate: const ScheduleEngine().calculate(trip),
  remaining: const ScheduleEngine().calculate(trip, useActuals: true),
);

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
    this.actual,
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
  final StopActual? actual;
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

  Schedule calculate(Trip trip, {bool useActuals = false}) {
    if (trip.start.isUtc != trip.end.isUtc || !trip.end.isAfter(trip.start)) {
      throw ArgumentError('End must be after start in the same time basis');
    }
    var current = trip.start;
    final rows = <ScheduledStop>[];
    final conflicts = <Conflict>[];
    DateTime? lastActual;
    var seenPending = false;
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
      final actual = stop.actual;
      if (actual != null) {
        if (seenPending) {
          throw ArgumentError('Cannot record actuals after a pending stop');
        }
        if (actual.departure.isUtc != trip.start.isUtc ||
            actual.departure.isBefore(trip.start) ||
            (actual.arrival != null &&
                (actual.arrival!.isUtc != trip.start.isUtc ||
                    actual.arrival!.isBefore(trip.start) ||
                    actual.arrival!.isAfter(actual.departure))) ||
            (actual.status == StopStatus.skipped) != (actual.arrival == null) ||
            (lastActual != null &&
                (actual.arrival ?? actual.departure).isBefore(lastActual))) {
          throw ArgumentError('Invalid or out-of-order stop actual');
        }
        lastActual = actual.departure;
      } else {
        seenPending = true;
      }
      if (useActuals && actual != null) {
        if (anchor != null &&
            actual.status != StopStatus.skipped &&
            (actual.arrival ?? actual.departure).isAfter(anchor)) {
          conflicts.add(Conflict(i, ConflictKind.missedAnchor));
        }
        final arrival = actual.arrival ?? actual.departure;
        current = actual.departure;
        if (actual.status != StopStatus.skipped && opening != null) {
          _openingConflicts(opening, arrival, current, i, conflicts);
        }
        rows.add(
          ScheduledStop(
            stop: stop,
            arrival: arrival,
            departure: current,
            slackMinutes: _slack(trip.end, current),
          ),
        );
        continue;
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
        _openingConflicts(opening, arrival, current, i, conflicts);
      }
      rows.add(
        ScheduledStop(
          stop: stop,
          arrival: arrival,
          departure: current,
          slackMinutes: _slack(trip.end, current),
        ),
      );
    }
    final slack = _slack(trip.end, current);
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

  static int _slack(DateTime end, DateTime current) {
    final remainingMs = end.difference(current).inMilliseconds;
    return remainingMs < 0
        ? -((-remainingMs + 59999) ~/ 60000)
        : remainingMs ~/ 60000;
  }

  void _openingConflicts(
    OpeningNote opening,
    DateTime arrival,
    DateTime departure,
    int index,
    List<Conflict> conflicts,
  ) {
    if (opening.closedWeekdays.contains(arrival.weekday) ||
        opening.closedWeekdays.contains(departure.weekday)) {
      conflicts.add(Conflict(index, ConflictKind.closedDay));
    }
    if (opening.opensAt != null) {
      final spansMultipleDays =
          arrival.year != departure.year ||
          arrival.month != departure.month ||
          arrival.day != departure.day;
      if (spansMultipleDays ||
          !_withinHours(arrival, opening) ||
          !_withinHours(departure, opening)) {
        conflicts.add(Conflict(index, ConflictKind.outsideOpeningHours));
      }
    }
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
