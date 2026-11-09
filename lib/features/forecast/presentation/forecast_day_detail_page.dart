import '../../../core/widgets/chart_axis_label.dart';
import '../../../core/widgets/adaptive_metric_grid.dart';
import 'dart:math' as math;

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

class ForecastDayDetailPage extends ConsumerStatefulWidget {
  const ForecastDayDetailPage({
    required this.dayIso,
    required this.days,
    super.key,
  });

  final String dayIso;
  final int days;

  @override
  ConsumerState<ForecastDayDetailPage> createState() =>
      _ForecastDayDetailPageState();
}

class _ForecastDayDetailPageState extends ConsumerState<ForecastDayDetailPage> {
  String? _cacheKey;
  Future<_ForecastDayBundle>? _future;
  int? _selectedIndex;

  Future<_ForecastDayBundle> _load(
    EnergySite site, {
    bool refresh = false,
  }) async {
    final targetDay = DateTime.tryParse('${widget.dayIso}T00:00:00')?.toLocal();
    final raw = await ref
        .read(cloudRunApiProvider)
        .fetchForecast(
          forceRefresh: refresh,
          lat: site.latitude,
          lon: site.longitude,
          days: widget.days,
          capacityKw: site.solarCapacityKw,
          tiltDeg: site.tiltDeg,
          azimuthDeg: site.azimuthDeg,
          windCapacityKw: site.windCapacityKw,
          windHubHeightM: site.windHubHeightM,
        );
    final points = parseForecast(raw);
    final daily = aggregateDaily(points);
    final dayPoints = targetDay == null
        ? const <ForecastPoint>[]
        : points
              .where(
                (point) =>
                    point.time.year == targetDay.year &&
                    point.time.month == targetDay.month &&
                    point.time.day == targetDay.day,
              )
              .toList(growable: false);
    final dailyBucket = targetDay == null
        ? null
        : daily
              .where(
                (bucket) =>
                    bucket.day.year == targetDay.year &&
                    bucket.day.month == targetDay.month &&
                    bucket.day.day == targetDay.day,
              )
              .cast<DailyForecastBucket?>()
              .firstOrNull;

    return _ForecastDayBundle(
      day: targetDay,
      dayPoints: dayPoints,
      dailyBucket: dailyBucket,
    );
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/forecast');
  }

  int _resolveSelectedIndex(List<ForecastPoint> points) {
    if (points.isEmpty) {
      return 0;
    }
    final current = _selectedIndex;
    if (current != null && current >= 0 && current < points.length) {
      return current;
    }
    var bestIndex = 0;
    var bestValue = points.first.renewableKw;
    for (var i = 1; i < points.length; i++) {
      if (points[i].renewableKw > bestValue) {
        bestValue = points[i].renewableKw;
        bestIndex = i;
      }
    }
    return bestIndex;
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

    final nextKey = '${site.forecastKey}-${widget.dayIso}-${widget.days}';
    if (_cacheKey != nextKey || _future == null) {
      _cacheKey = nextKey;
      _selectedIndex = null;
      _future = _load(site);
    }

    return FutureBuilder<_ForecastDayBundle>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return EmptyState(
            icon: Icons.error_outline_rounded,
            title: l10n.loadFailed,
            message: l10n.fetchErrorGeneric,
            actionLabel: l10n.retry,
            onAction: () =>
                setState(() => _future = _load(site, refresh: true)),
          );
        }

        if (!snapshot.hasData) {
          return LoadingState(
            title: l10n.forecastDayDetailTitle,
            subtitle: '${site.name} • ${widget.dayIso}',
          );
        }

        final data = snapshot.data!;
        if (data.day == null ||
            data.dayPoints.isEmpty ||
            data.dailyBucket == null) {
          return EmptyState(
            icon: Icons.calendar_month_outlined,
            title: l10n.forecastDayDetailTitle,
            message: l10n.forecastDayUnavailable,
            actionLabel: l10n.backToForecast,
            onAction: _goBack,
          );
        }

        final selectedIndex = _resolveSelectedIndex(data.dayPoints);
        final selectedPoint = data.dayPoints[selectedIndex];
        final riskPoint = math.max(
          selectedPoint.solarProbability,
          selectedPoint.windProbability,
        );
        final peakKw = data.dayPoints
            .map((point) => point.renewableKw)
            .reduce(math.max);
        final averageRisk = averageExtremeRisk(data.dayPoints);
        final recommendation = _buildRecommendation(
          context,
          selectedPoint,
          riskPoint,
        );

