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
    positive: Color(0xFF1B8A3A),
    negative: Color(0xFFD32F2F),
    pending: Color(0xFFF59E0B),
    partial: Color(0xFF1976D2),
    overdue: Color(0xFFD32F2F),
    settled: Color(0xFF1B8A3A),
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
  static const _seed = Color(0xFF0F766E);

  static ThemeData light() => _build(Brightness.light, AppColors.light);
  static ThemeData dark() => _build(Brightness.dark, AppColors.dark);

  static ThemeData _build(Brightness brightness, AppColors colors) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      // System font on purpose: no runtime font downloads.
      extensions: [colors],
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      appBarTheme: const AppBarTheme(centerTitle: false),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      navigationBarTheme: const NavigationBarThemeData(height: 68),
    );
  }
}
