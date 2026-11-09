import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/localization/locale_controller.dart';
import '../../l10n/app_localizations.dart';

class AppLanguageSwitcher extends ConsumerStatefulWidget {
  const AppLanguageSwitcher({
    this.compact = false,
    this.expanded = false,
    this.expandUpward = false,
    super.key,
  });

  final bool compact;
  final bool expanded;
  final bool expandUpward;

  @override
  ConsumerState<AppLanguageSwitcher> createState() =>
      _AppLanguageSwitcherState();
}

class _AppLanguageSwitcherState extends ConsumerState<AppLanguageSwitcher> {
  final _buttonKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locale = ref.watch(localeControllerProvider);
    final isNarrow = MediaQuery.sizeOf(context).width < 380;
    final horizontalPadding = widget.compact ? (isNarrow ? 6.0 : 8.0) : 14.0;
    final verticalPadding = widget.compact ? 8.0 : 12.0;
    final borderRadius = BorderRadius.circular(widget.compact ? 18 : 22);

    return Material(
      color: Colors.transparent,
      child: Material(
        color: Colors.transparent,
        borderRadius: borderRadius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: _buttonKey,
          onTap: () => _openPicker(context, locale),
          borderRadius: borderRadius,
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return theme.colorScheme.primary.withValues(alpha: 0.08);
            }
            if (states.contains(WidgetState.hovered)) {
              return const Color(0xFFF2F0FF);
            }
            return Colors.transparent;
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: verticalPadding,
            ),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.88),
              borderRadius: borderRadius,
              border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.92),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0x22141F52),
                  blurRadius: widget.compact ? 14 : 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: widget.expanded
                  ? MainAxisSize.max
                  : MainAxisSize.min,
              children: [
                Container(
                  width: widget.compact ? 26 : 32,
                  height: widget.compact ? 26 : 32,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.language_rounded,
                    size: widget.compact ? 15 : 18,
                    color: theme.colorScheme.primary,
                  ),
                ),
                SizedBox(width: widget.compact ? 6 : 8),
                Flexible(
                  child: Text(
                    _shortLabel(context, locale),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (widget.expanded) const Spacer(),
                const SizedBox(width: 4),
                Icon(
                  widget.expandUpward
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: widget.compact ? 18 : 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openPicker(BuildContext context, Locale locale) async {
    final buttonContext = _buttonKey.currentContext;
    if (buttonContext == null) {
      return;
    }

    final options = _languageOptions(context);
    if (MediaQuery.sizeOf(context).width < 520) {
      final selected = await showModalBottomSheet<Locale>(
        context: context,
        useSafeArea: true,
        showDragHandle: false,
        backgroundColor: Colors.transparent,
        builder: (context) {
          return _LanguageSheet(currentLocale: locale, options: options);
        },
      );

      if (selected != null && mounted) {
        await ref.read(localeControllerProvider.notifier).setLocale(selected);
      }
      return;
    }

    final theme = Theme.of(context);
    final renderBox = buttonContext.findRenderObject() as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final topLeft = renderBox.localToGlobal(Offset.zero, ancestor: overlay);
    final bottomRight = renderBox.localToGlobal(
      renderBox.size.bottomRight(Offset.zero),
      ancestor: overlay,
    );

    const estimatedMenuHeight = 236.0;
    const viewportPadding = 12.0;
    final menuWidth = math.min(
      math.max(248.0, renderBox.size.width),
      overlay.size.width - (viewportPadding * 2),
    );
    final maxLeft = math.max(
      viewportPadding,
      overlay.size.width - menuWidth - viewportPadding,
    );
    final leftPosition =
        (widget.expandUpward ? bottomRight.dx - menuWidth : topLeft.dx)
            .clamp(viewportPadding, maxLeft)
            .toDouble();
    final maxTop = math.max(
      viewportPadding,
      overlay.size.height - estimatedMenuHeight - viewportPadding,
    );
    final topPosition =
        (widget.expandUpward
                ? topLeft.dy - estimatedMenuHeight - 10
                : bottomRight.dy + 10)
            .clamp(viewportPadding, maxTop)
            .toDouble();
    final rightPosition = math.max(
      viewportPadding,
      overlay.size.width - leftPosition - menuWidth,
    );
    final bottomPosition = math.max(
      viewportPadding,
      overlay.size.height - topPosition - estimatedMenuHeight,
    );
    final selected = await showMenu<Locale>(
      context: context,
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: theme.colorScheme.outline.withValues(alpha: 0.92),
        ),
      ),
      constraints: BoxConstraints(minWidth: menuWidth, maxWidth: menuWidth),
      position: RelativeRect.fromLTRB(
        leftPosition,
        topPosition,
        rightPosition,
        bottomPosition,
      ),
      items: options
          .map(
            (option) => PopupMenuItem<Locale>(
              enabled: false,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: _LanguageMenuAction(
                locale: option.locale,
                shortLabel: option.shortLabel,
                fullLabel: option.fullLabel,
                selected: option.locale.languageCode == locale.languageCode,
              ),
            ),
          )
          .toList(growable: false),
    );

    if (selected != null && mounted) {
      await ref.read(localeControllerProvider.notifier).setLocale(selected);
    }
  }

  List<_LanguageOption> _languageOptions(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return [
      _LanguageOption(
        locale: const Locale('kk'),
        shortLabel: l10n.languageShortKazakh,
        fullLabel: l10n.languageKazakh,
      ),
      _LanguageOption(
        locale: const Locale('ru'),
        shortLabel: l10n.languageShortRussian,
        fullLabel: l10n.languageRussian,
      ),
      _LanguageOption(
        locale: const Locale('en'),
        shortLabel: l10n.languageShortEnglish,
        fullLabel: l10n.languageEnglish,
      ),
    ];
  }

  String _shortLabel(BuildContext context, Locale locale) {
    final l10n = AppLocalizations.of(context);
    switch (locale.languageCode) {
      case 'ru':
        return l10n.languageShortRussian;
      case 'en':
        return l10n.languageShortEnglish;
      case 'kk':
      default:
        return l10n.languageShortKazakh;
    }
  }
}

