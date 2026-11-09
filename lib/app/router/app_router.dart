import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/app_providers.dart';
import '../../core/widgets/app_shell.dart';
import '../../core/widgets/loading_state.dart';
import '../../features/auth/presentation/auth_page.dart';
import '../../features/auth/presentation/profile_setup_page.dart';
import '../../features/dashboard/presentation/dashboard_page.dart';
import '../../features/forecast/presentation/forecast_day_detail_page.dart';
import '../../features/forecast/presentation/forecast_page.dart';
import '../../features/optimization/presentation/optimization_page.dart';
import '../../features/profile/presentation/profile_page.dart';
import '../../features/sites/presentation/sites_map_page.dart';
import 'router_notifier.dart';

final routerNotifierProvider = Provider<RouterNotifier>((ref) {
  final notifier = RouterNotifier(
    authService: ref.watch(phoneAuthServiceProvider),
    firestoreRepository: ref.watch(firestoreRepositoryProvider),
  );
  ref.onDispose(notifier.dispose);
  return notifier;
});

final appRouterProvider = Provider<GoRouter>((ref) {
  final notifier = ref.watch(routerNotifierProvider);

  return GoRouter(
    initialLocation: '/loading',
    refreshListenable: notifier,
    routes: [
      GoRoute(path: '/loading', builder: (_, _) => const LoadingScaffold()),
      GoRoute(path: '/auth', builder: (_, _) => const AuthPage()),
      GoRoute(path: '/onboarding', builder: (_, _) => const ProfileSetupPage()),
      ShellRoute(
        builder: (context, state, child) {
          return AppShell(location: state.uri.path, child: child);
        },
        routes: [
          GoRoute(path: '/dashboard', builder: (_, _) => const DashboardPage()),
          GoRoute(path: '/sites', builder: (_, _) => const SitesMapPage()),
          GoRoute(path: '/forecast', builder: (_, _) => const ForecastPage()),
          GoRoute(
            path: '/forecast/day/:dayIso',
            builder: (context, state) {
              final dayIso = state.pathParameters['dayIso'] ?? '';
              final days =
                  int.tryParse(state.uri.queryParameters['days'] ?? '') ?? 7;
              return ForecastDayDetailPage(dayIso: dayIso, days: days);
            },
          ),
          GoRoute(
            path: '/optimization',
            builder: (_, _) => const OptimizationPage(),
          ),
          GoRoute(path: '/profile', builder: (_, _) => const ProfilePage()),
        ],
      ),
    ],
    redirect: (context, state) {
      final path = state.uri.path;

      if (notifier.isLoading) {
        return path == '/loading' ? null : '/loading';
      }

      if (!notifier.isAuthenticated) {
        return path == '/auth' ? null : '/auth';
      }

      if (notifier.needsProfile) {
        return path == '/onboarding' ? null : '/onboarding';
      }

      if (path == '/loading' || path == '/auth' || path == '/onboarding') {
        return '/dashboard';
      }

      return null;
    },
  );
});
