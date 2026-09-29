import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_colors.dart';
import '../constants/app_sizes.dart';
import 'app_text_styles.dart';

/// Single source of truth for the app's Material theme.
///
/// ## Why the theme carries so much of the redesign
///
/// Most screens in SUGO build from stock Material parts - `FilledButton`,
/// `OutlinedButton`, `AlertDialog`, `showModalBottomSheet`, `TabBar`,
/// `TextField`. Styling each one per call site is how an app ends up with four
/// shades of button and three dialog shapes. Styling them *here* means every
/// existing screen, including ones nobody has opened since they were written,
/// picks up the new look in one place, and a new screen is on-brand by
/// default.
///
/// Call sites should only override the theme when a control genuinely means
/// something different - a destructive action, an accent CTA - never to
/// restate what is already here.
class AppTheme {
  const AppTheme._();

  static ThemeData get light {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      onPrimary: Colors.white,
      primaryContainer: AppColors.primarySoft,
      onPrimaryContainer: AppColors.primaryDark,
      secondary: AppColors.secondary,
      onSecondary: Colors.white,
      secondaryContainer: AppColors.secondarySoft,
      onSecondaryContainer: AppColors.secondaryDark,
      tertiary: AppColors.accent,
      onTertiary: Colors.white,
      tertiaryContainer: AppColors.accentSoft,
      onTertiaryContainer: AppColors.accentDark,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      onSurfaceVariant: AppColors.textSecondary,
      surfaceContainerLowest: AppColors.surface,
      surfaceContainerLow: AppColors.primarySofter,
      surfaceContainer: AppColors.background,
      surfaceContainerHigh: AppColors.divider,
      outline: AppColors.border,
      outlineVariant: AppColors.divider,
      error: AppColors.error,
      onError: Colors.white,
    );

    final RoundedRectangleBorder controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: AppTextStyles.fontFamily,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,

