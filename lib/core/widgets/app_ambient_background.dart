import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

enum AppAmbientBackgroundVariant { auth, workspace }

class AppAmbientBackground extends StatefulWidget {
  const AppAmbientBackground({super.key, this.workspace = false})
    : variant = workspace
          ? AppAmbientBackgroundVariant.workspace
          : AppAmbientBackgroundVariant.auth;

  const AppAmbientBackground.auth({super.key})
    : workspace = false,
      variant = AppAmbientBackgroundVariant.auth;

  const AppAmbientBackground.workspace({super.key})
    : workspace = true,
      variant = AppAmbientBackgroundVariant.workspace;

  final bool workspace;
  final AppAmbientBackgroundVariant variant;

  @override
  State<AppAmbientBackground> createState() => _AppAmbientBackgroundState();
}

class _AppAmbientBackgroundState extends State<AppAmbientBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 20),
  );

  bool get _isTestBinding {
    final bindingName = WidgetsBinding.instance.runtimeType.toString();
    return bindingName.contains('TestWidgetsFlutterBinding');
  }

  @override
  void initState() {
    super.initState();
    if (_isTestBinding) {
      _controller.value = 0.5;
    } else {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final isMobile = MediaQuery.sizeOf(context).width < 760;
    final gradientColors = switch (widget.variant) {
      AppAmbientBackgroundVariant.auth => const [
        Color(0xFFF7F5FF),
        Color(0xFFF4F4FF),
        Color(0xFFFFFBF1),
      ],
      AppAmbientBackgroundVariant.workspace => const [
        Color(0xFFF6F3FF),
        Color(0xFFF3F5FF),
        Color(0xFFFBF8FF),
      ],
    };

    final blobs = _resolveSpecs(widget.variant, isMobile);

    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: gradientColors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          IgnorePointer(
            child: Stack(
              fit: StackFit.expand,
              children: [
                for (var index = 0; index < blobs.length; index++)
                  _AmbientBlob(
                    spec: blobs[index],
                    animation: disableAnimations
                        ? const AlwaysStoppedAnimation<double>(0.5)
                        : CurvedAnimation(
                            parent: _controller,
                            curve: Interval(
                              blobs[index].curveStart,
                              blobs[index].curveEnd,
                              curve: Curves.easeInOutSine,
                            ),
                          ),
                  ),
              ],
            ),
          ),
          if (widget.variant == AppAmbientBackgroundVariant.workspace)
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withValues(alpha: kIsWeb ? 0.18 : 0.12),
                      Colors.transparent,
                      const Color(0x14F2C24C),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AmbientBlob extends StatelessWidget {
  const _AmbientBlob({required this.spec, required this.animation});

  final _AmbientBlobSpec spec;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final alignment = AlignmentTween(
      begin: spec.beginAlignment,
      end: spec.endAlignment,
    ).animate(animation);
    final turns = Tween<double>(
      begin: spec.beginTurns,
      end: spec.endTurns,
    ).animate(animation);
    final scale = Tween<double>(
      begin: spec.beginScale,
      end: spec.endScale,
    ).animate(animation);

    return AlignTransition(
      alignment: alignment,
      child: RotationTransition(
        turns: turns,
        child: ScaleTransition(
          scale: scale,
          child: RepaintBoundary(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(
                sigmaX: spec.blurSigma,
                sigmaY: spec.blurSigma,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: spec.borderRadius,
                  gradient: LinearGradient(
                    colors: spec.colors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: SizedBox(width: spec.width, height: spec.height),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AmbientBlobSpec {
  const _AmbientBlobSpec({
    required this.width,
    required this.height,
    required this.beginAlignment,
    required this.endAlignment,
    required this.beginTurns,
    required this.endTurns,
    required this.beginScale,
    required this.endScale,
    required this.blurSigma,
    required this.colors,
    required this.borderRadius,
    required this.curveStart,
    required this.curveEnd,
  });

  final double width;
  final double height;
  final Alignment beginAlignment;
  final Alignment endAlignment;
  final double beginTurns;
  final double endTurns;
  final double beginScale;
  final double endScale;
  final double blurSigma;
  final List<Color> colors;
  final BorderRadius borderRadius;
  final double curveStart;
  final double curveEnd;
}

List<_AmbientBlobSpec> _resolveSpecs(
  AppAmbientBackgroundVariant variant,
  bool isMobile,
) {
  if (variant == AppAmbientBackgroundVariant.auth) {
    return [
      _AmbientBlobSpec(
        width: isMobile ? 240 : 380,
        height: isMobile ? 200 : 300,
        beginAlignment: const Alignment(-0.98, -0.88),
        endAlignment: const Alignment(-0.76, -0.62),
        beginTurns: -0.018,
        endTurns: 0.02,
        beginScale: 0.96,
        endScale: 1.05,
        blurSigma: isMobile ? 58 : 74,
        colors: const [Color(0x484D5CFF), Color(0x128E6BFF)],
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(220),
          topRight: Radius.circular(140),
          bottomLeft: Radius.circular(180),
          bottomRight: Radius.circular(190),
        ),
        curveStart: 0,
        curveEnd: 1,
      ),
      _AmbientBlobSpec(
        width: isMobile ? 250 : 420,
        height: isMobile ? 210 : 320,
        beginAlignment: const Alignment(1.02, -0.08),
        endAlignment: const Alignment(0.78, 0.18),
        beginTurns: 0.015,
        endTurns: -0.02,
        beginScale: 0.95,
        endScale: 1.08,
        blurSigma: isMobile ? 56 : 72,
        colors: const [Color(0x448758F2), Color(0x108758F2)],
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(170),
          topRight: Radius.circular(210),
          bottomLeft: Radius.circular(150),
          bottomRight: Radius.circular(230),
        ),
        curveStart: 0,
        curveEnd: 1,
      ),
      _AmbientBlobSpec(
        width: isMobile ? 210 : 320,
        height: isMobile ? 210 : 320,
        beginAlignment: const Alignment(0.08, 1.06),
        endAlignment: const Alignment(-0.12, 0.80),
        beginTurns: -0.02,
        endTurns: 0.016,
        beginScale: 0.98,
        endScale: 1.06,
        blurSigma: isMobile ? 60 : 74,
        colors: const [Color(0x3CF2C24C), Color(0x108758F2)],
        borderRadius: BorderRadius.circular(220),
        curveStart: 0,
        curveEnd: 1,
      ),
    ];
  }

  return [
    _AmbientBlobSpec(
      width: isMobile ? 220 : 340,
      height: isMobile ? 180 : 260,
      beginAlignment: const Alignment(-0.94, -0.86),
      endAlignment: const Alignment(-0.70, -0.56),
      beginTurns: -0.015,
      endTurns: 0.018,
      beginScale: 0.97,
      endScale: 1.04,
      blurSigma: isMobile ? 52 : 66,
      colors: const [Color(0x2E4D5CFF), Color(0x148758F2)],
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(180),
        topRight: Radius.circular(120),
        bottomLeft: Radius.circular(160),
        bottomRight: Radius.circular(150),
      ),
      curveStart: 0,
      curveEnd: 1,
    ),
    _AmbientBlobSpec(
      width: isMobile ? 240 : 360,
      height: isMobile ? 220 : 280,
      beginAlignment: const Alignment(0.98, -0.24),
      endAlignment: const Alignment(0.74, 0.04),
      beginTurns: 0.012,
      endTurns: -0.018,
      beginScale: 0.94,
      endScale: 1.07,
      blurSigma: isMobile ? 54 : 70,
      colors: const [Color(0x2A8758F2), Color(0x108758F2)],
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(210),
        topRight: Radius.circular(170),
        bottomLeft: Radius.circular(140),
        bottomRight: Radius.circular(230),
      ),
      curveStart: 0,
      curveEnd: 1,
    ),
    _AmbientBlobSpec(
      width: isMobile ? 200 : 300,
      height: isMobile ? 190 : 250,
      beginAlignment: const Alignment(-0.04, 0.98),
      endAlignment: const Alignment(0.12, 0.74),
      beginTurns: 0.01,
      endTurns: -0.01,
      beginScale: 0.98,
      endScale: 1.05,
      blurSigma: isMobile ? 52 : 68,
      colors: const [Color(0x26F2C24C), Color(0x0EFFFFFF)],
      borderRadius: BorderRadius.circular(200),
      curveStart: 0,
      curveEnd: 1,
    ),
    _AmbientBlobSpec(
      width: isMobile ? 160 : 220,
      height: isMobile ? 150 : 200,
      beginAlignment: const Alignment(0.26, -1.02),
      endAlignment: const Alignment(0.10, -0.72),
      beginTurns: -0.01,
      endTurns: 0.012,
      beginScale: 0.95,
      endScale: 1.06,
      blurSigma: isMobile ? 48 : 60,
      colors: const [Color(0x154D5CFF), Color(0x0EFFFFFF)],
      borderRadius: BorderRadius.circular(180),
      curveStart: 0,
      curveEnd: 1,
    ),
  ];
}
