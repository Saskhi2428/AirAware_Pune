import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// AIRAWare visual language v2 — a genuine premium indigo/purple identity,
/// not just Material 3 defaults with a seed color. Every screen pulls its
/// gradients, surfaces, and text styles from here so the app reads as one
/// designed product instead of a pile of default widgets.
class AppColors {
  // Brand
  static const indigo = Color(0xFF6366F1);
  static const indigoDeep = Color(0xFF4338CA);
  static const purple = Color(0xFF8B5CF6);
  static const violet = Color(0xFFA78BFA);

  // Dark surfaces (this app is designed dark-first — that's the premium
  // direction, not a fallback; light theme below stays consistent with it)
  static const bgTop = Color(0xFF0B0B18);
  static const bgBottom = Color(0xFF15132B);
  static const surface = Color(0xFF1C1A33);
  static const surfaceElevated = Color(0xFF242145);
  static const borderSubtle = Color(0x1FFFFFFF); // white @ 12%

  static const bgLight = Color(0xFFF6F5FC);
  static const surfaceLight = Color(0xFFFFFFFF);

  static const textPrimary = Color(0xFFF4F3FB);
  static const textSecondary = Color(0xFFA6A3C4);
  static const textMuted = Color(0xFF716D96);

  // AQI category colors (CPCB scale — do not reorder/rename these)
  static const aqiGood = Color(0xFF34D399);
  static const aqiSatisfactory = Color(0xFFA3E635);
  static const aqiModerate = Color(0xFFFBBF24);
  static const aqiPoor = Color(0xFFFB923C);
  static const aqiVeryPoor = Color(0xFFF87171);
  static const aqiSevere = Color(0xFF991B1B);
  static const aqiUnavailable = Color(0xFF6B7280);

  static Color colorForAqiCategory(String? category) {
    switch (category?.trim().toLowerCase()) {
      case 'good': return aqiGood;
      case 'satisfactory': return aqiSatisfactory;
      case 'moderate': return aqiModerate;
      case 'poor': return aqiPoor;
      case 'very poor': return aqiVeryPoor;
      case 'severe': return aqiSevere;
      default: return aqiUnavailable;
    }
  }

  static const backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [bgTop, bgBottom],
  );

  static LinearGradient brandGradient({double opacity = 1}) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [indigo.withValues(alpha: opacity), purple.withValues(alpha: opacity)],
      );
}

/// A reusable "glass" card: subtle translucent surface + soft border +
/// gentle shadow. This one decoration is what makes cards look premium
/// instead of flat Material cards sitting on a plain background.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Gradient? gradient;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: gradient ??
            const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.surfaceElevated, AppColors.surface],
            ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.borderSubtle, width: 1),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 24, offset: const Offset(0, 12)),
        ],
      ),
      child: child,
    );
  }
}

class AppTheme {
  static TextTheme _textTheme(Color base) => GoogleFonts.manropeTextTheme().apply(
        bodyColor: base,
        displayColor: base,
      ).copyWith(
        headlineMedium: GoogleFonts.manrope(
          fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.6, color: base,
        ),
        titleLarge: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w700, color: base),
        bodyMedium: GoogleFonts.manrope(fontSize: 14, height: 1.45, color: base),
      );

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.bgTop,
        textTheme: _textTheme(AppColors.textPrimary),
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.indigo,
          brightness: Brightness.dark,
          surface: AppColors.surface,
        ),
        cardTheme: CardThemeData(
          color: AppColors.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: AppColors.borderSubtle),
          ),
          margin: EdgeInsets.zero,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: AppColors.textPrimary,
          titleTextStyle: GoogleFonts.manrope(
            fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary,
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: AppColors.surfaceElevated,
          indicatorColor: AppColors.indigo.withValues(alpha: 0.35),
          labelTextStyle: WidgetStateProperty.resolveWith((states) => GoogleFonts.manrope(
                fontSize: 11,
                fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
                color: states.contains(WidgetState.selected) ? AppColors.textPrimary : AppColors.textMuted,
              )),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surface,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      );

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: AppColors.bgLight,
        textTheme: _textTheme(const Color(0xFF1F1B3A)),
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.indigo, brightness: Brightness.light),
        cardTheme: CardThemeData(
          color: AppColors.surfaceLight,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          margin: EdgeInsets.zero,
        ),
      );
}
