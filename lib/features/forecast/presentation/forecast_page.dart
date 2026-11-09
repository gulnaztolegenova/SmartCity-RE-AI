import '../../../core/widgets/aligned_panel_grid.dart';
import '../../../core/widgets/chart_axis_label.dart';
import '../../../core/widgets/adaptive_metric_grid.dart';
import 'dart:math' as math;

import 'package:data_table_2/data_table_2.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_city_renewable_ai/l10n/app_localizations.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/utils/forecast_utils.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_animated_content.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/loading_state.dart';
import '../../../core/widgets/metric_tile.dart';
import '../../../core/widgets/section_header.dart';
import '../../../data/models/energy_site.dart';

class ForecastPage extends ConsumerStatefulWidget {
  const ForecastPage({super.key});

  @override
  ConsumerState<ForecastPage> createState() => _ForecastPageState();
}

class _ForecastPageState extends ConsumerState<ForecastPage> {
  int _days = 7;
  String? _cacheKey;
  Future<_ForecastBundle>? _future;

  Future<_ForecastBundle> _load(
    EnergySite site,
    int days, {
    bool refresh = false,
  }) async {
    final raw = await ref
        .read(cloudRunApiProvider)
        .fetchForecast(
          lat: site.latitude,
          lon: site.longitude,
          days: days,
          forceRefresh: refresh,
          capacityKw: site.solarCapacityKw,
          tiltDeg: site.tiltDeg,
          azimuthDeg: site.azimuthDeg,
          windCapacityKw: site.windCapacityKw,
          windHubHeightM: site.windHubHeightM,
        );
    final points = parseForecast(raw);
    return _ForecastBundle(
      points: points,
      daily: aggregateDaily(points),
      metadata: raw,
    );
  }

  void _openDayDetail(BuildContext context, DateTime day) {
    final dayKey =
        '${day.year.toString().padLeft(4, '0')}-'
        '${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';
    context.push('/forecast/day/$dayKey?days=$_days');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final localeTag = Localizations.localeOf(context).toLanguageTag();
    final site = ref.watch(selectedSiteProvider);

    if (site == null) {
      return EmptyState(
        icon: Icons.solar_power_outlined,
        title: l10n.noSiteTitle,
        message: l10n.noSiteMessage,
      );
    }

    final nextKey = '${site.forecastKey}-$_days';
    if (_cacheKey != nextKey || _future == null) {
      _cacheKey = nextKey;
      _future = _load(site, _days);
    }

    return FutureBuilder<_ForecastBundle>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return EmptyState(
            icon: Icons.signal_wifi_bad_rounded,
            title: l10n.loadFailed,
            message: l10n.fetchErrorGeneric,
            actionLabel: l10n.retry,
            onAction: () =>
                setState(() => _future = _load(site, _days, refresh: true)),
          );
        }

        if (!snapshot.hasData) {
          return LoadingState(
            title: l10n.forecastPageTitle,
            subtitle: '${site.name} • ${site.city}',
          );
        }

