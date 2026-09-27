import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 主题状态：跟随系统 / 浅色 / 深色 + 自定义主色。
/// 通过 SharedPreferences 持久化，运行时即时生效。
class ThemeController extends ChangeNotifier {
  ThemeController._();
  static final ThemeController instance = ThemeController._();

  /// 当前生效的暗色语义（在 system 模式下由系统亮度实时决定）
  bool dark = false;

  /// 深浅模式：system（跟随系统）| light | dark
  String mode = 'system';
  Color accent = const Color(0xFFBE7E5A);

  ThemeMode get themeMode => mode == 'light'
      ? ThemeMode.light
      : mode == 'dark'
          ? ThemeMode.dark
          : ThemeMode.system;

  /// 跟随系统时，用实际系统亮度刷新 `dark`
  void applySystem(Brightness b) {
    if (mode == 'system') {
      final v = b == Brightness.dark;
      if (dark != v) {
        dark = v;
        notifyListeners();
      }
    }
  }

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    mode = sp.getString('ps_mode') ?? 'system';
    accent = Color(sp.getInt('ps_accent') ?? 0xFFBE7E5A);
    if (mode == 'light') {
      dark = false;
    } else if (mode == 'dark') {
      dark = true;
    } else {
      // mode == system：启动时即按当前系统亮度初始化 dark，
      // 避免进入软件首帧仍按浅色渲染、底部导航等白底滞后。
      dark = WidgetsBinding.instance.platformDispatcher.platformBrightness ==
          Brightness.dark;
    }
    notifyListeners();
  }

  Future<void> setMode(String m) async {
    mode = m;
    if (m == 'light') {
      dark = false;
    } else if (m == 'dark') {
      dark = true;
    }
    final sp = await SharedPreferences.getInstance();
    await sp.setString('ps_mode', m);
    notifyListeners();
  }

  Future<void> setAccent(Color c) async {
    accent = c;
    final sp = await SharedPreferences.getInstance();
    await sp.setInt('ps_accent', c.value);
    notifyListeners();
  }
}

/// 色板：根据亮度与主色派生全套语义色。
class Palette {
  final Color accent;

  // 底色
  final Color bg;
  final Color bgDeep;
  final Color surface;

  // 墨色
  final Color ink;
  final Color inkSoft;

  // 点缀（随主色联动）
  final Color clay;
  final Color clayDeep;
  final Color sage;
  final Color sand;

  final Color hairline;
  final Color error;

  Palette._({
    required this.accent,
    required this.bg,
    required this.bgDeep,
    required this.surface,
    required this.ink,
    required this.inkSoft,
    required this.clay,
    required this.clayDeep,
    required this.sage,
    required this.sand,
    required this.hairline,
    required this.error,
  });

  static Palette light(Color accent) {
    final clayDark = _darken(accent, 0.18);
    return Palette._(
      accent: accent,
      bg: const Color(0xFFF6F1E7),
      bgDeep: const Color(0xFFEFE8D9),
      surface: const Color(0xFFFFFFFF),
      ink: const Color(0xFF332E28),
      inkSoft: const Color(0xFF6E675E),
      clay: accent,
      clayDeep: clayDark,
      sage: const Color(0xFF7C8B7B),
      sand: const Color(0xFFE4D6C2),
      hairline: const Color(0xFFE8E0D1),
      error: const Color(0xFFB0553E),
    );
  }

  static Palette dark(Color accent) {
    final clayDark = _darken(accent, 0.22);
    return Palette._(
      accent: accent,
      bg: const Color(0xFF1B1815),
      bgDeep: const Color(0xFF22201C),
      surface: const Color(0xFF2A2622),
      ink: const Color(0xFFEDE6DA),
      inkSoft: const Color(0xFF9C9389),
      clay: accent,
      clayDeep: clayDark,
      sage: const Color(0xFF8C9A8C),
      sand: const Color(0xFF3B3530),
      hairline: const Color(0xFF3A342E),
      error: const Color(0xFFD8836A),
    );
  }

