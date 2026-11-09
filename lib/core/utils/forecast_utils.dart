import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';

import 'formatters.dart';

class ForecastPoint {
  const ForecastPoint({
    required this.time,
    required this.solarWh,
    required this.windWh,
    required this.solarProbability,
    required this.windProbability,
    required this.stepMinutes,
  });

  final DateTime time;
  final double solarWh;
  final double windWh;
  final double solarProbability;
  final double windProbability;
  final int stepMinutes;

  double get solarKw => solarWh / 1000 / (stepMinutes / 60);
  double get windKw => windWh / 1000 / (stepMinutes / 60);
  double get renewableKw => solarKw + windKw;
}

class DailyForecastBucket {
  const DailyForecastBucket({
    required this.day,
    required this.solarKwh,
    required this.windKwh,
  });

  final DateTime day;
  final double solarKwh;
  final double windKwh;

  double get renewableKwh => solarKwh + windKwh;
}

class BalancePoint {
  const BalancePoint({
    required this.time,
    required this.renewableKw,
    required this.loadKw,
    required this.netLoadKw,
    required this.windKw,
    required this.pvKw,
  });

  final DateTime time;
  final double renewableKw;
  final double loadKw;
  final double netLoadKw;
  final double windKw;
  final double pvKw;
}

List<ForecastPoint> parseForecast(Map<String, dynamic> raw) {
  final times = (raw['times'] as List? ?? const [])
      .map((e) => DateTime.tryParse('$e')?.toLocal())
      .whereType<DateTime>()
      .toList(growable: false);
  final solar =
      (raw['solar_pred'] as List? ?? raw['y_pred'] as List? ?? const [])
          .map(asDouble)
          .toList(growable: false);
  final wind = (raw['wind_pred'] as List? ?? const [])
      .map(asDouble)
      .toList(growable: false);
  final solarProb =
      (raw['solar_p_extreme'] as List? ?? raw['p_extreme'] as List? ?? const [])
          .map(asDouble)
          .toList(growable: false);
  final windProb = (raw['wind_p_extreme'] as List? ?? const [])
      .map(asDouble)
      .toList(growable: false);
  final stepMinutes = (raw['step_minutes'] as num?)?.toInt() ?? 15;
  final length = math.min(
    times.length,
    math.min(
      solar.length,
      math.min(wind.length, math.min(solarProb.length, windProb.length)),
    ),
  );

  return List<ForecastPoint>.generate(length, (index) {
    return ForecastPoint(
      time: times[index],
      solarWh: solar[index],
      windWh: wind[index],
      solarProbability: solarProb[index],
      windProbability: windProb[index],
      stepMinutes: stepMinutes,
    );
  }, growable: false);
}

List<DailyForecastBucket> aggregateDaily(List<ForecastPoint> points) {
  final buckets = <DateTime, List<ForecastPoint>>{};
  for (final point in points) {
    final day = DateTime(point.time.year, point.time.month, point.time.day);
    buckets.putIfAbsent(day, () => <ForecastPoint>[]).add(point);
  }
  final days = buckets.keys.toList()..sort();
  return days
      .map((day) {
        final items = buckets[day]!;
        final solarKwh =
            items.fold<double>(0, (sum, item) => sum + item.solarWh) / 1000;
        final windKwh =
            items.fold<double>(0, (sum, item) => sum + item.windWh) / 1000;
        return DailyForecastBucket(
          day: day,
          solarKwh: solarKwh,
          windKwh: windKwh,
        );
      })
      .toList(growable: false);
}

List<BalancePoint> parseBalance(Map<String, dynamic> raw) {
  final times = (raw['timestamps'] as List? ?? const [])
      .map((e) => DateTime.tryParse('$e')?.toLocal())
      .whereType<DateTime>()
      .toList(growable: false);
  final renewable = (raw['renewable_kw_pred'] as List? ?? const [])
      .map(asDouble)
      .toList(growable: false);
  final load = (raw['load_kw_pred'] as List? ?? const [])
      .map(asDouble)
      .toList(growable: false);
  final net = (raw['net_load_kw'] as List? ?? const [])
      .map(asDouble)
      .toList(growable: false);
  final wind = (raw['wind_kw_pred'] as List? ?? const [])
      .map(asDouble)
      .toList(growable: false);
  final pv = (raw['pv_kw_pred'] as List? ?? const [])
      .map(asDouble)
      .toList(growable: false);
  final length = [
    times.length,
    renewable.length,
    load.length,
    net.length,
    wind.length,
    pv.length,
  ].reduce(math.min);
  return List<BalancePoint>.generate(length, (index) {
    return BalancePoint(
      time: times[index],
      renewableKw: renewable[index],
      loadKw: load[index],
      netLoadKw: net[index],
      windKw: wind[index],
      pvKw: pv[index],
    );
  }, growable: false);
}

double averageExtremeRisk(List<ForecastPoint> points) {
  if (points.isEmpty) {
    return 0;
  }
  final value = points.fold<double>(
    0,
    (sum, point) =>
        sum + math.max(point.solarProbability, point.windProbability),
  );
  return value / points.length;
}

double peakRenewableKw(List<ForecastPoint> points) {
  if (points.isEmpty) {
    return 0;
  }
  return points.map((point) => point.renewableKw).reduce(math.max);
}

List<FlSpot> buildRenewableSpots(
  List<ForecastPoint> points, {
  int maxPoints = 48,
}) {
  final subset = points.take(maxPoints).toList(growable: false);
  return List<FlSpot>.generate(subset.length, (index) {
    return FlSpot(index.toDouble(), subset[index].renewableKw);
  }, growable: false);
}

List<FlSpot> buildLoadSpots(List<BalancePoint> points, {int maxPoints = 48}) {
  final subset = points.take(maxPoints).toList(growable: false);
  return List<FlSpot>.generate(subset.length, (index) {
    return FlSpot(index.toDouble(), subset[index].loadKw);
  }, growable: false);
}
