import '../../../core/widgets/aligned_panel_grid.dart';
import '../../../core/widgets/chart_axis_label.dart';
import '../../../core/widgets/adaptive_metric_grid.dart';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_city_renewable_ai/l10n/app_localizations.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/loading_state.dart';
import '../../../core/widgets/metric_tile.dart';
import '../../../core/widgets/section_header.dart';
import '../../../data/models/energy_site.dart';

class OptimizationPage extends ConsumerStatefulWidget {
  const OptimizationPage({super.key});

  @override
  ConsumerState<OptimizationPage> createState() => _OptimizationPageState();
}

class _OptimizationPageState extends ConsumerState<OptimizationPage> {
  int _days = 7;
  String? _siteId;
  Future<Map<String, dynamic>>? _future;

  bool _batteryEnabled = true;
  double _batteryCapacity = 80;
  double _chargePower = 18;
  double _dischargePower = 18;
  double _socMin = 0.10;
  double _socMax = 0.90;
  double _socInit = 0.50;

  void _seedFromSite(EnergySite site) {
    if (_siteId == site.forecastKey) {
      return;
    }
    _siteId = site.forecastKey;
    _batteryCapacity = math.max(5, site.batteryCapacityKwh);
    _chargePower = math.max(4, site.batteryCapacityKwh / 4);
    _dischargePower = math.max(4, site.batteryCapacityKwh / 4);
    _batteryEnabled = site.batteryCapacityKwh > 0;
    _future = _load(site);
  }

  Future<Map<String, dynamic>> _load(EnergySite site, {bool refresh = false}) {
    return ref
        .read(cloudRunApiProvider)
        .optimize(
          forceRefresh: refresh,
          lat: site.latitude,
          lon: site.longitude,
          days: _days,
          deviceId: site.id,
          capacityKw: site.solarCapacityKw,
          tiltDeg: site.tiltDeg,
          azimuthDeg: site.azimuthDeg,
          windCapacityKw: site.windCapacityKw,
          windHubHeightM: site.windHubHeightM,
          battery: <String, dynamic>{
            'enabled': _batteryEnabled,
            'battery_capacity_kwh': _batteryCapacity,
            'soc_min': _socMin,
            'soc_max': _socMax,
            'soc_init': _socInit,
            'charge_power_kw': _chargePower,
            'discharge_power_kw': _dischargePower,
            'eta_charge': 0.95,
            'eta_discharge': 0.95,
            'label': 'smart_city_dispatch',
          },
        );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final localeTag = Localizations.localeOf(context).toLanguageTag();
    final site = ref.watch(selectedSiteProvider);

    if (site == null) {
      return EmptyState(
        icon: Icons.battery_alert_rounded,
        title: l10n.noSiteTitle,
        message: l10n.noSiteMessage,
      );
    }

    _seedFromSite(site);

    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
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
          return LoadingState(
            title: l10n.optimizationTitle,
            subtitle: l10n.optimizationSubtitle,
          );
        }

