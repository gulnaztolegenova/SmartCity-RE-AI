import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../utils/formatters.dart';

/// Keep dates at the chart edges inside the plot and thin labels on narrow cards.
Widget chartAxisLabel(
  BuildContext context,
  TitleMeta meta,
  double value,
  String label, {
  int? itemCount,
}) {
  final scale = MediaQuery.textScalerOf(context).scale(1);
  final slots = math.max(2, (meta.parentAxisSize / (100 * scale)).floor());
  final tickCount = itemCount == null
      ? ((meta.max - meta.min) / meta.appliedInterval).ceil()
      : itemCount - 1;
  final stride = math.max(1, (tickCount / slots).ceil());
  final tick = itemCount == null
      ? ((value - meta.min) / meta.appliedInterval).round()
      : value.round();
  if (tick % stride != 0) return const SizedBox.shrink();
  return SideTitleWidget(
    meta: meta,
    space: 8,
    fitInside: SideTitleFitInsideData.fromTitleMeta(meta, distanceFromEdge: 0),
    child: Text(
      label,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.25),
    ),
  );
}

String chartDateTimeLabel(DateTime time, String locale) =>
    '${formatDateShort(time, locale)}\n${formatTimeLabel(time, locale)}';
