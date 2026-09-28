import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'bridge.dart';

/// 把 Lua 传来的 widget 描述（JSON/UISpec）转成 Flutter widget 树。
///
/// 设计目标：**尽量自适应**。
///  * 注册表驱动：内置 Material 常用控件；未知控件优雅降级；
///  * 通用属性绑定：child/children/appBar/body/items/leading/title/actions/
///    decoration/style/onPressed 等插槽与属性统一解析；
///  * 容错：单个节点构建失败只影响该节点，不会整屏白；
///  * 可扩展：`Renderer.register(name, builder)` 可加自定义控件。
///
/// 说明：Flutter 的 release(AOT) 没有反射（dart:mirrors 不支持 AOT），
/// 所以无法凭字符串创建任意 Flutter 控件；能覆盖的是「注册过的控件名」。
class Renderer {
  /// 兜底用的 Scaffold key（便于 Lua 通过 Dart 方法打开抽屉）。
  static final GlobalKey<ScaffoldState> scaffoldKey = GlobalKey<ScaffoldState>();

  /// 自定义控件扩展点：名字 -> 构建函数（参数为该节点的属性表）。
  static final Map<String, Widget Function(Map<String, dynamic>)> custom = {};

  static void register(String type, Widget Function(Map<String, dynamic>) builder) {
    custom[type.toLowerCase()] = builder;
  }

  static Widget build(dynamic spec) {
    if (spec is String) {
      try {
        return _build(jsonDecode(spec)) ?? const SizedBox.shrink();
      } catch (_) {
        return Text(spec);
      }
    }
    return _build(spec) ?? const SizedBox.shrink();
  }

  // ============================================================
  // 节点构建
  // ============================================================

  static Widget? _build(dynamic spec) {
    try {
      return _buildInner(spec);
    } catch (e) {
      // 单个节点出错不影响其它节点
      return Padding(
        padding: const EdgeInsets.all(4),
        child: Text('⚠ 节点渲染失败: $e', style: const TextStyle(color: Colors.red, fontSize: 11)),
      );
    }
  }

