import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'data/backup_screen.dart';
import 'data/trip_store.dart';
import 'domain/schedule.dart';
import 'main.dart' show AdaptiveShell;

bool get _ios => defaultTargetPlatform == TargetPlatform.iOS;

Route<void> _page(Widget child) => _ios
    ? CupertinoPageRoute<void>(builder: (_) => child)
    : MaterialPageRoute<void>(builder: (_) => child);

Widget _button(String label, VoidCallback? action, {Key? key}) => _ios
    ? CupertinoButton(key: key, onPressed: action, child: Text(label))
    : TextButton(key: key, onPressed: action, child: Text(label));

Widget _field(
  String label,
  TextEditingController controller, {
  Key? key,
  String? hint,
  TextInputType? keyboard,
  int maxLines = 1,
}) {
  final input = _ios
      ? CupertinoTextField(
          key: key,
          controller: controller,
          placeholder: hint,
          keyboardType: keyboard,
          maxLines: maxLines,
          maxLength: 500,
          padding: const EdgeInsets.all(12),
        )
      : TextField(
          key: key,
          controller: controller,
          decoration: InputDecoration(labelText: label, hintText: hint),
          keyboardType: keyboard,
          maxLines: maxLines,
          maxLength: 500,
        );
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: _ios
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Text(label), input],
          )
        : input,
  );
}

// No UTC conversion: user enters wall-clock times for this offline day.
DateTime _date(String text) {
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2})$',
  ).firstMatch(text.trim());
  if (match == null) throw const FormatException('Use yyyy-MM-dd HH:mm');
  final parts = [for (var i = 1; i <= 5; i++) int.parse(match.group(i)!)];
  final date = DateTime(parts[0], parts[1], parts[2], parts[3], parts[4]);
  if (date.year != parts[0] ||
      date.month != parts[1] ||
      date.day != parts[2] ||
      date.hour != parts[3] ||
      date.minute != parts[4]) {
    throw const FormatException('Invalid local date or time');
  }
  return date;
}

