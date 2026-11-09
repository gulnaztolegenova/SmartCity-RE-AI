import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static const _background = Color(0xFFF6F4FF);
  static const _surface = Color(0xFFFFFFFF);
  static const _primary = Color(0xFF4D5CFF);
  static const _secondary = Color(0xFF8758F2);
  static const _tertiary = Color(0xFFF2C24C);
  static const _outline = Color(0xFFD9DDF6);
  static const _text = Color(0xFF1E2150);
  static const _mutedText = Color(0xFF6C7199);
  static const _success = Color(0xFF24A76D);
  static const _danger = Color(0xFFE05A65);
  static const _fontFamily = 'Inter';

  static ThemeData light() {
    final base = ThemeData.light(useMaterial3: true);
    final textTheme = base.textTheme
        .apply(fontFamily: _fontFamily, bodyColor: _text, displayColor: _text)
        .copyWith(
          displaySmall: _interText(fontSize: 36, fontWeight: FontWeight.w800),
          headlineMedium: _interText(fontSize: 28, fontWeight: FontWeight.w800),
          headlineSmall: _interText(fontSize: 24, fontWeight: FontWeight.w800),
          titleLarge: _interText(fontSize: 20, fontWeight: FontWeight.w800),
          titleMedium: _interText(fontSize: 16, fontWeight: FontWeight.w700),
          bodyLarge: _interText(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            height: 1.45,
          ),
          bodyMedium: _interText(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            height: 1.5,
          ),
          bodySmall: _interText(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _mutedText,
          ),
          labelLarge: _interText(fontSize: 14, fontWeight: FontWeight.w800),
        );

    final colorScheme = ColorScheme.fromSeed(
      seedColor: _primary,
      brightness: Brightness.light,
      primary: _primary,
      secondary: _secondary,
      tertiary: _tertiary,
      surface: _surface,
      outline: _outline,
      error: _danger,
    );

    return base.copyWith(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: _background,
      textTheme: textTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        foregroundColor: _text,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFFD8DDF9),
          disabledForegroundColor: const Color(0xFF7C84B4),
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: _interText(fontSize: 14, fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _text,
          side: const BorderSide(color: _outline),
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: _interText(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: _primary,
          textStyle: _interText(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
      cardTheme: CardThemeData(
        color: _surface.withValues(alpha: 0.86),
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: _outline),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.90),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        labelStyle: _interText(color: _mutedText, fontWeight: FontWeight.w600),
        hintStyle: _interText(color: _mutedText, fontWeight: FontWeight.w500),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: _outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: _primary, width: 1.4),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: _outline),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: _danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: _danger, width: 1.4),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: _interText(color: _text, fontWeight: FontWeight.w700),
        menuStyle: MenuStyle(
          backgroundColor: const WidgetStatePropertyAll(Colors.white),
          shadowColor: const WidgetStatePropertyAll(Color(0x220F194E)),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.white),
          elevation: const WidgetStatePropertyAll(18),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(vertical: 10),
          ),
          side: const WidgetStatePropertyAll(
            BorderSide(color: _outline, width: 1.1),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white.withValues(alpha: 0.78),
        selectedColor: const Color(0xFFECEAFF),
        disabledColor: const Color(0xFFF0F1FA),
        labelStyle: _interText(color: _text, fontWeight: FontWeight.w700),
        secondaryLabelStyle: _interText(
          color: _primary,
          fontWeight: FontWeight.w800,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: _outline),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white.withValues(alpha: 0.92),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: const BorderSide(color: _outline),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF262C5B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      dividerColor: _outline,
      dataTableTheme: const DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(Colors.white),
        dividerThickness: 0.6,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white.withValues(alpha: 0.92),
        indicatorColor: _primary.withValues(alpha: 0.12),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return _interText(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: states.contains(WidgetState.selected)
                ? _primary
                : _mutedText,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        useIndicator: true,
        indicatorColor: _primary.withValues(alpha: 0.12),
        selectedIconTheme: const IconThemeData(color: _primary),
        unselectedIconTheme: const IconThemeData(color: _mutedText),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: _primary,
        foregroundColor: Colors.white,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: _primary),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
      extensions: const <ThemeExtension<dynamic>>[
        _StatusColors(success: _success, warning: _tertiary),
      ],
    );
  }

  static TextStyle _interText({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
  }) {
    return TextStyle(
      fontFamily: _fontFamily,
      package: null,
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color ?? _text,
      height: height,
    );
  }
}

class _StatusColors extends ThemeExtension<_StatusColors> {
  const _StatusColors({required this.success, required this.warning});

  final Color success;
  final Color warning;

  @override
  ThemeExtension<_StatusColors> copyWith({Color? success, Color? warning}) {
    return _StatusColors(
      success: success ?? this.success,
      warning: warning ?? this.warning,
    );
  }

  @override
  ThemeExtension<_StatusColors> lerp(
    covariant ThemeExtension<_StatusColors>? other,
    double t,
  ) {
    if (other is! _StatusColors) {
      return this;
    }
    return _StatusColors(
      success: Color.lerp(success, other.success, t) ?? success,
      warning: Color.lerp(warning, other.warning, t) ?? warning,
    );
  }
}
