import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:smart_city_renewable_ai/l10n/app_localizations.dart';

import '../../../../core/generated/deploy_metadata.g.dart';
import '../../../../core/widgets/app_ambient_background.dart';
import '../../../../core/widgets/app_language_switcher.dart';
import 'auth_energy_landscape.dart';

class AuthStageScaffold extends StatelessWidget {
  const AuthStageScaffold({
    required this.child,
    this.maxWidth = 560,
    this.showBrand = true,
    this.onRefresh,
    super.key,
  });

  final Widget child;
  final double maxWidth;
  final bool showBrand;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final isCompact = size.width < 760;
    final isKeyboardVisible = viewInsets.bottom > 0;
    final horizontalPadding = isCompact ? 16.0 : 32.0;
    final verticalPadding = isCompact ? 16.0 : 28.0;
    final l10n = AppLocalizations.of(context);
    final localeTag = Localizations.localeOf(context).toLanguageTag();
    final deployedAt = DateTime.tryParse(kLastDeployAtIso8601)?.toLocal();
    final deployedAtText = deployedAt == null
        ? ''
        : '${l10n.lastUpdatedLabel}\n'
              '${DateFormat('y-MMMM-dd HH:mm', localeTag).format(deployedAt)}';

    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: AppAmbientBackground.auth()),
          const Positioned.fill(child: AuthEnergyLandscape()),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  verticalPadding,
                  horizontalPadding,
                  0,
                ),
                child: RepaintBoundary(
                  child: AppLanguageSwitcher(compact: isCompact),
                ),
              ),
            ),
          ),
          SafeArea(
            child: RepaintBoundary(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final availableHeight = math.max(
                    0.0,
                    constraints.maxHeight - (verticalPadding * 2),
                  );

                  final scrollView = SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      verticalPadding,
                      horizontalPadding,
                      verticalPadding + viewInsets.bottom + 24,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: math.max(0, availableHeight),
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: maxWidth),
                          child: Column(
                            mainAxisAlignment: isCompact || isKeyboardVisible
                                ? MainAxisAlignment.start
                                : MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(height: isCompact ? 46 : 18),
                              if (showBrand) ...[
                                Text(
                                  l10n.appTitle,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: isCompact
                                        ? (isKeyboardVisible ? 26 : 32)
                                        : 48,
                                    height: 1,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: isCompact ? -1.2 : -1.8,
                                    color: const Color(0xFF152644),
                                  ),
                                ),
                                SizedBox(height: isCompact ? 18 : 26),
                              ],
                              child,
                              if (!isKeyboardVisible &&
                                  deployedAtText.trim().isNotEmpty) ...[
                                const SizedBox(height: 18),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.38),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: 0.55,
                                      ),
                                    ),
                                  ),
                                  child: Text(
                                    deployedAtText,
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          height: 1.45,
                                          color: const Color(0xC21B2850),
                                          shadows: const [
                                            Shadow(
                                              color: Color(0x66FFFFFF),
                                              blurRadius: 10,
                                            ),
                                          ],
                                        ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  );

                  if (onRefresh == null) {
                    return scrollView;
                  }

                  return RefreshIndicator.adaptive(
                    onRefresh: onRefresh!,
                    edgeOffset: verticalPadding + 12,
                    child: scrollView,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
