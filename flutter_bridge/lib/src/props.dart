import 'package:flutter/material.dart';

/// 属性别名：把 Lua 侧常见别名统一到规范键。规范的 Flutter 属性名保持不变。
const Map<String, String> kPropAliases = {
  // 回调
  'onClick': 'onTap',
  'onPressed': 'onTap',
  'click': 'onTap',
  'onChanged': 'onChange',
  // 尺寸/布局（AndroLua 习惯）
  'layout_width': 'width',
  'layout_height': 'height',
  'layout_weight': 'weight',
  'layout_gravity': 'alignment',
  'gravity': 'alignment',
  'align': 'alignment',
  'borderRadius': 'radius',
  'cornerRadius': 'radius',
  'spacing': 'gap',
  'value': 'text',
  'bg': 'backgroundColor',
  'fillColor': 'color',
};

/// 统一属性处理器：所有控件都通过它读取属性。
///
/// 职责：
///  * 归一化：兼容「规范化节点(有 type)」与「AndroLua 表风格(首元素是控件)」；
///  * 别名：`onPressed`/`onClick`/`layout_width`/`gravity`… → 规范键；
///  * 类型转换：颜色/尺寸/边距/对齐/枚举/图标/渐变/边框/回调 等；
///  * 类型化读取：`p.n('gap')`、`p.color('color')`、`p.inset('padding')` …
class Props {
  Props._(this.map);

  final Map<String, dynamic> map;

  static Props of(dynamic raw) => Props._(normalize(raw));

  /// 兼容两种节点写法，并把别名键写回规范键。
  static Map<String, dynamic> normalize(dynamic raw) {
    final m = <String, dynamic>{};
    if (raw is Map) {
      raw.forEach((k, v) => m[k.toString()] = v);
      final extra = m['props'];
      if (extra is Map) extra.forEach((k, v) => m[k.toString()] = v);
    }

    // AndroLua 表风格：{ Widget, k = v, {child}, ... }
    if (!m.containsKey('type') && !m.containsKey('t') && m.containsKey('1')) {
      final type = m.remove('1');
      final numeric = <int, dynamic>{};
      for (final k in m.keys.toList()) {
        final i = int.tryParse(k);
        if (i != null && i >= 2) numeric[i] = m.remove(k);
      }
      m['type'] = typeName(type);
      if (numeric.isNotEmpty) {
        final list = (numeric.keys.toList()..sort()).map((i) => numeric[i]).toList();
        final existing = m['children'];
        m['children'] = existing is List ? (<dynamic>[...list, ...existing]) : list;
      }
    }
    return m;
  }

  /// 控件名归一：中文/类名/带包名 → 控件名。
  static String typeName(dynamic v) {
    if (v == null) return '';
    var s = v.toString().trim();
    if (s.startsWith('class ')) s = s.substring(6).trim();
    final dot = s.lastIndexOf('.');
    if (dot >= 0 && dot < s.length - 1) s = s.substring(dot + 1);
    return s;
  }

  /// 规范化 -> 它的所有别名（反向索引）。渲染器读的都是规范键，需要靠它回退到用户写的别名。
  static final Map<String, List<String>> _aliasesOf = _buildReverse();

  static Map<String, List<String>> _buildReverse() {
    final m = <String, List<String>>{};
    kPropAliases.forEach((alias, canonical) {
      (m[canonical] ??= <String>[]).add(alias);
    });
    return m;
  }

  // ---------- 实例读取（含别名回退） ----------

  String get type => (map['type'] ?? map['t'] ?? '').toString().toLowerCase();

  /// 小写键 -> 原键，用于大小写不敏感读取（h.Text 与 h.text 等价）。
  late final Map<String, String> _lower = _buildLower();

  Map<String, String> _buildLower() {
    final m = <String, String>{};
    map.forEach((k, v) => m.putIfAbsent(k.toLowerCase(), () => k));
    return m;
  }

