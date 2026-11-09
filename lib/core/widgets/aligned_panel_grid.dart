import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Shared page grid: equal columns and content-sized, equal-height rows.
/// Measures real layouts, so charts, maps and LayoutBuilders are supported.
class AlignedPanelGrid extends StatelessWidget {
  const AlignedPanelGrid({
    required this.children,
    this.maxColumns = 2,
    this.minPanelWidth = 480,
    super.key,
  });

  final List<Widget> children;
  final int maxColumns;
  final double minPanelWidth;
  static const gap = 16.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = math.max(1.0, MediaQuery.textScalerOf(context).scale(1));
      var columns = math.max(
        1,
        math.min(
          maxColumns,
          ((constraints.maxWidth + gap) / (minPanelWidth * scale + gap))
              .floor(),
        ),
      );
      // Balanced groups avoid an isolated last card and empty grid cells.
      while (columns > 1 && children.length % columns != 0) {
        columns--;
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var start = 0; start < children.length; start += columns) ...[
            if (start > 0) const SizedBox(height: gap),
            if (columns == 1)
              children[start]
            else
              _EqualHeightRow(
                children: children.sublist(start, start + columns),
              ),
          ],
        ],
      );
    },
  );
}

class _PanelParentData extends ContainerBoxParentData<RenderBox> {}

class _EqualHeightRow extends MultiChildRenderObjectWidget {
  const _EqualHeightRow({required super.children});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderEqualHeightRow();
}

class _RenderEqualHeightRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _PanelParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _PanelParentData> {
  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _PanelParentData) {
      child.parentData = _PanelParentData();
    }
  }

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    final cellWidth =
        (width - AlignedPanelGrid.gap * (childCount - 1)) / childCount;
    var height = 0.0;
    // First measure each panel at its final width without constraining its height.
    // Unlike intrinsic measurement, this also supports LayoutBuilder and maps.
    var child = firstChild;
    while (child != null) {
      child.layout(
        BoxConstraints.tightFor(width: cellWidth),
        parentUsesSize: true,
      );
      height = math.max(height, child.size.height);
      child = childAfter(child);
    }
    size = constraints.constrain(Size(width, height));
    var x = 0.0;
    child = firstChild;
    while (child != null) {
      child.layout(
        BoxConstraints.tightFor(width: cellWidth, height: height),
        parentUsesSize: true,
      );
      (child.parentData! as _PanelParentData).offset = Offset(x, 0);
      x += cellWidth + AlignedPanelGrid.gap;
      child = childAfter(child);
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
