import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Props 缓存条目：保存原始对象引用，避免 identityHashCode 碰撞时误用。
class _PropsCacheEntry {
  _PropsCacheEntry(this.raw, this.props, this.keyCount);
  final Object raw;
  final Props props;

  /// 建缓存时的键数，用于 debug 下断言「同一 Map 实例没被原地改过」。
  final int keyCount;
}

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
  'bg': 'backgroundColor',
  // 注意：不再把 'value' -> 'text'、'fillColor' -> 'color' 全局别名化。
  // Slider/Checkbox/Dropdown 等控件的 value/fillColor 语义与 Text/Container 不同，
  // 全局映射会跨控件污染，改由各控件显式读取。
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

  /// Props 缓存：normalize 要新建 Map 并拷贝所有键，是每节点每次 render 的热路径。
  /// 用 identityHashCode 作 key，并校验 raw 仍是同一对象（防 hash 碰撞）——
  /// 只要调用方不修改传入的 Map（渲染器只读），缓存就是安全的。
  static final Map<int, _PropsCacheEntry> _cache = {};
  static const int _cacheLimit = 512;

  static Props of(dynamic raw) {
    if (raw is Map) {
      final id = identityHashCode(raw);
      final hit = _cache[id];
      if (hit != null && identical(hit.raw, raw)) {
        assert(
          hit.keyCount == raw.length,
          'Props.of: 传入的 Map 被原地修改过（键数变了）。同一实例必须保持内容不变，'
          '否则会命中缓存里的旧属性；改属性请换一个新 Map。',
        );
        // 命中时挪到末尾：热点条目不会被误踢（Map 按插入序迭代，这就是真 LRU）
        _cache.remove(id);
        _cache[id] = hit;
        return hit.props;
      }
      final props = Props._(normalize(raw));
      _cache[id] = _PropsCacheEntry(raw, props, raw.length);
      if (_cache.length > _cacheLimit) {
        // 超出上限就丢最早的一批（LRU：最少使用的在后面）
        final drop = _cache.keys.take(_cache.length - _cacheLimit).toList();
        for (final k in drop) {
          _cache.remove(k);
        }
      }
      return props;
    }
    return Props._(normalize(raw));
  }

  /// 清空缓存（测试或需要强制重解析时用）。
  static void clearCache() => _cache.clear();

  /// 兼容两种节点写法，并把别名键写回规范键。
  ///
  /// 识别规则（按顺序）：
  ///  1. 规范化节点：有 `type`（或 `t`）字段，直接用；`props` 子表会被展平；
  ///  2. AndroLua 表风格：`{ Widget名, k = v, {子1}, {子2}, ... }`，即首元素是控件名，
  ///     数字下标 ≥2 的项是子节点，其余键值对是属性——会把 `"1"` 换成 `type`，
  ///     并把数字下标的项按序号收集进 `children`；
  ///  3. 其余情况原样使用（可能没有 type，渲染时会走降级分支）。
  // 已知控件名（小写）：只用于「AndroLua 表风格」兜底判定（JSON 字符串形态的 spec、
  // 或直接传 Map 的场景）。常规路径由原生侧归一成 {type=...}，不走这里。
  // 扩展控件用 registerType 注册。
  static final Set<String> knownTypes = {
    'column', 'row', 'stack', 'container', 'padding', 'center', 'expanded', 'sizedbox', 'spacer', 'wrap',
    'align', 'aspectratio', 'cliprrect', 'opacity', 'safearea', 'positioned', 'fractionallysizedbox',
    'singlechildscrollview', 'transform', 'text', 'selectabletext', 'icon', 'image',
    'elevatedbutton', 'textbutton', 'filledbutton', 'outlinedbutton', 'iconbutton', 'floatingactionbutton',
    'materialbutton', 'card', 'circleavatar', 'chip', 'actionchip', 'filterchip', 'choicechip', 'inputchip',
    'listtile', 'listview', 'gridview', 'divider', 'verticaldivider', 'circularprogressindicator',
    'linearprogressindicator', 'snackbar', 'checkbox', 'switch', 'slider', 'rangeslider', 'textfield',
    'textformfield', 'inkwell', 'gesturedetector', 'dropdownbutton', 'dropdownbuttonformfield', 'scaffold',
    'appbar', 'drawer', 'useraccountsdrawerheader', 'bottomnavigationbar', 'bottomappbar', 'tab', 'tabbar',
    'tabbarview', 'defaulttabcontroller', 'tooltip', 'badge', 'placeholder', 'refreshindicator', 'switchlisttile',
    'checkboxlisttile', 'radiolisttile', 'radio', 'expansiontile', 'stepper', 'datatable', 'calendardatepicker',
    'animatedopacity', 'animatedcontainer', 'material', 'decoratedbox', 'coloredbox', 'constrainedbox',
    'intrinsicwidth', 'intrinsicheight', 'fittedbox', 'rotatedbox', 'clipoval', 'cliprect', 'offstage',
    'visibility', 'absorbpointer', 'ignorepointer', 'scrollbar', 'indexedstack', 'baseline', 'limitedbox',
    'segmentedbutton', 'togglebuttons', 'popupmenubutton', 'dismissible', 'navigationbar', 'navigationrail',
    'navigationdrawer', 'form', 'richtext', 'cupertinoactivityindicator', 'cupertinobutton', 'cupertinoswitch',
    'cupertinoslider', 'cupertinoalertdialog', 'cupertinonavigationbar', 'animatedalign', 'animatedpadding',
    'animatedscale', 'animatedrotation', 'animatedslide', 'animatedswitcher', 'animateddefaulttextstyle',
    'animatedcrossfade', 'animatedpositioned', 'animatedsize', 'animatedtheme', 'alertdialog', 'simpledialog',
    'dialog', 'bottomsheet', 'materialbanner', 'pageview', 'dropdownmenu', 'reorderablelistview',
    'expansionpanellist', 'table', 'customscrollview', 'slivertoboxadapter', 'sliverpadding', 'sliverlist',
    'slivergrid', 'sliverfillremaining', 'sliverappbar', 'searchbar', 'listwheelscrollview', 'qrcode',
    'qrimageview', 'fluttermap', 'linechart', 'barchart', 'piechart', 'videoplayer', 'audioplayer',
  };

  /// 注册自定义控件名（Renderer.register 会调），用于上面的兜底判定。
  static void registerType(String name) => knownTypes.add(name.trim().toLowerCase());

  static final Set<String> _canonicalProps = kPropAliases.values.toSet();
  static const Set<String> _structuralKeys = {'children', 'child', 'id', 'style', 'type', 't', 'props'};

  /// 这个键像不像控件属性（判定「首元素是控件名」的辅助条件）
  static bool _isKnownProp(String k) {
    final key = k.toLowerCase();
    if (int.tryParse(key) != null) return true; // 数字键 = 子节点
    return _canonicalProps.contains(key) || _structuralKeys.contains(key);
  }

  static Map<String, dynamic> normalize(dynamic raw) {
    final m = <String, dynamic>{};
    if (raw is Map) {
      raw.forEach((k, v) => m[k.toString()] = v);
      final extra = m['props'];
      if (extra is Map) extra.forEach((k, v) => m[k.toString()] = v);
    }

    // AndroLua 表风格：{ Widget, k = v, {child}, ... }
    // 只有当首元素真的像控件名（已知名/已注册，或这份表带已知属性键）才当节点，
    // 否则保持数据表原样——避免把恰好带 "1" 键的纯数据 Map 误判成控件。
    if (!m.containsKey('type') && !m.containsKey('t') && m.containsKey('1')) {
      final probe = m['1'];
      final probeName = typeName(probe).toLowerCase();
      final looksNode = knownTypes.contains(probeName) ||
          m.keys.any((k) => k != '1' && _isKnownProp(k));
      if (!looksNode) return m;
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
    var s = v.toString().toLowerCase().trim();
    if (s == 'fill' || s == 'match' || s == 'match_parent') return double.infinity;
    // 兼容 Android 习惯的单位后缀：16dp / 16sp / 16px
    s = s.replaceAll(RegExp(r'(dp|dip|sp|px)$'), '');
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
    // int 按 ARGB（0xAARRGGBB）解释，不是 RGB：0xFFFF0000 才是红色，
    // 0xFF0000 是 alpha=0 的**全透明红**。想写 RGB 请用字符串 '#FF0000'。
    if (v is int) {
      if (kDebugMode && v > 0 && v <= 0xFFFFFF) {
        // 这种值多半是想写 RGB，但按 ARGB 解释会得到透明色——提醒一下
        debugPrint('Props.toColor: $v 看起来是 RGB（高位没带 alpha），ARGB 解释下是透明色；'
            '请用 "#${v.toRadixString(16).padLeft(6, '0')}" 或 0xFF${v.toRadixString(16).padLeft(6, '0')}');
      }
      return Color(v);
    }
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
    // 支持 CSS 简写：#abc -> #aabbcc
    if (hex.length == 3 || hex.length == 4) {
      hex = hex.split('').map((c) => '$c$c').join();
    }
    if (hex.length == 6) hex = 'ff$hex';
    if (hex.length == 8) {
      final value = int.tryParse(hex, radix: 16);
      if (value != null) return Color(value);
    }
    return null;
  }

  static double? _len(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) {
      final s = v.toLowerCase().trim().replaceAll(RegExp(r'(dp|dip|sp|px)$'), '');
      return double.tryParse(s);
    }
    return null;
  }

  /// 边距：num / [全] / [垂直, 水平] / [左上右下] / {left,top,right,bottom}。
  /// 注意 [垂直, 水平] 的顺序沿用 AndroLua/Android 习惯（不是 CSS 的 [水平, 垂直]）。
  static EdgeInsets? toInsets(dynamic v) {
    if (v == null) return null;
    if (v is num) return EdgeInsets.all(v.toDouble());
    if (v is String) {
      final n = _len(v);
      return n == null ? null : EdgeInsets.all(n);
    }
    if (v is List) {
      // 用 _len 容错：元素可能是字符串（如 ['10', '20'] / ['8dp']），旧代码直接 as num 会崩
      final n = v.map(_len).whereType<double>().toList();
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

  /// 枚举名归一：小写 + 去空格/下划线/中划线（'Top Left' / 'top_left' → 'topleft'）
  static String _enumKey(dynamic v) =>
      v.toString().toLowerCase().replaceAll(RegExp(r'[\s_\-]'), '');

  static Alignment? toAlignment(dynamic v) {
    if (v == null) return null;
    switch (_enumKey(v)) {
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
    switch (v == null ? '' : _enumKey(v)) {
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

  static Duration toDuration(dynamic v) => Duration(milliseconds: toNum(v)?.round() ?? 0);

  static Curve toCurve(dynamic v) {
    switch (v == null ? '' : _enumKey(v)) {
      case 'ease': return Curves.ease;
      case 'easein': return Curves.easeIn;
      case 'easeout': return Curves.easeOut;
      case 'easeinout': return Curves.easeInOut;
      case 'linear': return Curves.linear;
      case 'bouncein': return Curves.bounceIn;
      case 'bounceout': return Curves.bounceOut;
      case 'elasticin': return Curves.elasticIn;
      case 'elasticout': return Curves.elasticOut;
      case 'fastoutslowin': return Curves.fastOutSlowIn;
      case 'decelerate': return Curves.decelerate;
      default: return Curves.easeInOut;
    }
  }

  static TextInputAction? toInputAction(dynamic v) {
    switch (v?.toString().toLowerCase()) {
      case 'done': return TextInputAction.done;
      case 'go': return TextInputAction.go;
      case 'next': return TextInputAction.next;
      case 'previous': return TextInputAction.previous;
      case 'search': return TextInputAction.search;
      case 'send': return TextInputAction.send;
      case 'none': return TextInputAction.none;
      case 'newline': return TextInputAction.newline;
      default: return null;
    }
  }

  static TextCapitalization toTextCapitalization(dynamic v) {
    switch (v?.toString().toLowerCase()) {
      case 'words': return TextCapitalization.words;
      case 'sentences': return TextCapitalization.sentences;
      case 'characters': return TextCapitalization.characters;
      default: return TextCapitalization.none;
    }
  }

  static BoxShape toBoxShape(dynamic v) =>
      v?.toString().toLowerCase() == 'circle' ? BoxShape.circle : BoxShape.rectangle;

  static BorderRadius? toBorderRadius(dynamic v) {
    if (v == null) return null;
    if (v is num) return BorderRadius.circular(v.toDouble());
    if (v is List) {
      final n = v.map(toNum).whereType<double>().toList();
      if (n.length == 1) return BorderRadius.circular(n[0]);
      if (n.length == 4) {
        return BorderRadius.only(
          topLeft: Radius.circular(n[0]),
          topRight: Radius.circular(n[1]),
          bottomRight: Radius.circular(n[2]),
          bottomLeft: Radius.circular(n[3]),
        );
      }
    }
    return null;
  }

  static BorderStyle toBorderStyle(dynamic v) =>
      v?.toString().toLowerCase() == 'none' ? BorderStyle.none : BorderStyle.solid;

  /// 形状：circle / stadium / beveled / rounded（默认）。
  /// 传了名字但识别不出时退回 rounded（避免“设置了但没生效”的困惑）；完全不传返回 null。
  static OutlinedBorder? toShape(dynamic v, [double? radius]) {
    if (v == null) return null;
    switch (v.toString().toLowerCase()) {
      case 'circle': return const CircleBorder();
      case 'stadium':
      case 'pill': return const StadiumBorder();
      case 'beveled': return BeveledRectangleBorder(borderRadius: BorderRadius.circular(radius ?? 0));
      default: return RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius ?? 4));
    }
  }

  static ImageRepeat toImageRepeat(dynamic v) {
    switch (v?.toString().toLowerCase()) {
      case 'repeat': return ImageRepeat.repeat;
      case 'repeatx': return ImageRepeat.repeatX;
      case 'repeaty': return ImageRepeat.repeatY;
      default: return ImageRepeat.noRepeat;
    }
  }

  static FilterQuality toFilterQuality(dynamic v) {
    switch (v?.toString().toLowerCase()) {
      case 'none': return FilterQuality.none;
      case 'low': return FilterQuality.low;
      case 'medium': return FilterQuality.medium;
      default: return FilterQuality.high;
    }
  }

  static StackFit toStackFit(dynamic v) {
    switch (v?.toString().toLowerCase()) {
      case 'expand': return StackFit.expand;
      case 'passthrough': return StackFit.passthrough;
      default: return StackFit.loose;
    }
  }

  static TextWidthBasis toTextWidthBasis(dynamic v) =>
      v?.toString().toLowerCase() == 'longestline' ? TextWidthBasis.longestLine : TextWidthBasis.parent;

  static BlendMode? toBlendMode(dynamic v) {
    switch (v?.toString().toLowerCase()) {
      case 'multiply': return BlendMode.multiply;
      case 'screen': return BlendMode.screen;
      case 'overlay': return BlendMode.overlay;
      case 'darken': return BlendMode.darken;
      case 'lighten': return BlendMode.lighten;
      case 'colorburn': return BlendMode.colorBurn;
      case 'colordodge': return BlendMode.colorDodge;
      case 'srcatop': return BlendMode.srcATop;
      case 'srcin': return BlendMode.srcIn;
      case 'dstin': return BlendMode.dstIn;
      case 'dstover': return BlendMode.dstOver;
      case 'xor': return BlendMode.xor;
      default: return null;
    }
  }

  /// 支持 linear / radial / sweep 三种渐变（type 字段区分，默认 linear）。
  static Gradient? toAnyGradient(dynamic v) {
    if (v is! Map) return null;
    final m = v.cast<String, dynamic>();
    final colors = toList(m['colors']).map(toColor).whereType<Color>().toList();
    if (colors.isEmpty) return null;
    final stops = toList(m['stops']).map(toNum).whereType<double>().toList();
    final type = (m['type'] ?? 'linear').toString().toLowerCase();
    if (type == 'radial') {
      return RadialGradient(
        colors: colors,
        stops: stops.isEmpty ? null : stops,
        center: toAlignment(m['center']) ?? Alignment.center,
        radius: toNum(m['radius']) ?? 0.5,
      );
    }
    if (type == 'sweep') {
      return SweepGradient(
        colors: colors,
        stops: stops.isEmpty ? null : stops,
        center: toAlignment(m['center']) ?? Alignment.center,
      );
    }
    // 角度：支持 angle（度），从 12 点方向顺时针。不传则用 begin/end。
    final angle = toNum(m['angle']);
    if (angle != null) {
      final rad = angle * math.pi / 180.0;
      final dx = math.sin(rad) / 2.0;
      final dy = -math.cos(rad) / 2.0;
      return LinearGradient(
        colors: colors,
        stops: stops.isEmpty ? null : stops,
        begin: Alignment(-dx, -dy),
        end: Alignment(dx, dy),
      );
    }
    return LinearGradient(
      colors: colors,
      stops: stops.isEmpty ? null : stops,
      begin: toAlignment(m['begin']) ?? Alignment.topLeft,
      end: toAlignment(m['end']) ?? Alignment.bottomRight,
    );
  }

  static Gradient? toGradient(dynamic v) => toAnyGradient(v);

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
      decorationColor: p.color('decorationColor'),
      decorationStyle: _decorationStyle(p['decorationStyle']),
      fontFamily: p.s('fontFamily'),
      fontFamilyFallback: toList(p['fontFamilyFallback']).isEmpty
          ? null
          : toList(p['fontFamilyFallback']).map((e) => e.toString()).toList(),
      shadows: toShadows(p['shadow'] ?? p['shadows']),
      backgroundColor: p.color('textBackgroundColor'),
      wordSpacing: p.n('wordSpacing'),
      letterSpacing: p.n('letterSpacing'),
      // 行高只认 lineHeight；height 在通用层是像素尺寸，
      // 仅在「看着像倍数」(≤4) 时才兼容旧写法，否则忽略（写 height=100 会变成 100 倍行高）
      height: p.n('lineHeight') ?? _lineHeightCompat(p.n('height')),
    );
  }

  /// `height` 作为行高倍数的旧写法兼容：只在 (0, 4] 区间内认（像素值一律不认）
  static double? _lineHeightCompat(double? h) => (h != null && h > 0 && h <= 4) ? h : null;

  static TextDecorationStyle? _decorationStyle(dynamic v) {
    switch (v?.toString().toLowerCase()) {
      case 'dashed': return TextDecorationStyle.dashed;
      case 'dotted': return TextDecorationStyle.dotted;
      case 'double': return TextDecorationStyle.double;
      case 'wavy': return TextDecorationStyle.wavy;
      case 'solid': return TextDecorationStyle.solid;
      default: return null;
    }
  }

  /// 语言/地区：'zh' / 'zh-CN' / 'zh_CN' -> Locale。
  static Locale? toLocale(dynamic v) {
    final s = v?.toString();
    if (s == null || s.isEmpty) return null;
    final parts = s.split(RegExp(r'[-_]'));
    return parts.length > 1 ? Locale(parts[0], parts[1]) : Locale(parts[0]);
  }

  /// 日期解析：支持 ISO 字符串 / 毫秒时间戳 / DateTime。
  static DateTime? toDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
    return DateTime.tryParse(v.toString());
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

  /// 密度：'standard' | 'comfortable' | 'compact'，或数字（横纵同值），或 {horizontal, vertical}
  static VisualDensity? toVisualDensity(dynamic v) {
    if (v == null) return null;
    if (v is num) return VisualDensity(horizontal: v.toDouble(), vertical: v.toDouble());
    if (v is Map) {
      return VisualDensity(
        horizontal: (v['horizontal'] as num?)?.toDouble() ?? 0,
        vertical: (v['vertical'] as num?)?.toDouble() ?? 0,
      );
    }
    switch (v.toString().toLowerCase()) {
      case 'compact':
        return VisualDensity.compact;
      case 'comfortable':
        return VisualDensity.comfortable;
      case 'standard':
        return VisualDensity.standard;
    }
    return null;
  }

  /// 点按目标尺寸：'padded' | 'shrinkwrap'（大小写/下划线都不讲究）
  static MaterialTapTargetSize? toTapTargetSize(dynamic v) {
    if (v == null) return null;
    switch (v.toString().toLowerCase().replaceAll('_', '')) {
      case 'padded':
        return MaterialTapTargetSize.padded;
      case 'shrinkwrap':
        return MaterialTapTargetSize.shrinkWrap;
    }
    return null;
  }

  /// 偏移：数字（x=y）/ [x, y] / {x, y}
  static Offset? toOffset(dynamic v) {
    if (v == null) return null;
    if (v is num) return Offset(v.toDouble(), v.toDouble());
    if (v is List && v.length >= 2) {
      return Offset((v[0] as num).toDouble(), (v[1] as num).toDouble());
    }
    if (v is Map) {
      return Offset((v['x'] as num?)?.toDouble() ?? 0, (v['y'] as num?)?.toDouble() ?? 0);
    }
    return null;
  }

  static IconData toIcon(dynamic name) {
    final key = name?.toString().toLowerCase();
    if (key == null) return Icons.widgets;
    final icon = icons[key];
    if (icon != null) return icon;
    // 未知名：用问号图标，并在 debug 下提醒（写错名字很常见，静默降级不好排查）
    if (kDebugMode) debugPrint('Props.toIcon: 未知图标名 "$key"，已用问号图标代替');
    return Icons.help_outline;
  }
}
