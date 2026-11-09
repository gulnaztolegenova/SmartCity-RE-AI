import 'package:flutter/material.dart';

import 'app_buttons.dart';

Future<bool> showAppConfirmationDialog({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmLabel,
  required String cancelLabel,
  IconData icon = Icons.help_outline_rounded,
  Color? accentColor,
}) async {
  final theme = Theme.of(context);
  final accent = accentColor ?? theme.colorScheme.primary;
  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      return Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(icon, color: accent, size: 28),
                ),
                const SizedBox(height: 18),
                Text(title, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 10),
                Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 22),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final stacked = constraints.maxWidth < 380;
                    final cancelButton = AppSecondaryButton(
                      label: cancelLabel,
                      onPressed: () => Navigator.of(context).pop(false),
                    );
                    final confirmButton = AppSecondaryButton(
                      label: confirmLabel,
                      icon: const Icon(Icons.logout_rounded),
                      foregroundColor: Colors.white,
                      backgroundColor: theme.colorScheme.error,
                      borderColor: theme.colorScheme.error,
                      loaderColor: Colors.white,
                      onPressed: () => Navigator.of(context).pop(true),
                    );

                    if (stacked) {
                      return Column(
                        children: [
                          SizedBox(width: double.infinity, child: cancelButton),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: confirmButton,
                          ),
                        ],
                      );
                    }

                    return Row(
                      children: [
                        Expanded(child: cancelButton),
                        const SizedBox(width: 12),
                        Expanded(child: confirmButton),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  return result ?? false;
}