  static Widget? _buildInner(dynamic spec) {
    if (spec == null) return null;
    if (spec is String) return Text(spec);
    if (spec is num || spec is bool) return Text('$spec');
    if (spec is! Map) return const SizedBox.shrink();

    final props = _props(spec);
    final type = (props['type'] ?? props['t'] ?? '').toString().toLowerCase();
    final children = _children(props['children'] ?? props['child']);

    Widget child0() => children.isNotEmpty ? children.first : const SizedBox.shrink();

    final ext = custom[type];
    if (ext != null) {
      return _wrapCommon(ext(props), props);
    }

    Widget result;
    switch (type) {
      // ---------- 布局 ----------
      case 'column':
        result = Column(
          mainAxisAlignment: _mainAxis(props['mainAxisAlignment'] ?? props['gravity']),
          crossAxisAlignment: _crossAxis(props['crossAxisAlignment']),
          mainAxisSize: _size(props['mainAxisSize']),
          spacing: _num(props['gap'] ?? props['spacing']) ?? 0,
          children: children,
        );
        break;
      case 'row':
        result = Row(
          mainAxisAlignment: _mainAxis(props['mainAxisAlignment'] ?? props['gravity']),
          crossAxisAlignment: _crossAxis(props['crossAxisAlignment']),
          mainAxisSize: _size(props['mainAxisSize']),
          spacing: _num(props['gap'] ?? props['spacing']) ?? 0,
          children: children,
        );
        break;
      case 'stack':
        result = Stack(
          alignment: _alignment(props['alignment']) ?? AlignmentDirectional.topStart,
          children: children,
        );
        break;
      case 'container':
        result = Container(
          width: _dim(props['width']),
          height: _dim(props['height']),
          alignment: _alignment(props['alignment']),
          padding: _insets(props['padding']),
          margin: _insets(props['margin']),
          decoration: _decoration(props),
          child: child0(),
        );
        break;
      case 'padding':
        result = Padding(padding: _insets(props['padding']) ?? EdgeInsets.zero, child: child0());
        break;
      case 'center':
        result = Center(child: child0());
        break;
      case 'expanded':
        result = Expanded(flex: _num(props['flex'] ?? props['weight'] ?? 1)?.round() ?? 1, child: child0());
        break;
      case 'sizedbox':
        result = SizedBox(width: _dim(props['width']), height: _dim(props['height']), child: children.isEmpty ? null : child0());
        break;
      case 'spacer':
        result = Spacer(flex: _num(props['flex'] ?? props['weight'] ?? 1)?.round() ?? 1);
        break;
      case 'wrap':
        result = Wrap(
          spacing: _num(props['gap'] ?? props['spacing']) ?? 0,
          runSpacing: _num(props['runSpacing']) ?? 0,
          alignment: _wrapAlignment(props['alignment']),
          children: children,
        );
        break;
      case 'align':
        result = Align(alignment: _alignment(props['alignment']) ?? Alignment.center, child: child0());
        break;
      case 'aspectratio':
        result = AspectRatio(aspectRatio: _num(props['aspectRatio'] ?? props['ratio']) ?? 1.0, child: child0());
        break;
      case 'cliprrect':
        result = ClipRRect(
          borderRadius: BorderRadius.circular(_num(props['radius']) ?? 8),
          child: child0(),
        );
        break;
      case 'opacity':
        result = Opacity(opacity: (_num(props['opacity']) ?? 1.0).clamp(0.0, 1.0), child: child0());
        break;
      case 'safearea':
        result = SafeArea(child: child0());
        break;
      case 'positioned':
        result = Positioned(
          left: _dim(props['left']),
          top: _dim(props['top']),
          right: _dim(props['right']),
          bottom: _dim(props['bottom']),
          width: _dim(props['width']),
          height: _dim(props['height']),
          child: child0(),
        );
        break;
      case 'fractionallysizedbox':
        result = FractionallySizedBox(
          widthFactor: _num(props['widthFactor']),
          heightFactor: _num(props['heightFactor']),
          alignment: _alignment(props['alignment']) ?? Alignment.centerLeft,
          child: child0(),
        );
        break;
      case 'singlechildscrollview':
        result = SingleChildScrollView(
          scrollDirection: _axis(props['scrollDirection']),
          physics: _physics(props['physics']),
          padding: _insets(props['padding']),
          child: child0(),
        );
        break;
      case 'transform':
        final t = props['translate'];
        final off = t is List && t.length >= 2
            ? Offset((t[0] as num).toDouble(), (t[1] as num).toDouble())
            : Offset.zero;
        result = Transform.translate(offset: off, child: child0());
        break;

      // ---------- 文本 / 图片 / 图标 ----------
      case 'text':
        result = Text(
          (props['text'] ?? props['value'] ?? '').toString(),
          textAlign: _textAlign(props['textAlign']),
          style: _textStyle(props),
          maxLines: _num(props['maxLines'])?.round(),
          overflow: _num(props['maxLines']) != null ? TextOverflow.ellipsis : null,
        );
        break;
      case 'selectabletext':
        result = SelectableText(
          (props['text'] ?? props['value'] ?? '').toString(),
          textAlign: _textAlign(props['textAlign']),
          style: _textStyle(props),
        );
        break;
      case 'icon':
        result = Icon(_icon(props['icon'] ?? props['name']), color: _color(props['color']), size: _num(props['size']));
        break;
      case 'image':
        final url = props['url'] ?? props['src'] ?? props['asset'];
        result = url != null
            ? Image.network(url.toString(), width: _dim(props['width']), height: _dim(props['height']), fit: BoxFit.cover)
            : const SizedBox.shrink();
        break;

      // ---------- 按钮 ----------
      case 'button' || 'elevatedbutton' || 'textbutton' || 'filledbutton' || 'outlinedbutton':
        final label = (props['text'] ?? props['label'] ?? 'Button').toString();
        final onTap = _voidCallback(props['onTap'] ?? props['onPressed'] ?? props['onClick'], fallback: props);
        final style = _buttonStyle(props);
        final child = _widgetOrText(props['child'], label);
        result = Padding(
          padding: _insets(props['padding']) ?? EdgeInsets.zero,
          child: type == 'textbutton'
              ? TextButton(onPressed: onTap, style: style, child: child)
              : type == 'outlinedbutton'
                  ? OutlinedButton(onPressed: onTap, style: style, child: child)
                  : type == 'filledbutton'
                      ? FilledButton(onPressed: onTap, style: style, child: child)
                      : ElevatedButton(onPressed: onTap, style: style, child: child),
        );
        break;
      case 'iconbutton':
        result = IconButton(
          icon: Icon(_icon(props['icon'] ?? props['name']), color: _color(props['color'])),
          onPressed: _voidCallback(props['onTap'] ?? props['onPressed'], fallback: props),
        );
        break;
      case 'floatingactionbutton':
        result = FloatingActionButton(
          onPressed: _voidCallback(props['onTap'] ?? props['onPressed'], fallback: props),
          backgroundColor: _color(props['color'] ?? props['backgroundColor']),
          child: Icon(_icon(props['icon'] ?? props['name'])),
        );
        break;

      // ---------- 容器类 ----------
      case 'card':
        result = Card(
          elevation: _num(props['elevation']) ?? 1,
          color: _color(props['color']) ?? _decoration(props)?.color,
          shadowColor: _color(props['shadowColor']),
          margin: _insets(props['margin']) ?? const EdgeInsets.all(4),
          shape: _num(props['radius']) != null
              ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(_num(props['radius'])!))
              : null,
          child: Padding(
            padding: _insets(props['padding']) ?? const EdgeInsets.all(12),
            child: child0(),
          ),
        );
        break;
      case 'circleavatar':
        result = CircleAvatar(
          radius: _num(props['radius']),
          backgroundColor: _color(props['color'] ?? props['backgroundColor']),
          child: children.isEmpty ? null : child0(),
        );
        break;
      case 'chip':
        result = Chip(label: Text((props['text'] ?? props['label'] ?? '').toString()));
        break;
      case 'listtile':
        result = ListTile(
          leading: _slotIcon(props['leading']),
          title: _slotText(props['title'] ?? props['text']),
          subtitle: _slotText(props['subtitle']),
          trailing: _slotText(props['trailing']),
          onTap: _voidCallback(props['onTap'] ?? props['onPressed'], fallback: props),
        );
        break;

      // ---------- 滚动 ----------
      case 'listview' || 'list':
        result = ListView(
          shrinkWrap: props['shrinkWrap'] == true,
          physics: _physics(props['physics']),
          padding: _insets(props['padding']),
          children: children,
        );
        break;
      case 'gridview':
        result = GridView.count(
          crossAxisCount: _num(props['crossAxisCount'] ?? props['columns'])?.round() ?? 2,
          mainAxisSpacing: _num(props['gap'] ?? props['mainAxisGap']) ?? 8,
          crossAxisSpacing: _num(props['gap'] ?? props['crossAxisGap']) ?? 8,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: children,
        );
        break;
      case 'divider':
        result = Divider(color: _color(props['color']), thickness: _num(props['thickness']));
        break;
      case 'circularprogressindicator':
        result = Center(child: CircularProgressIndicator(value: _num(props['value'])));
        break;
      case 'linearprogressindicator':
        result = LinearProgressIndicator(value: _num(props['value']));
        break;

      // ---------- 交互 ----------
      case 'checkbox':
        result = BridgeCheckbox(
          key: _nodeKey(props),
          initial: props['value'] == true,
          color: _color(props['color']),
          onChanged: (v) => _emit(props['onChange'] ?? props['onChanged'] ?? props['onPressed'], v, fallback: props),
        );
        break;
      case 'switch':
        result = BridgeSwitch(
          key: _nodeKey(props),
          initial: props['value'] == true,
          onChanged: (v) => _emit(props['onChange'] ?? props['onChanged'], v, fallback: props),
        );
        break;
      case 'slider':
        result = BridgeSlider(
          key: _nodeKey(props),
          initial: _num(props['value']) ?? 0,
          min: _num(props['min']) ?? 0,
          max: _num(props['max']) ?? 1,
          onChanged: (v) => _emit(props['onChange'] ?? props['onChanged'], v, fallback: props),
        );
        break;
      case 'textfield' || 'edittext':
        result = BridgeTextField(
          key: _nodeKey(props),
          hint: props['hint'] ?? (props['decoration'] is Map ? (props['decoration'] as Map)['hintText']?.toString() : null),
          label: props['label'] ?? (props['decoration'] is Map ? (props['decoration'] as Map)['labelText']?.toString() : null),
          initial: props['text']?.toString(),
          maxLines: _num(props['maxLines'])?.round(),
          onChanged: (v) => _emit(props['onChange'] ?? props['onChanged'], v, fallback: props),
        );
        break;
      case 'inkwell':
      case 'gesturedetector':
        final onTap = _voidCallback(props['onTap'] ?? props['onPressed'] ?? props['onClick'], fallback: props);
        result = type == 'inkwell' ? InkWell(onTap: onTap, child: child0()) : GestureDetector(onTap: onTap, child: child0());
        break;
      case 'dropdownbutton' || 'dropdownbuttonformfield':
        final dd = BridgeDropdown(
          key: _nodeKey(props),
          initial: props['value']?.toString(),
          items: _rawList(props['items']),
          onChanged: (v) => _emit(props['onChange'] ?? props['onChanged'], v, fallback: props),
        );
        result = type == 'dropdownbuttonformfield'
            ? DropdownButtonFormField<String>(
                initialValue: props['value']?.toString(),
                items: _dropdownItems(props['items']),
                onChanged: (v) => _emit(props['onChange'] ?? props['onChanged'], v, fallback: props),
                decoration: InputDecoration(
                  labelText: _decText(props, 'labelText'),
                  border: const OutlineInputBorder(),
                ),
              )
            : dd;
        break;

      // ---------- Scaffold 体系 ----------
      case 'scaffold':
        result = Scaffold(
          key: scaffoldKey,
          backgroundColor: _color(props['backgroundColor']),
          appBar: _build(props['appBar']) as PreferredSizeWidget?,
          drawer: _build(props['drawer']),
          endDrawer: _build(props['endDrawer']),
          body: _build(props['body']) ?? child0(),
          bottomNavigationBar: _build(props['bottomNavigationBar']),
          floatingActionButton: _build(props['floatingActionButton']),
        );
        break;
      case 'appbar':
      case 'appbarpreferredsize':
        result = AppBar(
          title: _build(props['title']),
          leading: _build(props['leading']),
          actions: _children(props['actions']),
          elevation: _num(props['elevation']),
          backgroundColor: _color(props['backgroundColor'] ?? props['color']),
          foregroundColor: _color(props['foregroundColor']),
          centerTitle: props['centerTitle'] == true,
          automaticallyImplyLeading: props['automaticallyImplyLeading'] != false,
        );
        break;
      case 'drawer':
        result = Drawer(
          backgroundColor: _color(props['backgroundColor']),
          child: child0(),
        );
        break;
      case 'useraccountsdrawerheader':
        result = UserAccountsDrawerHeader(
          decoration: _decoration(props),
          accountName: _build(props['accountName']),
          accountEmail: _build(props['accountEmail']),
          currentAccountPicture: _build(props['currentAccountPicture']),
          otherAccountsPictures: _children(props['otherAccountsPictures']),
        );
        break;
      case 'bottomnavigationbar':
        result = BridgeBottomNav(
          key: _nodeKey(props),
          items: _rawList(props['items']),
          initialIndex: _num(props['currentIndex'])?.round() ?? 0,
          selectedColor: _color(props['selectedItemColor']),
          unselectedColor: _color(props['unselectedItemColor']),
          type: props['type'] == 'shifting' ? BottomNavigationBarType.shifting : BottomNavigationBarType.fixed,
          onTap: (i) => _emit(props['onTap'], i, fallback: props),
        );
        break;
      case 'tab':
        result = const SizedBox.shrink(); // 仅用于 TabBar 内部
        break;
      case 'tabbar':
        result = TabBar(
          tabs: _rawList(props['tabs']).map((t) => Tab(text: (t is Map ? (t['text'] ?? t['label']) : t)?.toString())).toList(),
          indicatorColor: _color(props['indicatorColor']),
          labelColor: _color(props['labelColor']),
          unselectedLabelColor: _color(props['unselectedLabelColor']),
        );
        break;
      case 'tabbarview':
        result = TabBarView(children: children);
        break;
      case 'defaulttabcontroller':
        result = DefaultTabController(
          length: _num(props['length'])?.round() ?? 1,
          child: child0(),
        );
        break;

      // ---------- 原生 ----------
      case 'androidview':
      case 'android':
        result = AndroidView(
          viewType: (props['viewType'] ?? props['view'] ?? 'androlua/native').toString(),
          layoutDirection: TextDirection.ltr,
          creationParams: _creationParams(props),
          creationParamsCodec: const StandardMessageCodec(),
        );
        break;

      default:
        // 未识别类型：容错降级（有子节点当 Column，否则有文本当 Text，再无则忽略）
        if (children.isNotEmpty) {
          result = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
        } else if (props['text'] != null) {
          result = Text(props['text'].toString());
        } else {
          result = const SizedBox.shrink();
        }
    }

