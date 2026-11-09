import '../../../core/widgets/aligned_panel_grid.dart';
import '../../../core/widgets/chart_axis_label.dart';
import '../../../core/widgets/adaptive_metric_grid.dart';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_city_renewable_ai/l10n/app_localizations.dart';

import '../../../core/extensions/async_value_x.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/utils/forecast_utils.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_animated_content.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/app_fields.dart';
import '../../../core/widgets/loading_state.dart';
import '../../../core/widgets/metric_tile.dart';
import '../../../core/widgets/section_header.dart';
import '../../../data/models/energy_site.dart';
import '../../../data/models/user_profile.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  static const _trendPointLimit = 288;

  String? _selectedSiteId;
  String? _loadedSiteId;
  Future<_DashboardBundle>? _future;

  Future<_DashboardBundle> _load(
    EnergySite site, {
    bool refresh = false,
  }) async {
    final api = ref.read(cloudRunApiProvider);
    if (refresh) api.clearCache();
    final forecast7Future = api.fetchForecast(
      lat: site.latitude,
      lon: site.longitude,
      days: 7,
      capacityKw: site.solarCapacityKw,
      tiltDeg: site.tiltDeg,
      azimuthDeg: site.azimuthDeg,
      windCapacityKw: site.windCapacityKw,
      windHubHeightM: site.windHubHeightM,
    );
    final forecast14Future = api.fetchForecast(
      lat: site.latitude,
      lon: site.longitude,
      days: 14,
      capacityKw: site.solarCapacityKw,
      tiltDeg: site.tiltDeg,
      azimuthDeg: site.azimuthDeg,
      windCapacityKw: site.windCapacityKw,
      windHubHeightM: site.windHubHeightM,
    );
    final balanceFuture = api.fetchEnergyBalance(
      lat: site.latitude,
      lon: site.longitude,
      days: 7,
      deviceId: site.id,
      capacityKw: site.solarCapacityKw,
      tiltDeg: site.tiltDeg,
      azimuthDeg: site.azimuthDeg,
      windCapacityKw: site.windCapacityKw,
      windHubHeightM: site.windHubHeightM,
    );
    final meteoFuture = () async {
      try {
        return await api.fetchMeteo(
          lat: site.latitude,
          lon: site.longitude,
          hours: 24,
          stepMinutes: 60,
          timeout: const Duration(seconds: 8),
          retries: 0,
        );
      } catch (_) {
        return null;
      }
    }();

    final responses = await Future.wait([
      forecast7Future,
      forecast14Future,
      balanceFuture,
    ], eagerError: true);
    final forecast7 = parseForecast(responses[0]);
    final forecast14 = parseForecast(responses[1]);
    final rawBalance = responses[2];
    final balance = parseBalance(rawBalance);

    return _DashboardBundle(
      forecast7: forecast7,
      forecast14: forecast14,
      balance7: balance,
      rawBalance: rawBalance,
      meteo: meteoFuture,
    );
  }

  void _refresh(EnergySite site) {
    setState(() {
      _loadedSiteId = site.forecastKey;
      _future = _load(site, refresh: true);
    });
  }

  Future<void> _handleSiteChanged(
    String? siteId,
    List<EnergySite> sites,
    UserProfile? profile,
  ) async {
    if (siteId == null) {
      return;
    }
    final nextSite = _findSiteById(sites, siteId);
    if (nextSite == null) {
      return;
    }

    setState(() {
      _selectedSiteId = siteId;
      _loadedSiteId = nextSite.forecastKey;
      _future = _load(nextSite);
    });

    if (profile == null || profile.defaultSiteId == siteId) {
      return;
    }

    try {
      await ref
          .read(firestoreRepositoryProvider)
          .setDefaultSiteForUser(uid: profile.uid, siteId: siteId);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).dashboardDefaultSiteSaved),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).dashboardDefaultSiteSaveError,
          ),
        ),
      );
    }
  }

  EnergySite? _resolveActiveSite(
    List<EnergySite> sites,
    EnergySite? preferredSite,
  ) {
    if (sites.isEmpty) {
      return preferredSite;
    }
    final localSite = _findSiteById(sites, _selectedSiteId);
    if (localSite != null) {
      return localSite;
    }
    if (preferredSite != null) {
      return _findSiteById(sites, preferredSite.id) ?? preferredSite;
    }
    return sites.first;
  }

  EnergySite? _findSiteById(List<EnergySite> sites, String? siteId) {
    if (siteId == null) {
      return null;
    }
    for (final site in sites) {
      if (site.id == siteId) {
        return site;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final localeTag = Localizations.localeOf(context).toLanguageTag();
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    final sitesAsync = ref.watch(currentUserSitesProvider);
    final sites = sitesAsync.valueOrNull ?? const <EnergySite>[];
    final preferredSite = ref.watch(selectedSiteProvider);
    final meta = ref.watch(forecastMetaProvider).valueOrNull;

    if (sitesAsync.isLoading && preferredSite == null) {
      return LoadingState(
        title: l10n.dashboardHeroTitle,
        subtitle: l10n.dashboardHeroSubtitle,
      );
    }

    final site = _resolveActiveSite(sites, preferredSite);
    if (site == null) {
      return EmptyState(
        icon: Icons.location_off_outlined,
        title: l10n.noSiteTitle,
        message: l10n.noSiteMessage,
        actionLabel: l10n.goToSites,
        onAction: () => context.go('/sites'),
      );
    }

    if (_loadedSiteId != site.forecastKey || _future == null) {
      _loadedSiteId = site.forecastKey;
      _future = _load(site);
    }

    return FutureBuilder<_DashboardBundle>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return EmptyState(
            icon: Icons.error_outline_rounded,
            title: l10n.loadFailed,
            message: '${l10n.fetchErrorGeneric}\n${snapshot.error}',
            actionLabel: l10n.retry,
            onAction: () => _refresh(site),
          );
        }

        if (!snapshot.hasData) {
          return LoadingState(
            title: l10n.dashboardHeroTitle,
            subtitle: l10n.dashboardHeroSubtitle,
          );
        }

        final data = snapshot.data!;
        final renewable7 =
            data.forecast7.fold<double>(
              0,
              (sum, point) => sum + point.solarWh + point.windWh,
            ) /
            1000;
        final renewable14 =
            data.forecast14.fold<double>(
              0,
              (sum, point) => sum + point.solarWh + point.windWh,
            ) /
            1000;
        final solar7 =
            data.forecast7.fold<double>(
              0,
              (sum, point) => sum + point.solarWh,
            ) /
            1000;
        final wind7 =
            data.forecast7.fold<double>(0, (sum, point) => sum + point.windWh) /
            1000;
        final risk = averageExtremeRisk(data.forecast7);
        final peakKw = peakRenewableKw(data.forecast7);
        final totalLoad = asDouble(data.rawBalance['total_load_kwh']);
        final deficit = asDouble(data.rawBalance['total_deficit_kwh']);
        final selfSufficiency = totalLoad <= 0
            ? 0.0
            : (1 - (deficit / totalLoad)).clamp(0.0, 1.0);
        final gridDependency = (1 - selfSufficiency).clamp(0.0, 1.0);
        final trendPoints = data.balance7
            .take(math.min(data.balance7.length, _trendPointLimit))
            .toList(growable: false);
        final focus = _buildOperationalFocus(
          context: context,
          forecast: data.forecast7,
          trendPoints: trendPoints,
          risk: risk,
          selfSufficiency: selfSufficiency,
          solarKwh: solar7,
          windKwh: wind7,
        );

        final metrics = <Widget>[
          MetricTile(
            label: l10n.forecast7Day,
            value: formatEnergy(renewable7, localeTag),
            caption: site.city,
            icon: Icons.auto_graph_rounded,
          ),
          MetricTile(
            label: l10n.forecast14Day,
            value: formatEnergy(renewable14, localeTag),
            caption: l10n.renewableTotal,
            icon: Icons.calendar_view_week_rounded,
            color: Theme.of(context).colorScheme.secondary,
          ),
          MetricTile(
            label: l10n.peakRenewable,
            value: formatPower(peakKw, localeTag),
            caption: focus.peakWindow,
            icon: Icons.flash_on_rounded,
            color: Theme.of(context).colorScheme.tertiary,
          ),
          MetricTile(
            label: l10n.selfSufficiency,
            value: formatPercent(selfSufficiency, localeTag),
            caption: l10n.systemStatus,
            icon: Icons.bolt_rounded,
            color: const Color(0xFF126A80),
          ),
          MetricTile(
            label: l10n.extremeRisk,
            value: formatPercent(risk, localeTag),
            caption: l10n.averageRisk,
            icon: Icons.warning_amber_rounded,
            color: const Color(0xFFB97522),
          ),
          MetricTile(
            label: l10n.dashboardGridDependency,
            value: formatPercent(gridDependency, localeTag),
            caption: l10n.dashboardGridDependencyHint,
            icon: Icons.power_outlined,
            color: const Color(0xFF7A64D8),
          ),
        ];

        final heroSection = AppCard(
          animated: true,
          child: _HeroOverview(
            site: site,
            profile: profile,
            focus: focus,
            localeTag: localeTag,
            risk: risk,
            selfSufficiency: selfSufficiency,
          ),
        );

        final siteControl = _SiteControlCard(
          currentSite: site,
          sites: sites,
          profile: profile,
          localeTag: localeTag,
          modelLabel: meta == null
              ? l10n.unknown
              : '${meta['model_name']} / ${meta['model_version']}\n${meta['quality_model'] ?? ''}',
          onSiteChanged: (value) => _handleSiteChanged(value, sites, profile),
          isRefreshing: snapshot.connectionState == ConnectionState.waiting,
          onRefresh: () => _refresh(site),
        );

        return AppAnimatedContent(
          contentKey: site.id,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AlignedPanelGrid(
                  key: const ValueKey('dashboard-overview-row'),
                  children: [heroSection, siteControl],
                ),
                const SizedBox(height: 16),
                _ResponsiveMetricGrid(children: metrics),
                const SizedBox(height: 16),
                _TrendCard(points: trendPoints),
                const SizedBox(height: 16),
                AlignedPanelGrid(
                  key: const ValueKey('dashboard-context-row'),
                  maxColumns: 3,
                  minPanelWidth: 360,
                  children: [
                    _OperationalFocusCard(
                      focus: focus,
                      localeTag: localeTag,
                      risk: risk,
                      selfSufficiency: selfSufficiency,
                    ),
                    _MixCard(solarKwh: solar7, windKwh: wind7, peakKw: peakKw),
                    FutureBuilder<Map<String, dynamic>?>(
                      future: data.meteo,
                      builder: (_, weather) =>
                          _WeatherCard(meteo: weather.data),
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

  _OperationalFocus _buildOperationalFocus({
    required BuildContext context,
    required List<ForecastPoint> forecast,
    required List<BalancePoint> trendPoints,
    required double risk,
    required double selfSufficiency,
    required double solarKwh,
    required double windKwh,
  }) {
    final l10n = AppLocalizations.of(context);
    final localeTag = Localizations.localeOf(context).toLanguageTag();

    final peakPoint = trendPoints.isEmpty
        ? null
        : trendPoints.reduce((a, b) => a.renewableKw >= b.renewableKw ? a : b);
    final stepMinutes = forecast.isEmpty ? 15 : forecast.first.stepMinutes;
    final peakWindow = peakPoint == null
        ? l10n.unknown
        : '${formatTimeLabel(peakPoint.time, localeTag)} - '
              '${formatTimeLabel(peakPoint.time.add(Duration(minutes: stepMinutes)), localeTag)}';

    if (selfSufficiency < 0.45) {
      return _OperationalFocus(
        modeLabel: l10n.dashboardGridMode,
        recommendation: l10n.dashboardGridAction,
        peakWindow: peakWindow,
        icon: Icons.power_rounded,
        accent: const Color(0xFF7A64D8),
      );
    }
    if (solarKwh >= windKwh * 1.20 && solarKwh > 0) {
      return _OperationalFocus(
        modeLabel: l10n.dashboardSolarMode,
        recommendation: l10n.dashboardSolarAction,
        peakWindow: peakWindow,
        icon: Icons.wb_sunny_rounded,
        accent: Theme.of(context).colorScheme.tertiary,
      );
    }
    if (windKwh > solarKwh * 1.05) {
      return _OperationalFocus(
        modeLabel: l10n.dashboardWindMode,
        recommendation: l10n.dashboardWindAction,
        peakWindow: peakWindow,
        icon: Icons.air_rounded,
        accent: Theme.of(context).colorScheme.secondary,
      );
    }
    return _OperationalFocus(
      modeLabel: l10n.dashboardStableMode,
      recommendation: l10n.dashboardStableAction,
      peakWindow: peakWindow,
      icon: Icons.eco_rounded,
      accent: Theme.of(context).colorScheme.primary,
    );
  }
}

class _HeroCopy extends StatelessWidget {
  const _HeroCopy({
    required this.site,
    required this.profile,
    required this.focus,
  });

  final EnergySite site;
  final UserProfile? profile;
  final _OperationalFocus focus;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final localeTag = Localizations.localeOf(context).toLanguageTag();
    final isCompact = MediaQuery.sizeOf(context).width < 760;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.dashboardHeroTitle,
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
            fontSize: isCompact ? 28 : 34,
            height: isCompact ? 1.08 : null,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          l10n.dashboardHeroSubtitle,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _InfoChip(label: l10n.activeSite, value: site.name),
            _InfoChip(label: l10n.city, value: profile?.city ?? site.city),
            _InfoChip(
              label: l10n.dashboardCoverageMode,
              value: focus.modeLabel,
              accent: focus.accent,
            ),
            _InfoChip(
              label: l10n.latitude,
              value: formatNumber(site.latitude, localeTag, digits: 3),
            ),
          ],
        ),
      ],
    );
  }
}

