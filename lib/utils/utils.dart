import 'package:flutter/material.dart';
import 'package:logger/web.dart';

Logger logger = Logger();

String formatDate(BuildContext context, DateTime date) =>
    MaterialLocalizations.of(context).formatMediumDate(date);
String formatTime(BuildContext context, DateTime date) =>
    MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(date));
String formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}