  /// 读规范键；先精确，再大小写不敏感，最后回退到指向它的别名键（onPressed/layout_width/gravity…）。
  dynamic operator [](String k) {
    final v = map[k];
    if (v != null) return v;
    final lk = _lower[k.toLowerCase()];
    if (lk != null) {
      final lv = map[lk];
      if (lv != null) return lv;
    }
    final aliases = _aliasesOf[k];
    if (aliases != null) {
      for (final a in aliases) {
        final av = map[a];
        if (av != null) return av;
      }
    }
    return null;
  }

  bool has(String k) {
    if (map.containsKey(k)) return true;
    if (_lower.containsKey(k.toLowerCase())) return true;
    return _aliasesOf[k]?.any(map.containsKey) ?? false;
  }

  String? s(String k, [String? def]) {
    final v = this[k];
    return v == null ? def : v.toString();
  }

  double? n(String k) => toNum(this[k]);
  double nz(String k, [double def = 0]) => toNum(this[k]) ?? def;
  int? i(String k) => toNum(this[k])?.round();
  bool b(String k, [bool def = false]) => toBool(this[k]) ?? def;
  Color? color(String k) => toColor(this[k]);
  EdgeInsets? inset(String k) => toInsets(this[k]);
  Alignment? align(String k) => toAlignment(this[k]);
  Axis axis(String k) => toAxis(this[k]);
  List<dynamic> list(String k) => toList(this[k]);
  String? icon(String k) => this[k]?.toString();

  // ---------- 静态转换 ----------

  static double? toNum(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    if (v is bool) return v ? 1 : 0;
    return null;
  }

  static double? dim(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    final s = v.toString().toLowerCase();
    if (s == 'fill' || s == 'match' || s == 'match_parent') return double.infinity;
    return double.tryParse(s);
  }

  static bool? toBool(dynamic v) {
    if (v == null) return null;
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = v.toString().toLowerCase();
    if (s == 'true' || s == '1' || s == 'yes' || s == 'on') return true;
    if (s == 'false' || s == '0' || s == 'no' || s == 'off') return false;
    return null;
  }

  static Color? toColor(dynamic v) {
    if (v == null) return null;
    if (v is int) return Color(v);
    if (v is! String) return null;
    final named = {
      'red': Colors.red, 'green': Colors.green, 'blue': Colors.blue, 'black': Colors.black,
      'white': Colors.white, 'grey': Colors.grey, 'gray': Colors.grey, 'orange': Colors.orange,
      'purple': Colors.purple, 'teal': Colors.teal, 'transparent': Colors.transparent,
      'yellow': Colors.yellow, 'pink': Colors.pink, 'amber': Colors.amber, 'cyan': Colors.cyan,
      'indigo': Colors.indigo, 'brown': Colors.brown, 'lime': Colors.lime,
    };
    final lower = v.toLowerCase();
    if (named.containsKey(lower)) return named[lower];
    var hex = lower.replaceFirst('#', '').replaceFirst('0x', '');
    if (hex.length == 6) hex = 'ff$hex';
    if (hex.length == 8) {
      final value = int.tryParse(hex, radix: 16);
      if (value != null) return Color(value);
    }
    return null;
  }

  static EdgeInsets? toInsets(dynamic v) {
    if (v == null) return null;
    if (v is num) return EdgeInsets.all(v.toDouble());
    if (v is List) {
      final n = v.map((e) => (e as num).toDouble()).toList();
      if (n.length == 1) return EdgeInsets.all(n[0]);
      if (n.length == 2) return EdgeInsets.symmetric(vertical: n[0], horizontal: n[1]);
      if (n.length == 4) return EdgeInsets.fromLTRB(n[0], n[1], n[2], n[3]);
    }
    if (v is Map) {
      final m = v.cast<String, dynamic>();
      return EdgeInsets.only(
        left: toNum(m['left']) ?? 0, top: toNum(m['top']) ?? 0,
        right: toNum(m['right']) ?? 0, bottom: toNum(m['bottom']) ?? 0,
      );
    }
    return null;
  }