class _HeroOverview extends StatelessWidget {
  const _HeroOverview({
    required this.site,
    required this.profile,
    required this.focus,
    required this.localeTag,
    required this.risk,
    required this.selfSufficiency,
  });

  final EnergySite site;
  final UserProfile? profile;
  final _OperationalFocus focus;
  final String localeTag;
  final double risk;
  final double selfSufficiency;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 940;
        final recommendationCard = Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: focus.accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: focus.accent.withValues(alpha: 0.24)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: focus.accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(focus.icon, color: focus.accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.dashboardOperationalFocusTitle,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      focus.recommendation,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
        final quickFacts = Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _InfoChip(
              label: l10n.dashboardPeakWindow,
              value: focus.peakWindow,
              accent: focus.accent,
            ),
            _InfoChip(
              label: l10n.extremeRisk,
              value: formatPercent(risk, localeTag),
            ),
            _InfoChip(
              label: l10n.selfSufficiency,
              value: formatPercent(selfSufficiency, localeTag),
            ),
          ],
        );

        if (!isWide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HeroCopy(site: site, profile: profile, focus: focus),
              const SizedBox(height: 20),
              recommendationCard,
              const SizedBox(height: 18),
              quickFacts,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 6,
              child: _HeroCopy(site: site, profile: profile, focus: focus),
            ),
            const SizedBox(width: 18),
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  recommendationCard,
                  const SizedBox(height: 18),
                  quickFacts,
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SiteControlCard extends StatelessWidget {
  const _SiteControlCard({
    required this.currentSite,
    required this.sites,
    required this.profile,
    required this.localeTag,
    required this.modelLabel,
    required this.onSiteChanged,
    required this.onRefresh,
    required this.isRefreshing,
  });

  final EnergySite currentSite;
  final List<EnergySite> sites;
  final UserProfile? profile;
  final String localeTag;
  final String modelLabel;
  final Future<void> Function(String?) onSiteChanged;
  final VoidCallback onRefresh;
  final bool isRefreshing;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppCard(
      animated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: l10n.selectedSite,
            subtitle: l10n.dashboardSiteControlSubtitle,
            trailing: AppSecondaryButton(
              label: l10n.refresh,
              icon: const Icon(Icons.refresh_rounded),
              onPressed: onRefresh,
              isLoading: isRefreshing,
            ),
          ),
          const SizedBox(height: 18),
          AppDropdownMenuField<String>(
            label: l10n.dashboardInstalledPoints,
            selectedValue: currentSite.id,
            prefixIcon: const Icon(Icons.hub_rounded),
            options: [
              for (final site in sites)
                AppDropdownOption<String>(
                  value: site.id,
                  label: '${site.name} • ${site.city}',
                ),
            ],
            onSelected: (value) {
              onSiteChanged(value);
            },
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _InfoChip(label: l10n.defaultSite, value: currentSite.name),
              _InfoChip(
                label: l10n.address,
                value: currentSite.address.isEmpty
                    ? currentSite.city
                    : currentSite.address,
              ),
              _InfoChip(
                label: l10n.solarCapacity,
                value: formatPower(currentSite.solarCapacityKw, localeTag),
              ),
              _InfoChip(
                label: l10n.windCapacity,
                value: formatPower(currentSite.windCapacityKw, localeTag),
              ),
              _InfoChip(
                label: l10n.batteryCapacity,
                value: formatEnergy(currentSite.batteryCapacityKwh, localeTag),
              ),
              _InfoChip(label: l10n.serverModel, value: modelLabel),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              AppSecondaryButton(
                label: l10n.goToSites,
                icon: const Icon(Icons.map_outlined),
                onPressed: () => context.go('/sites'),
              ),
              if (profile?.organization case final organization?
                  when organization.trim().isNotEmpty)
                _InfoChip(label: l10n.organization, value: organization),
            ],
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
      AdaptiveMetricGrid(maxColumns: 3, children: children);
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.points});

  final List<BalancePoint> points;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final localeTag = Localizations.localeOf(context).toLanguageTag();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final renewableColor = scheme.primary;
    final loadColor = scheme.secondary;
    final netColor = const Color(0xFF14A0B8);

    final maxY = points.isEmpty
        ? 1.0
        : points
              .map(
                (point) => math.max(
                  point.renewableKw,
                  math.max(point.loadKw, point.netLoadKw),
                ),
              )
              .reduce(math.max);
    final minY = points.isEmpty
        ? 0.0
        : points.map((point) => point.netLoadKw).reduce(math.min);

    return AppCard(
      animated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: l10n.next72Hours,
            subtitle: l10n.next72HoursSubtitle,
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 360,
            child: LineChart(
              LineChartData(
                minY: minY >= 0 ? 0 : minY * 1.15,
                maxY: maxY * 1.18,
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: math.max(1, maxY / 4),
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: scheme.outline.withValues(alpha: 0.85),
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
                      reservedSize: 46,
                      interval: math.max(1, maxY / 4),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      minIncluded: true,
                      maxIncluded: true,
                      showTitles: true,
                      reservedSize: 64,
                      interval: math
                          .max(1, (points.length / 6).floor())
                          .toDouble(),
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
                    maxContentWidth: 240,
                    tooltipBorderRadius: BorderRadius.circular(18),
                    tooltipPadding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    getTooltipColor: (_) => const Color(0xFF24314B),
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
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
                            TextSpan(
                              text: '${l10n.renewable}: ',
                              style: labelStyle,
                            ),
                            TextSpan(
                              text:
                                  '${formatNumber(point.renewableKw, localeTag, digits: 3)} kW\n',
                              style: valueStyle?.copyWith(
                                color: renewableColor,
                              ),
                            ),
                            TextSpan(
                              text: '${l10n.loadDemand}: ',
                              style: labelStyle,
                            ),
                            TextSpan(
                              text:
                                  '${formatNumber(point.loadKw, localeTag, digits: 3)} kW\n',
                              style: valueStyle?.copyWith(color: loadColor),
                            ),
                            TextSpan(
                              text: '${l10n.netLoad}: ',
                              style: labelStyle,
                            ),
                            TextSpan(
                              text:
                                  '${formatNumber(point.netLoadKw, localeTag, digits: 3)} kW',
                              style: valueStyle?.copyWith(color: netColor),
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
                        FlLine(
                          color: color.withValues(alpha: 0.28),
                          strokeWidth: 2,
                        ),
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
                    (point) => point.renewableKw,
                    renewableColor,
                    width: 3.2,
                    shaded: true,
                  ),
                  _line(points, (point) => point.loadKw, loadColor, width: 2.6),
                  _line(
                    points,
                    (point) => point.netLoadKw,
                    netColor,
                    width: 2.4,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _LegendDot(color: renewableColor, label: l10n.renewable),
              _LegendDot(color: loadColor, label: l10n.loadDemand),
              _LegendDot(color: netColor, label: l10n.netLoad),
            ],
          ),
        ],
      ),
    );
  }

  LineChartBarData _line(
    List<BalancePoint> points,
    double Function(BalancePoint point) selector,
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

class _OperationalFocusCard extends StatelessWidget {
  const _OperationalFocusCard({
    required this.focus,
    required this.localeTag,
    required this.risk,
    required this.selfSufficiency,
  });

  final _OperationalFocus focus;
  final String localeTag;
  final double risk;
  final double selfSufficiency;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppCard(
      animated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: focus.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(focus.icon, color: focus.accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.dashboardOperationalFocusTitle,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.dashboardOperationalFocusSubtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _InfoChip(
                label: l10n.dashboardCoverageMode,
                value: focus.modeLabel,
                accent: focus.accent,
              ),
              _InfoChip(
                label: l10n.dashboardPeakWindow,
                value: focus.peakWindow,
              ),
              _InfoChip(
                label: l10n.extremeRisk,
                value: formatPercent(risk, localeTag),
              ),
              _InfoChip(
                label: l10n.selfSufficiency,
                value: formatPercent(selfSufficiency, localeTag),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            l10n.dashboardRecommendedAction,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            focus.recommendation,
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

class _MixCard extends StatelessWidget {
  const _MixCard({
    required this.solarKwh,
    required this.windKwh,
    required this.peakKw,
  });

  final double solarKwh;
  final double windKwh;
  final double peakKw;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final localeTag = Localizations.localeOf(context).toLanguageTag();
    final total = math.max(0.1, solarKwh + windKwh);
    final solarRatio = solarKwh / total;
    final windRatio = windKwh / total;

    return AppCard(
      animated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: l10n.energyMix, subtitle: l10n.renewableTotal),
          const SizedBox(height: 20),
          _MixRow(
            label: l10n.solarTotal,
            value: formatEnergy(solarKwh, localeTag),
            ratio: solarRatio,
            color: Theme.of(context).colorScheme.tertiary,
          ),
          const SizedBox(height: 14),
          _MixRow(
            label: l10n.windTotal,
            value: formatEnergy(windKwh, localeTag),
            ratio: windRatio,
            color: Theme.of(context).colorScheme.secondary,
          ),
          const SizedBox(height: 18),
          Divider(color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 18),
          Text(
            l10n.peakRenewable,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            formatPower(peakKw, localeTag),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ],
      ),
    );
  }
}

class _WeatherCard extends StatelessWidget {
  const _WeatherCard({required this.meteo});

  final Map<String, dynamic>? meteo;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final localeTag = Localizations.localeOf(context).toLanguageTag();
    final hourly =
        meteo?['hourly'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    final temp = asDouble(_first(hourly['temperature_2m']));
    final wind = asDouble(_first(hourly['wind_speed_10m']));
    final humidity = asDouble(_first(hourly['relative_humidity_2m']));
    final radiation = asDouble(_first(hourly['shortwave_radiation']));

    return AppCard(
      animated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: l10n.weatherWindow,
            subtitle: l10n.weatherWindowSubtitle,
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _InfoChip(
                label: l10n.currentTemperature,
                value: _first(hourly['temperature_2m']) == null
                    ? l10n.unknown
                    : '${formatNumber(temp, localeTag, digits: 1)} °C',
              ),
              _InfoChip(
                label: l10n.windSpeed,
                value: _first(hourly['wind_speed_10m']) == null
                    ? l10n.unknown
                    : '${formatNumber(wind, localeTag, digits: 1)} m/s',
              ),
              _InfoChip(
                label: l10n.humidity,
                value: _first(hourly['relative_humidity_2m']) == null
                    ? l10n.unknown
                    : '${formatNumber(humidity, localeTag)}%',
              ),
              _InfoChip(
                label: l10n.solarRadiation,
                value: _first(hourly['shortwave_radiation']) == null
                    ? l10n.unknown
                    : '${formatNumber(radiation, localeTag)} W/m²',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Object? _first(Object? value) {
    if (value is List && value.isNotEmpty) {
      return value.first;
    }
    return null;
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.value, this.accent});

  final String label;
  final String value;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final borderColor = accent ?? Theme.of(context).colorScheme.outline;
    final fillColor = accent?.withValues(alpha: 0.08);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: fillColor ?? Colors.white.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor.withValues(alpha: 0.72)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: accent ?? Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MixRow extends StatelessWidget {
  const _MixRow({
    required this.label,
    required this.value,
    required this.ratio,
    required this.color,
  });

  final String label;
  final String value;
  final double ratio;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: ratio.clamp(0.0, 1.0),
            minHeight: 10,
            color: color,
            backgroundColor: color.withValues(alpha: 0.14),
          ),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _DashboardBundle {
  const _DashboardBundle({
    required this.forecast7,
    required this.forecast14,
    required this.balance7,
    required this.rawBalance,
    required this.meteo,
  });

  final List<ForecastPoint> forecast7;
  final List<ForecastPoint> forecast14;
  final List<BalancePoint> balance7;
  final Map<String, dynamic> rawBalance;
  final Future<Map<String, dynamic>?> meteo;
}

class _OperationalFocus {
  const _OperationalFocus({
    required this.modeLabel,
    required this.recommendation,
    required this.peakWindow,
    required this.icon,
    required this.accent,
  });

  final String modeLabel;
  final String recommendation;
  final String peakWindow;
  final IconData icon;
  final Color accent;
}
