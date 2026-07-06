import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Brand colours for Companion Ranchi.
///
/// CUTE DATING-APP look: romantic rose/pink primary (#FF4D6D), coral-red
/// accents, fresh green for trust/online, soft pink-tinted surfaces, deep
/// plum "dark" cards for hero/refer/nav, very rounded cards and big imagery.
///
/// NOTE: the tokens still named `gold`/`goldDeep`/`cream` are kept for
/// backwards-compat but now hold PINK values, so legacy call-sites recolour
/// automatically.
class AppColors {
  AppColors._();

  /// Primary brand — romantic rose/pink (seed).
  static const Color primary = Color(0xFFFF4D6D);
  static const Color primaryDark = Color(0xFFE63B5E);
  static const Color primaryLight = Color(0xFFFFA5B8);

  /// Secondary / accent — warm coral red for CTAs and highlights.
  static const Color accent = Color(0xFFFF6B6B);
  static const Color accentSoft = Color(0xFFFFC2CD);

  /// Gradient anchors (pink → rose-red).
  static const Color gradientStart = Color(0xFFFF7EB3);
  static const Color gradientMid = Color(0xFFFF4D6D);
  static const Color gradientEnd = Color(0xFFFF5C7A);

  // Neutrals
  static const Color ink = Color(0xFF2E2A33); // soft near-black text
  static const Color inkMuted = Color(0xFF9B8E96); // muted mauve-grey
  static const Color line = Color(0xFFFBE3EA); // soft pink hairline
  static const Color surface = Color(0xFFFFFFFF);
  static const Color scaffold = Color(0xFFFFF8FB); // barely-pink white bg
  static const Color field = Color(0xFFFFEEF3); // soft pink input fill
  // Firmer pink border for white-filled inputs/chips — `line` is too faint to
  // separate a white control from the barely-pink scaffold.
  static const Color fieldBorder = Color(0xFFF3C9D6);

  /// Money surfaces (earnings hero, wallet balance) — emerald, "green = money".
  static const Color money = Color(0xFF136647);
  static const Color moneySoft = Color(0xFF1F8A5B);

  // Brand extras (now PINK — legacy "gold" names kept for compat).
  static const Color gold = Color(0xFFFF4D6D);
  static const Color goldDeep = Color(0xFFE63B5E);
  static const Color cream = Color(0xFFFFF0F4);

  /// Deep plum-rose surfaces for hero/refer/nav cards (romantic, cute).
  static const Color dark = Color(0xFF2A1620);
  static const Color darkSoft = Color(0xFF3A2330);

  // Dark mode neutrals (plum-tinted)
  static const Color darkScaffold = Color(0xFF1A1016);
  static const Color darkSurface = Color(0xFF241620);
  static const Color darkField = Color(0xFF2E1B26);
  static const Color darkLine = Color(0xFF3E2A36);
  static const Color darkInk = Color(0xFFFDEFF3);
  static const Color darkInkMuted = Color(0xFFC9AEB8);

  // Semantic
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);
  static const Color info = Color(0xFF2563EB);
  static const Color online = Color(0xFF22C55E);
  static const Color star = Color(0xFFFFB72C);

  /// Fresh "verified" green used for trust badges/checks across the app.
  static const Color verified = Color(0xFF22C55E);
}

/// Reusable gradients.
class AppGradients {
  AppGradients._();

