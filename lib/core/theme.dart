import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// SwidShop design system.
///
/// Colors sampled directly from the official SwidShop logo artwork and the
/// approved Chapter 2 prototype screens.
class AppColors {
  AppColors._();

  /// Primary brand color — logo, main CTAs, Buy Now badges.
  static const Color coral = Color(0xFFD85A30);

  /// Secondary — Swap elements, Trusted-seller accents.
  static const Color teal = Color(0xFF0F6E56);

  /// Bidding highlights, live countdown timers.
  static const Color amber = Color(0xFFEF9F27);

  /// Success states, Trusted badge checkmark.
  static const Color green = Color(0xFF1D9E75);

  /// Outbid alerts, warnings, errors.
  static const Color red = Color(0xFFE24B4A);

  /// Primary text color.
  static const Color ink = Color(0xFF2C2C2A);

  /// Secondary text, borders, disabled states.
  static const Color gray = Color(0xFF888780);

  /// Main background and card surfaces.
  static const Color cream = Color(0xFFF1EFE8);

  /// Card / surface white.
  static const Color surface = Color(0xFFFFFFFF);

  /// Darker coral for the splash gradient and native launch background.
  static const Color coralDeep = Color(0xFFC2461F);

  /// Lighter cream matching the logo artwork background.
  static const Color paper = Color(0xFFFCF8F4);

  /// Hairline borders on inputs, cards and dividers.
  static const Color line = Color(0xFFE4DFD4);

  /// Muted fill for unselected chips / segmented tracks.
  static const Color mist = Color(0xFFEAE6DD);
}

/// Builds the app-wide [ThemeData] for SwidShop.
class AppTheme {
  AppTheme._();

  static const double cardRadius = 16;
  static const double buttonRadius = 12;
  static const double appBarHeight = 56;

  /// Typography built on the 'Plus Jakarta Sans' family.
  ///
  /// * Bold (w700) → headings / prices
  /// * Medium (w500) → buttons / labels
  /// * Regular (w400) → body text
  /// The Google Fonts family name used app-wide.
  ///
  /// We read the family string from `GoogleFonts` (which also triggers the
  /// runtime font download) and build a Flutter [TextTheme] from it, rather
  /// than using `GoogleFonts.plusJakartaSansTextTheme()` — that helper returns
  /// the `material_ui` package's `TextTheme`, which is a *different type* from
  /// `package:flutter/material.dart`'s `TextTheme`.
  static String? get fontFamily => GoogleFonts.plusJakartaSans().fontFamily;

  static TextTheme get textTheme {
    final base = Typography.material2021().black.apply(fontFamily: fontFamily);
    TextStyle? b(TextStyle? s) => s?.copyWith(fontWeight: FontWeight.w700);
    TextStyle? m(TextStyle? s) => s?.copyWith(fontWeight: FontWeight.w500);
    TextStyle? r(TextStyle? s) => s?.copyWith(fontWeight: FontWeight.w400);
    return base.copyWith(
      displayLarge: b(base.displayLarge),
      displayMedium: b(base.displayMedium),
      displaySmall: b(base.displaySmall),
      headlineLarge: b(base.headlineLarge),
      headlineMedium: b(base.headlineMedium),
      headlineSmall: b(base.headlineSmall),
      titleLarge: b(base.titleLarge),
      titleMedium: m(base.titleMedium),
      titleSmall: m(base.titleSmall),
      labelLarge: m(base.labelLarge),
      labelMedium: m(base.labelMedium),
      labelSmall: m(base.labelSmall),
      bodyLarge: r(base.bodyLarge),
      bodyMedium: r(base.bodyMedium),
      bodySmall: r(base.bodySmall),
    );
  }

  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: AppColors.cream,
      textTheme: textTheme,
    );

    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.coral,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.coral,
      onPrimary: Colors.white,
      secondary: AppColors.teal,
      onSecondary: Colors.white,
      error: AppColors.red,
      onError: Colors.white,
      surface: AppColors.cream,
      onSurface: AppColors.ink,
    );

    return base.copyWith(
      colorScheme: scheme,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.cream,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: appBarHeight,
        titleTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.coral,
          foregroundColor: Colors.white,
          textStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w500),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(buttonRadius),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.teal,
          textStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w500),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: const TextStyle(color: Color(0xFFADA99F)),
        prefixIconColor: AppColors.gray,
        suffixIconColor: AppColors.gray,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(buttonRadius),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(buttonRadius),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(buttonRadius),
          borderSide: const BorderSide(color: AppColors.coral, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(buttonRadius),
          borderSide: const BorderSide(color: AppColors.red),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(buttonRadius),
          borderSide: const BorderSide(color: AppColors.red, width: 1.5),
        ),
      ),
    );
  }
}