        final data = snapshot.data!;
        final solar =
            data.points.fold<double>(0, (sum, item) => sum + item.solarWh) /
            1000;
        final wind =
            data.points.fold<double>(0, (sum, item) => sum + item.windWh) /
            1000;
        final renewable = solar + wind;
        final risk = averageExtremeRisk(data.points);
        final stepMinutes = data.points.isEmpty
            ? 15
            : data.points.first.stepMinutes;
        final horizonPointCount = math.max(
          1,
          ((72 * 60) / stepMinutes).round(),
        );
        final subset = data.points
            .take(math.min(data.points.length, horizonPointCount))
            .toList(growable: false);
        return AppAnimatedContent(
          contentKey: nextKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppCard(
                  animated: true,
                  child: SectionHeader(
                    title: l10n.forecastPageTitle,
                    subtitle:
                        '${site.name} • ${site.city}\n'
                        '${data.metadata['model_name'] ?? l10n.unknown} / ${data.metadata['model_version'] ?? l10n.unknown}\n'
                        '${l10n.qualityInputs}: ${data.qualityModel ?? l10n.unknown} — ${data.qualityStatus == null
                            ? l10n.unknown
                            : data.qualityNeedsAttention
                            ? l10n.qualityAttention
                            : l10n.qualityReference}\n'
                        '${l10n.siteEnergyEstimate}',
                    trailing: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        SegmentedButton<int>(
                          segments: [
                            ButtonSegment(value: 7, label: Text(l10n.day7)),
                            ButtonSegment(value: 14, label: Text(l10n.day14)),
                          ],
                          selected: {_days},
                          onSelectionChanged: (selection) {
                            setState(() {
                              _days = selection.first;
                            });
                          },
                        ),
                        AppSecondaryButton(
                          label: l10n.refreshForecast,
                          isLoading:
                              snapshot.connectionState ==
                              ConnectionState.waiting,
                          icon: const Icon(Icons.refresh_rounded),
                          onPressed: () => setState(
                            () => _future = _load(site, _days, refresh: true),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _ResponsiveMetricGrid(
                  children: [
                    MetricTile(
                      label: l10n.solarTotal,
                      value: formatEnergy(solar, localeTag),
                      icon: Icons.wb_sunny_outlined,
                      color: Theme.of(context).colorScheme.tertiary,
                    ),
                    MetricTile(
                      label: l10n.windTotal,
                      value: formatEnergy(wind, localeTag),
                      icon: Icons.air_rounded,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    MetricTile(
                      label: l10n.renewableTotal,
                      value: formatEnergy(renewable, localeTag),
                      icon: Icons.eco_outlined,
                    ),
                    MetricTile(
                      label: l10n.extremeRisk,
                      value: formatPercent(risk, localeTag),
                      caption: l10n.averageRisk,
                      icon: Icons.warning_amber_rounded,
                      color: const Color(0xFFB97522),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                AppCard(
                  animated: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SectionHeader(
                        title: l10n.hourlyCurve,
                        subtitle: l10n.hourlyCurveSubtitle,
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        height: 340,
                        child: _HourlyForecastChart(points: subset),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _DayHintCard(
                  onOpenDay: data.daily.isEmpty
                      ? null
                      : () => _openDayDetail(context, data.daily.first.day),
                ),
                const SizedBox(height: 16),
                AlignedPanelGrid(
                  key: const ValueKey('forecast-daily-row'),
                  children: [
                    _DailyBarCard(
                      days: data.daily,
                      onOpenDay: (day) => _openDayDetail(context, day),
                    ),
                    _DailyTableCard(
                      days: data.daily,
                      onOpenDay: (day) => _openDayDetail(context, day),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ResponsiveMetricGrid extends StatelessWidget {
  const _ResponsiveMetricGrid({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) =>
      AdaptiveMetricGrid(maxColumns: 4, children: children);
}

class _HourlyForecastChart extends StatelessWidget {
  const _HourlyForecastChart({required this.points});

  final List<ForecastPoint> points;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final localeTag = Localizations.localeOf(context).toLanguageTag();
    final scheme = theme.colorScheme;
    final maxY = points.isEmpty
        ? 1.0
        : points
              .map(
                (point) => math.max(
                  point.renewableKw,
                  math.max(point.solarKw, point.windKw),
                ),
              )
              .reduce(math.max);

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY * 1.15,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: math.max(1, maxY / 4),
          getDrawingHorizontalLine: (value) => FlLine(
            color: scheme.outline.withValues(alpha: 0.8),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              minIncluded: false,
              maxIncluded: false,
              showTitles: true,
              reservedSize: 40,
              interval: math.max(1, maxY / 4),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              minIncluded: true,
              maxIncluded: true,
              showTitles: true,
              reservedSize: 64,
              interval: math.max(1, (points.length / 6).floor()).toDouble(),
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= points.length) {
                  return const SizedBox.shrink();
                }
                return chartAxisLabel(
                  context,
                  meta,
                  value,
                  chartDateTimeLabel(points[index].time, localeTag),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          handleBuiltInTouches: true,
          touchTooltipData: LineTouchTooltipData(
            maxContentWidth: 220,
            tooltipBorderRadius: BorderRadius.circular(18),
            tooltipPadding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipColor: (_) => const Color(0xFF24314B),
            getTooltipItems: (touchedSpots) {
              if (touchedSpots.isEmpty) {
                return const <LineTooltipItem?>[];
              }
              final sorted = touchedSpots.toList()
                ..sort((a, b) => a.barIndex.compareTo(b.barIndex));
              final index = sorted.first.spotIndex;
              final point = points[index];
              final labelStyle = theme.textTheme.bodySmall?.copyWith(
                color: Colors.white70,
                fontWeight: FontWeight.w700,
                height: 1.45,
              );
              final valueStyle = theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                height: 1.45,
              );
              return List<LineTooltipItem?>.generate(sorted.length, (
                itemIndex,
              ) {
                if (itemIndex != 0) {
                  return null;
                }
                return LineTooltipItem(
                  '${formatDateTimeLabel(point.time, localeTag)}\n',
                  labelStyle ?? const TextStyle(color: Colors.white70),
                  children: [
                    TextSpan(text: '${l10n.solarTotal}: ', style: labelStyle),
                    TextSpan(
                      text:
                          '${formatNumber(point.solarKw, localeTag, digits: 3)} kW\n',
                      style: valueStyle?.copyWith(color: scheme.tertiary),
                    ),
                    TextSpan(text: '${l10n.windTotal}: ', style: labelStyle),
                    TextSpan(
                      text:
                          '${formatNumber(point.windKw, localeTag, digits: 3)} kW\n',
                      style: valueStyle?.copyWith(color: scheme.secondary),
                    ),
                    TextSpan(text: '${l10n.renewable}: ', style: labelStyle),
                    TextSpan(
                      text:
                          '${formatNumber(point.renewableKw, localeTag, digits: 3)} kW',
                      style: valueStyle?.copyWith(color: scheme.primary),
                    ),
                  ],
                );
              });
            },
          ),
        ),
        lineBarsData: [
          _line(
            points,
            (point) => point.solarKw,
            Theme.of(context).colorScheme.tertiary,
          ),
          _line(
            points,
            (point) => point.windKw,
            Theme.of(context).colorScheme.secondary,
          ),
          _line(
            points,
            (point) => point.renewableKw,
            Theme.of(context).colorScheme.primary,
            width: 3.2,
            shaded: true,
          ),
        ],
      ),
    );
  }

  LineChartBarData _line(
    List<ForecastPoint> points,
    double Function(ForecastPoint point) selector,
    Color color, {
    double width = 2.6,
    bool shaded = false,
  }) {
    return LineChartBarData(
      spots: [
        for (var i = 0; i < points.length; i++)
          FlSpot(i.toDouble(), selector(points[i])),
      ],
      isCurved: true,
      curveSmoothness: 0.18,
      barWidth: width,
      color: color,
      dotData: const FlDotData(show: false),
      belowBarData: shaded
          ? BarAreaData(show: true, color: color.withValues(alpha: 0.08))
          : BarAreaData(show: false),
    );
  }
}

class _DailyBarCard extends StatelessWidget {
  const _DailyBarCard({required this.days, required this.onOpenDay});

  final List<DailyForecastBucket> days;
  final ValueChanged<DateTime> onOpenDay;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final localeTag = Localizations.localeOf(context).toLanguageTag();
    final maxY = days.isEmpty
        ? 1.0
        : days.map((day) => day.renewableKwh).reduce(math.max);

    return LayoutBuilder(
      builder: (context, constraints) {
        final rodWidth =
            ((constraints.maxWidth - 88) / (math.max(1, days.length) * 5))
                .clamp(1.0, 9.0);
        return AppCard(
          animated: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(
                title: l10n.dailyBreakdown,
                subtitle: l10n.dailyBreakdownSubtitle,
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 440,
                child: BarChart(
                  BarChartData(
                    maxY: maxY * 1.2,
                    borderData: FlBorderData(show: false),
                    gridData: FlGridData(show: true, drawVerticalLine: false),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      leftTitles: const AxisTitles(
                        sideTitles: SideTitles(
                          minIncluded: false,
                          maxIncluded: false,
                          showTitles: true,
                          reservedSize: 40,
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          minIncluded: true,
                          maxIncluded: true,
                          showTitles: true,
                          reservedSize: 48,
                          interval: 1,
                          getTitlesWidget: (value, meta) {
                            final index = value.toInt();
                            if (index < 0 || index >= days.length) {
                              return const SizedBox.shrink();
                            }
                            return chartAxisLabel(
                              context,
                              meta,
                              value,
                              formatDateShort(days[index].day, localeTag),
                              itemCount: days.length,
                            );
                          },
                        ),
                      ),
                    ),
                    barTouchData: BarTouchData(
                      handleBuiltInTouches: true,
                      touchTooltipData: BarTouchTooltipData(
                        maxContentWidth: 180,
                        tooltipBorderRadius: BorderRadius.circular(18),
                        tooltipPadding: const EdgeInsets.fromLTRB(
                          14,
                          12,
                          14,
                          12,
                        ),
                        fitInsideHorizontally: true,
                        fitInsideVertically: true,
                        getTooltipColor: (_) => const Color(0xFF24314B),
                        getTooltipItem: (group, groupIndex, rod, rodIndex) {
                          if (groupIndex < 0 ||
                              groupIndex >= days.length ||
                              rodIndex != 0) {
                            return null;
                          }
                          final day = days[groupIndex];
                          final style = Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                height: 1.45,
                              );
                          final labelStyle = Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: Colors.white70,
                                fontWeight: FontWeight.w700,
                                height: 1.45,
                              );
                          return BarTooltipItem(
                            '${formatDateShort(day.day, localeTag)}\n',
                            labelStyle ??
                                const TextStyle(color: Colors.white70),
                            children: [
                              TextSpan(
                                text: '${l10n.renewable}: ',
                                style: labelStyle,
                              ),
                              TextSpan(
                                text:
                                    '${formatNumber(day.renewableKwh, localeTag, digits: 3)} kWh',
                                style: style,
                              ),
                            ],
                          );
                        },
                      ),
                      touchCallback: (event, response) {
                        if (event is FlTapUpEvent && response?.spot != null) {
                          onOpenDay(
                            days[response!.spot!.touchedBarGroupIndex].day,
                          );
                        }
                      },
                    ),
                    barGroups: [
                      for (var i = 0; i < days.length; i++)
                        BarChartGroupData(
                          x: i,
                          barsSpace: rodWidth * 0.4,
                          barRods: [
                            BarChartRodData(
                              toY: days[i].solarKwh,
                              color: Theme.of(context).colorScheme.tertiary,
                              width: rodWidth,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            BarChartRodData(
                              toY: days[i].windKwh,
                              color: Theme.of(context).colorScheme.secondary,
                              width: rodWidth,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            BarChartRodData(
                              toY: days[i].renewableKwh,
                              color: Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.22),
                              width: rodWidth,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DayHintCard extends StatelessWidget {
  const _DayHintCard({required this.onOpenDay});
  final VoidCallback? onOpenDay;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppCard(
      animated: true,
      child: SectionHeader(
        title: l10n.forecastOpenDay,
        subtitle: '${l10n.forecastOpenDaySubtitle} ${l10n.forecastTapDayHint}',
        trailing: AppSecondaryButton(
          label: l10n.forecastOpenDay,
          icon: const Icon(Icons.arrow_forward_rounded),
          onPressed: onOpenDay,
        ),
      ),
    );
  }
}

class _DailyTableCard extends StatelessWidget {
  const _DailyTableCard({required this.days, required this.onOpenDay});

  final List<DailyForecastBucket> days;
  final ValueChanged<DateTime> onOpenDay;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final localeTag = Localizations.localeOf(context).toLanguageTag();

    return AppCard(
      animated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: l10n.forecastTable,
            subtitle: l10n.forecastTableSubtitle,
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 440,
            child: DataTable2(
              minWidth: 600,
              headingRowHeight:
                  76 * math.max(1, MediaQuery.textScalerOf(context).scale(1)),
              isHorizontalScrollBarVisible: true,
              isVerticalScrollBarVisible: true,
              showCheckboxColumn: false,
              columnSpacing: 12,
              horizontalMargin: 0,
              columns: [
                DataColumn2(
                  label: Text(l10n.day, softWrap: true),
                  fixedWidth: 90,
                ),
                DataColumn2(
                  label: Text(l10n.solarTotal, softWrap: true),
                  size: ColumnSize.M,
                ),
                DataColumn2(
                  label: Text(l10n.windTotal, softWrap: true),
                  size: ColumnSize.M,
                ),
                DataColumn2(
                  label: Text(l10n.renewable, softWrap: true),
                  size: ColumnSize.M,
                ),
              ],
              rows: [
                for (var index = 0; index < days.length; index++)
                  DataRow.byIndex(
                    index: index,
                    onSelectChanged: (_) => onOpenDay(days[index].day),
                    cells: [
                      DataCell(
                        Text(formatDateShort(days[index].day, localeTag)),
                      ),
                      DataCell(
                        Text(formatEnergy(days[index].solarKwh, localeTag)),
                      ),
                      DataCell(
                        Text(formatEnergy(days[index].windKwh, localeTag)),
                      ),
                      DataCell(
                        Text(formatEnergy(days[index].renewableKwh, localeTag)),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ForecastBundle {
  const _ForecastBundle({
    required this.points,
    required this.daily,
    required this.metadata,
  });

  final Map<String, dynamic> metadata;
  String? get qualityModel =>
      (metadata['quality'] as Map?)?['model_name']?.toString();
  String? get qualityStatus =>
      (metadata['quality'] as Map?)?['status']?.toString();
  bool get qualityNeedsAttention => qualityStatus == 'attention';

  final List<ForecastPoint> points;
  final List<DailyForecastBucket> daily;
}