class _LanguageSheet extends StatelessWidget {
  const _LanguageSheet({required this.currentLocale, required this.options});

  final Locale currentLocale;
  final List<_LanguageOption> options;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          clipBehavior: Clip.antiAlias,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.outline.withValues(alpha: 0.92),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final option in options)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _LanguageMenuAction(
                      locale: option.locale,
                      shortLabel: option.shortLabel,
                      fullLabel: option.fullLabel,
                      selected:
                          option.locale.languageCode ==
                          currentLocale.languageCode,
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

class _LanguageMenuAction extends StatelessWidget {
  const _LanguageMenuAction({
    required this.locale,
    required this.shortLabel,
    required this.fullLabel,
    required this.selected,
  });

  final Locale locale;
  final String shortLabel;
  final String fullLabel;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).pop(locale),
        borderRadius: BorderRadius.circular(20),
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) {
            return const Color(0xFFE6E1FF);
          }
          if (states.contains(WidgetState.hovered)) {
            return const Color(0xFFF3F0FF);
          }
          return Colors.transparent;
        }),
        child: _LanguageMenuTile(
          shortLabel: shortLabel,
          fullLabel: fullLabel,
          selected: selected,
        ),
      ),
    );
  }
}

class _LanguageMenuTile extends StatelessWidget {
  const _LanguageMenuTile({
    required this.shortLabel,
    required this.fullLabel,
    required this.selected,
  });

  final String shortLabel;
  final String fullLabel;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: selected
            ? theme.colorScheme.primary.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.18)
              : Colors.transparent,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: selected
                  ? theme.colorScheme.primary.withValues(alpha: 0.12)
                  : const Color(0xFFF7F5FF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Text(
                shortLabel,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              fullLabel,
              style: theme.textTheme.titleMedium?.copyWith(
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface,
              ),
            ),
          ),
          if (selected)
            Icon(
              Icons.check_circle_rounded,
              size: 20,
              color: theme.colorScheme.primary,
            ),
        ],
      ),
    );
  }
}

class _LanguageOption {
  const _LanguageOption({
    required this.locale,
    required this.shortLabel,
    required this.fullLabel,
  });

  final Locale locale;
  final String shortLabel;
  final String fullLabel;
}