  static Color _darken(Color c, double amt) {
    final hsl = HSLColor.fromColor(c);
    final l = (hsl.lightness - amt).clamp(0.0, 1.0);
    return hsl.withLightness(l).toColor();
  }
}

/// 全局主题构建与访问入口
class AppTheme {
  AppTheme._();

  /// 当前会话的色板
  static Palette of(BuildContext context) {
    final c = ThemeController.instance;
    return c.dark ? Palette.dark(c.accent) : Palette.light(c.accent);
  }

  // ---- 便捷访问：随当前主题即时变化的语义色（供各处 `AppTheme.xxx` 使用）----
  static Palette get _cur =>
      ThemeController.instance.dark
          ? Palette.dark(ThemeController.instance.accent)
          : Palette.light(ThemeController.instance.accent);
  static Color get bg => _cur.bg;
  static Color get bgDeep => _cur.bgDeep;
  static Color get surface => _cur.surface;
  static Color get ink => _cur.ink;
  static Color get inkSoft => _cur.inkSoft;
  static Color get clay => _cur.clay;
  static Color get clayDeep => _cur.clayDeep;
  static Color get sage => _cur.sage;
  static Color get sand => _cur.sand;
  static Color get hairline => _cur.hairline;
  static Color get error => _cur.error;

  /// 构建 ThemeData（支持夜间 + 自定义主色）
  static ThemeData build({required bool dark, required Color accent}) {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: dark ? Brightness.dark : Brightness.light,
    ).copyWith(
      primary: accent,
      secondary: dark ? const Color(0xFF8C9A8C) : const Color(0xFF7C8B7B),
      error: dark ? const Color(0xFFD8836A) : const Color(0xFFB0553E),
    );

    final bg = dark ? const Color(0xFF1B1815) : const Color(0xFFF6F1E7);
    final surface = dark ? const Color(0xFF2A2622) : Colors.white;
    final ink = dark ? const Color(0xFFEDE6DA) : const Color(0xFF332E28);
    final inkSoft = dark ? const Color(0xFF9C9389) : const Color(0xFF6E675E);
    final hairline = dark ? const Color(0xFF3A342E) : const Color(0xFFE8E0D1);
    final clayDeep = dark ? _shade(accent, -0.22) : _shade(accent, -0.18);

    final base = ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: bg,
      brightness: dark ? Brightness.dark : Brightness.light,
      colorScheme: scheme,
      fontFamily: 'sans',
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: bg.withOpacity(0.96),
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: ink,
          fontSize: 19,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
      textTheme: base.textTheme.apply(bodyColor: ink, displayColor: ink).copyWith(
            titleLarge: const TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.3),
            titleMedium: const TextStyle(fontWeight: FontWeight.w600),
          ),
      dividerColor: hairline,
      splashColor: accent.withOpacity(0.08),
      highlightColor: accent.withOpacity(0.05),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: accent, width: 1.4),
        ),
        hintStyle: TextStyle(color: inkSoft.withOpacity(0.7)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 1),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(foregroundColor: WidgetStatePropertyAll(accent)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        elevation: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: accent.withOpacity(0.15),
        side: BorderSide(color: hairline),
        labelStyle: TextStyle(color: inkSoft, fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: dark ? const Color(0xFF35302A) : ink,
        // 显式锁定明暗两种模式下的文字色，避免夜间 Toast 用默认色衬在深底上看不清
        contentTextStyle: TextStyle(
          color: dark ? const Color(0xFFF2EBDD) : Colors.white,
          fontSize: 14,
        ),
        actionTextColor: dark ? const Color(0xFFE8C9A0) : Colors.white70,
      ),
    );
  }

  static Color _shade(Color c, double amt) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness + amt).clamp(0.0, 1.0)).toColor();
  }
}