import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Equal-width cards whose rows grow to fit the longest translated content.
class AdaptiveMetricGrid extends StatelessWidget {
  const AdaptiveMetricGrid({
    required this.children,
    this.maxColumns = 4,
    super.key,
  });
  final List<Widget> children;
  final int maxColumns;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final scale = MediaQuery.textScalerOf(context).scale(1);
      var columns = math.max(
        1,
        math.min(
          maxColumns,
          ((box.maxWidth + 16) / (260 * math.max(1, scale) + 16)).floor(),
        ),
      );
      while (columns > 1 && children.length % columns != 0) {
        columns--;
      }
      return Column(
        children: [
          for (var start = 0; start < children.length; start += columns) ...[
            if (start > 0) const SizedBox(height: 16),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var column = 0; column < columns; column++) ...[
                    if (column > 0) const SizedBox(width: 16),
                    Expanded(
                      child: start + column < children.length
                          ? children[start + column]
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      );
    },
  );
}
