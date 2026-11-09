import '../../../core/widgets/aligned_panel_grid.dart';
import '../../../core/widgets/adaptive_metric_grid.dart';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:smart_city_renewable_ai/l10n/app_localizations.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/extensions/async_value_x.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/utils/forecast_utils.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_animated_content.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/app_fields.dart';
import '../../../core/widgets/metric_tile.dart';
import '../../../core/widgets/section_header.dart';
import '../../../data/models/energy_site.dart';

class SitesMapPage extends ConsumerStatefulWidget {
  const SitesMapPage({super.key});

  @override
  ConsumerState<SitesMapPage> createState() => _SitesMapPageState();
}

enum _SiteAnalyticsRange { today, week7, week14 }

void _openForecastDayRoute(
  BuildContext context,
  DateTime day, {
  required int days,
}) {
  final dayKey =
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';
  context.push('/forecast/day/$dayKey?days=$days');
}

class _SitesMapPageState extends ConsumerState<SitesMapPage> {
  final MapController _mapController = MapController();
  LatLng? _draftPoint;
  String? _selectedSiteId;
  String? _analyticsSiteId;
  Future<_SiteAnalyticsBundle>? _analyticsFuture;
  _SiteAnalyticsRange _range = _SiteAnalyticsRange.today;

  Future<void> _openSiteDialog({EnergySite? existing}) async {
    final user = ref.read(firebaseUserProvider).valueOrNull;
    if (user == null) {
      return;
    }
    final isCompact = MediaQuery.sizeOf(context).width < 760;
    final navigator = Navigator.of(context);
    EnergySite? saved;
    if (isCompact) {
      saved = await navigator.push<EnergySite>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (context) {
            return _SiteEditorDialog(
              ownerUid: user.uid,
              existing: existing,
              draftPoint: _draftPoint,
              fullscreen: true,
            );
          },
        ),
      );
    } else {
      saved = await showDialog<EnergySite>(
        context: navigator.context,
        builder: (context) {
          return _SiteEditorDialog(
            ownerUid: user.uid,
            existing: existing,
            draftPoint: _draftPoint,
          );
        },
      );
    }
    if (saved == null) {
      return;
    }
    final repo = ref.read(firestoreRepositoryProvider);
    final siteId = await repo.saveSite(saved);
    if (existing == null) {
      await repo.setDefaultSiteForUser(uid: user.uid, siteId: siteId);
    }
    final persistedSite = saved.copyWith(id: siteId);
    setState(() {
      _draftPoint = null;
      _selectedSiteId = persistedSite.id;
      _bindAnalytics(persistedSite, refresh: true);
    });
    _mapController.move(
      LatLng(persistedSite.latitude, persistedSite.longitude),
      11,
    );
    if (!mounted) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.siteSaved),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _deleteSite(EnergySite site) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(l10n.delete),
          content: Text(l10n.deleteSiteConfirm),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.delete),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }
    await ref.read(firestoreRepositoryProvider).deleteSite(site.id);
    if (_selectedSiteId == site.id) {
      setState(() {
        _selectedSiteId = null;
        _analyticsSiteId = null;
        _analyticsFuture = null;
      });
    }
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.siteDeleted),
        behavior: SnackBarBehavior.floating,
      ),
    );
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

  EnergySite? _resolveActiveSite(
    List<EnergySite> sites,
    EnergySite? preferredSite,
  ) {
    if (sites.isEmpty) {
      return null;
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

  Future<_SiteAnalyticsBundle> _analyticsForSite(
    EnergySite site, {
    bool refresh = false,
  }) {
    return _loadSiteAnalytics(site, refresh: refresh);
  }

  void _bindAnalytics(EnergySite site, {bool refresh = false}) {
    _analyticsSiteId = site.forecastKey;
    _analyticsFuture = _analyticsForSite(site, refresh: refresh);
  }

  Future<void> _selectSite(EnergySite site) async {
    setState(() {
      _draftPoint = null;
      _selectedSiteId = site.id;
      _bindAnalytics(site);
    });
    _mapController.move(LatLng(site.latitude, site.longitude), 11);
  }

  Future<_SiteAnalyticsBundle> _loadSiteAnalytics(
    EnergySite site, {
    bool refresh = false,
  }) async {
    final api = ref.read(cloudRunApiProvider);
    final forecast7 = api.fetchForecast(
      lat: site.latitude,
      lon: site.longitude,
      days: 7,
      forceRefresh: refresh,
      capacityKw: site.solarCapacityKw,
      tiltDeg: site.tiltDeg,
      azimuthDeg: site.azimuthDeg,
      windCapacityKw: site.windCapacityKw,
      windHubHeightM: site.windHubHeightM,
    );
    final forecast14 = api.fetchForecast(
      lat: site.latitude,
      lon: site.longitude,
      days: 14,
      forceRefresh: refresh,
      capacityKw: site.solarCapacityKw,
      tiltDeg: site.tiltDeg,
      azimuthDeg: site.azimuthDeg,
      windCapacityKw: site.windCapacityKw,
      windHubHeightM: site.windHubHeightM,
    );
    final results = await Future.wait([
      forecast7,
      forecast14,
    ], eagerError: true);
    final points7 = parseForecast(results[0]);
    final points14 = parseForecast(results[1]);
    final todayPoints = _extractTodayPoints(points7);
    final todayDay = todayPoints.isEmpty
        ? null
        : _dateOnly(todayPoints.first.time);
    final markerX = _resolveCurrentHourMarker(todayPoints, todayDay);

    return _SiteAnalyticsBundle(
      todayDay: todayDay,
      todayPoints: todayPoints,
      todayMarkerX: markerX,
      daily7: aggregateDaily(points7),
      daily14: aggregateDaily(points14),
    );
  }

  List<ForecastPoint> _extractTodayPoints(List<ForecastPoint> points) {
    if (points.isEmpty) {
      return const <ForecastPoint>[];
    }
    final now = _dateOnly(DateTime.now());
    final matchingToday = points
        .where((point) => _dateOnly(point.time) == now)
        .toList(growable: false);
    if (matchingToday.isNotEmpty) {
      return matchingToday;
    }
    final firstDay = _dateOnly(points.first.time);
    return points
        .where((point) => _dateOnly(point.time) == firstDay)
        .toList(growable: false);
  }

  double? _resolveCurrentHourMarker(
    List<ForecastPoint> points,
    DateTime? todayDay,
  ) {
    if (points.isEmpty || todayDay == null) {
      return null;
    }
    final now = DateTime.now();
    if (_dateOnly(now) != todayDay) {
      return null;
    }
    final stepMinutes = points.first.stepMinutes;
    final start = DateTime(
      todayDay.year,
      todayDay.month,
      todayDay.day,
      points.first.time.hour,
      points.first.time.minute,
    );
    final deltaMinutes = now.difference(start).inMinutes;
    if (deltaMinutes < 0) {
      return 0;
    }
    final marker = deltaMinutes / stepMinutes;
    return marker.clamp(0, math.max(0, points.length - 1)).toDouble();
  }

  DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  Future<void> _openFullscreenMap(
    List<EnergySite> sites,
    EnergySite? activeSite,
  ) async {
    final result = await Navigator.of(context).push<_SiteMapFullscreenResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) {
          return _SiteMapFullscreenPage(
            sites: sites,
            initialSiteId: activeSite?.id,
            initialCenter: activeSite != null
                ? LatLng(activeSite.latitude, activeSite.longitude)
                : _draftPoint ??
                      const LatLng(
                        AppConstants.defaultLatitude,
                        AppConstants.defaultLongitude,
                      ),
            initialRange: _range,
            loadAnalytics: (site) => _analyticsForSite(site),
          );
        },
      ),
    );
    if (!mounted || result == null) {
      return;
    }
    final selected = _findSiteById(sites, result.selectedSiteId);
    setState(() {
      _range = result.range;
      _selectedSiteId = result.selectedSiteId;
      _draftPoint = null;
      if (selected != null) {
        _bindAnalytics(selected);
      }
    });
    if (selected != null) {
      _mapController.move(LatLng(selected.latitude, selected.longitude), 11);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final localeTag = Localizations.localeOf(context).toLanguageTag();
    final sitesAsync = ref.watch(currentUserSitesProvider);
    final preferredSite = ref.watch(selectedSiteProvider);
    final user = ref.watch(firebaseUserProvider).valueOrNull;

    return sitesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, error) => EmptyState(
        icon: Icons.error_outline_rounded,
        title: l10n.loadFailed,
        message: l10n.fetchErrorGeneric,
      ),
      data: (sites) {
        final activeSite = _resolveActiveSite(sites, preferredSite);
        if (activeSite != null &&
            (_analyticsFuture == null ||
                _analyticsSiteId != activeSite.forecastKey)) {
          _bindAnalytics(activeSite);
        }

        final center = activeSite != null
            ? LatLng(activeSite.latitude, activeSite.longitude)
            : _draftPoint ??
                  const LatLng(
                    AppConstants.defaultLatitude,
                    AppConstants.defaultLongitude,
                  );
        final markers = [
          for (final site in sites)
            Marker(
              point: LatLng(site.latitude, site.longitude),
              width: 76,
              height: 76,
              child: GestureDetector(
                onTap: () => _selectSite(site),
                child: _MapPin(isSelected: activeSite?.id == site.id),
              ),
            ),
          if (_draftPoint != null)
            Marker(
              point: _draftPoint!,
              width: 56,
              height: 56,
              child: const Icon(
                Icons.add_location_alt_rounded,
                color: Color(0xFFC27821),
                size: 34,
              ),
            ),
        ];

        final mapCard = AppCard(
          animated: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(title: l10n.sitesTitle, subtitle: l10n.mapLegend),
              const SizedBox(height: 18),
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: SizedBox(
                  height: MediaQuery.sizeOf(context).width < 760 ? 320 : 420,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: FlutterMap(
                          mapController: _mapController,
                          options: MapOptions(
                            initialCenter: center,
                            initialZoom: 10,
                            onTap: (_, point) {
                              setState(() => _draftPoint = point);
                            },
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'smart_city_renewable_ai',
                            ),
                            MarkerLayer(markers: markers),
                          ],
                        ),
                      ),
                      Positioned(
                        left: 16,
                        top: 16,
                        child: _MapOverlayIconButton(
                          icon: Icons.open_in_full_rounded,
                          tooltip: l10n.openFullscreenMap,
                          onTap: () => _openFullscreenMap(sites, activeSite),
                        ),
                      ),
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 16,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 260),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, animation) {
                            final slide = Tween<Offset>(
                              begin: const Offset(0, 0.12),
                              end: Offset.zero,
                            ).animate(animation);
                            return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: slide,
                                child: child,
                              ),
                            );
                          },
                          child: _draftPoint == null
                              ? const SizedBox.shrink()
                              : _MapDraftOverlay(
                                  key: const ValueKey('draft-overlay'),
                                  point: _draftPoint!,
                                  localeTag: localeTag,
                                  onDismiss: () {
                                    setState(() => _draftPoint = null);
                                  },
                                  onAddSite: () => _openSiteDialog(),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                l10n.tapMapToSelect,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        );

        final selectionPanel = activeSite == null
            ? _MapSelectionGuideCard(
                draftPoint: _draftPoint,
                localeTag: localeTag,
              )
            : _SelectedSiteSummaryCard(site: activeSite, localeTag: localeTag);

        final listCard = AppCard(
          animated: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(
                title: l10n.siteList,
                subtitle: l10n.siteListSubtitle,
              ),
              const SizedBox(height: 18),
              if (sites.isEmpty)
                EmptyState(
                  icon: Icons.location_off_rounded,
                  title: l10n.noSitesYet,
                  message: l10n.noSitesYetMessage,
                )
              else
                Column(
                  children: [
                    for (final site in sites) ...[
                      _SiteTile(
                        site: site,
                        selected: activeSite?.id == site.id,
                        isDefault: preferredSite?.id == site.id,
                        onSelect: () => _selectSite(site),
                        onEdit: () => _openSiteDialog(existing: site),
                        onDelete: () => _deleteSite(site),
                        onSetDefault:
                            user == null || preferredSite?.id == site.id
                            ? null
                            : () => ref
                                  .read(firestoreRepositoryProvider)
                                  .setDefaultSiteForUser(
                                    uid: user.uid,
                                    siteId: site.id,
                                  ),
                      ),
                      if (site != sites.last) const SizedBox(height: 12),
                    ],
                  ],
                ),
            ],
          ),
        );

        final details = activeSite == null
            ? const SizedBox.shrink()
            : FutureBuilder<_SiteAnalyticsBundle>(
                future: _analyticsFuture,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return EmptyState(
                      icon: Icons.analytics_outlined,
                      title: l10n.loadFailed,
                      message: l10n.fetchErrorGeneric,
                      actionLabel: l10n.retry,
                      onAction: () {
                        setState(() {
                          _bindAnalytics(activeSite, refresh: true);
                        });
                      },
                    );
                  }
                  if (!snapshot.hasData) {
                    return AppCard(
                      animated: true,
                      child: SizedBox(
                        height: 220,
                        child: Center(
                          child: CircularProgressIndicator(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    );
                  }
                  return _SiteAnalyticsCard(
                    site: activeSite,
                    bundle: snapshot.data!,
                    range: _range,
                    onRangeChanged: (range) {
                      setState(() => _range = range);
                    },
                    onOpenDay: (day, days) =>
                        _openForecastDayRoute(context, day, days: days),
                  );
                },
              );

        return AppAnimatedContent(
          contentKey: activeSite?.id ?? 'sites-map',
          child: SingleChildScrollView(
            child: Column(
              children: [
                AlignedPanelGrid(
                  key: const ValueKey('sites-overview-row'),
                  children: [mapCard, selectionPanel],
                ),
                if (activeSite != null) ...[
                  const SizedBox(height: 16),
                  details,
                ],
                const SizedBox(height: 16),
                listCard,
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SiteAnalyticsBundle {
  const _SiteAnalyticsBundle({
    required this.todayDay,
    required this.todayPoints,
    required this.todayMarkerX,
    required this.daily7,
    required this.daily14,
  });

  final DateTime? todayDay;
  final List<ForecastPoint> todayPoints;
  final double? todayMarkerX;
  final List<DailyForecastBucket> daily7;
  final List<DailyForecastBucket> daily14;
}

class _SiteMapFullscreenResult {
  const _SiteMapFullscreenResult({
    required this.selectedSiteId,
    required this.range,
  });

  final String? selectedSiteId;
  final _SiteAnalyticsRange range;
}

class _SiteMapFullscreenPage extends StatefulWidget {
  const _SiteMapFullscreenPage({
    required this.sites,
    required this.initialSiteId,
    required this.initialCenter,
    required this.initialRange,
    required this.loadAnalytics,
  });

  final List<EnergySite> sites;
  final String? initialSiteId;
  final LatLng initialCenter;
  final _SiteAnalyticsRange initialRange;
  final Future<_SiteAnalyticsBundle> Function(EnergySite site) loadAnalytics;

  @override
  State<_SiteMapFullscreenPage> createState() => _SiteMapFullscreenPageState();
}

class _SiteMapFullscreenPageState extends State<_SiteMapFullscreenPage> {
  final MapController _mapController = MapController();
  String? _activeSiteId;
  Future<_SiteAnalyticsBundle>? _analyticsFuture;
  late _SiteAnalyticsRange _range;

  @override
  void initState() {
    super.initState();
    _activeSiteId = widget.initialSiteId;
    _range = widget.initialRange;
    final initialSite = _activeSite;
    if (initialSite != null) {
      _analyticsFuture = widget.loadAnalytics(initialSite);
    }
  }

  EnergySite? get _activeSite {
    for (final site in widget.sites) {
      if (site.id == _activeSiteId) {
        return site;
      }
    }
    return null;
  }

  Future<void> _selectSite(EnergySite site) async {
    setState(() {
      _activeSiteId = site.id;
      _analyticsFuture = widget.loadAnalytics(site);
    });
    _mapController.move(LatLng(site.latitude, site.longitude), 12);
  }

  void _close() {
    Navigator.of(context).pop(
      _SiteMapFullscreenResult(selectedSiteId: _activeSiteId, range: _range),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final localeTag = Localizations.localeOf(context).toLanguageTag();
    final isCompact = MediaQuery.sizeOf(context).width < 920;
    final activeSite = _activeSite;
    final markers = [
      for (final site in widget.sites)
        Marker(
          point: LatLng(site.latitude, site.longitude),
          width: 76,
          height: 76,
          child: GestureDetector(
            onTap: () => _selectSite(site),
            child: _MapPin(isSelected: activeSite?.id == site.id),
          ),
        ),
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _close();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F6FF),
        body: Stack(
          children: [
            Positioned.fill(
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: widget.initialCenter,
                  initialZoom: 10,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'smart_city_renewable_ai',
                  ),
                  MarkerLayer(markers: markers),
                ],
              ),
            ),
            Positioned(
              left: 16,
              top: 16,
              child: SafeArea(
                child: _MapOverlayIconButton(
                  icon: Icons.close_rounded,
                  tooltip: l10n.closeFullscreenMap,
                  onTap: _close,
                ),
              ),
            ),
            Positioned(
              right: 16,
              top: 16,
              child: SafeArea(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  child: activeSite == null
                      ? const SizedBox.shrink()
                      : AppCard(
                          key: ValueKey('fullscreen-badge-${activeSite.id}'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Text(
                            '${activeSite.name} • ${activeSite.city}',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                ),
              ),
            ),
            Positioned(
              left: isCompact ? 16 : 24,
              right: isCompact ? 16 : 24,
              bottom: isCompact ? 16 : 24,
              child: SafeArea(
                top: false,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.08),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: activeSite == null
                      ? const SizedBox.shrink()
                      : FutureBuilder<_SiteAnalyticsBundle>(
                          key: ValueKey('fullscreen-overlay-${activeSite.id}'),
                          future: _analyticsFuture,
                          builder: (context, snapshot) {
                            final analyticsCard = snapshot.hasData
                                ? _SiteAnalyticsOverlayCard(
                                    site: activeSite,
                                    bundle: snapshot.data!,
                                    range: _range,
                                    compact: isCompact,
                                    onRangeChanged: (range) {
                                      setState(() => _range = range);
                                    },
                                    onOpenDay: (day, days) =>
                                        _openForecastDayRoute(
                                          context,
                                          day,
                                          days: days,
                                        ),
                                  )
                                : AppCard(
                                    padding: const EdgeInsets.all(18),
                                    child: SizedBox(
                                      height: isCompact ? 180 : 220,
                                      child: Center(
                                        child: CircularProgressIndicator(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                        ),
                                      ),
                                    ),
                                  );

                            final specsCard = _SelectedSiteSpecsPanel(
                              site: activeSite,
                              localeTag: localeTag,
                              compact: isCompact,
                            );

                            if (isCompact) {
                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  specsCard,
                                  const SizedBox(height: 12),
                                  analyticsCard,
                                ],
                              );
                            }

                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(child: analyticsCard),
                                const SizedBox(width: 16),
                                SizedBox(width: 340, child: specsCard),
                              ],
                            );
                          },
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

double _resolveAxisInterval(double maxValue) {
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

String _formatAxisValue(double value, String localeTag) {
  return formatNumber(value, localeTag, digits: value.abs() >= 10 ? 0 : 1);
}

int _resolveAxisLabelStep(int itemCount) {
  if (itemCount <= 8) {
    return 1;
  }
  if (itemCount <= 24) {
    return 4;
  }
  if (itemCount <= 48) {
    return 8;
  }
  return 16;
}

class _MapSelectionGuideCard extends StatelessWidget {
  const _MapSelectionGuideCard({
    required this.draftPoint,
    required this.localeTag,
  });

  final LatLng? draftPoint;
  final String localeTag;

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
            subtitle: draftPoint == null
                ? l10n.noSiteMessage
                : l10n.mapDraftPointSubtitle,
          ),
          const SizedBox(height: 18),
          if (draftPoint == null)
            EmptyState(
              icon: Icons.add_location_alt_outlined,
              title: l10n.mapDraftPointTitle,
              message: l10n.tapMapToSelect,
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _InlineInfo(
                  label: l10n.latitude,
                  value: formatNumber(
                    draftPoint!.latitude,
                    localeTag,
                    digits: 4,
                  ),
                ),
                _InlineInfo(
                  label: l10n.longitude,
                  value: formatNumber(
                    draftPoint!.longitude,
                    localeTag,
                    digits: 4,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _MapDraftOverlay extends StatelessWidget {
  const _MapDraftOverlay({
    required this.point,
    required this.localeTag,
    required this.onDismiss,
    required this.onAddSite,
    super.key,
  });

  final LatLng point;
  final String localeTag;
  final VoidCallback onDismiss;
  final Future<void> Function() onAddSite;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.18),
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1F18234F),
              blurRadius: 22,
              offset: Offset(0, 14),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 520;
            final summary = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.mapDraftPointTitle,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.mapDraftPointSubtitle,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _InlineInfo(
                      label: l10n.latitude,
                      value: formatNumber(point.latitude, localeTag, digits: 4),
                    ),
                    _InlineInfo(
                      label: l10n.longitude,
                      value: formatNumber(
                        point.longitude,
                        localeTag,
                        digits: 4,
                      ),
                    ),
                  ],
                ),
              ],
            );
            final actions = LayoutBuilder(
              builder: (context, innerConstraints) {
                final compactButtons = innerConstraints.maxWidth < 320;
                if (compactButtons) {
                  return Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: AppPrimaryButton(
                          label: l10n.addSite,
                          icon: const Icon(Icons.add_location_alt_rounded),
                          onPressed: onAddSite,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: AppSecondaryButton(
                          label: l10n.cancel,
                          icon: const Icon(Icons.close_rounded),
                          onPressed: onDismiss,
                        ),
                      ),
                    ],
                  );
                }
                return Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Flexible(
                      child: AppSecondaryButton(
                        label: l10n.cancel,
                        icon: const Icon(Icons.close_rounded),
                        onPressed: onDismiss,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: AppPrimaryButton(
                        label: l10n.addSite,
                        icon: const Icon(Icons.add_location_alt_rounded),
                        onPressed: onAddSite,
                      ),
                    ),
                  ],
                );
              },
            );

            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [summary, const SizedBox(height: 14), actions],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: summary),
                const SizedBox(width: 14),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: actions,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MapOverlayIconButton extends StatelessWidget {
  const _MapOverlayIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withValues(alpha: 0.92),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 10,
        shadowColor: const Color(0x20141F52),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Icon(icon, color: scheme.primary, size: 22),
          ),
        ),
      ),
    );
  }
}

