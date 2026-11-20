import 'package:flutter/material.dart';

class AppColors {
  static const brand = Color(0xFF4F46E5);
  static const todo = Color(0xFF64748B);
  static const inProgress = Color(0xFF2563EB);
  static const completed = Color(0xFF16A34A);
  static const overdue = Color(0xFFDC2626);
  static const warning = Color(0xFFD97706);

  static Color taskStatus(String s) => switch (s) {
        'in_progress' => inProgress,
        'completed' => completed,
        _ => todo,
      };

  static Color projectStatus(String s) => switch (s) {
        'active' => inProgress,
        'on_hold' => warning,
        'completed' => completed,
        _ => const Color(0xFF7C3AED),
      };

  static Color priority(String p) => switch (p) {
        'low' => const Color(0xFF0D9488),
        'medium' => const Color(0xFF2563EB),
        'high' => warning,
        'urgent' => overdue,
        _ => todo,
      };
}

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.brand, brightness: brightness);
  final isDark = brightness == Brightness.dark;
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: isDark ? const Color(0xFF0F1117) : const Color(0xFFF5F6FA),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: isDark ? const Color(0xFF181B24) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      isDense: true,
      filled: true,
      fillColor: isDark ? const Color(0xFF1E2230) : Colors.white,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    dialogTheme: DialogThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
    appBarTheme: AppBarTheme(
      backgroundColor: isDark ? const Color(0xFF0F1117) : const Color(0xFFF5F6FA),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
  );
}
