import 'package:flutter/material.dart';

import '../journey/journey.dart';

String modeName(JourneyMode mode) => switch (mode) {
  JourneyMode.road => 'Road journey',
  JourneyMode.expedition => 'Expedition',
};

/// Fewer decimals as distances grow: 10 m steps mean nothing on a 1,000 km
/// drive, and long numbers would not fit.
String kilometres(double meters) {
  final km = meters / 1000;
  final decimals = km < 10
      ? 2
      : km < 100
      ? 1
      : 0;
  return '${km.toStringAsFixed(decimals)} km';
}

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

/// Speed from the GPS, or a dash when it is unknown: never a guess.
String speedText(double? metersPerSecond) {
  if (metersPerSecond == null) return '—';
  final kmh = metersPerSecond * 3.6;
  return '${kmh < 1 ? 0 : kmh.round()} km/h';
}

/// "12.97630° N, 77.59290° E": five decimals is about a metre.
String coordinatesText(double latitude, double longitude) =>
    '${latitude.abs().toStringAsFixed(5)}° ${latitude < 0 ? 'S' : 'N'}, '
    '${longitude.abs().toStringAsFixed(5)}° ${longitude < 0 ? 'W' : 'E'}';