        return AppAnimatedContent(
          contentKey: nextKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppCard(
                  animated: true,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final stacked = constraints.maxWidth < 680;
                      final backButton = AppSecondaryButton(
                        label: '',
                        icon: const Icon(Icons.arrow_back_rounded),
                        onPressed: _goBack,
                      );
                      final headerText = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.forecastDayDetailTitle,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${site.name} • ${formatDateWithWeekday(data.day!, localeTag)}',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      );

                      if (stacked) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            backButton,
                            const SizedBox(height: 16),
                            headerText,
                          ],
                        );
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          backButton,
                          const SizedBox(width: 16),
                          Expanded(child: headerText),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                _ResponsiveMetricGrid(
                  children: [
                    MetricTile(
                      label: l10n.renewableTotal,
                      value: formatEnergy(
                        data.dailyBucket!.renewableKwh,
                        localeTag,
                      ),
                      icon: Icons.eco_outlined,
                    ),
                    MetricTile(
                      label: l10n.peakRenewable,
                      value: formatPower(peakKw, localeTag),
                      icon: Icons.flash_on_rounded,
                      color: Theme.of(context).colorScheme.tertiary,
                    ),
                    MetricTile(
                      label: l10n.solarTotal,
                      value: formatEnergy(
                        data.dailyBucket!.solarKwh,
                        localeTag,
                      ),
                      icon: Icons.wb_sunny_outlined,
                      color: Theme.of(context).colorScheme.tertiary,
                    ),
                    MetricTile(
                      label: l10n.windTotal,
                      value: formatEnergy(data.dailyBucket!.windKwh, localeTag),
                      icon: Icons.air_rounded,
                      color: Theme.of(context).colorScheme.secondary,
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
                        title: formatDateWithWeekday(data.day!, localeTag),
                        subtitle: l10n.forecastDayDetailSubtitle,
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        height: 360,
                        child: _ForecastDayChart(
                          points: data.dayPoints,
                          selectedIndex: selectedIndex,
                          onSelectedIndexChanged: (index) {
                            setState(() => _selectedIndex = index);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                AppCard(
                  animated: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SectionHeader(
                        title: l10n.forecastDetailInsightTitle,
                        subtitle: l10n.forecastDetailInsightSubtitle,
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _PointChip(
                            icon: Icons.schedule_rounded,
                            label: l10n.forecastPointTime,
                            value: formatTimeLabel(
                              selectedPoint.time,
                              localeTag,
                            ),
                          ),
                          _PointChip(
                            icon: Icons.bolt_rounded,
                            label: l10n.forecastPointRisk,
                            value: formatPercent(riskPoint, localeTag),
                          ),
                          _PointChip(
                            icon: Icons.calendar_today_rounded,
                            label: l10n.day,
                            value: formatDateShort(data.day!, localeTag),
                          ),
                          _PointChip(
                            icon: Icons.analytics_outlined,
                            label: l10n.averageRisk,
                            value: formatPercent(averageRisk, localeTag),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isWide = constraints.maxWidth >= 900;
                          final cards = [
                            _PointValueCard(
                              label: l10n.solarTotal,
                              value:
                                  '${formatNumber(selectedPoint.solarKw, localeTag, digits: 3)} kW',
                              accent: Theme.of(context).colorScheme.tertiary,
                              icon: Icons.wb_sunny_outlined,
                            ),
                            _PointValueCard(
                              label: l10n.windTotal,
                              value:
                                  '${formatNumber(selectedPoint.windKw, localeTag, digits: 3)} kW',
                              accent: Theme.of(context).colorScheme.secondary,
                              icon: Icons.air_rounded,
                            ),
                            _PointValueCard(
                              label: l10n.renewable,
                              value:
                                  '${formatNumber(selectedPoint.renewableKw, localeTag, digits: 3)} kW',
                              accent: Theme.of(context).colorScheme.primary,
                              icon: Icons.eco_outlined,
                            ),
                          ];
                          return isWide
                              ? Row(
                                  children: [
                                    for (var i = 0; i < cards.length; i++) ...[
                                      Expanded(child: cards[i]),
                                      if (i < cards.length - 1)
                                        const SizedBox(width: 12),
                                    ],
                                  ],
                                )
                              : Column(
                                  children: [
                                    for (var i = 0; i < cards.length; i++) ...[
                                      cards[i],
                                      if (i < cards.length - 1)
                                        const SizedBox(height: 12),
                                    ],
                                  ],
                                );
                        },
                      ),
                      const SizedBox(height: 18),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: recommendation.accent.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: recommendation.accent.withValues(
                              alpha: 0.32,
                            ),
                          ),
                        ),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final stacked = constraints.maxWidth < 420;
                            final iconCard = Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: recommendation.accent.withValues(
                                  alpha: 0.16,
                                ),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                recommendation.icon,
                                color: recommendation.accent,
                              ),
                            );
                            final textBlock = Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l10n.forecastPointRecommendation,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  recommendation.text,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                        height: 1.6,
                                      ),
                                ),
                              ],
                            );

                            if (stacked) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  iconCard,
                                  const SizedBox(height: 12),
                                  textBlock,
                                ],
                              );
                            }

                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                iconCard,
                                const SizedBox(width: 14),
                                Expanded(child: textBlock),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  _PointRecommendation _buildRecommendation(
    BuildContext context,
    ForecastPoint point,
    double riskPoint,
  ) {
    final l10n = AppLocalizations.of(context);
    if (riskPoint >= 0.30) {
      return _PointRecommendation(
        text: l10n.forecastRecommendationRisk,
        accent: const Color(0xFFB97522),
        icon: Icons.warning_amber_rounded,
      );
    }
    if (point.solarKw >= point.windKw * 1.20) {
      return _PointRecommendation(
        text: l10n.forecastRecommendationSolar,
        accent: Theme.of(context).colorScheme.tertiary,
        icon: Icons.wb_sunny_rounded,
      );
    }
    if (point.windKw > point.solarKw * 1.05) {
      return _PointRecommendation(
        text: l10n.forecastRecommendationWind,
        accent: Theme.of(context).colorScheme.secondary,
        icon: Icons.air_rounded,
      );
    }
    return _PointRecommendation(
      text: l10n.forecastRecommendationStable,
      accent: Theme.of(context).colorScheme.primary,
      icon: Icons.eco_rounded,
    );
  }
}

