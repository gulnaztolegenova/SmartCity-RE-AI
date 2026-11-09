import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/formatters.dart';

class AppTextField extends StatelessWidget {
  const AppTextField({
    this.controller,
    this.initialValue,
    required this.label,
    this.hint,
    this.validator,
    this.keyboardType,
    this.maxLines = 1,
    this.readOnly = false,
    this.enabled = true,
    this.onTap,
    this.inputFormatters,
    this.suffixIcon,
    this.prefixIcon,
    this.prefixText,
    this.onChanged,
    this.textInputAction,
    this.autofillHints,
    super.key,
  }) : assert(
         controller == null || initialValue == null,
         'Use either controller or initialValue.',
       );

  final TextEditingController? controller;
  final String? initialValue;
  final String label;
  final String? hint;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final int maxLines;
  final bool readOnly;
  final bool enabled;
  final VoidCallback? onTap;
  final List<TextInputFormatter>? inputFormatters;
  final Widget? suffixIcon;
  final Widget? prefixIcon;
  final String? prefixText;
  final ValueChanged<String>? onChanged;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: enabled,
      child: IgnorePointer(
        ignoring: !enabled,
        child: TextFormField(
          controller: controller,
          initialValue: initialValue,
          validator: validator,
          keyboardType: keyboardType,
          maxLines: maxLines,
          readOnly: readOnly || !enabled,
          enabled: true,
          onTap: onTap,
          inputFormatters: inputFormatters,
          onChanged: onChanged,
          textInputAction: textInputAction,
          autofillHints: autofillHints,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            suffixIcon: suffixIcon,
            prefixIcon: prefixIcon,
            prefixText: prefixText,
          ),
        ),
      ),
    );
  }
}

class AppPhoneField extends StatelessWidget {
  const AppPhoneField({
    required this.controller,
    required this.label,
    this.hint,
    this.validator,
    this.readOnly = false,
    this.enabled = true,
    this.onChanged,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? Function(String?)? validator;
  final bool readOnly;
  final bool enabled;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      controller: controller,
      label: label,
      hint: hint,
      keyboardType: TextInputType.phone,
      validator: validator,
      readOnly: readOnly,
      enabled: enabled,
      onChanged: onChanged,
      textInputAction: TextInputAction.done,
      autofillHints: const [AutofillHints.telephoneNumberNational],
      prefixText: '+7 ',
      prefixIcon: const Icon(Icons.phone_rounded),
      inputFormatters: const [KazakhPhoneInputFormatter()],
    );
  }
}

class AppDropdownOption<T> {
  const AppDropdownOption({
    required this.value,
    required this.label,
    this.leadingIcon,
  });

  final T value;
  final String label;
  final Widget? leadingIcon;
}

class AppDropdownMenuField<T> extends StatelessWidget {
  const AppDropdownMenuField({
    required this.label,
    required this.options,
    required this.selectedValue,
    required this.onSelected,
    this.prefixIcon,
    this.enabled = true,
    this.width,
    this.menuHeight = 280,
    super.key,
  });

  final String label;
  final List<AppDropdownOption<T>> options;
  final T? selectedValue;
  final ValueChanged<T?>? onSelected;
  final Widget? prefixIcon;
  final bool enabled;
  final double? width;
  final double menuHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final resolvedWidth =
            width ??
            (constraints.maxWidth.isFinite ? constraints.maxWidth : null);
        final decorationTheme = theme.inputDecorationTheme.copyWith(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 18,
          ),
        );

        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: enabled
                ? const [
                    BoxShadow(
                      color: Color(0x14141F52),
                      blurRadius: 22,
                      offset: Offset(0, 12),
                    ),
                  ]
                : null,
          ),
          child: TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 220),
            tween: Tween(begin: 0.0, end: 1.0),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) {
              return Transform.translate(
                offset: Offset(0, (1 - value) * 6),
                child: Opacity(opacity: value, child: child),
              );
            },
            child: DropdownMenu<T>(
              key: ValueKey<Object?>('$label::$selectedValue'),
              width: resolvedWidth,
              enabled: enabled,
              maxLines: null,
              menuHeight: menuHeight,
              requestFocusOnTap: false,
              enableFilter: false,
              initialSelection: selectedValue,
              onSelected: enabled ? onSelected : null,
              label: Text(label),
              leadingIcon: prefixIcon,
              textStyle: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
              inputDecorationTheme: decorationTheme,
              trailingIcon: const Icon(Icons.keyboard_arrow_down_rounded),
              selectedTrailingIcon: const Icon(Icons.keyboard_arrow_up_rounded),
              menuStyle: MenuStyle(
                backgroundColor: const WidgetStatePropertyAll(Colors.white),
                surfaceTintColor: const WidgetStatePropertyAll(Colors.white),
                shadowColor: const WidgetStatePropertyAll(Color(0x220F194E)),
                elevation: const WidgetStatePropertyAll(18),
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(vertical: 10),
                ),
                side: WidgetStatePropertyAll(
                  BorderSide(
                    color: theme.colorScheme.outline.withValues(alpha: 0.96),
                  ),
                ),
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),
              dropdownMenuEntries: options
                  .map(
                    (option) => DropdownMenuEntry<T>(
                      value: option.value,
                      label: option.label,
                      leadingIcon: option.leadingIcon,
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        );
      },
    );
  }
}
