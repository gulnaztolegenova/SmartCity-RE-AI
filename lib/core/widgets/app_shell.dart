import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:smart_city_renewable_ai/l10n/app_localizations.dart';

import '../../core/extensions/async_value_x.dart';
import '../../core/providers/app_providers.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/user_profile.dart';
import 'app_animated_content.dart';
import 'app_ambient_background.dart';
import 'app_card.dart';
import 'app_confirmation_dialog.dart';
import 'app_language_switcher.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({required this.location, required this.child, super.key});

  final String location;
  final Widget child;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  // Keep the current page and unsaved controls when the navigation shell reflows.
  final _pageKey = GlobalKey();
  String get location => widget.location;
  Widget get pageContent => AppAnimatedContent(
    key: _pageKey,
    contentKey: location,
    child: SizedBox(width: double.infinity, child: widget.child),
  );

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    final l10n = AppLocalizations.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 1024;
    final isCompact = width < 760;
    final isVeryNarrow = width < 420;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    final destinations = <_ShellDestination>[
      _ShellDestination(
        route: '/dashboard',
        label: l10n.navDashboard,
        icon: PhosphorIcons.squaresFour(),
      ),
      _ShellDestination(
        route: '/sites',
        label: l10n.navSites,
        icon: PhosphorIcons.mapPin(),
      ),
      _ShellDestination(
        route: '/forecast',
        label: l10n.navForecast,
        icon: PhosphorIcons.chartLineUp(),
      ),
      _ShellDestination(
        route: '/optimization',
        label: l10n.navOptimization,
        icon: PhosphorIcons.batteryChargingVertical(),
      ),
      _ShellDestination(
        route: '/profile',
        label: l10n.navProfile,
        icon: PhosphorIcons.userCircle(),
      ),
    ];

    final currentIndex = destinations.indexWhere(
      (item) => location.startsWith(item.route),
    );
    final safeIndex = currentIndex < 0 ? 0 : currentIndex;

    if (!isDesktop) {
      final navHeight = 64.0 + 28 * MediaQuery.textScalerOf(context).scale(1);
      final navBottom = bottomInset > 0 ? bottomInset + 8 : 12.0;
      final navClearance = navHeight + navBottom + 16;

      return Scaffold(
        extendBody: true,
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          toolbarHeight: isVeryNarrow ? 74 : 80,
          titleSpacing: 16,
          title: _MobileTopBarTitle(
            appTitle: l10n.appTitle,
            sectionLabel: destinations[safeIndex].label,
            veryNarrow: isVeryNarrow,
          ),
          actions: [
            Padding(
              padding: EdgeInsets.only(right: isVeryNarrow ? 10 : 12),
              child: const AppLanguageSwitcher(compact: true),
            ),
          ],
        ),
        body: Stack(
          children: [
            const Positioned.fill(child: AppAmbientBackground(workspace: true)),
            Positioned.fill(
              child: SafeArea(
                top: false,
                bottom: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    isCompact ? 12 : 16,
                    8,
                    isCompact ? 12 : 16,
                    navClearance,
                  ),
                  child: pageContent,
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: navBottom,
              child: _MobileBottomBar(
                height: navHeight,
                currentIndex: safeIndex,
                destinations: destinations,
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: AppAmbientBackground(workspace: true)),
          SafeArea(
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 10, 18),
                  child: SizedBox(
                    width: 292,
                    child: AppCard(
                      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
                      child: LayoutBuilder(
                        builder: (context, constraints) =>
                            SingleChildScrollView(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minHeight: constraints.maxHeight,
                                ),
                                child: IntrinsicHeight(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          gradient: const LinearGradient(
                                            colors: [
                                              Color(0xFF4D5CFF),
                                              Color(0xFF8758F2),
                                            ],
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              PhosphorIcons.lightning(),
                                              size: 16,
                                              color: Colors.white,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              l10n.shellBadge,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelLarge
                                                  ?.copyWith(
                                                    color: Colors.white,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 18),
                                      Text(
                                        l10n.appTitle,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.headlineSmall,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        l10n.appTagline,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                            ),
                                      ),
                                      const SizedBox(height: 28),
                                      for (
                                        var i = 0;
                                        i < destinations.length;
                                        i++
                                      ) ...[
                                        _SidebarButton(
                                          destination: destinations[i],
                                          selected: i == safeIndex,
                                        ),
                                        const SizedBox(height: 8),
                                      ],
                                      const Spacer(),
                                      _UserCard(profile: profile),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 18, 18, 18),
                    child: Column(
                      children: [
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1600),
                            child: AppCard(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 18,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          destinations[safeIndex].label,
                                          style: Theme.of(context)
                                              .textTheme
                                              .headlineSmall
                                              ?.copyWith(fontSize: 24),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          l10n.shellSubtitle,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  const AppLanguageSwitcher(),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 1600),
                              child: pageContent,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileTopBarTitle extends StatelessWidget {
  const _MobileTopBarTitle({
    required this.appTitle,
    required this.sectionLabel,
    required this.veryNarrow,
  });

  final String appTitle;
  final String sectionLabel;
  final bool veryNarrow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryLabel = veryNarrow ? sectionLabel : appTitle;
    final secondaryLabel = veryNarrow ? appTitle : sectionLabel;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          primaryLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
            fontSize: veryNarrow ? 18 : 20,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          secondaryLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _MobileBottomBar extends StatelessWidget {
  const _MobileBottomBar({
    required this.height,
    required this.currentIndex,
    required this.destinations,
  });

  final double height;
  final int currentIndex;
  final List<_ShellDestination> destinations;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          children: [
            for (var index = 0; index < destinations.length; index++)
              Expanded(
                child: _MobileNavButton(
                  destination: destinations[index],
                  selected: index == currentIndex,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MobileNavButton extends StatelessWidget {
  const _MobileNavButton({required this.destination, required this.selected});

  final _ShellDestination destination;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Tooltip(
      message: destination.label,
      child: Semantics(
        button: true,
        selected: selected,
        label: destination.label,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => context.go(destination.route),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            height: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: selected
                  ? Colors.white.withValues(alpha: 0.84)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(22),
              border: selected
                  ? Border.all(color: scheme.primary.withValues(alpha: 0.16))
                  : null,
              boxShadow: selected
                  ? const [
                      BoxShadow(
                        color: Color(0x14141F52),
                        blurRadius: 18,
                        offset: Offset(0, 10),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  destination.icon,
                  size: 22,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(height: 5),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    destination.label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    softWrap: false,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 10.5,
                      height: 1.15,
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarButton extends StatelessWidget {
  const _SidebarButton({required this.destination, required this.selected});

  final _ShellDestination destination;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => context.go(destination.route),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: selected
              ? const LinearGradient(
                  colors: [Color(0x144D5CFF), Color(0x128758F2)],
                )
              : null,
          border: Border.all(
            color: selected
                ? scheme.primary.withValues(alpha: 0.22)
                : scheme.outline,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: selected
                    ? scheme.primary.withValues(alpha: 0.14)
                    : Colors.white.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                destination.icon,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                destination.label,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: selected ? scheme.primary : scheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UserCard extends ConsumerWidget {
  const _UserCard({required this.profile});

  final UserProfile? profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authService = ref.watch(phoneAuthServiceProvider);
    final l10n = AppLocalizations.of(context);
    return AppCard(
      padding: const EdgeInsets.all(18),
      color: Colors.white.withValues(alpha: 0.72),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            profile?.fullName.isNotEmpty == true
                ? profile!.fullName
                : l10n.userOnlyWorkspace,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            formatPhoneDisplay(profile?.phoneNumber ?? ''),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.68),
              border: Border.all(color: Theme.of(context).colorScheme.outline),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Icon(
                  PhosphorIcons.lightning(),
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.userRoleLabel,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                final confirmed = await showAppConfirmationDialog(
                  context: context,
                  title: l10n.signOutConfirmTitle,
                  message: l10n.signOutConfirmMessage,
                  confirmLabel: l10n.signOutConfirmAction,
                  cancelLabel: l10n.signOutStay,
                  icon: Icons.logout_rounded,
                  accentColor: Theme.of(context).colorScheme.error,
                );
                if (!confirmed) {
                  return;
                }
                await authService.signOut();
              },
              icon: Icon(PhosphorIcons.signOut()),
              label: Text(l10n.signOut),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShellDestination {
  const _ShellDestination({
    required this.route,
    required this.label,
    required this.icon,
  });

  final String route;
  final String label;
  final IconData icon;
}