  static Alignment? toAlignment(dynamic v) {
    if (v == null) return null;
    switch (v.toString().toLowerCase()) {
      case 'center': return Alignment.center;
      case 'topleft': return Alignment.topLeft;
      case 'topright': return Alignment.topRight;
      case 'bottomleft': return Alignment.bottomLeft;
      case 'bottomright': return Alignment.bottomRight;
      case 'topcenter': return Alignment.topCenter;
      case 'bottomcenter': return Alignment.bottomCenter;
      case 'centerleft': return Alignment.centerLeft;
      case 'centerright': return Alignment.centerRight;
      default: return null;
    }
  }

  static WrapAlignment toWrapAlignment(dynamic v) {
    switch (v?.toString().toLowerCase()) {
      case 'center': return WrapAlignment.center;
      case 'end': case 'right': return WrapAlignment.end;
      case 'spacebetween': return WrapAlignment.spaceBetween;
      case 'spacearound': return WrapAlignment.spaceAround;
      default: return WrapAlignment.start;
    }
  }

  static MainAxisAlignment toMainAxis(dynamic v) {
    switch (v?.toString().toLowerCase()) {
      case 'center': return MainAxisAlignment.center;
      case 'end': return MainAxisAlignment.end;
      case 'spacebetween': case 'space_between': return MainAxisAlignment.spaceBetween;
      case 'spacearound': return MainAxisAlignment.spaceAround;
      case 'spaceevenly': return MainAxisAlignment.spaceEvenly;
      default: return MainAxisAlignment.start;
    }
  }

  static CrossAxisAlignment toCrossAxis(dynamic v) {
    switch (v?.toString().toLowerCase()) {
      case 'center': return CrossAxisAlignment.center;
      case 'end': return CrossAxisAlignment.end;
      case 'stretch': return CrossAxisAlignment.stretch;
      case 'baseline': return CrossAxisAlignment.baseline;
      default: return CrossAxisAlignment.start;
    }
  }

  static MainAxisSize toMainAxisSize(dynamic v) =>
      v?.toString().toLowerCase() == 'min' ? MainAxisSize.min : MainAxisSize.max;

  static TextAlign toTextAlign(dynamic v) {
    switch (v?.toString().toLowerCase()) {
      case 'center': return TextAlign.center;
      case 'right': case 'end': return TextAlign.right;
      case 'justify': return TextAlign.justify;
      default: return TextAlign.left;
    }
  }

  static Axis toAxis(dynamic v) =>
      v?.toString().toLowerCase() == 'horizontal' ? Axis.horizontal : Axis.vertical;

  static TextDirection toTextDirection(dynamic v) =>
      v?.toString().toLowerCase() == 'rtl' ? TextDirection.rtl : TextDirection.ltr;

  static VerticalDirection toVerticalDirection(dynamic v) =>
      v?.toString().toLowerCase() == 'up' ? VerticalDirection.up : VerticalDirection.down;

  static Clip toClip(dynamic v) {
    switch (v?.toString().toLowerCase()) {
      case 'none': return Clip.none;
      case 'hardedge':
      case 'hard_edge': return Clip.hardEdge;
      case 'antialiaswithsavelayer':
      case 'anti_alias_with_save_layer': return Clip.antiAliasWithSaveLayer;
      default: return Clip.antiAlias;
    }
  }

  static ScrollPhysics? toPhysics(dynamic v) {
    switch (v?.toString().toLowerCase()) {
      case 'neverscrollable': case 'never': return const NeverScrollableScrollPhysics();
      case 'bouncing': return const BouncingScrollPhysics();
      case 'clamping': return const ClampingScrollPhysics();
      default: return null;
    }
  }

  static Gradient? toGradient(dynamic v) {
    if (v is! Map) return null;
    final m = v.cast<String, dynamic>();
    final colors = toList(m['colors']).map((c) => toColor(c)).whereType<Color>().toList();
    if (colors.isEmpty) return null;
    return LinearGradient(
      colors: colors,
      begin: toAlignment(m['begin']) ?? Alignment.topLeft,
      end: toAlignment(m['end']) ?? Alignment.bottomRight,
    );
  }

