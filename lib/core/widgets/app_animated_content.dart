import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AppAnimatedContent extends StatefulWidget {
  const AppAnimatedContent({
    required this.child,
    required this.contentKey,
    this.duration = const Duration(milliseconds: 180),
    this.alignment = Alignment.topLeft,
    super.key,
  });

  final Widget child;
  final Object contentKey;
  final Duration duration;
  final Alignment alignment;

  @override
  State<AppAnimatedContent> createState() => _AppAnimatedContentState();
}

class _AppAnimatedContentState extends State<AppAnimatedContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  late Object _currentKey = widget.contentKey;

  @override
  void initState() {
    super.initState();
    _controller.value = 1;
  }

  bool get _animationsEnabled {
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return !disableAnimations && widget.duration != Duration.zero;
  }

  @override
  void didUpdateWidget(covariant AppAnimatedContent oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
      _curve = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    }

    if (oldWidget.contentKey != widget.contentKey) {
      _currentKey = widget.contentKey;
      if (_animationsEnabled) {
        _controller.forward(from: 0);
      } else {
        _controller.value = 1;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyedChild = KeyedSubtree(
      key: ValueKey(_currentKey),
      child: RepaintBoundary(
        child: Align(alignment: widget.alignment, child: widget.child),
      ),
    );

    if (!_animationsEnabled) {
      return keyedChild;
    }

    final slideDistance = kIsWeb ? 8.0 : 12.0;
    final scaleStart = kIsWeb ? 0.998 : 0.994;

    return AnimatedBuilder(
      animation: _curve,
      child: keyedChild,
      builder: (context, child) {
        final value = _curve.value;
        final opacity = 0.18 + (0.82 * value);
        final translateY = (1 - value) * slideDistance;
        final scale = scaleStart + ((1 - scaleStart) * value);

        return Opacity(
          opacity: opacity.clamp(0, 1),
          child: Transform.translate(
            offset: Offset(0, translateY),
            child: Transform.scale(scale: scale, child: child),
          ),
        );
      },
    );
  }
}
