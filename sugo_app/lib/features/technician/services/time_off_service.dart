import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../rb_cars/services/rb_cars_service.dart';
import '../models/time_off.dart';

/// The signed-in technician's own time off.
///
/// Plain PostgREST against `technician_time_off`: the table's policies already
/// say "your own rows only", and its trigger enforces the rules a form could
/// get wrong - no start in the past, no overlapping periods - so there is
/// nothing an edge function would add. Errors from those rules are mapped to
/// sentences here, by SQLSTATE, rather than shown raw.
class TimeOffService {
  TimeOffService({SupabaseClient? client})
    : _client = client ?? SupabaseService.client;

  final SupabaseClient _client;

  String get _uid {
    final String? id = _client.auth.currentUser?.id;
    if (id == null) throw const RbCarsFailure('Please sign in again.');
    return id;
  }

  /// Current and upcoming periods, soonest first. Ones that have ended are
  /// history and are not shown.
  Future<List<TimeOff>> upcoming() async {
    try {
      final List<dynamic> rows = await _client
          .from('technician_time_off')
          .select('id, starts_on, ends_on, note')
          .eq('technician_id', _uid)
          .gte('ends_on', TimeOff.toWire(TimeOff.dayOf(DateTime.now())))
          .order('starts_on');

      return rows
          .whereType<Map<String, dynamic>>()
          .map(TimeOff.fromJson)
          .toList(growable: false);
    } on PostgrestException catch (error) {
      _log('upcoming', error);
      throw const RbCarsFailure('Could not load your vacation dates.');
    }
  }

  Future<TimeOff> add({
    required DateTime startsOn,
    required DateTime endsOn,
    String? note,
  }) async {
    final String trimmed = (note ?? '').trim();
    try {
      final Map<String, dynamic> row = await _client
          .from('technician_time_off')
          .insert(<String, dynamic>{
            'technician_id': _uid,
            'starts_on': TimeOff.toWire(startsOn),
            'ends_on': TimeOff.toWire(endsOn),
            'note': trimmed.isEmpty ? null : trimmed,
          })
          .select('id, starts_on, ends_on, note')
          .single();

      return TimeOff.fromJson(row);
    } on PostgrestException catch (error) {
      _log('add', error);
      throw RbCarsFailure(_explain(error));
    }
  }

  /// Ends a vacation early, so clients can book them again today.
  ///
  /// A period that has not started yet - or started today - is simply
  /// deleted. One already under way is shortened to end yesterday instead:
  /// the days already taken off really were taken, and deleting them would
  /// rewrite why a client could not book on those days.
  Future<void> endNow(TimeOff period) async {
    final DateTime today = TimeOff.dayOf(DateTime.now());
    try {
      if (!period.startsOn.isBefore(today)) {
        await _client.from('technician_time_off').delete().eq('id', period.id);
        return;
      }
      await _client
          .from('technician_time_off')
          .update(<String, dynamic>{
            'ends_on': TimeOff.toWire(today.subtract(const Duration(days: 1))),
          })
          .eq('id', period.id);
    } on PostgrestException catch (error) {
      _log('endNow', error);
      throw const RbCarsFailure('Could not end your vacation. Please try again.');
    }
  }

  /// Moves the last day of [period] ("Edit dates"). The start stays: one
  /// already under way has started, and the database refuses a start in the
  /// past anyway.
  Future<void> changeEnd(TimeOff period, DateTime endsOn) async {
    try {
      await _client
          .from('technician_time_off')
          .update(<String, dynamic>{'ends_on': TimeOff.toWire(endsOn)})
          .eq('id', period.id);
    } on PostgrestException catch (error) {
      _log('changeEnd', error);
      throw RbCarsFailure(_explain(error));
    }
  }

  /// Removes a period that has not started.
  Future<void> cancel(TimeOff period) async {
    try {
      await _client.from('technician_time_off').delete().eq('id', period.id);
    } on PostgrestException catch (error) {
      _log('cancel', error);
      throw const RbCarsFailure('Could not remove those dates. Please try again.');
    }
  }

  /// The trigger's and constraints' errors, in the technician's words.
  static String _explain(PostgrestException error) {
    switch (error.code) {
      case '23P01':
        return 'Those dates overlap vacation you already added.';
      case '23514':
        if (error.message.contains('past')) {
          return 'A vacation cannot start in the past.';
        }
        if (error.message.contains('length')) {
          return 'A vacation can be at most ${TimeOff.maxDays} days. '
              'Add a second one for a longer break.';
        }
        return 'Those dates are not valid. Please pick them again.';
      case '42501':
        return 'Only technicians can add vacation dates.';
      default:
        return 'Could not save your vacation. Please try again.';
    }
  }

  void _log(String action, PostgrestException error) {
    debugPrint('TimeOffService.$action failed: ${error.code} ${error.message}');
  }
}