String _stamp(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
    '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

int _minutes(String text, String label, {bool positive = false}) {
  final value = int.tryParse(text.trim());
  if (value == null || value < (positive ? 1 : 0) || value > 100000) {
    throw FormatException(
      '$label must be ${positive ? 'positive' : 'nonnegative'} (max 100000)',
    );
  }
  return value;
}

class TripScreen extends StatefulWidget {
  const TripScreen({super.key, this.store});
  final TripStore? store;

  @override
  State<TripScreen> createState() => _TripScreenState();
}

class _TripScreenState extends State<TripScreen> {
  TripStore? store;
  TripSnapshot? snapshot;
  String? error;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.store != null) {
      store = widget.store;
      _refresh();
    } else {
      TripStore.open()
          .then((value) {
            if (!mounted) {
              value.close();
              return;
            }
            store = value;
            _refresh();
          })
          .catchError((Object e) {
            if (mounted) setState(() => error = '$e');
          });
    }
  }

  @override
  void dispose() {
    if (widget.store == null) store?.close();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final next = await store!.snapshot();
      if (mounted) {
        setState(() {
          snapshot = next;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> _edit(String? id, Trip? trip) async {
    if (store == null || busy) return;
    await Navigator.push(
      context,
      _page(TripEditor(store: store!, id: id, trip: trip)),
    );
    if (mounted) await _refresh();
  }

  Future<void> _delete(String id) async {
    if (busy) return;
    final confirmed = _ios
        ? await showCupertinoDialog<bool>(
            context: context,
            builder: (context) => CupertinoAlertDialog(
              title: const Text('Delete trip?'),
              actions: [
                CupertinoDialogAction(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                CupertinoDialogAction(
                  isDestructiveAction: true,
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Delete'),
                ),
              ],
            ),
          )
        : await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Delete trip?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Delete'),
                ),
              ],
            ),
          );
    if (confirmed != true || !mounted) return;
    setState(() => busy = true);
    try {
      await store!.deleteTrip(id);
      await _refresh();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AdaptiveShell(
    title: 'Day Raft',
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Offline plans. Travel legs and opening hours are your estimates, not live data.',
            ),
            Wrap(
              spacing: 12,
              children: [
                _button(
                  'New trip',
                  store == null || busy ? null : () => _edit(null, null),
                  key: const Key('new-trip'),
                ),
                _button('Local backups', () async {
                  await Navigator.push(context, _page(const BackupScreen()));
                  if (mounted && store != null) await _refresh();
                }),
              ],
            ),
            if (store == null && error == null)
              const Text('Opening local trips…'),
            if (error != null)
              Text('Error: $error', key: const Key('trip-error')),
            if (snapshot != null && snapshot!.trips.isEmpty)
              const Text('No trips yet. Create one to plan your day.'),
            for (final entry
                in snapshot?.trips.entries ?? <MapEntry<String, Trip>>[])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Semantics(
                  label:
                      'Trip ${entry.value.title.isEmpty ? 'Untitled trip' : entry.value.title}',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.value.title.isEmpty
                            ? 'Untitled trip'
                            : entry.value.title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${_stamp(entry.value.start)} · ${entry.value.stops.length} stops',
                      ),
                      _timeline(entry.value),
                      Wrap(
                        children: [
                          _button(
                            'Edit',
                            () => _edit(entry.key, entry.value),
                            key: Key('edit-${entry.key}'),
                          ),
                          _button('Delete', () => _delete(entry.key)),
                        ],
                      ),
                      const Divider(),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );

  static String _conflictLabel(Conflict conflict, bool isEstimated) {
    if (conflict.kind == ConflictKind.missedAnchor) {
      return isEstimated ? 'anchor at risk' : 'missed anchor';
    }
    return conflict.kind.name;
  }

  Widget _timeline(Trip trip) {
    Timeline tl;
    try {
      tl = planTimeline(trip);
    } catch (_) {
      return const SizedBox.shrink();
    }
    final hasActuals = trip.stops.any((s) => s.actual != null);
    final verdict = hasActuals ? tl.remaining.verdict : tl.estimate.verdict;
    final slack = hasActuals
        ? tl.remaining.slackMinutes
        : tl.estimate.slackMinutes;
    final verdictLabel = switch (verdict) {
      Verdict.onTrack => 'On track (slack: ${slack}m)',
      Verdict.tight => 'Tight (slack: ${slack}m)',
      Verdict.overrun => 'Overrun (${-slack}m late)',
    };
    final color = switch (verdict) {
      Verdict.onTrack => const Color(0xFF2E7D32),
      Verdict.tight => const Color(0xFFE65100),
      Verdict.overrun => const Color(0xFFC62828),
    };
    final conflicts = hasActuals
        ? tl.remaining.conflicts
        : tl.estimate.conflicts;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            verdictLabel,
            key: const Key('timeline-verdict'),
            style: TextStyle(fontWeight: FontWeight.bold, color: color),
          ),
          for (var i = 0; i < trip.stops.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                '${i + 1}. ${trip.stops[i].name} · '
                '${hasActuals && trip.stops[i].actual != null ? '${trip.stops[i].actual!.status.name} · ' : ''}'
                '${_stamp(tl.remaining.stops[i].arrival)} to ${_stamp(tl.remaining.stops[i].departure)} · '
                'slack ${tl.remaining.stops[i].slackMinutes}m'
                '${trip.stops[i].anchor == null ? '' : ' · anchor ${_stamp(trip.stops[i].anchor!)}'}'
                '${conflicts.where((c) => c.stopIndex == i).isEmpty ? '' : ' · ${conflicts.where((c) => c.stopIndex == i).map((c) => _conflictLabel(c, trip.stops[i].actual == null)).join(', ')}'}',
                key: Key('timeline-stop-$i'),
              ),
            ),
          if (conflicts.isNotEmpty)
            Text(
              '${conflicts.length} conflict(s) · user-maintained opening notes and fixed anchors',
              style: const TextStyle(color: Color(0xFFC62828)),
            ),
          if (hasActuals)
            Text(
              'Original estimate: ${tl.estimate.verdict.name} · slack ${tl.estimate.slackMinutes}m',
            ),
        ],
      ),
    );
  }
}

class _StopDraft {
  _StopDraft([Stop? stop])
    : name = TextEditingController(text: stop?.name ?? ''),
      dwell = TextEditingController(text: '${stop?.dwellMinutes ?? 30}'),
      cost = TextEditingController(text: '${stop?.roughCost ?? 0}'),
      notes = TextEditingController(text: stop?.notes ?? ''),
      mode = stop?.leg?.mode ?? TravelMode.walk,
      travel = TextEditingController(text: '${stop?.leg?.minutes ?? 0}'),
      anchor = TextEditingController(
        text: stop?.anchor == null ? '' : _stamp(stop!.anchor!),
      ),
      opens = TextEditingController(
        text: stop?.opening?.opensAt == null
            ? ''
            : _clock(stop!.opening!.opensAt!),
      ),
      closes = TextEditingController(
        text: stop?.opening?.closesAt == null
            ? ''
            : _clock(stop!.opening!.closesAt!),
      ),
      closed = TextEditingController(
        text: stop?.opening == null
            ? ''
            : ([...stop!.opening!.closedWeekdays]..sort()).join(','),
      ),
      actualStatus = stop?.actual?.status,
      actualArrival = TextEditingController(
        text: stop?.actual?.arrival == null
            ? ''
            : _stamp(stop!.actual!.arrival!),
      ),
      actualDeparture = TextEditingController(
        text: stop?.actual == null ? '' : _stamp(stop!.actual!.departure),
      );
  final TextEditingController name,
      dwell,
      cost,
      notes,
      travel,
      anchor,
      opens,
      closes,
      closed,
      actualArrival,
      actualDeparture;
  TravelMode mode;
  StopStatus? actualStatus;

