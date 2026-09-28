import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'bridge.dart';

/// 把 Lua 传来的 widget 描述（JSON/UISpec）转成 Flutter widget 树。
///
/// 描述形如：`{"type":"Column","gap":8,"children":[{"type":"Text","text":"hi"}]}`
/// 属性既可以直接写在节点上，也可以放在 `props` 子对象里。
class Renderer {
  static Widget build(dynamic spec) {
    if (spec is String) {
      // 支持 widget 描述是 JSON 字符串（Lua 侧 json.encode 后传入）。
      return _build(_decode(spec)) ?? const SizedBox.shrink();
    }
    return _build(spec) ?? const SizedBox.shrink();
  }

  static dynamic _decode(String s) {
    try {
      return jsonDecode(s);
    } catch (_) {
      return s;
    }
  }

  static Widget? _build(dynamic spec) {
    if (spec == null) return null;
    if (spec is String) return Text(spec);
    if (spec is num || spec is bool) return Text('$spec');
    if (spec is! Map) return const SizedBox.shrink();

    final node = spec.cast<dynamic, dynamic>();
    final props = <String, dynamic>{};
    node.forEach((k, v) => props[k.toString()] = v);
    final extra = props['props'];
    if (extra is Map) {
      extra.forEach((k, v) => props[k.toString()] = v);
    }

    final type = (props['type'] ?? props['t'] ?? '').toString().toLowerCase();
    final children = _children(props['children']);

    Widget child0() => children.isNotEmpty ? children.first : const SizedBox.shrink();

    Widget result;
    switch (type) {
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
        result = Stack(children: children);
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
      case 'sizedbox' || 'spacer':
        result = SizedBox(width: _dim(props['width']), height: _dim(props['height']));
        break;
      case 'text':
        result = Text(
          (props['text'] ?? props['value'] ?? '').toString(),
          textAlign: _textAlign(props['textAlign']),
          style: _textStyle(props),
          maxLines: _num(props['maxLines'])?.round(),
          overflow: _num(props['maxLines']) != null ? TextOverflow.ellipsis : null,
        );
        break;
      case 'button' || 'elevatedbutton' || 'textbutton' || 'filledbutton':
        final label = (props['text'] ?? props['label'] ?? 'Button').toString();
        final onTap = _voidCallback(props['onTap'], fallback: props);
        result = Padding(
          padding: _insets(props['padding']) ?? EdgeInsets.zero,
          child: type == 'textbutton'
              ? TextButton(onPressed: onTap, child: Text(label))
              : type == 'filledbutton'
                  ? FilledButton(onPressed: onTap, child: Text(label))
                  : ElevatedButton(onPressed: onTap, child: Text(label)),
        );
        break;
      case 'icon':
        result = Icon(_icon(props['icon'] ?? props['name']), color: _color(props['color']), size: _num(props['size']));
        break;
      case 'image':
        final url = props['url'] ?? props['src'];
        result = url != null
            ? Image.network(url.toString(), width: _dim(props['width']), height: _dim(props['height']), fit: BoxFit.cover)
            : const SizedBox.shrink();
        break;
      case 'card':
        result = Card(
          elevation: _num(props['elevation']) ?? 1,
          color: _color(props['color']),
          child: Padding(padding: _insets(props['padding']) ?? const EdgeInsets.all(12), child: child0()),
        );
        break;
      case 'listview' || 'list':
        result = ListView(
          shrinkWrap: props['shrinkWrap'] == true,
          padding: _insets(props['padding']),
          children: children,
        );
        break;
      case 'textfield' || 'edittext':
        result = TextField(
          decoration: InputDecoration(
            hintText: props['hint']?.toString(),
            labelText: props['label']?.toString(),
          ),
          onChanged: (v) => _emit(props['onChange'] ?? props['onChanged'], v, fallback: props),
        );
        break;
      case 'switch':
        result = Switch(
          value: props['value'] == true,
          onChanged: (v) => _emit(props['onChange'] ?? props['onChanged'], v, fallback: props),
        );
        break;
      case 'divider':
        result = const Divider();
        break;
      case 'androidview':
      case 'android':
        // Flutter 里再嵌 Android 原生控件：走 PlatformView。
        result = AndroidView(
          viewType: (props['viewType'] ?? props['view'] ?? 'androlua/native').toString(),
          layoutDirection: TextDirection.ltr,
          creationParams: _creationParams(props),
          creationParamsCodec: const StandardMessageCodec(),
        );
        break;
      default:
        // 未识别的类型：如果有子节点就当成 Column，否则当文本。
        result = children.isNotEmpty
            ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children)
            : Text((props['text'] ?? type).toString());
    }