    return _wrapCommon(result, props);
  }

  // ============================================================
  // 通用属性 / 结构处理
  // ============================================================

  static Map<String, dynamic> _props(Map raw) {
    final props = <String, dynamic>{};
    raw.forEach((k, v) => props[k.toString()] = v);
    final extra = props['props'];
    if (extra is Map) {
      extra.forEach((k, v) => props[k.toString()] = v);
    }
    return props;
  }

  /// weight / width / height 统一包裹。
  static Widget _wrapCommon(Widget child, Map<String, dynamic> props) {
    final weight = _num(props['weight']);
    Widget out = child;
    if (weight != null) {
      out = Expanded(flex: weight.round(), child: out);
    }
    final w = props['width'];
    final h = props['height'];
    if (w != null || h != null) {
      out = SizedBox(width: _dim(w), height: _dim(h), child: out);
    }
    return out;
  }

  static Key? _nodeKey(Map<String, dynamic> props) {
    final id = props['id'] ?? props['key'];
    return id == null ? null : ValueKey(id.toString());
  }

  static List<Widget> _children(dynamic raw) {
    if (raw is List) {
      return raw.map((e) => _build(e)).whereType<Widget>().toList();
    }
    if (raw is Map) {
      final one = _build(raw);
      return one == null ? [] : [one];
    }
    return [];
  }

  static List<dynamic> _rawList(dynamic raw) {
    if (raw is List) return raw;
    if (raw is Map) return [raw];
    return [];
  }

  /// 若给的是 widget 描述就用它，否则用文字。
  static Widget _widgetOrText(dynamic spec, String fallback) {
    if (spec is Map || spec is List) {
      return _build(spec) ?? Text(fallback);
    }
    return Text(fallback);
  }

  static Widget? _slotText(dynamic v) {
    if (v == null) return null;
    if (v is Map || v is List) return _build(v);
    return Text(v.toString());
  }

  static Widget? _slotIcon(dynamic v) {
    if (v == null) return null;
    if (v is Map || v is List) return _build(v);
    return Icon(_icon(v));
  }

  static dynamic _creationParams(Map<String, dynamic> props) {
    final p = props['params'];
    if (p is Map) return p.cast<String, dynamic>();
    return <String, dynamic>{
      'text': (props['text'] ?? '原生 AndroidView').toString(),
      'background': props['background']?.toString(),
    };
  }

  static String? _decText(Map<String, dynamic> props, String key) {
    final d = props['decoration'];
    if (d is Map && d[key] != null) return d[key].toString();
    return props[key]?.toString();
  }

  // ---------- 回调 ----------

  static VoidCallback? _voidCallback(dynamic onTap, {Map<String, dynamic>? fallback}) {
    if (onTap == null) return null;
    final action = onTap;
    return () {
      if (action is String) {
        final res = FlutterBridge.instance.invoke(action, fallback);
        FlutterBridge.instance.emit('onTap', {'action': action, 'result': res});
      } else if (action is Map) {
        final m = action.cast<String, dynamic>();
        final method = (m['call'] ?? m['method'] ?? '').toString();
        final args = m['args'] is Map ? (m['args'] as Map).cast<String, dynamic>() : null;
        final res = method.isEmpty ? null : FlutterBridge.instance.invoke(method, args);
        final event = (m['event'] ?? m['emit'] ?? 'onTap').toString();
        FlutterBridge.instance.emit(event, {'action': method, 'args': args, 'result': res});
      }
    };
  }

  static void _emit(dynamic spec, dynamic value, {Map<String, dynamic>? fallback}) {
    final name = spec is Map ? (spec['event'] ?? spec['emit'])?.toString() : spec?.toString();
    final method = spec is Map ? (spec['call'] ?? spec['method'])?.toString() : null;
    dynamic res;
    if (method != null && method.isNotEmpty) {
      final a = spec is Map ? spec['args'] : null;
      res = FlutterBridge.instance.invoke(method, a is Map ? a.cast<String, dynamic>() : null);
    }
    FlutterBridge.instance.emit(name ?? 'onChange', {'value': value, 'result': res});
  }

  // ---------- 装饰 ----------

  static BoxDecoration? _decoration(Map<String, dynamic> props) {
    final dRaw = props['decoration'];
    final d = dRaw is Map ? dRaw.cast<String, dynamic>() : <String, dynamic>{};
    final color = _color(d['color'] ?? props['color'] ?? props['backgroundColor']);
    final gradient = _gradient(d['gradient'] ?? props['gradient']);
    final radius = _num(d['borderRadius'] ?? d['radius'] ?? props['radius']);
    final border = _border(d, props);
    final shadows = _shadows(d['boxShadow'] ?? props['boxShadow']);
    if (color == null && gradient == null && radius == null && border == null && shadows == null) {
      return null;
    }
    return BoxDecoration(
      color: color,
      gradient: gradient,
      borderRadius: radius != null ? BorderRadius.circular(radius) : null,
      border: border,
      boxShadow: shadows,
    );
  }

  static Gradient? _gradient(dynamic v) {
    if (v is! Map) return null;
    final m = v.cast<String, dynamic>();
    final colors = (m['colors'] is List)
        ? (m['colors'] as List).map((c) => _color(c)).whereType<Color>().toList()
        : <Color>[];
    if (colors.isEmpty) return null;
    return LinearGradient(
      colors: colors,
      begin: _gradeAlign(m['begin']) ?? Alignment.topLeft,
      end: _gradeAlign(m['end']) ?? Alignment.bottomRight,
    );
  }

  static Alignment? _gradeAlign(dynamic v) {
    switch (v?.toString().toLowerCase()) {
      case 'topleft': return Alignment.topLeft;
      case 'topright': return Alignment.topRight;
      case 'bottomleft': return Alignment.bottomLeft;
      case 'bottomright': return Alignment.bottomRight;
      case 'center': return Alignment.center;
      case 'topcenter': return Alignment.topCenter;
      case 'bottomcenter': return Alignment.bottomCenter;
      default: return null;
    }
  }

  static BoxBorder? _border(Map<String, dynamic> d, Map<String, dynamic> props) {
    BorderSide side(Map m) => BorderSide(
          color: _color(m['color']) ?? Colors.black26,
          width: _num(m['width']) ?? 1,
        );
    final all = d['border'] ?? props['border'];
    if (all is Map) return Border.all(color: _color(all['color']) ?? Colors.black26, width: _num(all['width']) ?? 1);
    final bb = d['borderBottom'] ?? props['borderBottom'];
    final bt = d['borderTop'] ?? props['borderTop'];
    if (bb is Map || bt is Map) {
      return Border(
        top: bt is Map ? side(bt.cast<String, dynamic>()) : BorderSide.none,
        bottom: bb is Map ? side(bb.cast<String, dynamic>()) : BorderSide.none,
      );
    }
    final bw = _num(props['borderWidth']);
    if (bw != null) return Border.all(color: _color(props['borderColor']) ?? Colors.black26, width: bw);
    return null;
  }

  static List<BoxShadow>? _shadows(dynamic v) {
    if (v is! List) return null;
    final out = <BoxShadow>[];
    for (final e in v) {
      if (e is Map) {
        final m = e.cast<String, dynamic>();
        out.add(BoxShadow(
          color: _color(m['color']) ?? const Color(0x33000000),
          blurRadius: _num(m['blurRadius']) ?? 8,
          offset: Offset(_num(m['dx']) ?? 0, _num(m['dy']) ?? 2),
        ));
      }
    }
    return out.isEmpty ? null : out;
  }

  static ButtonStyle? _buttonStyle(Map<String, dynamic> props) {
    final sRaw = props['style'];
    final s = sRaw is Map ? sRaw.cast<String, dynamic>() : <String, dynamic>{};
    final bg = _color(s['backgroundColor'] ?? props['backgroundColor']);
    final fg = _color(s['foregroundColor'] ?? props['foregroundColor']);
    final pad = _insets(s['padding'] ?? props['padding']);
    final el = _num(s['elevation'] ?? props['elevation']);
    final radius = _num(s['radius'] ?? props['radius']);
    if (bg == null && fg == null && pad == null && el == null && radius == null) return null;
    return ButtonStyle(
      backgroundColor: bg != null ? WidgetStatePropertyAll<Color>(bg) : null,
      foregroundColor: fg != null ? WidgetStatePropertyAll<Color>(fg) : null,
      padding: pad != null ? WidgetStatePropertyAll<EdgeInsetsGeometry>(pad) : null,
      elevation: el != null ? WidgetStatePropertyAll<double>(el) : null,
      shape: radius != null
          ? WidgetStatePropertyAll<OutlinedBorder>(RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)))
          : null,
    );
  }

  static List<DropdownMenuItem<String>> _dropdownItems(dynamic raw) {
    return _rawList(raw).map((e) {
      final m = e is Map ? e.cast<String, dynamic>() : <String, dynamic>{};
      final value = (m['value'] ?? m['text'] ?? '').toString();
      return DropdownMenuItem<String>(value: value, child: Text((m['text'] ?? m['value'] ?? '').toString()));
    }).toList();
  }

  static ScrollPhysics? _physics(dynamic v) {
    switch (v?.toString().toLowerCase()) {
      case 'neverscrollable':
      case 'never':
        return const NeverScrollableScrollPhysics();
      case 'bouncing':
        return const BouncingScrollPhysics();
      case 'clamping':
        return const ClampingScrollPhysics();
      default:
        return null;
    }
  }

  // ---------- 基础类型转换 ----------

  static EdgeInsets? _insets(dynamic v) {
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
        left: _num(m['left']) ?? 0, top: _num(m['top']) ?? 0,
        right: _num(m['right']) ?? 0, bottom: _num(m['bottom']) ?? 0,
      );
    }
    return null;
  }

  static double? _dim(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    final s = v.toString().toLowerCase();
    if (s == 'fill' || s == 'match' || s == 'match_parent') return double.infinity;
    return double.tryParse(s);
  }

  static double? _num(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static Axis _axis(dynamic v) => v?.toString().toLowerCase() == 'horizontal' ? Axis.horizontal : Axis.vertical;

  static Color? _color(dynamic v) {
    if (v == null) return null;
    if (v is int) return Color(v);
    if (v is! String) return null;
    final named = {
      'red': Colors.red, 'green': Colors.green, 'blue': Colors.blue, 'black': Colors.black,
      'white': Colors.white, 'grey': Colors.grey, 'gray': Colors.grey, 'orange': Colors.orange,
      'purple': Colors.purple, 'teal': Colors.teal, 'transparent': Colors.transparent,
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

  static TextStyle _textStyle(Map<String, dynamic> props) {
    final weight = props['fontWeight'];
    FontWeight? fw;
    if (weight is num) {
      fw = FontWeight.values[(weight ~/ 100 - 1).clamp(0, 8)];
    } else if (weight is String) {
      switch (weight.toLowerCase()) {
        case 'bold': fw = FontWeight.bold; break;
        case 'normal': fw = FontWeight.normal; break;
        default:
          final n = int.tryParse(weight.replaceAll(RegExp(r'\D'), ''));
          if (n != null) fw = FontWeight.values[(n ~/ 100 - 1).clamp(0, 8)];
      }
    } else if (weight == true) {
      fw = FontWeight.bold;
    }
    return TextStyle(
      fontSize: _num(props['fontSize']),
      color: _color(props['color'] ?? props['textColor']),
      fontWeight: fw,
      height: _num(props['lineHeight']),
    );
  }

  static MainAxisAlignment _mainAxis(dynamic v) {
    switch (v?.toString().toLowerCase()) {
      case 'center': return MainAxisAlignment.center;
      case 'end': return MainAxisAlignment.end;
      case 'spacebetween': case 'space_between': return MainAxisAlignment.spaceBetween;
      case 'spacearound': return MainAxisAlignment.spaceAround;
      case 'spaceevenly': return MainAxisAlignment.spaceEvenly;
      default: return MainAxisAlignment.start;
    }
  }

  static CrossAxisAlignment _crossAxis(dynamic v) {
    switch (v?.toString().toLowerCase()) {
      case 'center': return CrossAxisAlignment.center;
      case 'end': return CrossAxisAlignment.end;
      case 'stretch': return CrossAxisAlignment.stretch;
      case 'baseline': return CrossAxisAlignment.baseline;
      default: return CrossAxisAlignment.start;
    }
  }

  static MainAxisSize _size(dynamic v) =>
      v?.toString().toLowerCase() == 'min' ? MainAxisSize.min : MainAxisSize.max;

  static TextAlign _textAlign(dynamic v) {
    switch (v?.toString().toLowerCase()) {
      case 'center': return TextAlign.center;
      case 'right': case 'end': return TextAlign.right;
      case 'justify': return TextAlign.justify;
      default: return TextAlign.left;
    }
  }

  static Alignment? _alignment(dynamic v) {
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

  static WrapAlignment _wrapAlignment(dynamic v) {
    switch (v?.toString().toLowerCase()) {
      case 'center': return WrapAlignment.center;
      case 'end': case 'right': return WrapAlignment.end;
      case 'spacebetween': return WrapAlignment.spaceBetween;
      case 'spacearound': return WrapAlignment.spaceAround;
      default: return WrapAlignment.start;
    }
  }

  static const Map<String, IconData> _icons = {
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
    'pause': Icons.pause, 'skip_next': Icons.skip_next, 'volume_up': Icons.volume_up,
    'cloud': Icons.cloud, 'folder': Icons.folder, 'attach_file': Icons.attach_file,
    'visibility': Icons.visibility, 'thumb_up': Icons.thumb_up, 'chat': Icons.chat,
    'bookmark': Icons.bookmark, 'error': Icons.error, 'help': Icons.help,
  };

  static IconData _icon(dynamic name) {
    final key = name?.toString().toLowerCase();
    if (key == null) return Icons.widgets;
    return _icons[key] ?? Icons.widgets;
  }
}

// ============================================================
// 有状态交互控件（点击/拖动即时生效并带动效；整树重绘时保留状态）
// ============================================================

class BridgeSwitch extends StatefulWidget {
  const BridgeSwitch({super.key, required this.initial, required this.onChanged});
  final bool initial;
  final ValueChanged<bool> onChanged;
  @override
  State<BridgeSwitch> createState() => _BridgeSwitchState();
}

class _BridgeSwitchState extends State<BridgeSwitch> {
  late bool _value = widget.initial;
  @override
  Widget build(BuildContext context) => Switch(
        value: _value,
        onChanged: (v) { setState(() => _value = v); widget.onChanged(v); },
      );
}

class BridgeCheckbox extends StatefulWidget {
  const BridgeCheckbox({super.key, required this.initial, this.color, required this.onChanged});
  final bool initial;
  final Color? color;
  final ValueChanged<bool> onChanged;
  @override
  State<BridgeCheckbox> createState() => _BridgeCheckboxState();
}

class _BridgeCheckboxState extends State<BridgeCheckbox> {
  late bool _value = widget.initial;
  @override
  Widget build(BuildContext context) => Checkbox(
        value: _value,
        activeColor: widget.color,
        onChanged: (v) { setState(() => _value = v == true); widget.onChanged(v == true); },
      );
}

class BridgeSlider extends StatefulWidget {
  const BridgeSlider({super.key, required this.initial, required this.min, required this.max, required this.onChanged});
  final double initial;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  @override
  State<BridgeSlider> createState() => _BridgeSliderState();
}

class _BridgeSliderState extends State<BridgeSlider> {
  late double _value = widget.initial;
  @override
  Widget build(BuildContext context) => Slider(
        value: _value.clamp(widget.min, widget.max),
        min: widget.min,
        max: widget.max,
        onChanged: (v) { setState(() => _value = v); widget.onChanged(v); },
      );
}

class BridgeTextField extends StatefulWidget {
  const BridgeTextField({super.key, this.hint, this.label, this.initial, this.maxLines, required this.onChanged});
  final String? hint;
  final String? label;
  final String? initial;
  final int? maxLines;
  final ValueChanged<String> onChanged;
  @override
  State<BridgeTextField> createState() => _BridgeTextFieldState();
}

class _BridgeTextFieldState extends State<BridgeTextField> {
  late final TextEditingController _controller = TextEditingController(text: widget.initial ?? '');
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => TextField(
        controller: _controller,
        maxLines: widget.maxLines,
        decoration: InputDecoration(hintText: widget.hint, labelText: widget.label),
        onChanged: widget.onChanged,
      );
}

/// 底部导航栏（有状态：点击切换选中项）。
class BridgeBottomNav extends StatefulWidget {
  const BridgeBottomNav({
    super.key,
    required this.items,
    this.initialIndex = 0,
    this.selectedColor,
    this.unselectedColor,
    this.type = BottomNavigationBarType.fixed,
    this.onTap,
  });
  final List<dynamic> items;
  final int initialIndex;
  final Color? selectedColor;
  final Color? unselectedColor;
  final BottomNavigationBarType type;
  final ValueChanged<int>? onTap;
  @override
  State<BridgeBottomNav> createState() => _BridgeBottomNavState();
}

class _BridgeBottomNavState extends State<BridgeBottomNav> {
  late int _index = widget.initialIndex;

  List<BottomNavigationBarItem> _items() {
    return widget.items.map((e) {
      final m = e is Map ? e.cast<String, dynamic>() : <String, dynamic>{};
      return BottomNavigationBarItem(
        icon: Icon(Renderer._icon(m['icon'])),
        label: (m['label'] ?? m['text'])?.toString(),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: _index.clamp(0, widget.items.isEmpty ? 0 : widget.items.length - 1),
      type: widget.type,
      selectedItemColor: widget.selectedColor,
      unselectedItemColor: widget.unselectedColor,
      onTap: (i) {
        setState(() => _index = i);
        widget.onTap?.call(i);
      },
      items: _items(),
    );
  }
}

/// 下拉选择（有状态：选择后更新并回调）。
class BridgeDropdown extends StatefulWidget {
  const BridgeDropdown({super.key, this.initial, required this.items, required this.onChanged});
  final String? initial;
  final List<dynamic> items;
  final ValueChanged<String?> onChanged;
  @override
  State<BridgeDropdown> createState() => _BridgeDropdownState();
}

class _BridgeDropdownState extends State<BridgeDropdown> {
  late String? _value = widget.initial;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<String>(
      value: _value,
      items: Renderer._dropdownItems(widget.items),
      onChanged: (v) { setState(() => _value = v); widget.onChanged(v); },
    );
  }
}
