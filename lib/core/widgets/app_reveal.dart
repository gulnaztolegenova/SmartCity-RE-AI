import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AppReveal extends StatefulWidget {
  const AppReveal({
    required this.child,
    this.enabled = true,
    this.duration = const Duration(milliseconds: 180),
    this.curve = Curves.easeOutCubic,
    this.offsetY = 10,
    this.scaleBegin = 0.996,
    this.opacityBegin = 0.22,
    super.key,
  });

  final Widget child;
  final bool enabled;
  final Duration duration;
  final Curve curve;
  final double offsetY;
  final double scaleBegin;
  final double opacityBegin;

  @override
  State<AppReveal> createState() => _AppRevealState();
}

class _AppRevealState extends State<AppReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: 1,
  );

  late Animation<double> _animation = CurvedAnimation(
    parent: _controller,
    curve: widget.curve,
  );
  bool _animatedOnce = false;

  bool get _animationsEnabled {
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return widget.enabled &&
        !disableAnimations &&
        widget.duration != Duration.zero;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_animatedOnce || !_animationsEnabled) {
      _controller.value = 1;
      return;
    }

    _animatedOnce = true;
    _controller.forward(from: 0);
  }

  @override
  void didUpdateWidget(covariant AppReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
    }
    if (oldWidget.curve != widget.curve) {
      _animation = CurvedAnimation(parent: _controller, curve: widget.curve);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_animationsEnabled) {
      return widget.child;
    }

    final effectiveOffsetY = kIsWeb ? widget.offsetY * 0.5 : widget.offsetY;
    final effectiveScaleBegin = kIsWeb
        ? 1 - ((1 - widget.scaleBegin) * 0.35)
        : widget.scaleBegin;
    final effectiveOpacityBegin = kIsWeb
        ? 1 - ((1 - widget.opacityBegin) * 0.35)
        : widget.opacityBegin;

    return AnimatedBuilder(
      animation: _animation,
      child: widget.child,
      builder: (context, revealedChild) {
        final value = _animation.value;
        final opacity =
            effectiveOpacityBegin + ((1 - effectiveOpacityBegin) * value);
        final translateY = (1 - value) * effectiveOffsetY;
        final scale = effectiveScaleBegin + ((1 - effectiveScaleBegin) * value);

        return Opacity(
          opacity: opacity.clamp(0, 1),
          child: Transform.translate(
            offset: Offset(0, translateY),
            child: Transform.scale(scale: scale, child: revealedChild),
          ),
        );
      },
    );
  }
}