  /// Primary brand gradient (buttons, hero headers).
  static const LinearGradient primary = LinearGradient(
    colors: [AppColors.gradientStart, AppColors.gradientEnd],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Subtle gradient for cards / sheets.
  static const LinearGradient card = LinearGradient(
    colors: [AppColors.gradientStart, AppColors.gradientEnd],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Emerald gradient for money surfaces (earnings hero, wallet balance).
  static const LinearGradient money = LinearGradient(
    colors: [AppColors.money, AppColors.moneySoft],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Gold accent gradient for promotional surfaces.
  static const LinearGradient accent = LinearGradient(
    colors: [AppColors.gradientStart, AppColors.gradientEnd],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  /// Dark photo scrim used over large companion images.
  static const LinearGradient photoScrim = LinearGradient(
    colors: [Colors.transparent, Color(0xCC000000)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}

/// Spacing and radius tokens for consistent layout.
class AppSpacing {
  AppSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  static const double radiusSm = 10;
  static const double radius = 16;
  static const double radiusLg = 24;
  static const double radiusPill = 100;
}

/// Material 3 theme factory.
class AppTheme {
  AppTheme._();

  static const double _radius = AppSpacing.radius;

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: brightness,
    ).copyWith(
      primary: AppColors.primary,
      secondary: AppColors.accent,
      surface: isDark ? AppColors.darkSurface : AppColors.surface,
      error: AppColors.danger,
    );

    final baseTextColor = isDark ? AppColors.darkInk : AppColors.ink;
    final mutedColor = isDark ? AppColors.darkInkMuted : AppColors.inkMuted;

    final textTheme = GoogleFonts.nunitoTextTheme(
      ThemeData(brightness: brightness).textTheme,
    ).apply(
      bodyColor: baseTextColor,
      displayColor: baseTextColor,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor:
          isDark ? AppColors.darkScaffold : AppColors.scaffold,
      textTheme: textTheme,
      primaryColor: AppColors.primary,
      splashFactory: InkRipple.splashFactory,
      visualDensity: VisualDensity.adaptivePlatformDensity,

      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: isDark ? AppColors.darkScaffold : AppColors.scaffold,
        foregroundColor: baseTextColor,
        centerTitle: false,
        titleTextStyle: GoogleFonts.nunito(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: baseTextColor,
        ),
        iconTheme: IconThemeData(color: baseTextColor),
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          side: BorderSide(
            color: isDark ? AppColors.darkLine : AppColors.line,
            width: 1,
          ),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size.fromHeight(54),
          textStyle: GoogleFonts.nunito(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primaryDark,
          minimumSize: const Size.fromHeight(54),
          side: const BorderSide(color: AppColors.primary, width: 1.4),
          textStyle: GoogleFonts.nunito(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primaryDark,
          textStyle: GoogleFonts.nunito(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        // White fields with a visible pink border — a pink-on-pink fill made
        // inputs read as disabled (no depth against the scaffold).
        fillColor: isDark ? AppColors.darkField : Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg,
        ),
        hintStyle: TextStyle(color: mutedColor),
        labelStyle: TextStyle(color: mutedColor),
        helperStyle: TextStyle(color: mutedColor, fontSize: 12),
        prefixIconColor: mutedColor,
        suffixIconColor: mutedColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radius),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radius),
          borderSide: BorderSide(
            color: isDark ? AppColors.darkLine : AppColors.fieldBorder,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radius),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radius),
          borderSide: const BorderSide(color: AppColors.danger, width: 1.4),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radius),
          borderSide: const BorderSide(color: AppColors.danger, width: 1.6),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: isDark ? AppColors.darkField : AppColors.field,
        selectedColor: AppColors.primary,
        secondarySelectedColor: AppColors.primary,
        labelStyle: TextStyle(color: baseTextColor),
        secondaryLabelStyle: const TextStyle(color: AppColors.ink),
        side: BorderSide(color: isDark ? AppColors.darkLine : AppColors.line),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.surface,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: mutedColor,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        showUnselectedLabels: true,
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.surface,
        indicatorColor: AppColors.primary.withValues(alpha: 0.14),
        elevation: 0,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? AppColors.primary : mutedColor,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return GoogleFonts.nunito(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? AppColors.primary : mutedColor,
          );
        }),
      ),

      dividerTheme: DividerThemeData(
        color: isDark ? AppColors.darkLine : AppColors.line,
        thickness: 1,
        space: 1,
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppSpacing.radiusLg),
          ),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.ink,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
      ),

      iconTheme: IconThemeData(color: baseTextColor),
      listTileTheme: ListTileThemeData(
        iconColor: mutedColor,
        textColor: baseTextColor,
      ),
    );
  }
}