        final data = snapshot.data!;
        final timestamps = (data['timestamps'] as List? ?? const [])
            .map((e) => '$e')
            .toList();
        final renewable = (data['renewable_kw_pred'] as List? ?? const [])
            .map(asDouble)
            .toList();
        final load = (data['load_kw_pred'] as List? ?? const [])
            .map(asDouble)
            .toList();
        final after = (data['grid_import_kw_after'] as List? ?? const [])
            .map(asDouble)
            .toList();
        final soc = (data['soc_kwh'] as List? ?? const [])
            .map(asDouble)
            .toList();
        final maxY = [...renewable, ...load, ...after, 1.0].reduce(math.max);
        final maxSoc = [0.1, ...soc].reduce(math.max);

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppCard(
                animated: true,
                child: SectionHeader(
                  title: l10n.optimizationTitle,
                  subtitle: l10n.optimizationSubtitle,
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
                            _future = _load(site);
                          });
                        },
                      ),
                      AppPrimaryButton(
                        label: l10n.runOptimization,
                        isLoading:
                            snapshot.connectionState == ConnectionState.waiting,
                        icon: const Icon(Icons.auto_fix_high_rounded),
                        onPressed: () async {
                          setState(() => _future = _load(site, refresh: true));
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const _OptimizationGuideCard(),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final controls = _BatteryCard(
                    batteryEnabled: _batteryEnabled,
                    batteryCapacity: _batteryCapacity,
                    chargePower: _chargePower,
                    dischargePower: _dischargePower,
                    socInit: _socInit,
                    socMin: _socMin,
                    socMax: _socMax,
                    onChanged:
                        ({
                          bool? batteryEnabled,
                          double? batteryCapacity,
                          double? chargePower,
                          double? dischargePower,
                          double? socInit,
                          double? socMin,
                          double? socMax,
                        }) {
                          setState(() {
                            _batteryEnabled = batteryEnabled ?? _batteryEnabled;
                            _batteryCapacity =
                                batteryCapacity ?? _batteryCapacity;
                            _chargePower = chargePower ?? _chargePower;
                            _dischargePower = dischargePower ?? _dischargePower;
                            _socInit = socInit ?? _socInit;
                            _socMin = socMin ?? _socMin;
                            _socMax = socMax ?? _socMax;
                          });
                        },
                  );
                  final results = Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _OptimizationChartCard(
                        title: l10n.loadVsRenewable,
                        subtitle: l10n.loadVsRenewableSubtitle,
                        timestamps: timestamps,
                        load: load,
                        renewable: renewable,
                        after: after,
                        maxY: maxY,
                      ),
                      const SizedBox(height: 16),
                      _SocCard(soc: soc, timestamps: timestamps, maxY: maxSoc),
                    ],
                  );

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ResponsiveMetricGrid(
                        children: [
                          MetricTile(
                            label: l10n.gridImportBefore,
                            value: formatEnergy(
                              asDouble(data['total_grid_import_kwh_before']),
                              localeTag,
                            ),
                            icon: Icons.flash_on_outlined,
                          ),
                          MetricTile(
                            label: l10n.gridImportAfter,
                            value: formatEnergy(
                              asDouble(data['total_grid_import_kwh_after']),
                              localeTag,
                            ),
                            icon: Icons.flash_off_rounded,
                            color: Theme.of(context).colorScheme.secondary,
                          ),
                          MetricTile(
                            label: l10n.reduction,
                            value: formatPercent(
                              asDouble(data['grid_import_reduction_pct']) / 100,
                              localeTag,
                            ),
                            icon: Icons.trending_down_rounded,
                            color: Theme.of(context).colorScheme.tertiary,
                          ),
                          MetricTile(
                            label: l10n.selfSufficiency,
                            value: formatPercent(
                              asDouble(data['self_sufficiency_ratio_after']),
                              localeTag,
                            ),
                            icon: Icons.bolt_rounded,
                            color: const Color(0xFF0F738C),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      AlignedPanelGrid(
                        key: const ValueKey('optimization-workspace-row'),
                        children: [controls, results],
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BatteryCard extends StatelessWidget {
  const _BatteryCard({
    required this.batteryEnabled,
    required this.batteryCapacity,
    required this.chargePower,
    required this.dischargePower,
    required this.socInit,
    required this.socMin,
    required this.socMax,
    required this.onChanged,
  });

  final bool batteryEnabled;
  final double batteryCapacity;
  final double chargePower;
  final double dischargePower;
  final double socInit;
  final double socMin;
  final double socMax;
  final void Function({
    bool? batteryEnabled,
    double? batteryCapacity,
    double? chargePower,
    double? dischargePower,
    double? socInit,
    double? socMin,
    double? socMax,
  })
  onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AppCard(
      animated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: l10n.batteryScenario,
            subtitle: l10n.optimizationMethodSubtitle,
          ),
          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: batteryEnabled,
            onChanged: (value) => onChanged(batteryEnabled: value),
            title: Text(l10n.batteryEnabled),
          ),
          Text(
            l10n.optimizationGuideConfigureBody,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.5),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _ScenarioChip(
                label: l10n.batteryCapacity,
                value: '${batteryCapacity.toStringAsFixed(0)} kWh',
              ),
              _ScenarioChip(
                label: l10n.chargePower,
                value: '${chargePower.toStringAsFixed(0)} kW',
              ),
              _ScenarioChip(
                label: l10n.dischargePower,
                value: '${dischargePower.toStringAsFixed(0)} kW',
              ),
              _ScenarioChip(
                label: l10n.optimizationReserveBand,
                value:
                    '${(socMin * 100).toStringAsFixed(0)}% - ${(socMax * 100).toStringAsFixed(0)}%',
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SliderField(
            label: l10n.batteryCapacity,
            value: batteryCapacity,
            min: 5,
            max: 300,
            suffix: 'kWh',
            onChanged: batteryEnabled
                ? (value) => onChanged(batteryCapacity: value)
                : null,
          ),
          _SliderField(
            label: l10n.chargePower,
            value: chargePower,
            min: 2,
            max: 120,
            suffix: 'kW',
            onChanged: batteryEnabled
                ? (value) => onChanged(chargePower: value)
                : null,
          ),
          _SliderField(
            label: l10n.dischargePower,
            value: dischargePower,
            min: 2,
            max: 120,
            suffix: 'kW',
            onChanged: batteryEnabled
                ? (value) => onChanged(dischargePower: value)
                : null,
          ),
          _SliderField(
            label: l10n.initialCharge,
            value: socInit * 100,
            min: 10,
            max: 90,
            suffix: '%',
            onChanged: batteryEnabled
                ? (value) => onChanged(socInit: value / 100)
                : null,
          ),
          _SliderField(
            label: l10n.minCharge,
            value: socMin * 100,
            min: 0,
            max: 40,
            suffix: '%',
            onChanged: batteryEnabled
                ? (value) {
                    final normalized = value / 100;
                    onChanged(
                      socMin: normalized,
                      socInit: math.max(socInit, normalized),
                    );
                  }
                : null,
          ),
          _SliderField(
            label: l10n.maxCharge,
            value: socMax * 100,
            min: 60,
            max: 100,
            suffix: '%',
            onChanged: batteryEnabled
                ? (value) {
                    final normalized = value / 100;
                    onChanged(
                      socMax: normalized,
                      socInit: math.min(socInit, normalized),
                    );
                  }
                : null,
          ),
        ],
      ),
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

class _OptimizationGuideCard extends StatelessWidget {
  const _OptimizationGuideCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final steps = [
      (
        icon: Icons.tune_rounded,
        title: l10n.optimizationGuideConfigureTitle,
        body: l10n.optimizationGuideConfigureBody,
      ),
      (
        icon: Icons.play_circle_outline_rounded,
        title: l10n.optimizationGuideRunTitle,
        body: l10n.optimizationGuideRunBody,
      ),
      (
        icon: Icons.insights_outlined,
        title: l10n.optimizationGuideReviewTitle,
        body: l10n.optimizationGuideReviewBody,
      ),
    ];

    return AppCard(
      animated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: l10n.optimizationGuideTitle,
            subtitle: l10n.optimizationGuideSubtitle,
          ),
          const SizedBox(height: 18),
          AdaptiveMetricGrid(
            maxColumns: 3,
            children: [
              for (var index = 0; index < steps.length; index++)
                _OptimizationStepCard(
                  index: index + 1,
                  icon: steps[index].icon,
                  title: steps[index].title,
                  body: steps[index].body,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OptimizationStepCard extends StatelessWidget {
  const _OptimizationStepCard({
    required this.index,
    required this.icon,
    required this.title,
    required this.body,
  });

  final int index;
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accent.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Stack(
              children: [
                Center(child: Icon(icon, color: accent, size: 20)),
                Positioned(
                  right: 6,
                  top: 4,
                  child: Text(
                    '$index',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            body,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              height: 1.6,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScenarioChip extends StatelessWidget {
  const _ScenarioChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _SliderField extends StatelessWidget {
  const _SliderField({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.suffix,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String suffix;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    final stacked = MediaQuery.sizeOf(context).width < 480;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (stacked) ...[
          Text(label, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text('${value.toStringAsFixed(0)} $suffix'),
        ] else
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text('${value.toStringAsFixed(0)} $suffix'),
            ],
          ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _OptimizationChartCard extends StatelessWidget {
  const _OptimizationChartCard({
    required this.title,
    required this.subtitle,
    required this.timestamps,
    required this.load,
    required this.renewable,
    required this.after,
    required this.maxY,
  });

  final String title;
  final String subtitle;
  final List<String> timestamps;
  final List<double> load;
  final List<double> renewable;
  final List<double> after;
  final double maxY;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final localeTag = Localizations.localeOf(context).toLanguageTag();
    final theme = Theme.of(context);
    final isCompact = MediaQuery.sizeOf(context).width < 760;
    final maxPoints = math.min(
      timestamps.length,
      math.min(load.length, renewable.length),
    );
    final bottomInterval = _resolveChartBottomInterval(maxPoints, isCompact);
    final yInterval = _resolveChartAxisInterval(maxY);
    final spotsLoad = [
      for (var i = 0; i < maxPoints; i++) FlSpot(i.toDouble(), load[i]),
    ];
    final spotsRenewable = [
      for (var i = 0; i < maxPoints; i++) FlSpot(i.toDouble(), renewable[i]),
    ];
    final spotsAfter = [
      for (var i = 0; i < maxPoints && i < after.length; i++)
        FlSpot(i.toDouble(), after[i]),
    ];

    return AppCard(
      animated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: title, subtitle: subtitle),
          const SizedBox(height: 18),
          SizedBox(
            height: 320,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: maxY * 1.15,
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: yInterval,
                ),
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
                      reservedSize: 46,
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      minIncluded: true,
                      maxIncluded: true,
                      showTitles: true,
                      reservedSize: 64,
                      interval: bottomInterval,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 ||
                            index >= maxPoints ||
                            index >= timestamps.length) {
                          return const SizedBox.shrink();
                        }
                        final dt = DateTime.tryParse(
                          timestamps[index],
                        )?.toLocal();
                        if (dt == null) {
                          return const SizedBox.shrink();
                        }
                        return chartAxisLabel(
                          context,
                          meta,
                          value,
                          chartDateTimeLabel(dt, localeTag),
                        );
                      },
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  handleBuiltInTouches: true,
                  touchTooltipData: LineTouchTooltipData(
                    maxContentWidth: isCompact ? 220 : 260,
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
                      if (index < 0 || index >= maxPoints) {
                        return const <LineTooltipItem?>[];
                      }
                      final dt = DateTime.tryParse(
                        timestamps[index],
                      )?.toLocal();
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
                          '${dt == null ? '' : formatDateTimeLabel(dt, localeTag)}\n',
                          labelStyle ?? const TextStyle(color: Colors.white70),
                          children: [
                            TextSpan(
                              text: '${l10n.loadDemand}: ',
                              style: labelStyle,
                            ),
                            TextSpan(
                              text:
                                  '${formatNumber(load[index], localeTag, digits: 2)} kW\n',
                              style: valueStyle?.copyWith(
                                color: theme.colorScheme.secondary,
                              ),
                            ),
                            TextSpan(
                              text: '${l10n.renewable}: ',
                              style: labelStyle,
                            ),
                            TextSpan(
                              text:
                                  '${formatNumber(renewable[index], localeTag, digits: 2)} kW\n',
                              style: valueStyle?.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            TextSpan(
                              text: '${l10n.gridImportAfter}: ',
                              style: labelStyle,
                            ),
                            TextSpan(
                              text:
                                  '${formatNumber(index < after.length ? after[index] : 0, localeTag, digits: 2)} kW',
                              style: valueStyle?.copyWith(
                                color: theme.colorScheme.tertiary,
                              ),
                            ),
                          ],
                        );
                      });
                    },
                  ),
                ),
                lineBarsData: [
                  _line(spotsLoad, Theme.of(context).colorScheme.secondary),
                  _line(spotsRenewable, Theme.of(context).colorScheme.primary),
                  _line(spotsAfter, Theme.of(context).colorScheme.tertiary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  LineChartBarData _line(List<FlSpot> spots, Color color) {
    return LineChartBarData(
      spots: spots,
      isCurved: false,
      barWidth: 2.8,
      color: color,
      dotData: const FlDotData(show: false),
    );
  }
}

class _SocCard extends StatelessWidget {
  const _SocCard({
    required this.soc,
    required this.timestamps,
    required this.maxY,
  });

  final List<double> soc;
  final List<String> timestamps;
  final double maxY;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final localeTag = Localizations.localeOf(context).toLanguageTag();
    final theme = Theme.of(context);
    final isCompact = MediaQuery.sizeOf(context).width < 760;
    final maxPoints = math.min(soc.length, timestamps.length);
    final bottomInterval = _resolveChartBottomInterval(maxPoints, isCompact);
    final yInterval = _resolveChartAxisInterval(maxY);

    return AppCard(
      animated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: l10n.batterySoc,
            subtitle: l10n.batterySocSubtitle,
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 250,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: maxY * 1.15,
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: yInterval,
                ),
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
                      reservedSize: 46,
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      minIncluded: true,
                      maxIncluded: true,
                      showTitles: true,
                      reservedSize: 64,
                      interval: bottomInterval,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 ||
                            index >= maxPoints ||
                            index >= timestamps.length) {
                          return const SizedBox.shrink();
                        }
                        final dt = DateTime.tryParse(
                          timestamps[index],
                        )?.toLocal();
                        if (dt == null) {
                          return const SizedBox.shrink();
                        }
                        return chartAxisLabel(
                          context,
                          meta,
                          value,
                          chartDateTimeLabel(dt, localeTag),
                        );
                      },
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  handleBuiltInTouches: true,
                  touchTooltipData: LineTouchTooltipData(
                    maxContentWidth: isCompact ? 200 : 220,
                    tooltipBorderRadius: BorderRadius.circular(18),
                    tooltipPadding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    getTooltipColor: (_) => const Color(0xFF24314B),
                    getTooltipItems: (touchedSpots) {
                      if (touchedSpots.isEmpty) {
                        return const <LineTooltipItem?>[];
                      }
                      final index = touchedSpots.first.spotIndex;
                      if (index < 0 || index >= maxPoints) {
                        return const <LineTooltipItem?>[];
                      }
                      final dt = DateTime.tryParse(
                        timestamps[index],
                      )?.toLocal();
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
                      return [
                        LineTooltipItem(
                          '${dt == null ? '' : formatDateTimeLabel(dt, localeTag)}\n',
                          labelStyle ?? const TextStyle(color: Colors.white70),
                          children: [
                            TextSpan(
                              text: '${l10n.batterySoc}: ',
                              style: labelStyle,
                            ),
                            TextSpan(
                              text:
                                  '${formatNumber(soc[index], localeTag, digits: 2)} kWh',
                              style: valueStyle?.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ];
                    },
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: [
                      for (var i = 0; i < maxPoints; i++)
                        FlSpot(i.toDouble(), soc[i]),
                    ],
                    isCurved: false,
                    color: Theme.of(context).colorScheme.primary,
                    barWidth: 3,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.10),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

double _resolveChartAxisInterval(double maxValue) {
  final rough = math.max(1, maxValue / 4);
  if (rough >= 100) {
    return (rough / 50).ceil() * 50.0;
  }
  if (rough >= 50) {
    return (rough / 25).ceil() * 25.0;
  }
  if (rough >= 10) {
    return (rough / 5).ceil() * 5.0;
  }
  if (rough >= 5) {
    return (rough / 2).ceil() * 2.0;
  }
  return double.parse(rough.toStringAsFixed(1));
}

double _resolveChartBottomInterval(int pointCount, bool isCompact) {
  final targetDivisions = isCompact ? 4 : 6;
  return math.max(1, (pointCount / targetDivisions).floor()).toDouble();
}
