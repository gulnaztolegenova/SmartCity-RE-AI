import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class OtpCodeField extends StatefulWidget {
  const OtpCodeField({
    required this.onChanged,
    required this.onCompleted,
    this.length = 6,
    this.enabled = true,
    this.autofocus = true,
    this.hasError = false,
    super.key,
  });

  final int length;
  final bool enabled;
  final bool autofocus;
  final bool hasError;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onCompleted;

  @override
  State<OtpCodeField> createState() => _OtpCodeFieldState();
}

class _OtpCodeFieldState extends State<OtpCodeField> {
  late final TextEditingController _controller = TextEditingController();
  late final FocusNode _focusNode = FocusNode();

  String _lastCompletedCode = '';

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChanged);
    _controller.addListener(_handleControllerChanged);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleControllerChanged)
      ..dispose();
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  String get _value => _controller.text;

  void _handleControllerChanged() {
    final sanitized = _controller.text.replaceAll(RegExp(r'\D'), '');
    final trimmed = sanitized.length > widget.length
        ? sanitized.substring(0, widget.length)
        : sanitized;

    if (trimmed != _controller.text) {
      _controller.value = TextEditingValue(
        text: trimmed,
        selection: TextSelection.collapsed(offset: trimmed.length),
      );
      return;
    }

    if (mounted) {
      setState(() {});
    }
    _notifyParent();
  }

  void _notifyParent() {
    final value = _value;
    widget.onChanged(value);
    if (value.length == widget.length && value != _lastCompletedCode) {
      _lastCompletedCode = value;
      widget.onCompleted(value);
    } else if (value.length < widget.length) {
      _lastCompletedCode = '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final outlineColor = widget.hasError
        ? theme.colorScheme.error.withValues(alpha: 0.6)
        : theme.colorScheme.outline;
    final value = _value;
    final focusedIndex = value.length.clamp(0, widget.length - 1);

    return LayoutBuilder(
      builder: (context, constraints) {
        final spacing = constraints.maxWidth < 340
            ? 6.0
            : constraints.maxWidth < 420
            ? 8.0
            : 12.0;
        final rawSize =
            (constraints.maxWidth - (spacing * (widget.length - 1))) /
            widget.length;
        final boxWidth = rawSize.clamp(28.0, 60.0);
        final boxHeight = math.max(
          46.0,
          math.min(66.0, boxWidth * (constraints.maxWidth < 360 ? 1.32 : 1.38)),
        );

        return GestureDetector(
          onTap: widget.enabled ? _focusNode.requestFocus : null,
          behavior: HitTestBehavior.translucent,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(widget.length, (index) {
                  final hasValue = index < value.length;
                  final isActive =
                      _focusNode.hasFocus &&
                      ((value.length == widget.length &&
                              index == widget.length - 1) ||
                          index == focusedIndex);
                  final digit = hasValue ? value[index] : '';

                  return Padding(
                    padding: EdgeInsets.only(
                      right: index == widget.length - 1 ? 0 : spacing,
                    ),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: boxWidth,
                      height: boxHeight,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isActive
                              ? theme.colorScheme.primary
                              : hasValue
                              ? theme.colorScheme.primary.withValues(
                                  alpha: 0.34,
                                )
                              : outlineColor.withValues(alpha: 0.9),
                          width: isActive ? 1.8 : 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: isActive
                                ? theme.colorScheme.primary.withValues(
                                    alpha: 0.14,
                                  )
                                : const Color(0x10141F52),
                            blurRadius: isActive ? 18 : 12,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Center(
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 160),
                          style: theme.textTheme.headlineSmall!.copyWith(
                            fontWeight: FontWeight.w800,
                            color: _digitColor(
                              theme: theme,
                              isActive: isActive,
                              hasValue: hasValue,
                            ),
                          ),
                          child: Text(digit),
                        ),
                      ),
                    ),
                  );
                }),
              ),
              Positioned(
                width: 1,
                height: 1,
                child: Opacity(
                  opacity: 0,
                  child: IgnorePointer(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      enabled: widget.enabled,
                      autofocus: widget.autofocus,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      showCursor: false,
                      enableInteractiveSelection: false,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      style: const TextStyle(
                        color: Colors.transparent,
                        fontSize: 1,
                      ),
                      cursorColor: Colors.transparent,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        isCollapsed: true,
                        counterText: '',
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(widget.length),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Color _digitColor({
    required ThemeData theme,
    required bool isActive,
    required bool hasValue,
  }) {
    if (isActive || hasValue) {
      return theme.colorScheme.primary;
    }

    return theme.colorScheme.onSurface.withValues(alpha: 0.32);
  }
}