  static String _clock(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
  static int? _time(String input) {
    if (input.trim().isEmpty) return null;
    final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(input.trim());
    if (match == null) throw const FormatException('Opening hours: use HH:mm');
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    if (hour > 24 || minute > 59 || (hour == 24 && minute != 0)) {
      throw const FormatException('Invalid opening hour');
    }
    return hour * 60 + minute;
  }

  Stop parse() {
    final weekdays = <int>{};
    if (closed.text.trim().isNotEmpty) {
      for (final part in closed.text.split(',')) {
        final day = int.tryParse(part.trim());
        if (day == null || day < 1 || day > 7) {
          throw const FormatException(
            'Closed weekdays: use comma-separated 1–7 (Monday=1)',
          );
        }
        weekdays.add(day);
      }
    }
    final open = _time(opens.text);
    final close = _time(closes.text);
    if ((open == null) != (close == null)) {
      throw const FormatException('Enter both opening and closing time');
    }
    if (name.text.trim().isEmpty) {
      throw const FormatException('Stop name required');
    }
    StopActual? actual;
    if (actualStatus != null) {
      final dep = actualDeparture.text.trim().isEmpty
          ? null
          : _date(actualDeparture.text);
      if (dep == null) {
        throw const FormatException('Actual departure required when marked');
      }
      final arr = actualArrival.text.trim().isEmpty
          ? null
          : _date(actualArrival.text);
      if (actualStatus == StopStatus.skipped && arr != null) {
        throw const FormatException('Skipped stop has no arrival time');
      }
      if (actualStatus != StopStatus.skipped && arr == null) {
        throw const FormatException(
          'Arrival time required for completed/late stop',
        );
      }
      actual = StopActual(status: actualStatus!, departure: dep, arrival: arr);
    }
    return Stop(
      name: name.text.trim(),
      dwellMinutes: _minutes(dwell.text, 'Dwell', positive: true),
      roughCost: _minutes(cost.text, 'Rough cost'),
      notes: notes.text,
      actual: actual,
      leg: Leg(mode: mode, minutes: _minutes(travel.text, 'Travel')),
      anchor: anchor.text.trim().isEmpty ? null : _date(anchor.text),
      opening: open == null && weekdays.isEmpty
          ? null
          : OpeningNote(
              opensAt: open,
              closesAt: close,
              closedWeekdays: weekdays,
            ),
    );
  }

  void dispose() {
    for (final controller in [
      name,
      dwell,
      cost,
      notes,
      travel,
      anchor,
      opens,
      closes,
      closed,
      actualArrival,
      actualDeparture,
    ]) {
      controller.dispose();
    }
  }
}

class TripEditor extends StatefulWidget {
  const TripEditor({super.key, required this.store, this.id, this.trip});
  final TripStore store;
  final String? id;
  final Trip? trip;
  @override
  State<TripEditor> createState() => _TripEditorState();
}

class _TripEditorState extends State<TripEditor> {
  late final TextEditingController title, start, end;
  late final List<_StopDraft> stops;
  String? error;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    title = TextEditingController(text: widget.trip?.title ?? '');
    start = TextEditingController(
      text: _stamp(
        widget.trip?.start ?? DateTime(now.year, now.month, now.day, 9),
      ),
    );
    end = TextEditingController(
      text: _stamp(
        widget.trip?.end ?? DateTime(now.year, now.month, now.day, 18),
      ),
    );
    stops = [
      for (final stop in widget.trip?.stops ?? <Stop>[]) _StopDraft(stop),
    ];
  }

