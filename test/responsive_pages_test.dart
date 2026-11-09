import 'package:smart_city_renewable_ai/core/widgets/app_card.dart';
import 'package:smart_city_renewable_ai/core/widgets/aligned_panel_grid.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_city_renewable_ai/core/providers/app_providers.dart';
import 'package:smart_city_renewable_ai/core/theme/app_theme.dart';
import 'package:smart_city_renewable_ai/core/widgets/app_shell.dart';
import 'package:smart_city_renewable_ai/core/widgets/metric_tile.dart';
import 'package:smart_city_renewable_ai/data/models/energy_site.dart';
import 'package:smart_city_renewable_ai/data/models/user_profile.dart';
import 'package:smart_city_renewable_ai/data/services/cloud_run_api.dart';
import 'package:smart_city_renewable_ai/features/dashboard/presentation/dashboard_page.dart';
import 'package:smart_city_renewable_ai/features/forecast/presentation/forecast_page.dart';
import 'package:smart_city_renewable_ai/features/forecast/presentation/forecast_day_detail_page.dart';
import 'package:smart_city_renewable_ai/features/optimization/presentation/optimization_page.dart';
import 'package:smart_city_renewable_ai/features/sites/presentation/sites_map_page.dart';
import 'package:smart_city_renewable_ai/features/profile/presentation/profile_page.dart';
import 'package:smart_city_renewable_ai/features/auth/presentation/auth_page.dart';
import 'package:smart_city_renewable_ai/features/auth/presentation/profile_setup_page.dart';
import 'package:smart_city_renewable_ai/l10n/app_localizations.dart';

class FakeUser extends Fake implements User {
  @override
  String get uid => 'layout-test-user';
  @override
  String? get phoneNumber => '+77000000000';
}

class FakeAuth extends Fake implements FirebaseAuth {}

const evidence = 'build/layout_evidence';
const fixtures = 'test/fixtures';
final site = EnergySite(
  id: 'astana-calculation-20261029',
  ownerUid: 'layout-test-user',
  name: 'Астана — расчётный объект',
  city: 'Astana',
  address: 'Расчётная точка 50.968, 71.344',
  geo: const GeoPoint(50.968, 71.344),
  solarCapacityKw: 25,
  tiltDeg: 35,
  azimuthDeg: 180,
  windCapacityKw: 12,
  windHubHeightM: 80,
  batteryCapacityKwh: 80,
);
const profile = UserProfile(
  uid: 'layout-test-user',
  fullName: 'Толегенова Гүлназ',
  phoneNumber: '+77000000000',
  city: 'Astana',
  preferredLanguageCode: 'kk',
);

Map<String, dynamic> readFixture(String name) =>
    jsonDecode(File('$fixtures/$name.json').readAsStringSync())
        as Map<String, dynamic>;