    return _wrapCommon(result, props);
  }

  /// 统一处理 weight / width / height 等布局包裹。
  static Widget _wrapCommon(Widget child, Map<String, dynamic> props) {
    final weight = _num(props['weight']);
    Widget out = child;
    if (weight != null) {
      out = Expanded(flex: weight.round(), child: out);
    }
    final w = props['width'];
    final h = props['height'];
    if (w != null || h != null) {
      out = SizedBox(
        width: _dim(w),
        height: _dim(h),
        child: out,
      );
    }
    return out;
  }

  static List<Widget> _children(dynamic raw) {
    if (raw is List) {
      return raw.map((e) => _build(e)).whereType<Widget>().toList();
    }
    if (raw is Map) {
      // 单子节点写成对象的情况。
      final one = _build(raw);
      return one == null ? [] : [one];
    }
    return [];
  }

  static dynamic _creationParams(Map<String, dynamic> props) {
    final p = props['params'];
    if (p is Map) return p.cast<String, dynamic>();
    return <String, dynamic>{
      'text': props['text']?.toString() ?? '原生 AndroidView',
      'background': props['background']?.toString(),
    };
  }

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
        FlutterBridge.instance.emit('onTap', {'action': method, 'args': args, 'result': res});
      }
    };
  }

  static void _emit(dynamic spec, dynamic value, {Map<String, dynamic>? fallback}) {
    final name = spec is Map ? (spec['event'] ?? spec['emit'])?.toString() : spec?.toString();
    final method = spec is Map ? (spec['call'] ?? spec['method'])?.toString() : null;
    dynamic res;
    if (method != null && method.isNotEmpty) {
      res = FlutterBridge.instance.invoke(
        method,
        spec is Map && spec['args'] is Map ? (spec['args'] as Map).cast<String, dynamic>() : null,
      );
    }
    FlutterBridge.instance.emit(
      name ?? 'onChange',
      {'value': value, 'result': res},
    );
  }

  static BoxDecoration? _decoration(Map<String, dynamic> props) {
    final color = _color(props['color'] ?? props['backgroundColor']);
    final radius = _num(props['radius'] ?? props['borderRadius']);
    final border = _num(props['borderWidth']) != null
        ? Border.all(color: _color(props['borderColor']) ?? Colors.black26, width: _num(props['borderWidth'])!)
        : null;
    if (color == null && radius == null && border == null) return null;
    return BoxDecoration(
      color: color,
      borderRadius: radius != null ? BorderRadius.circular(radius) : null,
      border: border,
    );
  }

  static TextStyle _textStyle(Map<String, dynamic> props) {
    final weight = props['fontWeight'];
    FontWeight? fw;
    if (weight is num) {
      fw = FontWeight.values[(weight ~/ 100 - 1).clamp(0, 8)];
    } else if (weight is String) {
      switch (weight.toLowerCase()) {
        case 'bold':
          fw = FontWeight.bold;
          break;
        case 'normal':
          fw = FontWeight.normal;
          break;
        default:
          final n = int.tryParse(weight.replaceAll(RegExp(r'\D'), ''));
          if (n != null) fw = FontWeight.values[(n ~/ 100 - 1).clamp(0, 8)];
      }
    }
    return TextStyle(
      fontSize: _num(props['fontSize']),
      color: _color(props['color'] ?? props['textColor']),
      fontWeight: fw,
    );
  }

  static Color? _color(dynamic v) {
    if (v == null) return null;
    if (v is int) return Color(v);
    if (v is! String) return null;
    final named = {
      'red': Colors.red,
      'green': Colors.green,
      'blue': Colors.blue,
      'black': Colors.black,
      'white': Colors.white,
      'grey': Colors.grey,
      'orange': Colors.orange,
      'purple': Colors.purple,
      'teal': Colors.teal,
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
        left: _num(m['left']) ?? 0,
        top: _num(m['top']) ?? 0,
        right: _num(m['right']) ?? 0,
        bottom: _num(m['bottom']) ?? 0,
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

  static MainAxisAlignment _mainAxis(dynamic v) {
    switch (v?.toString().toLowerCase()) {
      case 'center':
        return MainAxisAlignment.center;
      case 'end':
        return MainAxisAlignment.end;
      case 'spacebetween':
      case 'space_between':
      case 'space-around':
      case 'spaceevenly':
        return MainAxisAlignment.spaceBetween;
      default:
        return MainAxisAlignment.start;
    }
  }

  static CrossAxisAlignment _crossAxis(dynamic v) {
    switch (v?.toString().toLowerCase()) {
      case 'center':
        return CrossAxisAlignment.center;
      case 'end':
        return CrossAxisAlignment.end;
      case 'stretch':
        return CrossAxisAlignment.stretch;
      default:
        return CrossAxisAlignment.start;
    }
  }

  static MainAxisSize _size(dynamic v) =>
      v?.toString().toLowerCase() == 'min' ? MainAxisSize.min : MainAxisSize.max;

  static TextAlign _textAlign(dynamic v) {
    switch (v?.toString().toLowerCase()) {
      case 'center':
        return TextAlign.center;
      case 'right':
      case 'end':
        return TextAlign.right;
      default:
        return TextAlign.left;
    }
  }

  static Alignment? _alignment(dynamic v) {
    if (v == null) return null;
    switch (v.toString().toLowerCase()) {
      case 'center':
        return Alignment.center;
      case 'topleft':
        return Alignment.topLeft;
      case 'topright':
        return Alignment.topRight;
      case 'bottomleft':
        return Alignment.bottomLeft;
      case 'bottomright':
        return Alignment.bottomRight;
      default:
        return null;
    }
  }

  static IconData _icon(dynamic name) {
    const icons = <String, IconData>{
      'home': Icons.home,
      'add': Icons.add,
      'delete': Icons.delete,
      'star': Icons.star,
      'favorite': Icons.favorite,
      'settings': Icons.settings,
      'search': Icons.search,
      'check': Icons.check,
      'close': Icons.close,
      'arrow_forward': Icons.arrow_forward,
      'person': Icons.person,
    };
    return icons[name?.toString().toLowerCase()] ?? Icons.widgets;
  }
}
