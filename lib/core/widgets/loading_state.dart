import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:smart_city_renewable_ai/l10n/app_localizations.dart';

import 'app_ambient_background.dart';
import 'app_card.dart';

class LoadingScaffold extends StatelessWidget {
  const LoadingScaffold({this.title, this.subtitle, super.key});

  final String? title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          AppAmbientBackground(),
          Center(
            child: LoadingState(
              title: title ?? l10n.appTitle,
              subtitle: subtitle ?? l10n.appTagline,
            ),
          ),
        ],
      ),
    );
  }
}

class LoadingState extends StatelessWidget {
  const LoadingState({
    this.title,
    this.subtitle,
    this.compact = false,
    super.key,
  });

  final String? title;
  final String? subtitle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxWidth = compact ? 420.0 : 520.0;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: AppCard(
          animated: true,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 22 : 28,
            vertical: compact ? 22 : 28,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _WindLoader(compact: compact),
              SizedBox(height: compact ? 16 : 22),
              if (title != null && title!.trim().isNotEmpty)
                Text(
                  title!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
              if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.55,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _WindLoader extends StatefulWidget {
  const _WindLoader({required this.compact});

  final bool compact;

  @override
  State<_WindLoader> createState() => _WindLoaderState();
}

class _WindLoaderState extends State<_WindLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1650),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = widget.compact ? 164.0 : 204.0;
    final height = widget.compact ? 90.0 : 116.0;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final progress = _controller.value;
        final shimmerOffset = -1.0 + (progress * 2.0);

        return SizedBox(
          width: width,
          height: height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          colors: [
                            const Color(0x668758F2),
                            const Color(0x334D5CFF),
                            const Color(0x22F2C24C),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.42, 0.74, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: width * 0.72,
                  height: height * 0.62,
                  child: CustomPaint(
                    painter: _WindHeadPainter(rotation: progress * math.pi * 2),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: widget.compact ? 8 : 10,
                child: Column(
                  children: [
                    Container(
                      height: widget.compact ? 10 : 12,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: const Color(0xFFDDE2FF),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        children: [
                          Align(
                            alignment: Alignment(shimmerOffset, 0),
                            child: FractionallySizedBox(
                              widthFactor: 0.36,
                              child: Container(
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Color(0xFF4D5CFF),
                                      Color(0xFF8758F2),
                                      Color(0xFFF2C24C),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: widget.compact ? 9 : 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(3, (index) {
                        final active =
                            ((progress * 6).floor() + index) % 3 == 0;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 240),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: active ? 24 : 12,
                          height: 6,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            color: active
                                ? const Color(0xFF4D5CFF)
                                : const Color(0xFFC9D0F7),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _WindHeadPainter extends CustomPainter {
  const _WindHeadPainter({required this.rotation});

  final double rotation;

  @override
  void paint(Canvas canvas, Size size) {
    final mastPaint = Paint()
      ..color = const Color(0xFF6A709D)
      ..strokeWidth = size.width * 0.05
      ..strokeCap = StrokeCap.round;
    final hubPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFF5F7FF), Color(0xFFD5DBFF)],
      ).createShader(Offset.zero & size);
    final nacellePaint = Paint()..color = const Color(0xFF9AA4E8);

    final hub = Offset(size.width * 0.52, size.height * 0.42);
    canvas.drawLine(Offset(size.width * 0.52, size.height), hub, mastPaint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(size.width * 0.52, size.height * 0.44),
          width: size.width * 0.12,
          height: size.height * 0.09,
        ),
        const Radius.circular(999),
      ),
      nacellePaint,
    );
    canvas.drawCircle(hub, size.width * 0.06, hubPaint);

    canvas.save();
    canvas.translate(hub.dx, hub.dy);
    canvas.rotate(rotation);
    for (var i = 0; i < 3; i++) {
      canvas.save();
      canvas.rotate(i * 2 * math.pi / 3);
      final blade = Path()
        ..moveTo(-size.width * 0.03, 0)
        ..quadraticBezierTo(
          size.width * 0.10,
          -size.height * 0.09,
          size.width * 0.28,
          0,
        )
        ..quadraticBezierTo(
          size.width * 0.10,
          size.height * 0.09,
          -size.width * 0.03,
          0,
        );
      canvas.drawPath(blade, hubPaint);
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WindHeadPainter oldDelegate) {
    return oldDelegate.rotation != rotation;
  }
}