  static BoxBorder? toBorder(dynamic v) {
    if (v is Map) {
      final m = v.cast<String, dynamic>();
      final all = m['all'] ?? m['border'];
      if (all is Map) {
        final a = all.cast<String, dynamic>();
        return Border.all(color: toColor(a['color']) ?? Colors.black26, width: toNum(a['width']) ?? 1);
      }
      BorderSide side(dynamic s) {
        final mm = s is Map ? s.cast<String, dynamic>() : <String, dynamic>{};
        return BorderSide(color: toColor(mm['color']) ?? Colors.black26, width: toNum(mm['width']) ?? 1);
      }
      final hasPerSide = ['top', 'bottom', 'left', 'right'].any(m.containsKey);
      if (hasPerSide) {
        return Border(
          top: m['top'] != null ? side(m['top']) : BorderSide.none,
          bottom: m['bottom'] != null ? side(m['bottom']) : BorderSide.none,
          left: m['left'] != null ? side(m['left']) : BorderSide.none,
          right: m['right'] != null ? side(m['right']) : BorderSide.none,
        );
      }
    }
    return null;
  }

  static List<BoxShadow>? toShadows(dynamic v) {
    final list = toList(v);
    final out = <BoxShadow>[];
    for (final e in list) {
      if (e is Map) {
        final m = e.cast<String, dynamic>();
        out.add(BoxShadow(
          color: toColor(m['color']) ?? const Color(0x33000000),
          blurRadius: toNum(m['blurRadius']) ?? 8,
          spreadRadius: toNum(m['spreadRadius']) ?? 0,
          offset: Offset(toNum(m['dx']) ?? 0, toNum(m['dy']) ?? 2),
        ));
      }
    }
    return out.isEmpty ? null : out;
  }

  static TextStyle toTextStyle(Props p) {
    final weight = p['fontWeight'];
    FontWeight? fw;
    if (weight is num) {
      fw = FontWeight.values[(weight ~/ 100 - 1).clamp(0, 8)];
    } else if (weight is bool) {
      fw = weight ? FontWeight.bold : FontWeight.normal;
    } else if (weight is String) {
      switch (weight.toLowerCase()) {
        case 'bold': fw = FontWeight.bold; break;
        case 'normal': fw = FontWeight.normal; break;
        default:
          final n = int.tryParse(weight.replaceAll(RegExp(r'\D'), ''));
          if (n != null) fw = FontWeight.values[(n ~/ 100 - 1).clamp(0, 8)];
      }
    }
    return TextStyle(
      fontSize: p.n('fontSize'),
      color: p.color('color') ?? p.color('textColor'),
      fontWeight: fw,
      fontStyle: p.s('fontStyle')?.toLowerCase() == 'italic' ? FontStyle.italic : null,
      decoration: toTextDecoration(p['decoration']),
      letterSpacing: p.n('letterSpacing'),
      height: p.n('lineHeight') ?? p.n('height'),
    );
  }

  static TextDecoration? toTextDecoration(dynamic v) {
    switch (v?.toString().toLowerCase()) {
      case 'underline': return TextDecoration.underline;
      case 'linethrough':
      case 'line_through':
      case 'strikethrough': return TextDecoration.lineThrough;
      case 'overline': return TextDecoration.overline;
      case 'none': return TextDecoration.none;
      default: return null;
    }
  }

  static BoxFit toBoxFit(dynamic v) {
    switch (v?.toString().toLowerCase()) {
      case 'contain': return BoxFit.contain;
      case 'fill': return BoxFit.fill;
      case 'fitwidth':
      case 'fit_width': return BoxFit.fitWidth;
      case 'fitheight':
      case 'fit_height': return BoxFit.fitHeight;
      case 'none': return BoxFit.none;
      case 'scaledown':
      case 'scale_down': return BoxFit.scaleDown;
      default: return BoxFit.cover;
    }
  }

