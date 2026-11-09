import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

class AnimatedEnergyScene extends StatefulWidget {
  const AnimatedEnergyScene({super.key, this.compact = false});

  final bool compact;

  @override
  State<AnimatedEnergyScene> createState() => _AnimatedEnergySceneState();
}

class _AnimatedEnergySceneState extends State<AnimatedEnergyScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.compact ? 160.0 : 220.0;
    final sunSize = widget.compact ? 46.0 : 64.0;
    final panelWidth = widget.compact ? 110.0 : 150.0;
    final panelHeight = widget.compact ? 62.0 : 82.0;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return SizedBox(
          width: size * 1.5,
          height: size,
          child: Stack(
            children: [
              Positioned(
                top: widget.compact ? 6 : 2,
                left: (size * 1.5 - sunSize) / 2,
                child: Transform.scale(
                  scale: 0.96 + (0.08 * math.sin(t * math.pi * 2)),
                  child: Container(
                    width: sunSize,
                    height: sunSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const RadialGradient(
                        colors: [Color(0xFFFFE38A), Color(0xFFF2C24C)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0x55F2C24C),
                          blurRadius: widget.compact ? 18 : 28,
                          spreadRadius: widget.compact ? 7 : 12,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                right: widget.compact ? -4 : 4,
                bottom: widget.compact ? 8 : 14,
                child: IgnorePointer(
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(
                      sigmaX: widget.compact ? 22 : 30,
                      sigmaY: widget.compact ? 22 : 30,
                    ),
                    child: Container(
                      width: widget.compact ? 118 : 154,
                      height: widget.compact ? 118 : 154,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            const Color(0x608758F2),
                            const Color(0x384D5CFF),
                            const Color(0x18F2C24C),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.36, 0.7, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                bottom: 8,
                child: Transform(
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.001)
                    ..rotateX(0.78),
                  alignment: Alignment.center,
                  child: Container(
                    width: panelWidth,
                    height: panelHeight,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF323E9A), Color(0xFF6A55E2)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(
                        color: const Color(0xAACED5FF),
                        width: 1.2,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x1E4D5CFF),
                          blurRadius: 18,
                          offset: Offset(0, 12),
                        ),
                      ],
                    ),
                    child: CustomPaint(painter: _SolarGridPainter()),
                  ),
                ),
              ),
              Positioned(
                left: widget.compact ? 82 : 116,
                bottom: widget.compact ? 70 : 98,
                child: Opacity(
                  opacity: 0.55 + 0.25 * math.sin(t * math.pi * 2),
                  child: Icon(
                    Icons.bolt_rounded,
                    color: const Color(0xFFF2C24C),
                    size: widget.compact ? 18 : 24,
                  ),
                ),
              ),
              Positioned(
                right: widget.compact ? 18 : 24,
                bottom: 0,
                child: SizedBox(
                  width: widget.compact ? 70 : 92,
                  height: widget.compact ? 132 : 168,
                  child: CustomPaint(
                    painter: _WindTurbinePainter(rotation: t * math.pi * 2),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SolarGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x55EEF2FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    const horizontalLines = 4;
    const verticalLines = 6;
    for (var i = 1; i < horizontalLines; i++) {
      final y = size.height * i / horizontalLines;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    for (var i = 1; i < verticalLines; i++) {
      final x = size.width * i / verticalLines;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _WindTurbinePainter extends CustomPainter {
  const _WindTurbinePainter({required this.rotation});

  final double rotation;

  @override
  void paint(Canvas canvas, Size size) {
    final polePaint = Paint()
      ..color = const Color(0xFF606A9B)
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    final bladePaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFF8F7FF), Color(0xFFD8DCFF)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;
    final nacellePaint = Paint()..color = const Color(0xFFBEC5F1);

    final hub = Offset(size.width * 0.55, size.height * 0.28);
    canvas.drawLine(Offset(size.width * 0.55, size.height), hub, polePaint);
    canvas.drawCircle(hub, 8, nacellePaint);

    canvas.save();
    canvas.translate(hub.dx, hub.dy);
    canvas.rotate(rotation);
    for (var i = 0; i < 3; i++) {
      canvas.save();
      canvas.rotate(i * 2 * math.pi / 3);
      final blade = Path()
        ..moveTo(-4, 0)
        ..quadraticBezierTo(size.width * 0.16, -8, size.width * 0.28, 0)
        ..quadraticBezierTo(size.width * 0.16, 8, -4, 0);
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
