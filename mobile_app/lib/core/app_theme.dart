import 'package:flutter/material.dart';

class AppColors {
  static const Color background = Color(0xFF0F0F0F);
  static const Color surface = Color(0xFF1E1E1E);
  static const Color surfaceLight = Color(0xFF282828);
  static const Color primary = Color(0xFFFF0033); // YouTube Red Accent
  static const Color primaryDark = Color(0xFFCC0029);
  static const Color textPrimary = Color(0xFFF1F1F1);
  static const Color textSecondary = Color(0xFFAAAAAA);
  static const Color divider = Color(0xFF2E2E2E);
  static const Color chipBackground = Color(0xFF272727);
  static const Color chipSelected = Color(0xFFF1F1F1);
  static const Color chipTextSelected = Color(0xFF0F0F0F);
}

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      primaryColor: AppColors.primary,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        secondary: AppColors.primaryDark,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.background,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      cardTheme: const CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
    );
  }
}