class _SelectedSiteSpecsPanel extends StatelessWidget {
  const _SelectedSiteSpecsPanel({
    required this.site,
    required this.localeTag,
    this.compact = false,
  });

  final EnergySite site;
  final String localeTag;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppCard(
      animated: true,
      padding: EdgeInsets.all(compact ? 18 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.selectedSite,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            '${site.name} • ${site.city}',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _InlineInfo(
                label: l10n.address,
                value: site.address.isEmpty ? site.city : site.address,
              ),
              _InlineInfo(
                label: l10n.latitude,
                value: formatNumber(site.latitude, localeTag, digits: 3),
              ),
              _InlineInfo(
                label: l10n.longitude,
                value: formatNumber(site.longitude, localeTag, digits: 3),
              ),
              _InlineInfo(
                label: l10n.solarCapacity,
                value: formatPower(site.solarCapacityKw, localeTag),
              ),
              _InlineInfo(
                label: l10n.windCapacity,
                value: formatPower(site.windCapacityKw, localeTag),
              ),
              _InlineInfo(
                label: l10n.batteryCapacity,
                value: formatEnergy(site.batteryCapacityKwh, localeTag),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SiteAnalyticsOverlayCard extends StatelessWidget {
  const _SiteAnalyticsOverlayCard({
    required this.site,
    required this.bundle,
    required this.range,
    required this.onRangeChanged,
    required this.onOpenDay,
    this.compact = false,
  });

  final EnergySite site;
  final _SiteAnalyticsBundle bundle;
  final _SiteAnalyticsRange range;
  final ValueChanged<_SiteAnalyticsRange> onRangeChanged;
  final void Function(DateTime day, int days) onOpenDay;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final chart = switch (range) {
      _SiteAnalyticsRange.today =>
        bundle.todayDay == null
            ? EmptyState(
                icon: Icons.bar_chart_rounded,
                title: l10n.today,
                message: l10n.forecastDayUnavailable,
              )
            : _TodayForecastBarChart(
                points: bundle.todayPoints,
                currentHourMarker: bundle.todayMarkerX,
                onOpenDay: () => onOpenDay(bundle.todayDay!, 7),
                height: compact ? 210 : 236,
              ),
      _SiteAnalyticsRange.week7 => _DailyForecastBarChart(
        days: bundle.daily7,
        rangeDays: 7,
        onOpenDay: (day) => onOpenDay(day, 7),
        height: compact ? 210 : 236,
      ),
      _SiteAnalyticsRange.week14 => _DailyForecastBarChart(
        days: bundle.daily14,
        rangeDays: 14,
        onOpenDay: (day) => onOpenDay(day, 14),
        height: compact ? 210 : 236,
      ),
    };

    return AppCard(
      animated: true,
      padding: EdgeInsets.all(compact ? 18 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final stackHeader = compact || constraints.maxWidth < 620;
              final siteTitle = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.mapAnalyticsTitle,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${site.name} • ${site.city}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              );
              final rangeSwitcher = SegmentedButton<_SiteAnalyticsRange>(
                segments: [
                  ButtonSegment(
                    value: _SiteAnalyticsRange.today,
                    label: Text(l10n.today),
                  ),
                  ButtonSegment(
                    value: _SiteAnalyticsRange.week7,
                    label: Text(l10n.day7),
                  ),
                  ButtonSegment(
                    value: _SiteAnalyticsRange.week14,
                    label: Text(l10n.day14),
                  ),
                ],
                selected: {range},
                onSelectionChanged: (selection) {
                  onRangeChanged(selection.first);
                },
              );
              if (stackHeader) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    siteTitle,
                    const SizedBox(height: 14),
                    SizedBox(width: double.infinity, child: rangeSwitcher),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: siteTitle),
                  const SizedBox(width: 12),
                  rangeSwitcher,
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          chart,
          const SizedBox(height: 12),
          Text(
            l10n.mapTapBarHint,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _SelectedSiteSummaryCard extends StatelessWidget {
  const _SelectedSiteSummaryCard({required this.site, required this.localeTag});

  final EnergySite site;
  final String localeTag;

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
            subtitle: '${site.name} • ${site.city}',
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _InlineInfo(
                label: l10n.address,
                value: site.address.isEmpty ? site.city : site.address,
              ),
              _InlineInfo(
                label: l10n.latitude,
                value: formatNumber(site.latitude, localeTag, digits: 3),
              ),
              _InlineInfo(
                label: l10n.longitude,
                value: formatNumber(site.longitude, localeTag, digits: 3),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _ResponsiveMetricGrid(
            maxColumns: 1,
            children: [
              MetricTile(
                compact: true,
                label: l10n.solarCapacity,
                value: formatPower(site.solarCapacityKw, localeTag),
                icon: Icons.wb_sunny_outlined,
              ),
              MetricTile(
                compact: true,
                label: l10n.windCapacity,
                value: formatPower(site.windCapacityKw, localeTag),
                icon: Icons.air_rounded,
              ),
              MetricTile(
                compact: true,
                label: l10n.batteryCapacity,
                value: formatEnergy(site.batteryCapacityKwh, localeTag),
                icon: Icons.battery_full_rounded,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SiteAnalyticsCard extends StatelessWidget {
  const _SiteAnalyticsCard({
    required this.site,
    required this.bundle,
    required this.range,
    required this.onRangeChanged,
    required this.onOpenDay,
  });

  final EnergySite site;
  final _SiteAnalyticsBundle bundle;
  final _SiteAnalyticsRange range;
  final ValueChanged<_SiteAnalyticsRange> onRangeChanged;
  final void Function(DateTime day, int days) onOpenDay;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final chart = switch (range) {
      _SiteAnalyticsRange.today =>
        bundle.todayDay == null
            ? EmptyState(
                icon: Icons.bar_chart_rounded,
                title: l10n.today,
                message: l10n.forecastDayUnavailable,
              )
            : _TodayForecastBarChart(
                points: bundle.todayPoints,
                currentHourMarker: bundle.todayMarkerX,
                onOpenDay: () => onOpenDay(bundle.todayDay!, 7),
              ),
      _SiteAnalyticsRange.week7 => _DailyForecastBarChart(
        days: bundle.daily7,
        rangeDays: 7,
        onOpenDay: (day) => onOpenDay(day, 7),
      ),
      _SiteAnalyticsRange.week14 => _DailyForecastBarChart(
        days: bundle.daily14,
        rangeDays: 14,
        onOpenDay: (day) => onOpenDay(day, 14),
      ),
    };

    return AppCard(
      animated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: l10n.mapAnalyticsTitle,
            subtitle:
                '${site.name} • ${site.city}\n${l10n.mapAnalyticsSubtitle}',
            trailing: SegmentedButton<_SiteAnalyticsRange>(
              segments: [
                ButtonSegment(
                  value: _SiteAnalyticsRange.today,
                  label: Text(l10n.today),
                ),
                ButtonSegment(
                  value: _SiteAnalyticsRange.week7,
                  label: Text(l10n.day7),
                ),
                ButtonSegment(
                  value: _SiteAnalyticsRange.week14,
                  label: Text(l10n.day14),
                ),
              ],
              selected: {range},
              onSelectionChanged: (selection) {
                onRangeChanged(selection.first);
              },
            ),
          ),
          const SizedBox(height: 18),
          chart,
          const SizedBox(height: 16),
          Text(
            l10n.mapTapBarHint,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _TodayForecastBarChart extends StatelessWidget {
  const _TodayForecastBarChart({
    required this.points,
    required this.currentHourMarker,
    required this.onOpenDay,
    this.height = 320,
  });

  final List<ForecastPoint> points;
  final double? currentHourMarker;
  final VoidCallback onOpenDay;
  final double height;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final localeTag = Localizations.localeOf(context).toLanguageTag();
    final theme = Theme.of(context);
    final maxY = points.isEmpty
        ? 1.0
        : points.map((point) => point.renewableKw).reduce(math.max);
    final labelStep = _resolveAxisLabelStep(points.length);
    final yInterval = _resolveAxisInterval(maxY);
    final barWidth = points.length > 72
        ? 6.0
        : points.length > 48
        ? 8.0
        : points.length > 24
        ? 10.0
        : 12.0;

    return SizedBox(
      height: height,
      child: BarChart(
        BarChartData(
          maxY: maxY * 1.2,
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: yInterval,
          ),
          extraLinesData: currentHourMarker == null
              ? const ExtraLinesData()
              : ExtraLinesData(
                  verticalLines: [
                    VerticalLine(
                      x: currentHourMarker!,
                      strokeWidth: 2,
                      dashArray: const [5, 4],
                      color: theme.colorScheme.secondary.withValues(alpha: 0.9),
                    ),
                  ],
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
                reservedSize: 48,
                interval: yInterval,
                getTitlesWidget: (value, meta) {
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(
                      _formatAxisValue(value, localeTag),
                      style: theme.textTheme.bodySmall,
                    ),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                minIncluded: false,
                maxIncluded: false,
                showTitles: true,
                reservedSize: 52,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 ||
                      index >= points.length ||
                      (index % labelStep != 0 && index != points.length - 1)) {
                    return const SizedBox.shrink();
                  }
                  return SideTitleWidget(
                    meta: meta,
                    angle: -0.55,
                    child: Text(
                      formatTimeLabel(points[index].time, localeTag),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                    ),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            handleBuiltInTouches: true,
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => const Color(0xFF24314B),
              tooltipBorderRadius: BorderRadius.circular(18),
              tooltipPadding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                if (groupIndex < 0 || groupIndex >= points.length) {
                  return null;
                }
                final point = points[groupIndex];
                return BarTooltipItem(
                  '${formatTimeLabel(point.time, localeTag)}\n',
                  theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white70,
                        fontWeight: FontWeight.w700,
                      ) ??
                      const TextStyle(color: Colors.white70),
                  children: [
                    TextSpan(
                      text:
                          '${l10n.renewable}: ${formatNumber(point.renewableKw, localeTag, digits: 2)} kW',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                );
              },
            ),
            touchCallback: (event, response) {
              if (event is FlTapUpEvent && response?.spot != null) {
                onOpenDay();
              }
            },
          ),
          barGroups: [
            for (var index = 0; index < points.length; index++)
              BarChartGroupData(
                x: index,
                barRods: [
                  BarChartRodData(
                    toY: points[index].renewableKw,
                    width: barWidth,
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ],
              ),
          ],
        ),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      ),
    );
  }
}

class _DailyForecastBarChart extends StatelessWidget {
  const _DailyForecastBarChart({
    required this.days,
    required this.rangeDays,
    required this.onOpenDay,
    this.height = 320,
  });

  final List<DailyForecastBucket> days;
  final int rangeDays;
  final ValueChanged<DateTime> onOpenDay;
  final double height;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final localeTag = Localizations.localeOf(context).toLanguageTag();
    final theme = Theme.of(context);
    final maxY = days.isEmpty
        ? 1.0
        : days.map((day) => day.renewableKwh).reduce(math.max);
    final yInterval = _resolveAxisInterval(maxY);
    final labelStep = rangeDays >= 14 ? 2 : 1;

    return SizedBox(
      height: height,
      child: BarChart(
        BarChartData(
          maxY: maxY * 1.2,
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
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                minIncluded: false,
                maxIncluded: false,
                showTitles: true,
                reservedSize: 48,
                interval: yInterval,
                getTitlesWidget: (value, meta) {
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(
                      _formatAxisValue(value, localeTag),
                      style: theme.textTheme.bodySmall,
                    ),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                minIncluded: false,
                maxIncluded: false,
                showTitles: true,
                reservedSize: 46,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 ||
                      index >= days.length ||
                      (index % labelStep != 0 && index != days.length - 1)) {
                    return const SizedBox.shrink();
                  }
                  return SideTitleWidget(
                    meta: meta,
                    angle: -0.35,
                    child: Text(
                      formatDayLabel(days[index].day, localeTag),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                    ),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            handleBuiltInTouches: true,
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => const Color(0xFF24314B),
              tooltipBorderRadius: BorderRadius.circular(18),
              tooltipPadding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                if (groupIndex < 0 ||
                    groupIndex >= days.length ||
                    rodIndex != 0) {
                  return null;
                }
                final day = days[groupIndex];
                return BarTooltipItem(
                  '${formatDateShort(day.day, localeTag)}\n',
                  theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white70,
                        fontWeight: FontWeight.w700,
                      ) ??
                      const TextStyle(color: Colors.white70),
                  children: [
                    TextSpan(
                      text:
                          '${l10n.renewable}: ${formatEnergy(day.renewableKwh, localeTag)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                );
              },
            ),
            touchCallback: (event, response) {
              if (event is FlTapUpEvent && response?.spot != null) {
                onOpenDay(days[response!.spot!.touchedBarGroupIndex].day);
              }
            },
          ),
          barGroups: [
            for (var i = 0; i < days.length; i++)
              BarChartGroupData(
                x: i,
                barsSpace: 6,
                barRods: [
                  BarChartRodData(
                    toY: days[i].renewableKwh,
                    color: theme.colorScheme.primary,
                    width: rangeDays == 14 ? 14 : 18,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ],
              ),
          ],
        ),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      ),
    );
  }
}

class _InlineInfo extends StatelessWidget {
  const _InlineInfo({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.78),
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

class _ResponsiveMetricGrid extends StatelessWidget {
  const _ResponsiveMetricGrid({required this.children, this.maxColumns = 4});
  final List<Widget> children;
  final int maxColumns;
  @override
  Widget build(BuildContext context) =>
      AdaptiveMetricGrid(maxColumns: maxColumns, children: children);
}

class _MapPin extends StatelessWidget {
  const _MapPin({required this.isSelected});

  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final color = isSelected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.secondary;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: isSelected ? 30 : 24,
          height: isSelected ? 30 : 24,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.30),
                blurRadius: 18,
                spreadRadius: 4,
              ),
            ],
          ),
          child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 16),
        ),
      ],
    );
  }
}

class _SiteTile extends StatelessWidget {
  const _SiteTile({
    required this.site,
    required this.selected,
    required this.isDefault,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
    required this.onSetDefault,
  });

  final EnergySite site;
  final bool selected;
  final bool isDefault;
  final VoidCallback onSelect;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onSetDefault;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final highlight = selected || isDefault;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onSelect,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            color: highlight
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)
                : const Color(0xFFFDFEFE),
            border: Border.all(
              color: highlight
                  ? Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.28)
                  : Theme.of(context).colorScheme.outline,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      site.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (isDefault)
                    Chip(label: Text(l10n.defaultSite))
                  else if (selected)
                    Chip(label: Text(l10n.selectedSite)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${site.city} • ${site.address}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  Chip(
                    label: Text(
                      '${l10n.solarCapacity}: ${site.solarCapacityKw.toStringAsFixed(0)} kW',
                    ),
                  ),
                  Chip(
                    label: Text(
                      '${l10n.windCapacity}: ${site.windCapacityKw.toStringAsFixed(0)} kW',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  AppSecondaryButton(
                    label: l10n.edit,
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: onEdit,
                  ),
                  if (!isDefault)
                    AppSecondaryButton(
                      label: l10n.setAsDefault,
                      icon: const Icon(Icons.star_outline_rounded),
                      onPressed: onSetDefault,
                    ),
                  AppSecondaryButton(
                    label: l10n.delete,
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: onDelete,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SiteEditorDialog extends StatefulWidget {
  const _SiteEditorDialog({
    required this.ownerUid,
    required this.existing,
    required this.draftPoint,
    this.fullscreen = false,
  });

  final String ownerUid;
  final EnergySite? existing;
  final LatLng? draftPoint;
  final bool fullscreen;

  @override
  State<_SiteEditorDialog> createState() => _SiteEditorDialogState();
}

class _SiteEditorDialogState extends State<_SiteEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _cityController;
  late final TextEditingController _addressController;
  late final TextEditingController _latController;
  late final TextEditingController _lonController;
  late final TextEditingController _solarController;
  late final TextEditingController _tiltController;
  late final TextEditingController _azimuthController;
  late final TextEditingController _windController;
  late final TextEditingController _hubController;
  late final TextEditingController _batteryController;
  late final TextEditingController _notesController;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final lat =
        existing?.latitude ??
        widget.draftPoint?.latitude ??
        AppConstants.defaultLatitude;
    final lon =
        existing?.longitude ??
        widget.draftPoint?.longitude ??
        AppConstants.defaultLongitude;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _cityController = TextEditingController(
      text: existing?.city ?? AppConstants.defaultCity,
    );
    _addressController = TextEditingController(text: existing?.address ?? '');
    _latController = TextEditingController(text: lat.toStringAsFixed(5));
    _lonController = TextEditingController(text: lon.toStringAsFixed(5));
    _solarController = TextEditingController(
      text: (existing?.solarCapacityKw ?? 25).toStringAsFixed(0),
    );
    _tiltController = TextEditingController(
      text: (existing?.tiltDeg ?? 35).toStringAsFixed(0),
    );
    _azimuthController = TextEditingController(
      text: (existing?.azimuthDeg ?? 180).toStringAsFixed(0),
    );
    _windController = TextEditingController(
      text: (existing?.windCapacityKw ?? 12).toStringAsFixed(0),
    );
    _hubController = TextEditingController(
      text: (existing?.windHubHeightM ?? 80).toStringAsFixed(0),
    );
    _batteryController = TextEditingController(
      text: (existing?.batteryCapacityKwh ?? 80).toStringAsFixed(0),
    );
    _notesController = TextEditingController(text: existing?.notes ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _cityController.dispose();
    _addressController.dispose();
    _latController.dispose();
    _lonController.dispose();
    _solarController.dispose();
    _tiltController.dispose();
    _azimuthController.dispose();
    _windController.dispose();
    _hubController.dispose();
    _batteryController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isCompact = MediaQuery.sizeOf(context).width < 760;
    final title = widget.existing == null
        ? l10n.siteFormTitleNew
        : l10n.siteFormTitleEdit;

    final formContent = Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!widget.fullscreen) ...[
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 18),
          ],
          AppTextField(
            controller: _nameController,
            validator: (value) => value == null || value.trim().isEmpty
                ? l10n.requiredField
                : null,
            label: l10n.siteName,
          ),
          const SizedBox(height: 12),
          AppTextField(
            controller: _cityController,
            validator: (value) => value == null || value.trim().isEmpty
                ? l10n.requiredField
                : null,
            label: l10n.city,
          ),
          const SizedBox(height: 12),
          AppTextField(controller: _addressController, label: l10n.address),
          const SizedBox(height: 12),
          _ResponsiveFieldPair(
            first: AppTextField(
              controller: _latController,
              validator: (value) => double.tryParse(value ?? '') == null
                  ? l10n.invalidNumber
                  : null,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              label: l10n.latitude,
            ),
            second: AppTextField(
              controller: _lonController,
              validator: (value) => double.tryParse(value ?? '') == null
                  ? l10n.invalidNumber
                  : null,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              label: l10n.longitude,
            ),
          ),
          const SizedBox(height: 12),
          _ResponsiveFieldPair(
            first: AppTextField(
              controller: _solarController,
              validator: (value) => double.tryParse(value ?? '') == null
                  ? l10n.invalidNumber
                  : null,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              label: l10n.solarCapacity,
            ),
            second: AppTextField(
              controller: _windController,
              validator: (value) => double.tryParse(value ?? '') == null
                  ? l10n.invalidNumber
                  : null,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              label: l10n.windCapacity,
            ),
          ),
          const SizedBox(height: 12),
          _ResponsiveFieldPair(
            first: AppTextField(
              controller: _tiltController,
              validator: (value) => double.tryParse(value ?? '') == null
                  ? l10n.invalidNumber
                  : null,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              label: l10n.tilt,
            ),
            second: AppTextField(
              controller: _azimuthController,
              validator: (value) => double.tryParse(value ?? '') == null
                  ? l10n.invalidNumber
                  : null,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              label: l10n.azimuth,
            ),
          ),
          const SizedBox(height: 12),
          _ResponsiveFieldPair(
            first: AppTextField(
              controller: _hubController,
              validator: (value) => double.tryParse(value ?? '') == null
                  ? l10n.invalidNumber
                  : null,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              label: l10n.windHubHeight,
            ),
            second: AppTextField(
              controller: _batteryController,
              validator: (value) => double.tryParse(value ?? '') == null
                  ? l10n.invalidNumber
                  : null,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              label: l10n.batteryCapacity,
            ),
          ),
          const SizedBox(height: 12),
          AppTextField(
            controller: _notesController,
            maxLines: 3,
            label: l10n.notes,
          ),
          const SizedBox(height: 20),
          _ResponsiveFieldPair(
            first: AppSecondaryButton(
              label: l10n.cancel,
              onPressed: () => Navigator.of(context).pop(),
            ),
            second: AppPrimaryButton(
              label: l10n.saveSite,
              icon: const Icon(Icons.save_outlined),
              onPressed: () async {
                if (!_formKey.currentState!.validate()) {
                  return;
                }
                Navigator.of(context).pop(
                  EnergySite(
                    id: widget.existing?.id ?? '',
                    ownerUid: widget.ownerUid,
                    name: _nameController.text.trim(),
                    city: _cityController.text.trim(),
                    address: _addressController.text.trim(),
                    geo: GeoPoint(
                      double.parse(_latController.text.trim()),
                      double.parse(_lonController.text.trim()),
                    ),
                    solarCapacityKw: double.parse(_solarController.text.trim()),
                    tiltDeg: double.parse(_tiltController.text.trim()),
                    azimuthDeg: double.parse(_azimuthController.text.trim()),
                    windCapacityKw: double.parse(_windController.text.trim()),
                    windHubHeightM: double.parse(_hubController.text.trim()),
                    batteryCapacityKwh: double.parse(
                      _batteryController.text.trim(),
                    ),
                    notes: _notesController.text.trim().isEmpty
                        ? null
                        : _notesController.text.trim(),
                    createdAt: widget.existing?.createdAt,
                    updatedAt: widget.existing?.updatedAt,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );

    final dialogBody = SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.all(isCompact ? 18 : 24),
        child: formContent,
      ),
    );

    if (widget.fullscreen) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: Text(title),
        ),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                child: AppCard(
                  animated: true,
                  padding: EdgeInsets.zero,
                  child: dialogBody,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Dialog(
      insetPadding: EdgeInsets.all(isCompact ? 12 : 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: dialogBody,
      ),
    );
  }
}

class _ResponsiveFieldPair extends StatelessWidget {
  const _ResponsiveFieldPair({required this.first, required this.second});

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 520;
        if (stacked) {
          return Column(children: [first, const SizedBox(height: 12), second]);
        }

        return Row(
          children: [
            Expanded(child: first),
            const SizedBox(width: 12),
            Expanded(child: second),
          ],
        );
      },
    );
  }
}
