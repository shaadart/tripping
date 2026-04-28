import 'package:flutter/material.dart';

import '../journey/journey.dart';

String modeName(JourneyMode mode) => switch (mode) {
  JourneyMode.road => 'Road journey',
  JourneyMode.expedition => 'Expedition',
};

String kilometres(double meters) => '${(meters / 1000).toStringAsFixed(2)} km';

String clockTime(Duration duration) {
  final hours = duration.inHours;
  final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
  final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
  return '$hours:$minutes:$seconds';
}

String age(Duration age) {
  if (age.inSeconds < 60) return '${age.inSeconds} s';
  if (age.inMinutes < 60) return '${age.inMinutes} min';
  return '${age.inHours} h ${age.inMinutes % 60} min';
}

String timeOfDay(BuildContext context, DateTime time) =>
    MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(time.toLocal()));

/// "Tue, Oct 28 · 15:05" in the user's locale and time zone.
String dayAndTime(BuildContext context, DateTime time) =>
    '${MaterialLocalizations.of(context).formatMediumDate(time.toLocal())} · '
    '${timeOfDay(context, time)}';
