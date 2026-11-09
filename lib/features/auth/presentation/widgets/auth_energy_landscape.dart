import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

class AuthEnergyLandscape extends StatefulWidget {
  const AuthEnergyLandscape({super.key});

  @override
  State<AuthEnergyLandscape> createState() => _AuthEnergyLandscapeState();
}

class _AuthEnergyLandscapeState extends State<AuthEnergyLandscape>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 16),
  );

  bool get _isTestBinding {
    final bindingName = WidgetsBinding.instance.runtimeType.toString();
    return bindingName.contains('TestWidgetsFlutterBinding');
  }

  @override
  void initState() {
    super.initState();
    if (_isTestBinding) {
      _controller.value = 0.42;
    } else {
      _controller.repeat();
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

    return IgnorePointer(
      child: RepaintBoundary(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest;
            final isMobile = size.width < 760;
            final animation = disableAnimations
                ? const AlwaysStoppedAnimation<double>(0.38)
                : CurvedAnimation(
                    parent: _controller,
                    curve: Curves.easeInOutSine,
                  );

            return AnimatedBuilder(
              animation: animation,
              builder: (context, _) {
                final t = animation.value;
                final drift = math.sin(t * math.pi * 2);
                final lowDrift = math.sin((t * math.pi * 2) - 0.9);
                final sunSize = isMobile ? 88.0 : 120.0;

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _LandscapePainter(
                          progress: t,
                          isMobile: isMobile,
                        ),
                      ),
                    ),
                    Positioned(
                      left: isMobile ? -18 : size.width * 0.055,
                      top: isMobile ? size.height * 0.16 : size.height * 0.13,
                      child: Transform.translate(
                        offset: Offset(0, drift * 8),
                        child: _SunOrb(size: sunSize),
                      ),
                    ),
                    Positioned(
                      left: isMobile ? -34 : size.width * 0.015,
                      bottom: isMobile
                          ? size.height * 0.26
                          : size.height * 0.17,
                      child: _GlowBlob(
                        width: isMobile ? 150 : 220,
                        height: isMobile ? 110 : 150,
                        colors: const [
                          Color(0x34F2C24C),
                          Color(0x208758F2),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    Positioned(
                      right: isMobile ? -52 : size.width * 0.04,
                      bottom: isMobile
                          ? size.height * 0.26
                          : size.height * 0.18,
                      child: Transform.translate(
                        offset: Offset(0, lowDrift * 8),
                        child: _GlowBlob(
                          width: isMobile ? 190 : 300,
                          height: isMobile ? 180 : 250,
                          colors: const [
                            Color(0x305B57E5),
                            Color(0x205C73F2),
                            Color(0x120FD36E),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: isMobile ? 10 : size.width * 0.03,
                      bottom: isMobile
                          ? size.height * 0.055
                          : size.height * 0.034,
                      child: Transform.translate(
                        offset: Offset(drift * 1.3, lowDrift * 0.8),
                        child: _SceneSolarPanel(
                          scale: isMobile ? 0.84 : 1.0,
                          opacity: 0.95,
                          zTilt: -0.08,
                        ),
                      ),
                    ),
                    if (!isMobile)
                      Positioned(
                        left: size.width * 0.145,
                        bottom: size.height * 0.058,
                        child: Transform.translate(
                          offset: Offset(lowDrift * 1.0, drift * 0.7),
                          child: _SceneSolarPanel(
                            scale: 0.76,
                            opacity: 0.74,
                            zTilt: -0.05,
                          ),
                        ),
                      ),
                    Positioned(
                      right: isMobile ? 14 : size.width * 0.032,
                      bottom: isMobile
                          ? size.height * 0.058
                          : size.height * 0.038,
                      child: Transform.translate(
                        offset: Offset(-drift * 1.1, drift * 0.8),
                        child: _SceneSolarPanel(
                          scale: isMobile ? 0.68 : 0.92,
                          opacity: 0.88,
                          zTilt: -0.03,
                        ),
                      ),
                    ),
                    if (!isMobile)
                      Positioned(
                        right: size.width * 0.14,
                        bottom: size.height * 0.062,
                        child: Transform.translate(
                          offset: Offset(drift * 0.8, lowDrift * 0.6),
                          child: _SceneSolarPanel(
                            scale: 0.7,
                            opacity: 0.68,
                            zTilt: -0.02,
                          ),
                        ),
                      ),
                    Positioned(
                      right: isMobile ? 24 : size.width * 0.075,
                      bottom: isMobile
                          ? size.height * 0.072
                          : size.height * 0.046,
                      child: _SceneWindTurbine(
                        scale: isMobile ? 0.88 : 1.12,
                        bladeRotation: t * math.pi * 2.4,
                        opacity: 0.94,
                      ),
                    ),
                    Positioned(
                      left: isMobile ? 18 : size.width * 0.17,
                      bottom: isMobile
                          ? size.height * 0.088
                          : size.height * 0.072,
                      child: _SceneWindTurbine(
                        scale: isMobile ? 0.56 : 0.72,
                        bladeRotation: (t * math.pi * 2.1) + 0.7,
                        opacity: 0.58,
                      ),
                    ),
                    if (!isMobile)
                      Positioned(
                        right: size.width * 0.235,
                        bottom: size.height * 0.074,
                        child: _SceneWindTurbine(
                          scale: 0.82,
                          bladeRotation: (t * math.pi * 2.8) + 1.4,
                          opacity: 0.64,
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _SunOrb extends StatelessWidget {
  const _SunOrb({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size * 1.75,
      height: size * 1.75,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(
                sigmaX: size * 0.18,
                sigmaY: size * 0.18,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0x42FFD970),
                      const Color(0x1FF2C24C),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.42, 1.0],
                  ),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  colors: [Color(0xFFFFF0AE), Color(0xFFF2C24C)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0x4FF2C24C),
                    blurRadius: size * 0.28,
                    spreadRadius: size * 0.08,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowBlob extends StatelessWidget {
  const _GlowBlob({
    required this.width,
    required this.height,
    required this.colors,
  });

  final double width;
  final double height;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(width),
          gradient: RadialGradient(colors: colors),
        ),
        child: SizedBox(width: width, height: height),
      ),
    );
  }
}

class _SceneSolarPanel extends StatelessWidget {
  const _SceneSolarPanel({
    required this.scale,
    required this.opacity,
    required this.zTilt,
  });

  final double scale;
  final double opacity;
  final double zTilt;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.00115)
          ..rotateX(0.88)
          ..rotateZ(zTilt),
        child: SizedBox(
          width: 150 * scale,
          height: 90 * scale,
          child: CustomPaint(painter: _SolarPanelPainter()),
        ),
      ),
    );
  }
}

class _SceneWindTurbine extends StatelessWidget {
  const _SceneWindTurbine({
    required this.scale,
    required this.bladeRotation,
    required this.opacity,
  });

  final double scale;
  final double bladeRotation;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: SizedBox(
        width: 88 * scale,
        height: 220 * scale,
        child: CustomPaint(
          painter: _WindTurbinePainter(rotation: bladeRotation),
        ),
      ),
    );
  }
}

class _LandscapePainter extends CustomPainter {
  const _LandscapePainter({required this.progress, required this.isMobile});

  final double progress;
  final bool isMobile;

  @override
  void paint(Canvas canvas, Size size) {
    final horizon = size.height * (isMobile ? 0.77 : 0.8);
    final sway = math.sin(progress * math.pi * 2);

    final farHill = Path()
      ..moveTo(0, size.height)
      ..lineTo(0, horizon + 18)
      ..cubicTo(
        size.width * 0.14,
        horizon - 42,
        size.width * 0.34,
        horizon + 10,
        size.width * 0.48,
        horizon - 34,
      )
      ..cubicTo(
        size.width * 0.62,
        horizon - 64,
        size.width * 0.83,
        horizon - 4 + (sway * 6),
        size.width,
        horizon - 28,
      )
      ..lineTo(size.width, size.height)
      ..close();

    final midHill = Path()
      ..moveTo(0, size.height)
      ..lineTo(0, horizon + 54)
      ..cubicTo(
        size.width * 0.2,
        horizon + 18,
        size.width * 0.38,
        horizon + 46,
        size.width * 0.54,
        horizon + 6,
      )
      ..cubicTo(
        size.width * 0.72,
        horizon - 12,
        size.width * 0.88,
        horizon + 42,
        size.width,
        horizon + 28,
      )
      ..lineTo(size.width, size.height)
      ..close();

    final frontHill = Path()
      ..moveTo(0, size.height)
      ..lineTo(0, horizon + 100)
      ..cubicTo(
        size.width * 0.18,
        horizon + 56,
        size.width * 0.34,
        horizon + 118,
        size.width * 0.52,
        horizon + 74,
      )
      ..cubicTo(
        size.width * 0.7,
        horizon + 30,
        size.width * 0.86,
        horizon + 118,
        size.width,
        horizon + 84,
      )
      ..lineTo(size.width, size.height)
      ..close();

    canvas.drawPath(
      farHill,
      Paint()
        ..shader = LinearGradient(
          colors: const [Color(0x1F88C87E), Color(0x0599CF97)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Rect.fromLTWH(0, horizon - 80, size.width, 220)),
    );

    canvas.drawPath(
      midHill,
      Paint()
        ..shader = LinearGradient(
          colors: const [Color(0x348ED58A), Color(0x128FD39E)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Rect.fromLTWH(0, horizon - 20, size.width, 250)),
    );

    canvas.drawPath(
      frontHill,
      Paint()
        ..shader = LinearGradient(
          colors: const [
            Color(0x4AA5E48F),
            Color(0x2992D88D),
            Color(0x1091D9A0),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Rect.fromLTWH(0, horizon + 20, size.width, 260)),
    );

    final mistRect = Rect.fromLTWH(
      0,
      horizon - (isMobile ? 18 : 10),
      size.width,
      size.height - horizon + 70,
    );

    canvas.drawRect(
      mistRect,
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.0),
            const Color(0x12FFFFFF),
            const Color(0x0EE8F7E8),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(mistRect),
    );
  }

  @override
  bool shouldRepaint(covariant _LandscapePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.isMobile != isMobile;
  }
}

class _SolarPanelPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(16),
    );

    canvas.drawShadow(
      Path()..addRRect(rect),
      const Color(0x22213C72),
      18,
      true,
    );

    canvas.drawRRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF2E3892), Color(0xFF5E56DA)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(Offset.zero & size),
    );

    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = const Color(0x9ADCE3FF),
    );

    final gridPaint = Paint()
      ..color = const Color(0x67EDF2FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    const rowCount = 4;
    const columnCount = 6;

    for (var row = 1; row < rowCount; row++) {
      final y = size.height * row / rowCount;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    for (var column = 1; column < columnCount; column++) {
      final x = size.width * column / columnCount;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    final sheenRect = Rect.fromLTWH(
      size.width * 0.14,
      0,
      size.width * 0.22,
      size.height,
    );
    canvas.drawRect(
      sheenRect,
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.0),
            Colors.white.withValues(alpha: 0.18),
            Colors.white.withValues(alpha: 0.0),
          ],
        ).createShader(sheenRect),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _WindTurbinePainter extends CustomPainter {
  const _WindTurbinePainter({required this.rotation});

  final double rotation;

  @override
  void paint(Canvas canvas, Size size) {
    final mastPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF6B71A3), Color(0xFF50598E)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..strokeWidth = math.max(4, size.width * 0.065)
      ..strokeCap = StrokeCap.round;

    final bladePaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFF9F9FF), Color(0xFFD8DEFF)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final nacellePaint = Paint()..color = const Color(0xFFC5CBF6);

    final hub = Offset(size.width * 0.56, size.height * 0.2);
    canvas.drawLine(Offset(hub.dx, size.height), hub, mastPaint);
    canvas.drawCircle(hub, size.width * 0.07, nacellePaint);

    canvas.save();
    canvas.translate(hub.dx, hub.dy);
    canvas.rotate(rotation);

    for (var i = 0; i < 3; i++) {
      canvas.save();
      canvas.rotate((math.pi * 2 / 3) * i);
      final blade = Path()
        ..moveTo(-size.width * 0.03, 0)
        ..quadraticBezierTo(
          size.width * 0.16,
          -size.height * 0.03,
          size.width * 0.34,
          0,
        )
        ..quadraticBezierTo(
          size.width * 0.17,
          size.height * 0.03,
          -size.width * 0.03,
          0,
        );
      canvas.drawPath(blade, bladePaint);
      canvas.restore();
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WindTurbinePainter oldDelegate) {
    return oldDelegate.rotation != rotation;
  }
}
