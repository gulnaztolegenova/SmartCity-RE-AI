import 'package:flutter/material.dart';

import 'app_reveal.dart';

class AppCard extends StatelessWidget {
  const AppCard({
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.color,
    this.onTap,
    this.animated = false,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final VoidCallback? onTap;
  final bool animated;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(24);
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color:
            color ??
            Theme.of(context).cardTheme.color?.withValues(alpha: 0.88) ??
            Colors.white.withValues(alpha: 0.88),
        borderRadius: borderRadius,
        boxShadow: const [
          BoxShadow(
            color: Color(0x12131E4E),
            blurRadius: 24,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: child,
    );

    final material = Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: borderRadius,
        side: BorderSide(color: Theme.of(context).colorScheme.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: content,
    );

    final card = onTap == null
        ? material
        : Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: borderRadius,
              child: material,
            ),
          );

    return AppReveal(enabled: animated, child: card);
  }
}
