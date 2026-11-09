import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_city_renewable_ai/l10n/app_localizations.dart';

import '../app/localization/locale_controller.dart';
import '../app/router/app_router.dart';
import '../core/extensions/async_value_x.dart';
import '../core/providers/app_providers.dart';
import '../core/theme/app_theme.dart';

class SmartCityRenewableApp extends ConsumerStatefulWidget {
  const SmartCityRenewableApp({super.key});

  @override
  ConsumerState<SmartCityRenewableApp> createState() =>
      _SmartCityRenewableAppState();
}

class _SmartCityRenewableAppState extends ConsumerState<SmartCityRenewableApp> {
  @override
  void initState() {
    super.initState();
    ref.listenManual(currentUserProfileProvider, (previous, next) {
      unawaited(
        ref
            .read(localeControllerProvider.notifier)
            .syncWithProfile(next.valueOrNull),
      );
    }, fireImmediately: true);
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final locale = ref.watch(localeControllerProvider);

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      theme: AppTheme.light(),
      routerConfig: router,
    );
  }
}
