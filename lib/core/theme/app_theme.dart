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

  static ThemeData? _light;
  static ThemeData? _dark;
  static ThemeData light() => _light ??= _build(
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

  static ThemeData dark() => _dark ??= _build(
    AppColors.dark,
    // Pure black and white. Only money and status colours carry hue.
    const ColorScheme.dark(
      primary: Colors.white,
      onPrimary: Colors.black,
      primaryContainer: Color(0xFF2E2E2E),
      onPrimaryContainer: Colors.white,
      secondary: Color(0xFFCCCCCC),
      onSecondary: Colors.black,
      secondaryContainer: Color(0xFF333333),
      onSecondaryContainer: Colors.white,
      tertiary: Color(0xFFCCCCCC),
      onTertiary: Colors.black,
      tertiaryContainer: Color(0xFF333333),
      onTertiaryContainer: Colors.white,
      surface: Colors.black,
      onSurface: Colors.white,
      onSurfaceVariant: Color(0xFFB3B3B3),
      surfaceContainerLowest: Color(0xFF0D0D0D),
      surfaceContainerLow: Color(0xFF121212),
      surfaceContainer: Color(0xFF181818),
      surfaceContainerHigh: Color(0xFF202020),
      surfaceContainerHighest: Color(0xFF2A2A2A),
      surfaceTint: Colors.transparent,
      inverseSurface: Colors.white,
      onInverseSurface: Colors.black,
      inversePrimary: Colors.black,
      outline: Color(0xFF7A7A7A),
      outlineVariant: Color(0xFF2C2C2C),
      error: Color(0xFFFF7B72),
      onError: Colors.black,
    ),
  );

  static ThemeData _build(AppColors colors, ColorScheme scheme) {
    final isLight = scheme.brightness == Brightness.light;
    final radius = BorderRadius.circular(20);
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
      // Lighter ripple than the default sparkle: smoother on low-end phones.
      splashFactory: InkRipple.splashFactory,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLowest,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
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
        indicatorColor: scheme.primary.withValues(alpha: isLight ? 0.10 : 0.22),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
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

/// Brand colours that differ between the two themes. Light mode is navy on
/// cream; dark mode is strictly black, white and grey. Widgets must use these
/// instead of the navy constants.
extension BrandContext on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  /// Solid emphasis fill (selected chips, primary actions) and its text.
  Color get accentFill => isDark ? Colors.white : AppTheme.navy;
  Color get onAccent => isDark ? Colors.black : Colors.white;

  /// Hero cards. Their text is white in both themes.
  List<Color> get heroGradient => isDark
      ? const [Color(0xFF1F1F1F), Color(0xFF101010)]
      : const [Color(0xFF1D4068), AppTheme.navy];

  /// Full-screen brand background (lock screen).
  Color get brandBackground => isDark ? Colors.black : AppTheme.navy;

  /// A colour picked for an account, source or category: kept in light mode,
  /// shown white in dark mode.
  Color tone(Color c) => isDark ? Colors.white : c;

  /// Chart series [i] and the text drawn on top of it.
  Color series(int i) {
    const light = [
      AppTheme.navy,
      AppTheme.navyMid,
      AppTheme.navySoft,
      Color(0xFF8FA6BF),
      Color(0xFFB7C5D6),
      Color(0xFF607D8B),
    ];
    const dark = [
      Color(0xFFFFFFFF),
      Color(0xFFC4C4C4),
      Color(0xFF949494),
      Color(0xFF6B6B6B),
      Color(0xFF4A4A4A),
      Color(0xFF333333),
    ];
    return (isDark ? dark : light)[i % 6];
  }

  Color onSeries(int i) => isDark && i % 6 < 3 ? Colors.black : Colors.white;
}