  @override
  void dispose() {
    title.dispose();
    start.dispose();
    end.dispose();
    for (final stop in stops) {
      stop.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      if (title.text.trim().isEmpty) {
        throw const FormatException('Trip title required');
      }
      final trip = Trip(
        title: title.text.trim(),
        start: _date(start.text),
        end: _date(end.text),
        stops: [for (final stop in stops) stop.parse()],
      );
      const ScheduleEngine().calculate(trip);
      await widget.store.saveTrip(
        widget.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        trip,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AdaptiveShell(
    title: widget.trip == null ? 'New trip' : 'Edit trip',
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _field('Trip title', title, key: const Key('trip-title')),
            _field(
              'Start (yyyy-MM-dd HH:mm)',
              start,
              key: const Key('trip-start'),
              hint: '2026-10-25 09:00',
            ),
            _field(
              'End (yyyy-MM-dd HH:mm)',
              end,
              key: const Key('trip-end'),
              hint: '2026-10-25 18:00',
            ),
            const Text(
              'Local clock times. For overnight trips, enter next-day end date.',
            ),
            for (var i = 0; i < stops.length; i++) _stopFields(i),
            _button(
              'Add stop',
              stops.length >= 1000
                  ? null
                  : () => setState(() => stops.add(_StopDraft())),
              key: const Key('add-stop'),
            ),
            if (error != null)
              Text('Error: $error', key: const Key('editor-error')),
            Wrap(
              children: [
                _button(
                  'Save trip',
                  saving ? null : _save,
                  key: const Key('save-trip'),
                ),
                _button('Cancel', () => Navigator.pop(context)),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  Widget _stopFields(int index) {
    final stop = stops[index];
    return Semantics(
      label: 'Stop ${index + 1}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          Text(
            'Stop ${index + 1}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          Wrap(
            children: [
              _button(
                'Move up stop ${index + 1}',
                index == 0
                    ? null
                    : () => setState(() {
                        final item = stops.removeAt(index);
                        stops.insert(index - 1, item);
                      }),
              ),
              _button(
                'Move down stop ${index + 1}',
                index == stops.length - 1
                    ? null
                    : () => setState(() {
                        final item = stops.removeAt(index);
                        stops.insert(index + 1, item);
                      }),
              ),
              _button(
                'Remove stop ${index + 1}',
                () => setState(() => stops.removeAt(index).dispose()),
              ),
            ],
          ),
          _field('Stop name', stop.name, key: Key('stop-name-$index')),
          _field(
            'Dwell minutes',
            stop.dwell,
            key: Key('stop-dwell-$index'),
            keyboard: TextInputType.number,
          ),
          _field(
            'Rough cost (whole units; your currency)',
            stop.cost,
            keyboard: TextInputType.number,
          ),
          _field('Notes', stop.notes, maxLines: 2),
          Text('Travel to this stop: ${stop.mode.name} (user estimate)'),
          Wrap(
            children: [
              for (final mode in TravelMode.values)
                _button(mode.name, () => setState(() => stop.mode = mode)),
            ],
          ),
          _field(
            'Travel minutes to this stop',
            stop.travel,
            keyboard: TextInputType.number,
          ),
          _field('Fixed arrival (yyyy-MM-dd HH:mm; optional)', stop.anchor),
          _field('Opens (HH:mm; optional)', stop.opens),
          _field('Closes (HH:mm; optional)', stop.closes),
          _field('Closed weekdays (1–7; Monday=1)', stop.closed, hint: '6,7'),
          const Text('Day-of actual (entered by you):'),
          Wrap(
            children: [
              _button(
                'Pending stop ${index + 1}',
                () => setState(() {
                  stop.actualStatus = null;
                  stop.actualArrival.clear();
                  stop.actualDeparture.clear();
                }),
              ),
              for (final status in StopStatus.values)
                _button(
                  '${status.name} stop ${index + 1}',
                  () => setState(() {
                    stop.actualStatus = status;
                    if (status == StopStatus.skipped) {
                      stop.actualArrival.clear();
                    }
                  }),
                ),
            ],
          ),
          if (stop.actualStatus != null) ...[
            Text('Status: ${stop.actualStatus!.name}'),
            if (stop.actualStatus != StopStatus.skipped)
              _field(
                'Actual arrival (yyyy-MM-dd HH:mm)',
                stop.actualArrival,
                key: Key('actual-arrival-$index'),
              ),
            _field(
              'Actual departure (yyyy-MM-dd HH:mm)',
              stop.actualDeparture,
              key: Key('actual-departure-$index'),
            ),
          ],
          const Text(
            'Opening hours are your notes, not live venue data. Recheck legs after changing stop order.',
          ),
        ],
      ),
    );
  }
}
