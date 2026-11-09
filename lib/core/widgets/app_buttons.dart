import 'dart:async';

import 'package:flutter/material.dart';

class AppPrimaryButton extends StatefulWidget {
  const AppPrimaryButton({
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
    super.key,
  });

  final String label;
  final FutureOr<void> Function()? onPressed;
  final bool isLoading;
  final Widget? icon;

  @override
  State<AppPrimaryButton> createState() => _AppPrimaryButtonState();
}

class _AppPrimaryButtonState extends State<AppPrimaryButton> {
  bool _submitting = false;

  bool get _isBusy => widget.isLoading || _submitting;

  Future<void> _handlePressed() async {
    final callback = widget.onPressed;
    if (callback == null || _isBusy) {
      return;
    }

    final result = callback();
    if (result is Future) {
      setState(() => _submitting = true);
      try {
        await result;
      } finally {
        if (mounted) {
          setState(() => _submitting = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final buttonChild = _isBusy
        ? const _ButtonLoader(color: Colors.white)
        : _ButtonContent(label: widget.label, icon: widget.icon);

    return FilledButton(
      onPressed: widget.onPressed == null || _isBusy ? null : _handlePressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        disabledBackgroundColor: _isBusy
            ? Theme.of(context).colorScheme.primary
            : null,
        disabledForegroundColor: Colors.white,
      ),
      child: buttonChild,
    );
  }
}

class AppSecondaryButton extends StatefulWidget {
  const AppSecondaryButton({
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
    this.foregroundColor,
    this.backgroundColor,
    this.borderColor,
    this.loaderColor,
    super.key,
  });

  final String label;
  final FutureOr<void> Function()? onPressed;
  final bool isLoading;
  final Widget? icon;
  final Color? foregroundColor;
  final Color? backgroundColor;
  final Color? borderColor;
  final Color? loaderColor;

  @override
  State<AppSecondaryButton> createState() => _AppSecondaryButtonState();
}

class _AppSecondaryButtonState extends State<AppSecondaryButton> {
  bool _submitting = false;

  bool get _isBusy => widget.isLoading || _submitting;

  Future<void> _handlePressed() async {
    final callback = widget.onPressed;
    if (callback == null || _isBusy) {
      return;
    }

    final result = callback();
    if (result is Future) {
      setState(() => _submitting = true);
      try {
        await result;
      } finally {
        if (mounted) {
          setState(() => _submitting = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final foreground = widget.foregroundColor ?? primary;
    final background = widget.backgroundColor;
    final border = widget.borderColor ?? const Color(0xFFD9DDF6);
    final loaderColor = widget.loaderColor ?? Colors.white;
    final buttonChild = _isBusy
        ? _ButtonLoader(color: loaderColor)
        : _ButtonContent(label: widget.label, icon: widget.icon);

    return OutlinedButton(
      onPressed: widget.onPressed == null || _isBusy ? null : _handlePressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        foregroundColor: foreground,
        backgroundColor: _isBusy
            ? (background ?? primary)
            : (background ?? Colors.white.withValues(alpha: 0.68)),
        disabledBackgroundColor: _isBusy ? (background ?? primary) : background,
        side: BorderSide(color: _isBusy ? (background ?? primary) : border),
        disabledForegroundColor: _isBusy ? loaderColor : foreground,
      ),
      child: buttonChild,
    );
  }
}

class _ButtonContent extends StatelessWidget {
  const _ButtonContent({required this.label, this.icon});

  final String label;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    if (icon == null) {
      return Text(label, textAlign: TextAlign.center);
    }

    if (label.trim().isEmpty) {
      return icon!;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        icon!,
        const SizedBox(width: 10),
        Flexible(child: Text(label, textAlign: TextAlign.center)),
      ],
    );
  }
}

class _ButtonLoader extends StatelessWidget {
  const _ButtonLoader({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(
        strokeWidth: 2.2,
        valueColor: AlwaysStoppedAnimation<Color>(color),
      ),
    );
  }
}
