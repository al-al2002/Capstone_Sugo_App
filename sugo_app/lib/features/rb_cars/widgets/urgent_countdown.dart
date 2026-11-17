import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';

/// The five-minute clock on an urgent request (2026-11-17).
///
/// Counts down to [deadline] once a second, shown as "4:32". The technician
/// sees how long they have to accept; the client sees how long before the
/// request passes to the next technician. Both read the same deadline -
/// `job_matches.offered_at` plus five minutes - which is also the moment the
/// server's `urgent-offer-sweep` passes it on, so the clock and what actually
/// happens agree.
///
/// Orange while there is time, red in the last minute. At zero it stops,
/// shows "Passing on…" and calls [onExpired] once.
class UrgentCountdown extends StatefulWidget {
  const UrgentCountdown({
    super.key,
    required this.deadline,
    this.onExpired,
    this.clock,
  });

  final DateTime deadline;
  final VoidCallback? onExpired;

  /// For tests: what "now" is.
  final DateTime Function()? clock;

  @override
  State<UrgentCountdown> createState() => _UrgentCountdownState();
}

class _UrgentCountdownState extends State<UrgentCountdown> {
  Timer? _ticker;
  bool _expiredSent = false;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  Duration get _left {
    final Duration left = widget.deadline.difference(_now());
    return left.isNegative ? Duration.zero : left;
  }

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(UrgentCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deadline != widget.deadline) {
      _expiredSent = false;
      _start();
    }
  }

  void _start() {
    _ticker?.cancel();
    if (_left == Duration.zero) {
      _expire();
      return;
    }
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      if (_left == Duration.zero) _expire();
    });
  }

  void _expire() {
    _ticker?.cancel();
    if (_expiredSent) return;
    _expiredSent = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onExpired?.call();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Duration left = _left;
    final bool done = left == Duration.zero;
    final bool lastMinute = left.inSeconds < 60;
    final Color ink = lastMinute ? AppColors.error : AppColors.accentDark;
    final Color wash = lastMinute ? AppColors.errorSoft : AppColors.accentSoft;
    final String time =
        '${left.inMinutes}:${(left.inSeconds % 60).toString().padLeft(2, '0')}';

    final Widget pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: wash,
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.timer_outlined, size: 14, color: ink),
          const SizedBox(width: 4),
          Text(
            done ? 'Passing on…' : time,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: ink,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );

    return Semantics(
      label: done
          ? 'Time is up'
          : '${left.inMinutes} minutes ${left.inSeconds % 60} seconds left',
      liveRegion: lastMinute,
      excludeSemantics: true,
      child: pill,
    );
  }
}