  static TextOverflow? toOverflow(dynamic v) {
    switch (v?.toString().toLowerCase()) {
      case 'ellipsis': return TextOverflow.ellipsis;
      case 'clip': return TextOverflow.clip;
      case 'fade': return TextOverflow.fade;
      case 'visible': return TextOverflow.visible;
      default: return null;
    }
  }

  static TextInputType? toKeyboardType(dynamic v) {
    switch (v?.toString().toLowerCase()) {
      case 'number':
      case 'phone': return TextInputType.phone;
      case 'decimal': return const TextInputType.numberWithOptions(decimal: true);
      case 'email': return TextInputType.emailAddress;
      case 'url': return TextInputType.url;
      case 'multiline': return TextInputType.multiline;
      case 'text': return TextInputType.text;
      default: return null;
    }
  }

  static List<dynamic> toList(dynamic v) {
    if (v == null) return const [];
    if (v is List) return v;
    return [v];
  }

  // ---------- 图标 ----------

  static const Map<String, IconData> icons = {
    'home': Icons.home, 'add': Icons.add, 'delete': Icons.delete, 'star': Icons.star,
    'favorite': Icons.favorite, 'settings': Icons.settings, 'search': Icons.search,
    'check': Icons.check, 'close': Icons.close, 'arrow_forward': Icons.arrow_forward,
    'arrow_back': Icons.arrow_back, 'arrow_upward': Icons.arrow_upward,
    'arrow_downward': Icons.arrow_downward, 'arrow_drop_up': Icons.arrow_drop_up,
    'arrow_drop_down': Icons.arrow_drop_down, 'person': Icons.person, 'people': Icons.people,
    'menu': Icons.menu, 'more_vert': Icons.more_vert, 'more_horiz': Icons.more_horiz,
    'notifications': Icons.notifications, 'dashboard': Icons.dashboard, 'analytics': Icons.analytics,
    'bar_chart': Icons.bar_chart, 'message': Icons.message, 'mail': Icons.mail,
    'timer': Icons.timer, 'task_alt': Icons.task_alt, 'upload_file': Icons.upload_file,
    'download': Icons.download, 'share': Icons.share, 'print': Icons.print,
    'description': Icons.description, 'image': Icons.image, 'circle': Icons.circle,
    'remove': Icons.remove, 'logout': Icons.logout, 'login': Icons.login,
    'edit': Icons.edit, 'lock': Icons.lock, 'info': Icons.info, 'warning': Icons.warning,
    'refresh': Icons.refresh, 'filter_list': Icons.filter_list, 'sort': Icons.sort,
    'calendar_today': Icons.calendar_today, 'schedule': Icons.schedule, 'attach_money': Icons.attach_money,
    'shopping_cart': Icons.shopping_cart, 'phone': Icons.phone, 'email': Icons.email,
    'map': Icons.map, 'camera_alt': Icons.camera_alt, 'play_arrow': Icons.play_arrow,
    'pause': Icons.pause, 'skip_next': Icons.skip_next, 'skip_previous': Icons.skip_previous,
    'volume_up': Icons.volume_up, 'volume_off': Icons.volume_off, 'cloud': Icons.cloud,
    'folder': Icons.folder, 'attach_file': Icons.attach_file, 'visibility': Icons.visibility,
    'thumb_up': Icons.thumb_up, 'chat': Icons.chat, 'bookmark': Icons.bookmark,
    'error': Icons.error, 'help': Icons.help, 'qr_code': Icons.qr_code, 'location_on': Icons.location_on,
    'navigation': Icons.navigation, 'my_location': Icons.my_location, 'store': Icons.store,
    'account_circle': Icons.account_circle, 'vpn_key': Icons.vpn_key, 'security': Icons.security,
  };

  static IconData toIcon(dynamic name) {
    final key = name?.toString().toLowerCase();
    if (key == null) return Icons.widgets;
    return icons[key] ?? Icons.widgets;
  }
}
