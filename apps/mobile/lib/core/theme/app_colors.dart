import 'package:flutter/material.dart';

/// Design tokens directly mapped from DESIGN.md
class AppColors {
  AppColors._();

  // Brand & Accent (Coinbase Blue)
  static const Color primary = Color(0xFF0052FF); // Coinbase Blue
  static const Color primaryActive = Color(0xFF003ECC);
  static const Color primaryDisabled = Color(0xFFA8B8CC);
  static const Color accentYellow = Color(0xFFF4B000);
  static const Color accentAmber = Color(0xFFF4B000); // Compatibility alias
  static const Color accentTeal = Color(0xFF05B169); // Compatibility alias

  // Surface
  static const Color canvas = Color(0xFFFFFFFF); // Pure white canvas
  static const Color surfaceSoft = Color(0xFFF7F7F7);
  static const Color surfaceSubtle = Color(0xFFF9FAFB); // Modern subtle neutral
  static const Color surfaceTint = Color(0xFFF0F4FF); // Soft blue tint
  static const Color surfaceGreenTint = Color(0xFFE8F7F0); // Soft green tint
  static const Color surfaceCard = Color(0xFFFFFFFF);
  static const Color surfaceStrong = Color(0xFFEEF0F3);
  static const Color surfaceCreamStrong = Color(0xFFEEF0F3); // Compatibility alias
  static const Color surfaceDark = Color(0xFF0A0B0D); // Deep near-black product surface
  static const Color surfaceDarkElevated = Color(0xFF16181C);
  static const Color surfaceDarkSoft = Color(0xFF16181C); // Compatibility alias
  static const Color hairline = Color(0xFFDEE1E6);
  static const Color hairlineSoft = Color(0xFFEEF0F3);
  static const Color hairlineSubtle = Color(0xFFE5E7EB); // Delicate modern border

  // Text
  static const Color ink = Color(0xFF0A0B0D); // Display headings & primary text
  static const Color bodyStrong = Color(0xFF0A0B0D);
  static const Color body = Color(0xFF5B616E); // Cool gray running text
  static const Color muted = Color(0xFF7C828A);
  static const Color mutedSoft = Color(0xFFA8ACB3);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onDark = Color(0xFFFFFFFF);
  static const Color onDarkSoft = Color(0xFFA8ACB3);

  // Trading Semantics & Status
  static const Color semanticUp = Color(0xFF05B169); // "Price up" green (text color only)
  static const Color semanticDown = Color(0xFFCF202F); // "Price down" red (text color only)
  static const Color success = Color(0xFF05B169);
  static const Color warning = Color(0xFFF4B000);
  static const Color error = Color(0xFFCF202F);
}
