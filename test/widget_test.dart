import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_city_renewable_ai/core/theme/app_theme.dart';
import 'package:smart_city_renewable_ai/core/widgets/app_buttons.dart';

void main() {
  testWidgets('busy secondary button keeps a contrasting spinner background', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: AppSecondaryButton(
            label: 'Обновить прогноз',
            onPressed: () {},
            isLoading: true,
          ),
        ),
      ),
    );
    final button = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
    expect(button.onPressed, isNull);
    expect(
      button.style!.backgroundColor!.resolve({WidgetState.disabled}),
      AppTheme.light().colorScheme.primary,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
