import 'package:material_ui/material_ui.dart';

/// Semantic colours used the same way everywhere:
/// green = money in / positive, red = money out / negative.
/// Status chips: pending amber, partial blue, overdue red, settled green.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.positive,
    required this.negative,
    required this.pending,
    required this.partial,
    required this.overdue,
    required this.settled,
  });

  final Color positive;
  final Color negative;
  final Color pending;
  final Color partial;
  final Color overdue;
  final Color settled;

  static const light = AppColors(
    positive: Color(0xFF1F7A1F),
    negative: Color(0xFFCD1F1F),
    pending: Color(0xFFD98A00),
    partial: Color(0xFF2A4E76),
    overdue: Color(0xFFCD1F1F),
    settled: Color(0xFF1F7A1F),
  );

  static const dark = AppColors(
    positive: Color(0xFF5FD27F),
    negative: Color(0xFFFF7B72),
    pending: Color(0xFFFFC04D),
    partial: Color(0xFF64B5F6),
    overdue: Color(0xFFFF7B72),
    settled: Color(0xFF5FD27F),
  );

  /// Green for >= 0 style "good" values, red for negatives.
  Color forAmount(int paisa) => paisa < 0 ? negative : positive;

  @override
  AppColors copyWith({
    Color? positive,
    Color? negative,
    Color? pending,
    Color? partial,
    Color? overdue,
    Color? settled,
  }) => AppColors(
    positive: positive ?? this.positive,
    negative: negative ?? this.negative,
    pending: pending ?? this.pending,
    partial: partial ?? this.partial,
    overdue: overdue ?? this.overdue,
    settled: settled ?? this.settled,
  );

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    return AppColors(
      positive: Color.lerp(positive, other.positive, t)!,
      negative: Color.lerp(negative, other.negative, t)!,
      pending: Color.lerp(pending, other.pending, t)!,
      partial: Color.lerp(partial, other.partial, t)!,
      overdue: Color.lerp(overdue, other.overdue, t)!,
      settled: Color.lerp(settled, other.settled, t)!,
    );
  }
}

extension AppColorsContext on BuildContext {
  AppColors get appColors => Theme.of(this).extension<AppColors>()!;
}

abstract final class AppTheme {
  // Palette taken from designs/UI Screens: warm cream paper, deep navy.
  static const navy = Color(0xFF112E4E);
  static const navyHero = Color(0xFF183858);
  static const navyMid = Color(0xFF2A4E76);
  static const navySoft = Color(0xFF5C7C9F);
  static const cream = Color(0xFFF9F3E8);
  static const creamCard = Color(0xFFFBF6EC);
  static const stroke = Color(0xFFE6E0D8);
  static const ink = Color(0xFF0B1F3A);

  static ThemeData light() => _build(
    AppColors.light,
    const ColorScheme.light(
      primary: navy,
      onPrimary: Colors.white,
      secondary: navyMid,
      onSecondary: Colors.white,
      surface: cream,
      onSurface: ink,
      onSurfaceVariant: Color(0xFF4A5A70),
      surfaceContainerLowest: creamCard,
      surfaceContainerLow: creamCard,
      surfaceContainer: Color(0xFFF2EBDD),
      surfaceContainerHigh: Color(0xFFEDE5D5),
      outline: Color(0xFF9AA3B0),
      outlineVariant: stroke,
      error: Color(0xFFCD1F1F),
    ),
  );

  static ThemeData dark() => _build(
    AppColors.dark,
    const ColorScheme.dark(
      primary: Color(0xFF8FB0D6),
      onPrimary: Color(0xFF0B1F3A),
      secondary: navySoft,
      onSecondary: Colors.white,
      surface: Color(0xFF0B1B2E),
      onSurface: Color(0xFFF1EBDD),
      onSurfaceVariant: Color(0xFFB4BDC9),
      surfaceContainerLowest: Color(0xFF0E2238),
      surfaceContainerLow: Color(0xFF12283F),
      surfaceContainer: Color(0xFF163049),
      surfaceContainerHigh: Color(0xFF1B3856),
      outline: Color(0xFF6F8099),
      outlineVariant: Color(0xFF28415E),
      error: Color(0xFFFF7B72),
    ),
  );

  static ThemeData _build(AppColors colors, ColorScheme scheme) {
    final isLight = scheme.brightness == Brightness.light;
    final radius = BorderRadius.circular(14);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      // System font on purpose: no runtime font downloads.
      extensions: [colors],
      textTheme: ThemeData(
        brightness: scheme.brightness,
      ).textTheme.apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.primary),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: isLight ? navy : scheme.primary,
        foregroundColor: isLight ? Colors.white : scheme.onPrimary,
        shape: const CircleBorder(),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => TextStyle(
            fontSize: 11,
            letterSpacing: -0.2,
            overflow: TextOverflow.visible,
            fontWeight: s.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            color: s.contains(WidgetState.selected)
                ? scheme.onSurface
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
