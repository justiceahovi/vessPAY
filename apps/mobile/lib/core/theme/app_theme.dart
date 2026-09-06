import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  static const String serifFontFamily = 'Georgia';
  static const String sansFontFamily = 'sans-serif';

  // Typography helper getters
  static TextStyle display({
    double fontSize = 28,
    FontWeight fontWeight = FontWeight.w400,
    Color color = AppColors.ink,
    double letterSpacing = -1.0,
    double height = 1.15,
  }) {
    return GoogleFonts.inter(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  // Compatibility alias
  static TextStyle displaySerif({
    double fontSize = 28,
    FontWeight fontWeight = FontWeight.w400,
    Color color = AppColors.ink,
    double letterSpacing = -0.5,
    double height = 1.2,
  }) => display(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
      );

  static TextStyle numberDisplay({
    double fontSize = 18,
    FontWeight fontWeight = FontWeight.w500,
    Color color = AppColors.ink,
    double letterSpacing = 0,
    double height = 1.4,
  }) {
    return GoogleFonts.jetBrainsMono(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  static TextStyle sans({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.w400,
    Color color = AppColors.ink,
    double letterSpacing = 0,
    double height = 1.4,
  }) {
    return GoogleFonts.inter(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  static ThemeData get lightTheme {
    final baseTextTheme = ThemeData.light().textTheme;
    final interTextTheme = GoogleFonts.interTextTheme(baseTextTheme);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.canvas,
      fontFamily: GoogleFonts.inter().fontFamily,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        onPrimary: AppColors.onPrimary,
        surface: AppColors.canvas,
        onSurface: AppColors.ink,
        error: AppColors.error,
        onError: Colors.white,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.canvas,
        foregroundColor: AppColors.ink,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle.dark.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: AppColors.canvas,
        ),
        titleTextStyle: GoogleFonts.inter(
          color: AppColors.ink,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.canvas,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.primary.withValues(alpha: 0.12),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        height: 64,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return GoogleFonts.inter(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected ? AppColors.primary : AppColors.muted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 22,
            color: isSelected ? AppColors.primary : AppColors.muted,
          );
        }),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.canvas,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        dragHandleColor: AppColors.hairline,
        dragHandleSize: Size(40, 4),
        showDragHandle: true,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surfaceCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: AppColors.hairline, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          elevation: 0,
          minimumSize: const Size(double.infinity, 44),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(100), // Pill geometry per DESIGN.md
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: AppColors.canvas,
          foregroundColor: AppColors.ink,
          elevation: 0,
          side: const BorderSide(color: AppColors.hairline, width: 1),
          minimumSize: const Size(double.infinity, 44),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(100), // Pill geometry per DESIGN.md
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.hairline,
        thickness: 1,
        space: 1,
      ),
      textTheme: interTextTheme.copyWith(
        // Calm weight 400 display headlines per DESIGN.md
        displayLarge: GoogleFonts.inter(
          fontSize: 52,
          fontWeight: FontWeight.w400,
          color: AppColors.ink,
          letterSpacing: -1.3,
          height: 1.0,
        ),
        displayMedium: GoogleFonts.inter(
          fontSize: 44,
          fontWeight: FontWeight.w400,
          color: AppColors.ink,
          letterSpacing: -1.0,
          height: 1.09,
        ),
        displaySmall: GoogleFonts.inter(
          fontSize: 36,
          fontWeight: FontWeight.w400,
          color: AppColors.ink,
          letterSpacing: -0.5,
          height: 1.11,
        ),
        headlineMedium: GoogleFonts.inter(
          fontSize: 24,
          fontWeight: FontWeight.w500,
          color: AppColors.ink,
          letterSpacing: -0.3,
          height: 1.25,
        ),
        headlineSmall: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w500,
          color: AppColors.ink,
          height: 1.3,
        ),
        // Sans titles and body per DESIGN.md
        titleLarge: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
        titleMedium: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
        titleSmall: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
        bodyLarge: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: AppColors.bodyStrong,
          height: 1.5,
        ),
        bodyMedium: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: AppColors.body,
          height: 1.5,
        ),
        bodySmall: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: AppColors.muted,
          height: 1.4,
        ),
        labelLarge: GoogleFonts.inter(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
        labelMedium: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppColors.muted,
        ),
        labelSmall: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: AppColors.mutedSoft,
        ),
      ),
    );
  }

}