CloudRunApi mockApi({Completer<http.Response>? weather}) => CloudRunApi(
  baseUrl: 'https://example.test',
  client: MockClient((r) async {
    String? file;
    switch (r.url.path) {
      case '/forecast/7d':
      case '/forecast/14d':
        file = r.url.path.endsWith('14d')
            ? 'cloud_forecast_14d'
            : 'cloud_forecast_7d';
      case '/energy/balance':
        file = 'final_balance_7d';
      case '/optimize':
        file = jsonDecode(r.body)['days'] == 14
            ? 'final_optimize_14d'
            : 'final_optimize_7d';
      case '/meta':
        file = 'cloud_meta';
      case '/health':
        file = 'final_cloud_health';
      case '/meteo':
        if (weather != null) return weather.future;
    }
    return http.Response(
      jsonEncode(file == null ? {} : readFixture(file)),
      200,
    );
  }),
);
Future<void> mount(
  WidgetTester tester,
  Widget page,
  String route,
  Size size, {
  double scale = 1,
  String locale = 'kk',
  CloudRunApi? api,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        firebaseAuthProvider.overrideWithValue(FakeAuth()),
        firebaseUserProvider.overrideWith((ref) => Stream.value(FakeUser())),
        currentUserProfileProvider.overrideWith((ref) => Stream.value(profile)),
        currentUserSitesProvider.overrideWith((ref) => Stream.value([site])),
        selectedSiteProvider.overrideWithValue(site),
        cloudRunApiProvider.overrideWithValue(api ?? mockApi()),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: RepaintBoundary(
          key: const ValueKey('capture'),
          child: route.startsWith('/auth')
              ? page
              : AppShell(location: route, child: page),
        ),
      ),
    ),
  );
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final fonts =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final font in fonts) {
      final loader = FontLoader(font['family'] as String);
      for (final asset in font['fonts'] as List) {
        loader.addFont(rootBundle.load(asset['asset'] as String));
      }
      await loader.load();
    }
  });
  final pages = <String, Widget Function()>{
    'dashboard': () => const DashboardPage(),
    'forecast': () => const ForecastPage(),
    'day': () => const ForecastDayDetailPage(dayIso: '2026-10-30', days: 7),
    'optimization': () => const OptimizationPage(),
    'sites': () => const SitesMapPage(),
    'profile': () => const ProfilePage(),
    'auth': () => const AuthPage(),
    'auth-setup': () => const ProfileSetupPage(),
  };
  for (final size in [
    const Size(320, 640),
    const Size(360, 800),
    const Size(390, 844),
    const Size(768, 1024),
    const Size(1024, 600),
    const Size(1024, 768),
    const Size(1440, 900),
    const Size(1920, 1080),
    const Size(2560, 1440),
  ]) {
    for (final entry in pages.entries) {
      testWidgets('${entry.key} ${size.width.toInt()}x${size.height.toInt()}', (
        tester,
      ) async {
        await mount(tester, entry.value(), '/${entry.key}', size);
        expect(tester.takeException(), isNull);
        if (!entry.key.startsWith('auth')) {
          expect(find.byType(MetricTile), findsWidgets);
        }
        // Panel borders share columns and row baselines at desktop widths.
        for (final grid in tester.widgetList<AlignedPanelGrid>(
          find.byType(AlignedPanelGrid),
        )) {
          final gridRect = tester.getRect(find.byWidget(grid));
          if (gridRect.width >= grid.minPanelWidth * 2 + AlignedPanelGrid.gap &&
              grid.children.length == 2) {
            final left = tester.getRect(find.byWidget(grid.children[0]));
            final right = tester.getRect(find.byWidget(grid.children[1]));
            expect(left.width, closeTo(right.width, 0.01));
            expect(left.height, closeTo(right.height, 0.01));
            expect(left.top, closeTo(right.top, 0.01));
            expect(left.bottom, closeTo(right.bottom, 0.01));
            expect(right.left - left.right, closeTo(16, 0.01));
            expect(left.left, closeTo(gridRect.left, 0.01));
            expect(right.right, closeTo(gridRect.right, 0.01));
          }
        }
        // Every KPI's complete label/value/caption must fit inside its card.
        for (final tile in find.byType(MetricTile).evaluate()) {
          final box = tile.renderObject! as RenderBox;
          final bounds = box.localToGlobal(Offset.zero) & box.size;
          for (final text
              in find
                  .descendant(
                    of: find.byWidget(tile.widget),
                    matching: find.byType(Text),
                  )
                  .evaluate()) {
            final tb = text.renderObject! as RenderBox;
            final rect = tb.localToGlobal(Offset.zero) & tb.size;
            expect(rect.bottom, lessThanOrEqualTo(bounds.bottom + 1));
            expect(rect.right, lessThanOrEqualTo(bounds.right + 1));
          }
        }
        if (size.width == 390 || size.width == 1440 || size.width == 1920) {
          await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('capture')),
            );
            final image = await boundary.toImage(pixelRatio: 1);
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            final dir = Directory('$evidence/layout');
            await dir.create(recursive: true);
            await File(
              '${dir.path}/${entry.key}_${size.width.toInt()}.png',
            ).writeAsBytes(data!.buffer.asUint8List());
          });
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      });
    }
  }
  for (final width in [320.0, 768.0, 1440.0]) {
    testWidgets('site editor and keyboard $width', (tester) async {
      await mount(tester, const SitesMapPage(), '/sites', Size(width, 800));
      final context = tester.element(find.byType(SitesMapPage));
      final l10n = AppLocalizations.of(context);
      final edit = find.text(l10n.edit).first;
      await tester.ensureVisible(edit);
      await tester.pump();
      await tester.tap(edit);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull);
      expect(find.byType(TextFormField), findsWidgets);
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pump();
      expect(tester.takeException(), isNull);
      tester.view.resetViewInsets();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  }
  testWidgets('ultrawide header and page share the same outer edges', (
    tester,
  ) async {
    await mount(
      tester,
      const ProfilePage(),
      '/profile',
      const Size(2560, 1440),
    );
    final l10n = AppLocalizations.of(tester.element(find.byType(AppShell)));
    final header = find
        .ancestor(
          of: find.text(l10n.shellSubtitle),
          matching: find.byType(AppCard),
        )
        .first;
    final headerRect = tester.getRect(header);
    final panelsRect = tester.getRect(
      find.byKey(const ValueKey('profile-settings-row')),
    );
    expect(headerRect.left, closeTo(panelsRect.left, 0.01));
    expect(headerRect.right, closeTo(panelsRect.right, 0.01));
    expect(headerRect.width, 1600);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('battery controls remain interactive after reflow', (
    tester,
  ) async {
    await mount(
      tester,
      const OptimizationPage(),
      '/optimization',
      const Size(1920, 1080),
    );
    final slider = find.byType(Slider).first;
    await tester.ensureVisible(slider);
    await tester.pump();
    final before = tester.widget<Slider>(slider).value;
    await tester.drag(slider, const Offset(100, 0));
    await tester.pump();
    expect(tester.widget<Slider>(slider).value, isNot(before));
    final changed = tester.widget<Slider>(slider).value;
    tester.view.physicalSize = const Size(390, 844);
    await tester.pump();
    expect(tester.widget<Slider>(slider).value, changed);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  for (final entry in {
    'dashboard': 'dashboard-context-row',
    'forecast': 'forecast-daily-row',
    'optimization': 'optimization-workspace-row',
    'profile': 'profile-settings-row',
    'sites': 'sites-overview-row',
  }.entries) {
    testWidgets('desktop panel geometry ${entry.key}', (tester) async {
      await mount(
        tester,
        pages[entry.key]!(),
        '/${entry.key}',
        const Size(1920, 1080),
      );
      await tester.ensureVisible(find.byKey(ValueKey(entry.value)));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('capture')),
        );
        final image = await boundary.toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '$evidence/layout/${entry.key}_panels_1920.png',
        ).writeAsBytes(data!.buffer.asUint8List());
      });
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  }
  for (final name in ['forecast', 'optimization', 'dashboard', 'day']) {
    testWidgets('inspect chart and table $name', (tester) async {
      await mount(tester, pages[name]!(), '/$name', const Size(390, 844));
      if (name == 'forecast' || name == 'optimization') {
        final l10n = AppLocalizations.of(tester.element(find.byType(AppShell)));
        await tester.tap(find.text(l10n.day14));
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(tester.takeException(), isNull);
      }
      if (name == 'optimization') {
        for (final chart in tester.widgetList<LineChart>(
          find.byType(LineChart),
        )) {
          expect(chart.data.lineBarsData.first.spots.length, 336);
        }
      }
      final scroll = find
          .descendant(
            of: find.byWidgetPredicate(
              (w) => w.runtimeType == pages[name]!().runtimeType,
            ),
            matching: find.byType(Scrollable),
          )
          .first;
      final position = tester.state<ScrollableState>(scroll).position;
      position.jumpTo(
        position.maxScrollExtent * (name == 'forecast' ? 0.63 : 1.0),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('capture')),
        );
        final image = await boundary.toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '$evidence/layout/${name}_chart_390.png',
        ).writeAsBytes(data!.buffer.asUint8List());
      });
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  }
  testWidgets('Dashboard core data does not wait for weather', (tester) async {
    final weather = Completer<http.Response>();
    await mount(
      tester,
      const DashboardPage(),
      '/dashboard',
      const Size(1440, 900),
      api: mockApi(weather: weather),
    );
    expect(find.byType(MetricTile), findsWidgets);
    expect(weather.isCompleted, false);
    weather.complete(http.Response('{}', 200));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
  });
  for (final lang in ['kk', 'ru', 'en']) {
    testWidgets('large text on mobile $lang', (tester) async {
      await mount(
        tester,
        const ForecastPage(),
        '/forecast',
        const Size(360, 800),
        scale: 1.4,
        locale: lang,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