class _ForecastDayChart extends StatelessWidget {
  const _ForecastDayChart({
    required this.points,
    required this.selectedIndex,
    required this.onSelectedIndexChanged,
  });

  final List<ForecastPoint> points;
  final int selectedIndex;
  final ValueChanged<int> onSelectedIndexChanged;

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
              minIncluded: false,
              maxIncluded: false,
              showTitles: true,
              reservedSize: 42,
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
                  formatTimeLabel(points[index].time, localeTag),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          handleBuiltInTouches: true,
          touchCallback: (event, response) {
            final spots = response?.lineBarSpots;
            if (spots == null || spots.isEmpty) {
              return;
            }
            onSelectedIndexChanged(spots.first.spotIndex);
          },
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
                  '${formatTimeLabel(point.time, localeTag)}\n',
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
          getTouchedSpotIndicator: (barData, spotIndexes) {
            return spotIndexes.map((spotIndex) {
              final color = barData.color ?? scheme.primary;
              return TouchedSpotIndicatorData(
                FlLine(color: color.withValues(alpha: 0.28), strokeWidth: 2),
                FlDotData(
                  getDotPainter: (spot, percent, bar, index) =>
                      FlDotCirclePainter(
                        radius: 4.8,
                        color: Colors.white,
                        strokeWidth: 3,
                        strokeColor: color,
                      ),
                ),
              );
            }).toList();
          },
        ),
        lineBarsData: [
          _line(
            points,
            (point) => point.solarKw,
            scheme.tertiary,
            selectedIndex,
          ),
          _line(
            points,
            (point) => point.windKw,
            scheme.secondary,
            selectedIndex,
          ),
          _line(
            points,
            (point) => point.renewableKw,
            scheme.primary,
            selectedIndex,
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
    Color color,
    int selectedIndex, {
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
      showingIndicators: [selectedIndex],
      belowBarData: shaded
          ? BarAreaData(show: true, color: color.withValues(alpha: 0.08))
          : BarAreaData(show: false),
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

class _PointChip extends StatelessWidget {
  const _PointChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 2),
                Text(value, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PointValueCard extends StatelessWidget {
  const _PointValueCard({
    required this.label,
    required this.value,
    required this.accent,
    required this.icon,
  });

  final String label;
  final String value;
  final Color accent;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.24)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 4),
                Text(value, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ForecastDayBundle {
  const _ForecastDayBundle({
    required this.day,
    required this.dayPoints,
    required this.dailyBucket,
  });

  final DateTime? day;
  final List<ForecastPoint> dayPoints;
  final DailyForecastBucket? dailyBucket;
}

class _PointRecommendation {
  const _PointRecommendation({
    required this.text,
    required this.accent,
    required this.icon,
  });

  final String text;
  final Color accent;
  final IconData icon;
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