      // One page transition app-wide: the Android 14 fade-through-slide on
      // Android, the native slide on iOS. Before this, screens mixed the old
      // zoom transition with custom ones, and a flow of five screens moved
      // three different ways.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(
            backgroundColor: AppColors.background,
          ),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(
            backgroundColor: AppColors.background,
          ),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(
            backgroundColor: AppColors.background,
          ),
        },
      ),

      textTheme: _textTheme,

      // Titles sit left, beside the back arrow, where Android puts them and
      // where the eye already is after tapping back. A centred title on a
      // phone is an iOS idiom, and SUGO is used mostly on Android.
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: AppTextStyles.title,
        iconTheme: IconThemeData(color: AppColors.textPrimary, size: 22),
        actionsIconTheme: IconThemeData(color: AppColors.textPrimary, size: 22),
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),

      iconTheme: const IconThemeData(color: AppColors.textPrimary, size: 22),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.fieldFill,
        hintStyle: AppTextStyles.hint,
        labelStyle: AppTextStyles.caption,
        floatingLabelStyle: AppTextStyles.label.copyWith(
          color: AppColors.secondaryDark,
        ),
        helperStyle: AppTextStyles.micro,
        errorStyle: AppTextStyles.micro.copyWith(
          color: AppColors.error,
          fontWeight: FontWeight.w600,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSizes.lg,
          vertical: AppSizes.lg,
        ),
        border: _fieldBorder(AppColors.border),
        enabledBorder: _fieldBorder(AppColors.border),
        // Focus is blue, not navy: blue is the colour that says "here".
        focusedBorder: _fieldBorder(AppColors.secondary, width: 1.6),
        errorBorder: _fieldBorder(AppColors.error),
        focusedErrorBorder: _fieldBorder(AppColors.error, width: 1.6),
        disabledBorder: _fieldBorder(AppColors.divider),
        prefixIconColor: AppColors.hint,
        suffixIconColor: AppColors.hint,
      ),

      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.secondary,
        selectionColor: AppColors.secondary.withValues(alpha: 0.22),
        selectionHandleColor: AppColors.secondary,
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.border,
          disabledForegroundColor: AppColors.hint,
          elevation: 0,
          shadowColor: Colors.transparent,
          minimumSize: const Size.fromHeight(AppSizes.buttonHeight),
          padding: const EdgeInsets.symmetric(horizontal: AppSizes.xl),
          shape: controlShape,
          textStyle: AppTextStyles.button,
        ),
      ),

      // FilledButton is the Material 3 primary button and several screens
      // use it directly. Same look as ElevatedButton, so which one a screen
      // happened to reach for makes no visible difference.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.border,
          disabledForegroundColor: AppColors.hint,
          minimumSize: const Size(64, AppSizes.socialButtonHeight),
          padding: const EdgeInsets.symmetric(horizontal: AppSizes.xl),
          shape: controlShape,
          textStyle: AppTextStyles.button,
        ),
      ),

      // Text buttons draw 40 tall but take a 48 tap area ("padded"). They
      // were 36 and shrink-wrapped, which put "Forgot password?" and every
      // "See all" under the 48dp floor.
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.secondaryDark,
          textStyle: AppTextStyles.link,
          padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm),
          minimumSize: const Size(0, 40),
          tapTargetSize: MaterialTapTargetSize.padded,
          shape: controlShape,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          backgroundColor: AppColors.surface,
          minimumSize: const Size.fromHeight(AppSizes.socialButtonHeight),
          padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg),
          side: const BorderSide(color: AppColors.border),
          shape: controlShape,
          textStyle: AppTextStyles.socialButton,
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          minimumSize: const Size(AppSizes.touchTarget, AppSizes.touchTarget),
        ),
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 2,
        highlightElevation: 4,
        shape: StadiumBorder(),
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
          return states.contains(WidgetState.selected)
              ? AppColors.primary
              : Colors.transparent;
        }),
        side: const BorderSide(color: AppColors.hint, width: 1.4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),

      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
          return states.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.hint;
        }),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
          return states.contains(WidgetState.selected)
              ? Colors.white
              : AppColors.hint;
        }),
        trackColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
          return states.contains(WidgetState.selected)
              ? AppColors.secondary
              : AppColors.divider;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((
          Set<WidgetState> states,
        ) {
          return states.contains(WidgetState.selected)
              ? AppColors.secondary
              : AppColors.border;
        }),
      ),

      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.secondary,
        inactiveTrackColor: AppColors.divider,
        thumbColor: AppColors.primary,
        overlayColor: Color(0x1F087FEA),
        valueIndicatorColor: AppColors.primary,
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.secondary,
        linearTrackColor: AppColors.divider,
        circularTrackColor: Colors.transparent,
      ),

      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.primary,
        disabledColor: AppColors.divider,
        side: const BorderSide(color: AppColors.border),
        labelStyle: AppTextStyles.caption.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: AppTextStyles.caption.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
        padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm),
        shape: const StadiumBorder(),
        checkmarkColor: Colors.white,
      ),

      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textSecondary,
        labelStyle: AppTextStyles.label,
        unselectedLabelStyle: AppTextStyles.label.copyWith(
          fontWeight: FontWeight.w600,
        ),
        indicatorColor: AppColors.primary,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: AppColors.divider,
        overlayColor: WidgetStatePropertyAll<Color>(
          AppColors.primary.withValues(alpha: 0.05),
        ),
      ),

      cardTheme: CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.panelRadius),
          side: const BorderSide(color: AppColors.border),
        ),
      ),

      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.textSecondary,
        textColor: AppColors.textPrimary,
        titleTextStyle: TextStyle(
          fontFamily: AppTextStyles.fontFamily,
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        subtitleTextStyle: TextStyle(
          fontFamily: AppTextStyles.fontFamily,
          fontSize: 13,
          color: AppColors.textSecondary,
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: AppSizes.lg),
        minVerticalPadding: AppSizes.md,
      ),

      // Every sheet in the app: rounded top, white, navy-tinted scrim.
      //
      // The drag handle is NOT switched on here. Four existing sheets (rating,
      // ask-a-question, score breakdown, job completion) already draw their
      // own, and a theme-wide handle would give them two. `showSugoBottomSheet`
      // draws one for every new sheet instead.
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: AppColors.surface,
        modalBarrierColor: AppColors.navy.withValues(alpha: 0.45),
        elevation: 0,
        modalElevation: 0,
        dragHandleColor: AppColors.border,
        dragHandleSize: const Size(40, 4),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppSizes.sheetRadius),
          ),
        ),
        clipBehavior: Clip.antiAlias,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        barrierColor: AppColors.navy.withValues(alpha: 0.45),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.sheetRadius),
        ),
        titleTextStyle: AppTextStyles.title,
        contentTextStyle: AppTextStyles.subtitle,
        actionsPadding: const EdgeInsets.fromLTRB(
          AppSizes.lg,
          0,
          AppSizes.lg,
          AppSizes.lg,
        ),
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shadowColor: AppColors.navy.withValues(alpha: 0.2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.tileRadius),
        ),
        textStyle: AppTextStyles.body,
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.navy,
          borderRadius: BorderRadius.circular(AppSizes.sm),
        ),
        textStyle: AppTextStyles.micro.copyWith(color: Colors.white),
      ),

      badgeTheme: const BadgeThemeData(
        backgroundColor: AppColors.accent,
        textColor: Colors.white,
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: 0,
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.navy,
        actionTextColor: const Color(0xFF9CC0FF),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.tileRadius),
        ),
        contentTextStyle: const TextStyle(
          fontFamily: AppTextStyles.fontFamily,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.white,
          height: 1.4,
        ),
      ),

      datePickerTheme: DatePickerThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: AppColors.primary,
        headerForegroundColor: Colors.white,
        todayBorder: const BorderSide(color: AppColors.secondary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.sheetRadius),
        ),
      ),

      timePickerTheme: TimePickerThemeData(
        backgroundColor: AppColors.surface,
        dialHandColor: AppColors.primary,
        hourMinuteColor: AppColors.primarySoft,
        hourMinuteTextColor: AppColors.primary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.sheetRadius),
        ),
      ),
    );
  }

  /// Material's text roles mapped onto the SUGO scale, so widgets that read the
  /// theme directly (a `ListTile`, a dialog, a `TextField`) land on the same
  /// sizes and weights as screens that use [AppTextStyles].
  static const TextTheme _textTheme = TextTheme(
    displaySmall: AppTextStyles.displayLarge,
    headlineMedium: AppTextStyles.display,
    headlineSmall: AppTextStyles.headline,
    titleLarge: AppTextStyles.title,
    titleMedium: TextStyle(
      fontFamily: AppTextStyles.fontFamily,
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: AppColors.textPrimary,
    ),
    titleSmall: AppTextStyles.titleSmall,
    bodyLarge: TextStyle(
      fontFamily: AppTextStyles.fontFamily,
      fontSize: 15,
      fontWeight: FontWeight.w400,
      color: AppColors.textPrimary,
      height: 1.45,
    ),
    bodyMedium: AppTextStyles.body,
    bodySmall: AppTextStyles.caption,
    labelLarge: AppTextStyles.label,
    labelMedium: AppTextStyles.micro,
    labelSmall: AppTextStyles.overline,
  );

  static OutlineInputBorder _fieldBorder(Color color, {double width = 1.2}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSizes.fieldRadius),
      borderSide: BorderSide(color: color, width: width),
    );
  }
}
