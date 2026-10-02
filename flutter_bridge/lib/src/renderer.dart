import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:just_audio/just_audio.dart';
import 'package:latlong2/latlong.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:video_player/video_player.dart';

import 'bridge.dart';
import 'props.dart';

/// 把 Lua 传来的 widget 描述（JSON/UISpec）转成 Flutter widget 树。
///
/// 设计目标：**尽量自适应**。
///  * 统一属性处理器 [Props]：归一 + 别名 + 类型转换；
///  * 注册表驱动：内置 Material/常用控件；未知控件优雅降级；`Renderer.register` 可扩展；
///  * 容错：单个节点构建失败只影响该节点，不会整屏白；
///  * 列表用 `ListView.builder`：支持模板式懒加载（`itemTemplate` + `$index`）。
///
/// 说明：Flutter release(AOT) 无反射（dart:mirrors 不支持 AOT），无法凭字符串创建
/// 任意 Flutter 控件；能覆盖的是「注册过的控件名」。
class Renderer {
  /// 兜底用的 Scaffold key（便于 Lua 通过 Dart 方法打开抽屉）。
  static final GlobalKey<ScaffoldState> scaffoldKey = GlobalKey<ScaffoldState>();

  /// 自定义控件扩展点：名字 -> 构建函数。
  /// 新签名：[Widget Function(Props p, List<Widget> children)]（能拿到归一化属性与子节点）；
  /// 旧签名 [Widget Function(Map<String, dynamic> props)] 仍然兼容。
  static final Map<String, Function> custom = {};

  static void register(String type, Function builder) {
    custom[type.toLowerCase()] = builder;
    // 让 Props 的「AndroLua 表风格」兜底判定也认识这个控件名
    Props.registerType(type);
  }

  static Widget build(dynamic spec) {
    if (spec is String) {
      try {
        final decoded = jsonDecode(spec);
        // 整页重渲染：告知当前布局里还有哪些 id，不在里面的控制器才能回收
        FlutterControl.markAlive(_collectIds(decoded));
        return _build(decoded, '0') ?? const SizedBox.shrink();
      } catch (_) {
        return Text(spec);
      }
    }
    FlutterControl.markAlive(_collectIds(spec));
    return _build(spec, '0') ?? const SizedBox.shrink();
  }

  // ============================================================
  // 节点构建
  // ============================================================

  /// 嵌套深度上限。
  ///
  /// 深度从 path 推导（path 每往下钻一层就多一段），**不用静态计数器**：
  /// 主树构建与 `_IdNode` 的定点重建可能在同一次构建中交错发生，
  /// 共享计数器会互相污染、误报“嵌套过深”。从 path 推导天然可重入。
  static const int _maxDepth = 200;

  static int _depthOf(String path) {
    var n = 0;
    for (var i = 0; i < path.length; i++) {
      if (path.codeUnitAt(i) == 0x2f) n++; // '/'
    }
    return n;
  }

  static Widget _tooDeep() => const Padding(
        padding: EdgeInsets.all(4),
        child: Text('⚠ 节点嵌套过深（可能存在环）', style: TextStyle(color: Colors.red, fontSize: 11)),
      );

  /// 收集 spec 里所有节点的 id（供控制器回收判断「这个 id 还在不在当前布局里」）。
  static Set<String> _collectIds(dynamic node, [Set<String>? out]) {
    final ids = out ?? <String>{};
    if (node is Map) {
      final id = node['id'];
      if (id != null && id.toString().isNotEmpty) ids.add(id.toString());
      for (final v in node.values) {
        if (v is Map || v is List) _collectIds(v, ids);
      }
    } else if (node is List) {
      for (final v in node) {
        if (v is Map || v is List) _collectIds(v, ids);
      }
    }
    return ids;
  }

  static Widget? _build(dynamic spec, String path) {
    if (_depthOf(path) >= _maxDepth) return _tooDeep();
    try {
      return _buildInner(spec, path);
    } catch (e) {
      return Padding(
        padding: const EdgeInsets.all(4),
        child: Text('⚠ 节点渲染失败: $e', style: const TextStyle(color: Colors.red, fontSize: 11)),
      );
    }
  }

  static Widget? _buildInner(dynamic spec, String path) {
    if (spec == null) return null;
    if (spec is String) return Text(spec);
    if (spec is num || spec is bool) return Text('$spec');
    if (spec is List) {
      if (spec.isEmpty) return null;
      return _buildInner(<String, dynamic>{'type': Props.typeName(spec.first), 'children': spec.sublist(1)}, path);
    }
    if (spec is! Map) return const SizedBox.shrink();

    final p = Props.of(spec);
    // 带 id 的节点包一层可按 id 定点更新的壳（命令式 h.Text=值 / patch 局部重建）。
    final id = p['id'];
    if (id != null && id.toString().isNotEmpty) {
      return _IdNode(key: ValueKey('idnode:$id'), id: id.toString(), spec: spec, path: path);
    }
    return _buildNode(p, path, _children(p['children'] ?? p['child'], path));
  }

  /// 构建单个节点（不含 id 包裹）。_IdNode 定点重建时也走这里，避免重复包裹。
  static Widget? _buildNodeFor(dynamic spec, String path) {
    // 与 _build 同样做深度检查：_IdNode 的定点重建也不能绕过，
    // 否则带环的 patch/notifier 更新仍会栈溢出。
    if (_depthOf(path) >= _maxDepth) return _tooDeep();
    // spec 可能是 JSON 字符串（如原生 patch 下发），先解码再构建。
    if (spec is String) {
      try {
        spec = jsonDecode(spec);
      } catch (_) {}
    }
    if (spec is! Map) return _buildInner(spec, path);
    final p = Props.of(spec);
    try {
      return _buildNode(p, path, _children(p['children'] ?? p['child'], path));
    } catch (e) {
      return Padding(
        padding: const EdgeInsets.all(4),
        child: Text('⚠ 节点渲染失败: $e', style: const TextStyle(color: Colors.red, fontSize: 11)),
      );
    }
  }

  static Widget? _buildNode(Props p, String path, List<Widget> children) {
    Widget child0() => children.isNotEmpty ? children.first : const SizedBox.shrink();

    final ext = custom[p.type];
    if (ext != null) {
      Widget? w;
      if (ext is Widget Function(Props, List<Widget>)) {
        w = ext(p, children);
      } else if (ext is Widget Function(Map<String, dynamic>)) {
        w = ext(p.map);
      } else {
        // 兜底：返回可空的函数（如 Widget? Function(Props, List<Widget>)）或类型推断不明确的闭包，
        // `is` 判断都不命中，这里用 Function.apply 动态调用。
        try {
          w = Function.apply(ext, [p, children]) as Widget?;
        } catch (e) {
          if (kDebugMode) debugPrint('Renderer: 自定义控件 $p.type 调用失败(新签名): $e');
          try {
            w = Function.apply(ext, [p.map]) as Widget?;
          } catch (e2) {
            if (kDebugMode) debugPrint('Renderer: 自定义控件 $p.type 调用失败(旧签名): $e2');
          }
        }
      }
      if (w != null) return _wrapCommon(w, p);
    }

    Widget result;
    switch (p.type) {
      // ---------- 布局 ----------
      case 'column':
        result = Column(
          mainAxisAlignment: Props.toMainAxis(p['mainAxisAlignment'] ?? p['gravity']),
          crossAxisAlignment: Props.toCrossAxis(p['crossAxisAlignment']),
          mainAxisSize: Props.toMainAxisSize(p['mainAxisSize']),
          textDirection: p.has('textDirection') ? Props.toTextDirection(p['textDirection']) : null,
          verticalDirection: p.has('verticalDirection') ? Props.toVerticalDirection(p['verticalDirection']) : VerticalDirection.down,
          textBaseline: p.has('textBaseline') ? TextBaseline.alphabetic : null,
          spacing: p.n('spacing') ?? p.nz('gap'),
          children: children,
        );
        break;
      case 'row':
        result = Row(
          mainAxisAlignment: Props.toMainAxis(p['mainAxisAlignment'] ?? p['gravity']),
          crossAxisAlignment: Props.toCrossAxis(p['crossAxisAlignment']),
          mainAxisSize: Props.toMainAxisSize(p['mainAxisSize']),
          textDirection: p.has('textDirection') ? Props.toTextDirection(p['textDirection']) : null,
          verticalDirection: p.has('verticalDirection') ? Props.toVerticalDirection(p['verticalDirection']) : VerticalDirection.down,
          textBaseline: p.has('textBaseline') ? TextBaseline.alphabetic : null,
          spacing: p.n('spacing') ?? p.nz('gap'),
          children: children,
        );
        break;
      case 'stack':
        result = Stack(
          alignment: p.align('alignment') ?? AlignmentDirectional.topStart,
          fit: p.has('fit') ? Props.toStackFit(p['fit']) : StackFit.loose,
          clipBehavior: p.has('clipBehavior') ? Props.toClip(p['clipBehavior']) : (p.b('clip') ? Clip.antiAlias : Clip.hardEdge),
          children: children,
        );
        break;
      case 'container':
        result = Container(
          width: Props.dim(p['width']),
          height: Props.dim(p['height']),
          alignment: p.align('alignment'),
          padding: p.inset('padding'),
          margin: p.inset('margin'),
          color: p.has('decoration') ? null : p.color('color'),
          decoration: _decoration(p),
          foregroundDecoration: p['foregroundDecoration'] != null ? _decoration(Props.of(p['foregroundDecoration'])) : null,
          constraints: (p.has('minWidth') || p.has('maxWidth') || p.has('minHeight') || p.has('maxHeight')) ? _constraints(p) : null,
          transform: _matrix4(p['transform']),
          transformAlignment: p.align('transformAlignment'),
          clipBehavior: p.b('clip') ? Clip.antiAlias : Clip.none,
          child: child0(),
        );
        break;
      case 'padding':
        result = Padding(padding: p.inset('padding') ?? EdgeInsets.zero, child: child0());
        break;
      case 'center':
        result = Center(child: child0());
        break;
      case 'expanded':
        result = Expanded(flex: p.i('flex') ?? p.i('weight') ?? 1, child: child0());
        break;
      case 'sizedbox':
        result = SizedBox(
          width: Props.dim(p['width']),
          height: Props.dim(p['height']),
          child: children.isEmpty ? null : child0(),
        );
        break;
      case 'spacer':
        result = Spacer(flex: p.i('flex') ?? p.i('weight') ?? 1);
        break;
      case 'wrap':
        result = Wrap(
          spacing: p.nz('gap'),
          runSpacing: p.nz('runSpacing'),
          alignment: Props.toWrapAlignment(p['alignment']),
          children: children,
        );
        break;
      case 'align':
        result = Align(alignment: p.align('alignment') ?? Alignment.center, child: child0());
        break;
      case 'aspectratio':
        result = AspectRatio(aspectRatio: p.n('aspectRatio') ?? p.n('ratio') ?? 1.0, child: child0());
        break;
      case 'cliprrect':
        result = ClipRRect(
          borderRadius: BorderRadius.circular(p.n('radius') ?? 8),
          child: child0(),
        );
        break;
      case 'opacity':
        result = Opacity(opacity: (p.n('opacity') ?? 1.0).clamp(0.0, 1.0), child: child0());
        break;
      case 'safearea':
        result = SafeArea(child: child0());
        break;
      case 'positioned':
        result = Positioned(
          left: Props.dim(p['left']),
          top: Props.dim(p['top']),
          right: Props.dim(p['right']),
          bottom: Props.dim(p['bottom']),
          width: Props.dim(p['width']),
          height: Props.dim(p['height']),
          child: child0(),
        );
        break;
      case 'fractionallysizedbox':
        result = FractionallySizedBox(
          widthFactor: p.n('widthFactor'),
          heightFactor: p.n('heightFactor'),
          alignment: p.align('alignment') ?? Alignment.centerLeft,
          child: child0(),
        );
        break;
      case 'singlechildscrollview':
        result = SingleChildScrollView(
          controller: p['id'] != null ? FlutterControl.scroll(p['id'].toString()) : null,
          scrollDirection: p.axis('scrollDirection'),
          physics: Props.toPhysics(p['physics']),
          padding: p.inset('padding'),
          child: child0(),
        );
        break;
      case 'transform':
        final t = p['translate'];
        final off = t is List && t.length >= 2
            ? Offset(Props.toNum(t[0]) ?? 0, Props.toNum(t[1]) ?? 0)
            : Offset.zero;
        result = Transform.translate(offset: off, child: child0());
        break;

      // ---------- 文本 / 图片 / 图标 ----------
      case 'text':
        result = Text(
          (p['text'] ?? p['value'] ?? p['data'] ?? '').toString(),
          style: Props.toTextStyle(p),
          textAlign: p.has('textAlign') ? Props.toTextAlign(p['textAlign']) : null,
          textDirection: p.has('textDirection') ? Props.toTextDirection(p['textDirection']) : null,
          softWrap: p.has('softWrap') ? p.b('softWrap', true) : null,
          overflow: Props.toOverflow(p['overflow']) ?? (p.i('maxLines') != null ? TextOverflow.ellipsis : null),
          textScaler: p.n('textScaleFactor') != null || p.n('textScaler') != null
              ? TextScaler.linear(p.n('textScaleFactor') ?? p.n('textScaler')!)
              : null,
          maxLines: p.i('maxLines'),
          semanticsLabel: p.s('semanticsLabel'),
          locale: p.has('locale') ? Props.toLocale(p['locale']) : null,
          textWidthBasis: p.has('textWidthBasis') ? Props.toTextWidthBasis(p['textWidthBasis']) : null,
          selectionColor: p.color('selectionColor'),
        );
        break;
      case 'selectabletext':
        result = SelectableText(
          (p['text'] ?? p['value'] ?? '').toString(),
          style: Props.toTextStyle(p),
          textAlign: p.has('textAlign') ? Props.toTextAlign(p['textAlign']) : null,
          maxLines: p.i('maxLines'),
          autofocus: p.b('autofocus'),
          showCursor: p.b('showCursor', true),
          cursorColor: p.color('cursorColor'),
          selectionColor: p.color('selectionColor'),
          textDirection: p.has('textDirection') ? Props.toTextDirection(p['textDirection']) : null,
        );
        break;
      case 'icon':
        result = Icon(
          Props.toIcon(p['icon'] ?? p['name']),
          color: p.color('color'),
          size: p.n('size') ?? p.n('iconSize'),
          fill: p.n('fill'),
          weight: p.n('weight'),
          grade: p.n('grade'),
          opticalSize: p.n('opticalSize'),
          semanticLabel: p.s('semanticsLabel'),
          textDirection: p.has('textDirection') ? Props.toTextDirection(p['textDirection']) : null,
          shadows: Props.toShadows(p['shadows']),
        );
        break;
      case 'image':
        result = _imageWidget(p);
        break;

      // ---------- 按钮 ----------
      case 'elevatedbutton' || 'textbutton' || 'filledbutton' || 'outlinedbutton':
        final label = (p['text'] ?? p['label'] ?? 'Button').toString();
        Widget child = _widgetOrText(p['child'], label, '$path/child');
        if (p['icon'] != null) {
          child = Row(
            mainAxisSize: MainAxisSize.min,
            children: [Icon(Props.toIcon(p['icon'])), SizedBox(width: p.nz('iconGap', 8)), child],
          );
        }
        final onTap = p.b('enabled', true) ? _tapHandler(p) : null;
        final style = _buttonStyle(p);
        Widget btn = p.type == 'textbutton'
            ? TextButton(onPressed: onTap, style: style, child: child)
            : p.type == 'outlinedbutton'
                ? OutlinedButton(onPressed: onTap, style: style, child: child)
                : p.type == 'filledbutton'
                    ? FilledButton(onPressed: onTap, style: style, child: child)
                    : ElevatedButton(onPressed: onTap, style: style, child: child);
        if (p['tooltip'] != null) btn = Tooltip(message: p['tooltip'].toString(), child: btn);
        result = Padding(padding: p.inset('padding') ?? EdgeInsets.zero, child: btn);
        break;
      case 'iconbutton':
        result = IconButton(
          icon: children.isNotEmpty
              ? child0()
              : Icon(Props.toIcon(p['icon'] ?? p['name']), color: p.color('iconColor')),
          iconSize: p.n('iconSize') ?? p.n('size'),
          color: p.color('color'),
          disabledColor: p.color('disabledColor'),
          tooltip: p.s('tooltip'),
          splashRadius: p.n('splashRadius'),
          padding: p.inset('padding'),
          alignment: p.align('alignment') ?? Alignment.center,
          autofocus: p.b('autofocus'),
          enableFeedback: p.b('enableFeedback', true),
          onPressed: p.b('enabled', true) ? _tapHandler(p) : null,
        );
        break;
      case 'floatingactionbutton':
        result = FloatingActionButton(
          onPressed: p.b('enabled', true) ? _tapHandler(p) : null,
          backgroundColor: p.color('color') ?? p.color('backgroundColor'),
          foregroundColor: p.color('foregroundColor'),
          elevation: p.n('elevation'),
          highlightElevation: p.n('highlightElevation'),
          focusColor: p.color('focusColor'),
          hoverColor: p.color('hoverColor'),
          splashColor: p.color('splashColor'),
          mini: p.b('mini'),
          tooltip: p.s('tooltip'),
          heroTag: p['heroTag']?.toString(),
          shape: Props.toShape(p.s('shape'), p.n('radius')),
          child: children.isNotEmpty ? child0() : Icon(Props.toIcon(p['icon'] ?? p['name'])),
        );
        break;

      // ---------- 容器类 ----------
      case 'card':
        result = Card(
          elevation: p.n('elevation') ?? 1,
          color: p.color('color') ?? p.color('backgroundColor') ?? _decoration(p)?.color,
          shadowColor: p.color('shadowColor'),
          surfaceTintColor: p.color('surfaceTintColor'),
          margin: p.inset('margin') ?? const EdgeInsets.all(4),
          borderOnForeground: p.b('borderOnForeground', true),
          clipBehavior: p.has('clipBehavior') ? Props.toClip(p['clipBehavior']) : Clip.none,
          shape: Props.toShape(p.s('shape'), p.n('radius') ?? p.n('borderRadius')),
          child: Padding(
            padding: p.inset('padding') ?? const EdgeInsets.all(12),
            child: child0(),
          ),
        );
        break;
      case 'circleavatar':
        result = CircleAvatar(
          radius: p.n('radius') ?? p.n('size'),
          backgroundColor: p.color('color') ?? p.color('backgroundColor'),
          child: children.isEmpty ? null : child0(),
        );
        break;
      case 'chip':
        result = Chip(
          avatar: p['avatar'] != null ? Icon(Props.toIcon(p['avatar'])) : null,
          label: Text((p['text'] ?? p['label'] ?? '').toString()),
          labelStyle: Props.toTextStyle(p),
          labelPadding: p.inset('labelPadding'),
          backgroundColor: p.color('backgroundColor') ?? p.color('color'),
          padding: p.inset('padding'),
          side: _borderSide(p['side']),
          shape: Props.toShape(p.s('shape'), p.n('radius')),
          elevation: p.n('elevation'),
          shadowColor: p.color('shadowColor'),
          surfaceTintColor: p.color('surfaceTintColor'),
          deleteIcon: p['deleteIcon'] != null ? Icon(Props.toIcon(p['deleteIcon'])) : null,
          onDeleted: p['onDeleted'] != null ? () => _emit(p['onDeleted'], null, fallback: p.map) : null,
        );
        break;
      case 'listtile':
        result = ListTile(
          leading: _slotIcon(p['leading'], '$path/leading'),
          title: _slotText(p['title'] ?? p['text'], '$path/title'),
          subtitle: _slotText(p['subtitle'], '$path/subtitle'),
          trailing: _slotText(p['trailing'], '$path/trailing'),
          isThreeLine: p.b('isThreeLine'),
          dense: p.b('dense'),
          enabled: p.b('enabled', true),
          selected: p.b('selected'),
          autofocus: p.b('autofocus'),
          contentPadding: p.inset('contentPadding'),
          minVerticalPadding: p.n('minVerticalPadding'),
          tileColor: p.color('tileColor'),
          selectedTileColor: p.color('selectedTileColor'),
          focusColor: p.color('focusColor'),
          hoverColor: p.color('hoverColor'),
          iconColor: p.color('iconColor'),
          textColor: p.color('textColor'),
          shape: Props.toShape(p.s('shape'), p.n('radius')),
          enableFeedback: p.b('enableFeedback', true),
          onTap: _tapHandler(p),
          onLongPress: _namedEvent(p, 'longPress'),
        );
        break;

      // ---------- 滚动 / 列表 ----------
      case 'listview':
        result = _listView(p, children, path);
        break;
      case 'gridview':
        final gCount = p.i('itemCount');
        final gTemplate = p['itemTemplate'] ?? p['item'];
        final gUseBuilder = gTemplate != null && gCount != null && gCount > 0;
        final gNeedsSubst = gUseBuilder && _hasTemplateVar(gTemplate);
        result = GridView.builder(
          controller: p['id'] != null ? FlutterControl.scroll(p['id'].toString()) : null,
          padding: p.inset('padding'),
          scrollDirection: p.axis('scrollDirection'),
          reverse: p.b('reverse'),
          physics: p.has('physics') ? Props.toPhysics(p['physics']) : const NeverScrollableScrollPhysics(),
          shrinkWrap: p.has('shrinkWrap') ? p.b('shrinkWrap') : true,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: p.i('crossAxisCount') ?? p.i('columns') ?? 2,
            mainAxisSpacing: p.n('gap') ?? p.n('mainAxisSpacing') ?? 8,
            crossAxisSpacing: p.n('gap') ?? p.n('crossAxisSpacing') ?? 8,
            childAspectRatio: p.n('childAspectRatio') ?? 1.0,
          ),
          itemCount: gUseBuilder ? gCount : children.length,
          itemBuilder: (ctx, i) => gUseBuilder
              ? (_build(gNeedsSubst ? _subst(gTemplate, i) : gTemplate, '$path/$i') ?? const SizedBox.shrink())
              : children[i],
        );
        break;
      case 'divider':
        result = Divider(
          color: p.color('color'),
          thickness: p.n('thickness'),
          height: p.n('height'),
          indent: p.n('indent'),
          endIndent: p.n('endIndent'),
        );
        break;
      case 'circularprogressindicator':
        result = Center(
          child: CircularProgressIndicator(
            value: p.n('value'),
            color: p.color('color'),
            backgroundColor: p.color('backgroundColor'),
            strokeWidth: p.n('strokeWidth') ?? 4.0,
            strokeCap: p.s('strokeCap')?.toLowerCase() == 'round' ? StrokeCap.round : StrokeCap.square,
            semanticsLabel: p.s('semanticsLabel'),
          ),
        );
        break;
      case 'linearprogressindicator':
        result = LinearProgressIndicator(
          value: p.n('value'),
          color: p.color('color'),
          backgroundColor: p.color('backgroundColor'),
          minHeight: p.n('minHeight'),
          semanticsLabel: p.s('semanticsLabel'),
          borderRadius: Props.toBorderRadius(p['borderRadius'] ?? p['radius']),
        );
        break;
      case 'snackbar':
        result = SnackBar(
          content: child0(),
          backgroundColor: p.color('backgroundColor') ?? p.color('color'),
          elevation: p.n('elevation'),
          duration: p.has('duration') ? Props.toDuration(p['duration']) : const Duration(milliseconds: 4000),
          behavior: p.s('behavior')?.toLowerCase() == 'floating' ? SnackBarBehavior.floating : SnackBarBehavior.fixed,
          width: p.n('width'),
          action: p['action'] != null
              ? SnackBarAction(label: (p['actionLabel'] ?? 'OK').toString(), onPressed: _tapHandler(p) ?? () {})
              : null,
        );
        break;

      // ---------- 交互 ----------
      case 'checkbox':
        result = BridgeCheckbox(
          key: _nodeKey(p, path),
          p: p,
          onChanged: (v) => _change(p, v),
        );
        break;
      case 'switch':
        result = BridgeSwitch(
          key: _nodeKey(p, path),
          p: p,
          onChanged: (v) => _change(p, v),
        );
        break;
      case 'slider':
        result = BridgeSlider(
          key: _nodeKey(p, path),
          p: p,
          onChanged: (v) => _change(p, v),
        );
        break;
      case 'textfield' || 'textformfield':
        result = BridgeTextField(
          key: _nodeKey(p, path),
          p: p,
          onChanged: (v) => _change(p, v),
          onSubmitted: (p['onSubmitted'] ?? p['onSubmit']) != null
              ? (v) => _emit(p['onSubmitted'] ?? p['onSubmit'], v, fallback: p.map)
              : null,
        );
        break;
      case 'inkwell':
      case 'gesturedetector':
        final onTap = _tapHandler(p);
        final onLongPress = _namedEvent(p, 'longPress');
        final onDoubleTap = _namedEvent(p, 'doubleTap');
        result = p.type == 'inkwell'
            ? InkWell(onTap: onTap, onLongPress: onLongPress, onDoubleTap: onDoubleTap, child: child0())
            : GestureDetector(onTap: onTap, onLongPress: onLongPress, onDoubleTap: onDoubleTap, child: child0());
        break;
      case 'dropdownbutton' || 'dropdownbuttonformfield':
        result = p.type == 'dropdownbuttonformfield'
            ? DropdownButtonFormField<String>(
                initialValue: p.s('value'),
                items: _dropdownItems(p['items']),
                onChanged: (v) => _emit(p['onChange'], v, fallback: p.map),
                decoration: InputDecoration(labelText: _decText(p, 'labelText'), border: const OutlineInputBorder()),
              )
            : BridgeDropdown(
                key: _nodeKey(p, path),
                p: p,
                onChanged: (v) => _emit(p['onChange'], v, fallback: p.map),
              );
        break;

      // ---------- Scaffold 体系 ----------
      case 'scaffold':
        result = Scaffold(
          key: scaffoldKey,
          backgroundColor: p.color('backgroundColor'),
          appBar: _preferred(_build(p['appBar'], '$path/appBar')),
          drawer: _build(p['drawer'], '$path/drawer'),
          endDrawer: _build(p['endDrawer'], '$path/endDrawer'),
          body: _build(p['body'], '$path/body') ?? child0(),
          bottomNavigationBar: _build(p['bottomNavigationBar'], '$path/bottomNav'),
          bottomSheet: _build(p['bottomSheet'], '$path/bottomSheet'),
          floatingActionButton: _build(p['floatingActionButton'], '$path/fab'),
          floatingActionButtonLocation: _fabLocation(p.s('floatingActionButtonLocation')),
          persistentFooterButtons: p.list('persistentFooterButtons').isEmpty
              ? null
              : _children(p['persistentFooterButtons'], '$path/footer'),
          extendBody: p.b('extendBody'),
          extendBodyBehindAppBar: p.b('extendBodyBehindAppBar'),
          resizeToAvoidBottomInset: p.has('resizeToAvoidBottomInset') ? p.b('resizeToAvoidBottomInset', true) : null,
          drawerEnableOpenDragGesture: p.b('drawerEnableOpenDragGesture', true),
          endDrawerEnableOpenDragGesture: p.b('endDrawerEnableOpenDragGesture', true),
          drawerScrimColor: p.color('drawerScrimColor'),
          drawerEdgeDragWidth: p.n('drawerEdgeDragWidth'),
          primary: p.has('primary') ? p.b('primary') : null,
          persistentFooterAlignment: p.align('persistentFooterAlignment') is Alignment
              ? (p.align('persistentFooterAlignment') as Alignment)
              : null,
        );
        break;
      case 'appbar':
        result = AppBar(
          title: _build(p['title'], '$path/title'),
          leading: _build(p['leading'], '$path/leading'),
          actions: _children(p['actions'], '$path/actions'),
          bottom: _preferred(_build(p['bottom'], '$path/bottom')),
          elevation: p.n('elevation'),
          scrolledUnderElevation: p.n('scrolledUnderElevation'),
          shadowColor: p.color('shadowColor'),
          surfaceTintColor: p.color('surfaceTintColor'),
          backgroundColor: p.color('backgroundColor') ?? p.color('color'),
          foregroundColor: p.color('foregroundColor'),
          centerTitle: p.b('centerTitle'),
          titleSpacing: p.n('titleSpacing'),
          leadingWidth: p.n('leadingWidth'),
          toolbarHeight: p.n('toolbarHeight'),
          shape: Props.toShape(p.s('shape'), p.n('radius')),
          automaticallyImplyLeading: p.b('automaticallyImplyLeading', true),
        );
        break;
      case 'drawer':
        result = Drawer(
          backgroundColor: p.color('backgroundColor') ?? p.color('color'),
          width: p.n('width'),
          elevation: p.n('elevation'),
          shadowColor: p.color('shadowColor'),
          surfaceTintColor: p.color('surfaceTintColor'),
          shape: Props.toShape(p.s('shape'), p.n('radius')),
          clipBehavior: p.has('clipBehavior') ? Props.toClip(p['clipBehavior']) : Clip.none,
          child: child0(),
        );
        break;
      case 'useraccountsdrawerheader':
        result = UserAccountsDrawerHeader(
          decoration: _decoration(p),
          accountName: _build(p['accountName'], '$path/accountName'),
          accountEmail: _build(p['accountEmail'], '$path/accountEmail'),
          currentAccountPicture: _build(p['currentAccountPicture'], '$path/avatar'),
          otherAccountsPictures: _children(p['otherAccountsPictures'], '$path/otherAccounts'),
        );
        break;
      case 'bottomnavigationbar':
        result = BridgeBottomNav(
          key: _nodeKey(p, path),
          items: p.list('items'),
          initialIndex: p.i('currentIndex') ?? 0,
          selectedColor: p.color('selectedItemColor'),
          unselectedColor: p.color('unselectedItemColor'),
          type: p.s('type') == 'shifting' ? BottomNavigationBarType.shifting : BottomNavigationBarType.fixed,
          onTap: (i) => _emit(p['onTap'], i, fallback: p.map),
        );
        break;
      case 'tab':
        result = const SizedBox.shrink();
        break;
      case 'tabbar':
        result = TabBar(
          tabs: p.list('tabs').map((t) {
            final tp = Props.of(t);
            return Tab(
              text: (tp['text'] ?? tp['label'])?.toString(),
              icon: tp['icon'] != null ? Icon(Props.toIcon(tp['icon'])) : null,
            );
          }).toList(),
          isScrollable: p.b('isScrollable'),
          indicatorColor: p.color('indicatorColor'),
          indicatorWeight: p.n('indicatorWeight') ?? 2.0,
          indicatorSize: p.s('indicatorSize')?.toLowerCase() == 'label' ? TabBarIndicatorSize.label : TabBarIndicatorSize.tab,
          labelColor: p.color('labelColor'),
          unselectedLabelColor: p.color('unselectedLabelColor'),
          labelStyle: p['labelStyle'] != null ? Props.toTextStyle(Props.of(p['labelStyle'])) : null,
          unselectedLabelStyle: p['unselectedLabelStyle'] != null ? Props.toTextStyle(Props.of(p['unselectedLabelStyle'])) : null,
          labelPadding: p.inset('labelPadding'),
          padding: p.inset('padding'),
          dividerColor: p.color('dividerColor'),
          automaticIndicatorColorAdjustment: p.b('automaticIndicatorColorAdjustment', true),
          splashFactory: _noSplash(p) ? NoSplash.splashFactory : null,
          overlayColor: _tabOverlay(p),
          dividerHeight: p.n('dividerHeight'),
          indicator: _tabIndicator(p),
        );
        break;
      case 'tabbarview':
        result = TabBarView(children: children);
        break;
      case 'defaulttabcontroller':
        final tabId = p['id']?.toString();
        final tabLen = p.i('length') ?? 1;
        final tabIndex = (p.i('index') ?? p.i('initialIndex') ?? 0).clamp(0, tabLen - 1);
        result = BridgeTabs(
          key: tabId != null ? ValueKey('tabs:$tabId') : null,
          id: tabId,
          length: tabLen,
          index: tabIndex,
          onChanged: (i) => _change(p, i),
          child: child0(),
        );
        break;

      // ---------- 二维码 / 地图 / 图表 / 媒体 ----------
      case 'qrcode' || 'qrimageview':
        result = QrImageView(
          data: (p['data'] ?? p['text'] ?? '').toString(),
          size: p.n('size'),
          backgroundColor: p.color('background') ?? Colors.white,
          eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: p.color('color') ?? Colors.black),
          dataModuleStyle: QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: p.color('color') ?? Colors.black),
        );
        break;
      case 'fluttermap':
        result = _mapView(p);
        break;
      case 'linechart' || 'barchart' || 'piechart':
        result = _chart(p);
        break;
      case 'videoplayer':
        result = BridgeVideo(
          id: p['id']?.toString(),
          url: (p['url'] ?? p['src'] ?? '').toString(),
          autoPlay: p.b('autoPlay'),
          loop: p.b('loop'),
          showControls: p.b('controls', true),
        );
        break;
      case 'audioplayer':
        result = BridgeAudio(
          id: p['id']?.toString(),
          url: (p['url'] ?? p['src'] ?? '').toString(),
          title: p.s('title') ?? p.s('text'),
          autoPlay: p.b('autoPlay'),
        );
        break;

      // ---------- 反馈 / 提示 ----------
      case 'tooltip':
        result = Tooltip(
          message: (p['message'] ?? p['text'] ?? '').toString(),
          child: child0(),
        );
        break;
      case 'badge':
        final label = p['label'] ?? p['text'];
        result = Badge(
          label: label == null
              ? null
              : (label is Map || label is List ? _build(label, '$path/label') : Text(label.toString())),
          isLabelVisible: p.b('isLabelVisible', true),
          backgroundColor: p.color('backgroundColor') ?? p.color('color'),
          textColor: p.color('textColor'),
          smallSize: p.n('smallSize'),
          largeSize: p.n('largeSize'),
          padding: p.inset('padding'),
          alignment: p.align('alignment'),
          offset: Props.toOffset(p['offset']),
          child: children.isEmpty ? null : child0(),
        );
        break;
      case 'placeholder':
        result = Placeholder(
          color: p.color('color') ?? const Color(0xFF455A64),
          strokeWidth: p.n('strokeWidth') ?? 2,
          fallbackWidth: p.n('fallbackWidth') ?? p.n('width') ?? 100,
          fallbackHeight: p.n('fallbackHeight') ?? p.n('height') ?? 100,
          child: children.isEmpty ? null : child0(),
        );
        break;
      case 'refreshindicator':
        final refreshCb = p['onRefresh'];
        final refreshId = p['id'];
        result = RefreshIndicator(
          key: refreshId != null ? FlutterControl.refreshKey(refreshId.toString()) : null,
          onRefresh: () async {
            // 支持声明式 onRefresh="函数名" / { event=..., args=... }，也兼容旧的 id 写法
            if (refreshCb is String) {
              FlutterBridge.instance.emit(refreshCb, {'action': refreshCb, 'type': 'refresh'});
            } else if (refreshCb is Map) {
              _emit(refreshCb, null, fallback: p.map, type: 'refresh');
            } else if (refreshId != null) {
              FlutterBridge.instance.emit(refreshId.toString(), {'id': refreshId.toString(), 'type': 'refresh'});
            }
            await Future<void>.delayed(Duration(milliseconds: p.i('delay') ?? 600));
          },
          color: p.color('color'),
          backgroundColor: p.color('backgroundColor'),
          strokeWidth: p.n('strokeWidth'),
          displacement: p.n('displacement'),
          edgeOffset: p.n('edgeOffset'),
          elevation: p.n('elevation'),
          triggerMode: p.s('triggerMode')?.toLowerCase() == 'anywhere'
              ? RefreshIndicatorTriggerMode.anywhere
              : RefreshIndicatorTriggerMode.onEdge,
          child: child0(),
        );
        break;

      // ---------- 更多 Material 控件 ----------
      case 'switchlisttile':
        result = BridgeSwitchListTile(
          key: _nodeKey(p, path),
          title: (p['title'] ?? p['text'])?.toString(),
          subtitle: p.s('subtitle'),
          initial: p.b('value'),
          onChanged: (v) => _change(p, v),
        );
        break;
      case 'checkboxlisttile':
        result = BridgeCheckboxListTile(
          key: _nodeKey(p, path),
          title: (p['title'] ?? p['text'])?.toString(),
          subtitle: p.s('subtitle'),
          initial: p.b('value'),
          onChanged: (v) => _change(p, v),
        );
        break;
      case 'radiolisttile':
        result = RadioGroup<dynamic>(
          groupValue: p['groupValue'] ?? p['group'],
          onChanged: (v) => _emit(p['onChange'], v, fallback: p.map),
          child: RadioListTile<dynamic>(
            title: _slotText(p['title'] ?? p['text'], '$path/title') ?? const SizedBox.shrink(),
            subtitle: _slotText(p['subtitle'], '$path/subtitle'),
            value: p['value'],
          ),
        );
        break;
      case 'radio':
        result = RadioGroup<dynamic>(
          groupValue: p['groupValue'] ?? p['group'],
          onChanged: (v) => _emit(p['onChange'], v, fallback: p.map),
          child: Radio<dynamic>(value: p['value']),
        );
        break;
      case 'expansiontile':
        result = BridgeExpansionTile(
          key: _nodeKey(p, path),
          p: p,
          title: _slotText(p['title'] ?? p['text'], '$path/title') ?? const SizedBox.shrink(),
          subtitle: _slotText(p['subtitle'], '$path/subtitle'),
          leading: _slotText(p['leading'], '$path/leading'),
          children: children,
          onChanged: (v) => _emit(p['onChange'] ?? p['onExpansionChanged'], v, fallback: p.map, type: 'expansion'),
        );
        break;
      case 'stepper':
        final steps = p.list('steps');
        if (steps.isEmpty) {
          result = const SizedBox.shrink();
        } else {
          result = Stepper(
            currentStep: (p.i('currentStep') ?? 0).clamp(0, steps.length - 1),
            onStepContinue: _namedEvent(p, 'stepContinue'),
            onStepCancel: _namedEvent(p, 'stepCancel'),
            steps: steps.map((s) {
              final sp = Props.of(s);
              return Step(
                title: _slotText(sp['title'], '$path/step/title') ?? const SizedBox.shrink(),
                subtitle: _slotText(sp['subtitle'], '$path/step/subtitle'),
                content: _slotText(sp['content'], '$path/step/content') ?? const SizedBox.shrink(),
              );
            }).toList(),
          );
        }
        break;
      case 'datatable':
        final columns = p.list('columns');
        final rowsRaw = p.list('rows');
        if (columns.isEmpty) {
          result = const SizedBox.shrink();
        } else {
          result = DataTable(
            columnSpacing: p.n('columnSpacing'),
            horizontalMargin: p.n('horizontalMargin'),
            headingRowHeight: p.n('headingRowHeight'),
            dataRowMinHeight: p.n('dataRowMinHeight'),
            dataRowMaxHeight: p.n('dataRowMaxHeight'),
            dividerThickness: p.n('dividerThickness'),
            headingRowColor: Renderer._colorState(p, 'headingRowColor'),
            dataRowColor: Renderer._colorState(p, 'dataRowColor'),
            headingTextStyle: _textStyleOrNull(p['headingTextStyle']),
            dataTextStyle: _textStyleOrNull(p['dataTextStyle']),
            showBottomBorder: p.b('showBottomBorder'),
            showCheckboxColumn: p.b('showCheckboxColumn', true),
            clipBehavior: p.has('clipBehavior') ? Props.toClip(p['clipBehavior']) : Clip.none,
            columns: [
              for (var i = 0; i < columns.length; i++)
                DataColumn(label: _dataCell(columns[i], '$path/col$i')),
            ],
            rows: [
              for (var r = 0; r < rowsRaw.length; r++)
                DataRow(
                  cells: [
                    for (var c = 0; c < Props.toList(rowsRaw[r]).length; c++)
                      DataCell(_dataCell(Props.toList(rowsRaw[r])[c], '$path/r$r/c$c')),
                  ],
                ),
            ],
          );
        }
        break;

      // ---------- 日期 ----------
      case 'calendardatepicker':
        final now = DateTime.now();
        final first = _parseDate(p['firstDate']) ?? DateTime(now.year - 1, now.month, now.day);
        final last = _parseDate(p['lastDate']) ?? DateTime(now.year + 1, now.month, now.day);
        var initial = _parseDate(p['initialDate']) ?? now;
        if (initial.isBefore(first)) initial = first;
        if (initial.isAfter(last)) initial = last;
        result = CalendarDatePicker(
          initialDate: initial,
          firstDate: first,
          lastDate: last,
          onDateChanged: (d) => _emit(p['onChange'], d.toIso8601String(), fallback: p.map),
        );
        break;

      // ---------- 动画 ----------
      case 'animatedopacity':
        result = AnimatedOpacity(
          opacity: (p.n('opacity') ?? 1.0).clamp(0.0, 1.0),
          duration: Duration(milliseconds: p.i('duration') ?? 200),
          child: child0(),
        );
        break;
      case 'animatedcontainer':
        result = AnimatedContainer(
          duration: Duration(milliseconds: p.i('duration') ?? 200),
          width: Props.dim(p['width']),
          height: Props.dim(p['height']),
          alignment: p.align('alignment'),
          padding: p.inset('padding'),
          margin: p.inset('margin'),
          decoration: _decoration(p),
          child: child0(),
        );
        break;

      // ============================================================
      // 更多布局 / 装饰 / 包装
      // ============================================================
      case 'material':
        result = Material(
          color: p.color('color') ?? p.color('backgroundColor'),
          elevation: p.n('elevation') ?? 0,
          borderRadius: p.n('radius') != null ? BorderRadius.circular(p.n('radius')!) : null,
          child: child0(),
        );
        break;
      case 'decoratedbox':
        result = DecoratedBox(decoration: _decoration(p) ?? const BoxDecoration(), child: child0());
        break;
      case 'coloredbox':
        result = ColoredBox(color: p.color('color') ?? Colors.transparent, child: child0());
        break;
      case 'constrainedbox':
        result = ConstrainedBox(constraints: _constraints(p), child: child0());
        break;
      case 'intrinsicwidth':
        result = IntrinsicWidth(child: child0());
        break;
      case 'intrinsicheight':
        result = IntrinsicHeight(child: child0());
        break;
      case 'fittedbox':
        result = FittedBox(fit: Props.toBoxFit(p['fit']), child: child0());
        break;
      case 'rotatedbox':
        result = RotatedBox(quarterTurns: p.i('quarterTurns') ?? p.i('turns') ?? 1, child: child0());
        break;
      case 'clipoval':
        result = ClipOval(child: child0());
        break;
      case 'cliprect':
        result = ClipRect(child: child0());
        break;
      case 'offstage':
        result = Offstage(offstage: p.b('offstage', true), child: child0());
        break;
      case 'visibility':
        result = Visibility(visible: p.b('visible', true), child: child0());
        break;
      case 'absorbpointer':
        result = AbsorbPointer(absorbing: p.b('absorbing', true), child: child0());
        break;
      case 'ignorepointer':
        result = IgnorePointer(ignoring: p.b('ignoring', true), child: child0());
        break;
      case 'scrollbar':
        result = Scrollbar(child: child0());
        break;
      case 'indexedstack':
        result = IndexedStack(index: p.i('index') ?? 0, children: children);
        break;
      case 'baseline':
        result = Baseline(
          baselineType: p.s('baselineType')?.toLowerCase() == 'alphabetic'
              ? TextBaseline.alphabetic
              : TextBaseline.ideographic,
          baseline: p.n('baseline') ?? 0,
          child: child0(),
        );
        break;
      case 'limitedbox':
        result = LimitedBox(
          maxWidth: p.n('maxWidth') ?? double.infinity,
          maxHeight: p.n('maxHeight') ?? double.infinity,
          child: child0(),
        );
        break;

      // ============================================================
      // 更多按钮 / 选择控件
      // ============================================================
      case 'materialbutton':
        result = MaterialButton(
          onPressed: _tapHandler(p),
          color: p.color('color') ?? p.color('backgroundColor'),
          child: _widgetOrText(p['child'], (p['text'] ?? 'Button').toString(), '$path/child'),
        );
        break;
      case 'segmentedbutton':
        result = SegmentedButton<String>(
          segments: p.list('segments').map((s) {
            final sp = Props.of(s);
            return ButtonSegment<String>(
              value: (sp['value'] ?? sp['label'] ?? '').toString(),
              label: Text((sp['label'] ?? sp['text'] ?? '').toString()),
              icon: sp['icon'] != null ? Icon(Props.toIcon(sp['icon'])) : null,
            );
          }).toList(),
          selected: Props.toList(p['selected']).map((e) => e.toString()).toSet(),
          onSelectionChanged: (s) => _emit(p['onChange'], s.toList(), fallback: p.map),
        );
        break;
      case 'togglebuttons':
        final sel = Props.toList(p['isSelected']).map((e) => Props.toBool(e) ?? false).toList();
        result = ToggleButtons(
          isSelected: sel.length == children.length ? sel : List<bool>.filled(children.length, false),
          onPressed: (i) => _emit(p['onChange'], i, fallback: p.map),
          children: children,
        );
        break;
      case 'popupmenubutton':
        result = PopupMenuButton<String>(
          icon: p['icon'] != null ? Icon(Props.toIcon(p['icon'])) : null,
          itemBuilder: (ctx) => p.list('items').map((it) {
            final ip = Props.of(it);
            return PopupMenuItem<String>(
              value: (ip['value'] ?? ip['text'] ?? '').toString(),
              child: Text((ip['text'] ?? ip['label'] ?? '').toString()),
            );
          }).toList(),
          onSelected: (v) => _emit(p['onChange'], v, fallback: p.map),
        );
        break;
      case 'actionchip' || 'filterchip' || 'choicechip' || 'inputchip':
        final chLabel = (p['text'] ?? p['label'] ?? '').toString();
        final chAvatar = p['avatar'] != null ? Icon(Props.toIcon(p['avatar'])) : null;
        if (p.type == 'actionchip') {
          result = ActionChip(avatar: chAvatar, label: Text(chLabel), onPressed: _tapHandler(p));
        } else if (p.type == 'filterchip') {
          result = FilterChip(avatar: chAvatar, label: Text(chLabel), selected: p.b('selected'), onSelected: (v) => _emit(p['onChange'], v, fallback: p.map));
        } else if (p.type == 'choicechip') {
          result = ChoiceChip(avatar: chAvatar, label: Text(chLabel), selected: p.b('selected'), onSelected: (v) => _emit(p['onChange'], v, fallback: p.map));
        } else {
          result = InputChip(
            avatar: chAvatar,
            label: Text(chLabel),
            selected: p.b('selected'),
            onPressed: _tapHandler(p),
            onDeleted: p['onDeleted'] != null ? () => _emit(p['onDeleted'], null, fallback: p.map) : null,
          );
        }
        break;
      case 'rangeslider':
        result = BridgeRangeSlider(
          key: _nodeKey(p, path),
          start: p.n('start') ?? p.n('min') ?? 0,
          end: p.n('end') ?? p.n('max') ?? 1,
          min: p.n('min') ?? 0,
          max: p.n('max') ?? 1,
          onChanged: (v) => _change(p, v),
        );
        break;
      case 'dismissible':
        result = Dismissible(
          key: ValueKey(p['id'] ?? 'dismiss:$path'),
          direction: p.s('direction')?.toLowerCase() == 'horizontal'
              ? DismissDirection.horizontal
              : DismissDirection.endToStart,
          child: child0(),
          onDismissed: (_) => _emit(p['onDismiss'], null, fallback: p.map),
        );
        break;

      // ============================================================
      // 导航 / 表单 / 其它
      // ============================================================
      case 'navigationbar':
        result = BridgeNavigationBar(
          key: _nodeKey(p, path),
          p: p,
          items: p.list('items') ?? p.list('destinations'),
          initialIndex: p.i('currentIndex') ?? p.i('selectedIndex') ?? 0,
          onTap: (i) => _emit(p['onTap'] ?? p['onChange'] ?? p['onDestinationSelected'], i, fallback: p.map),
        );
        break;
      case 'bottomappbar':
        result = BottomAppBar(
          color: p.color('color') ?? p.color('backgroundColor'),
          elevation: p.n('elevation'),
          height: p.n('height'),
          padding: p.inset('padding'),
          notchMargin: p.n('notchMargin'),
          shadowColor: p.color('shadowColor'),
          surfaceTintColor: p.color('surfaceTintColor'),
          shape: Props.toShape(p.s('shape'), p.n('radius')),
          clipBehavior: p.has('clipBehavior') ? Props.toClip(p['clipBehavior']) : Clip.none,
          child: child0(),
        );
        break;
      case 'form':
        result = Form(child: child0());
        break;
      case 'verticaldivider':
        result = VerticalDivider(
          color: p.color('color'),
          thickness: p.n('thickness'),
          width: p.n('width'),
          indent: p.n('indent'),
          endIndent: p.n('endIndent'),
        );
        break;
      case 'richtext':
        result = Text.rich(TextSpan(children: p.list('spans').map((s) {
          final sp = Props.of(s);
          return TextSpan(text: (sp['text'] ?? '').toString(), style: Props.toTextStyle(sp));
        }).toList()));
        break;
      case 'cupertinoactivityindicator':
        result = const Center(child: CupertinoActivityIndicator());
        break;

      // ============================================================
      // 动画
      // ============================================================
      case 'animatedalign':
        result = AnimatedAlign(
          alignment: p.align('alignment') ?? Alignment.center,
          duration: Duration(milliseconds: p.i('duration') ?? 200),
          child: child0(),
        );
        break;
      case 'animatedpadding':
        result = AnimatedPadding(
          padding: p.inset('padding') ?? EdgeInsets.zero,
          duration: Duration(milliseconds: p.i('duration') ?? 200),
          child: child0(),
        );
        break;
      case 'animatedscale':
        result = AnimatedScale(
          scale: p.n('scale') ?? 1,
          duration: Duration(milliseconds: p.i('duration') ?? 200),
          child: child0(),
        );
        break;
      case 'animatedrotation':
        result = AnimatedRotation(
          turns: p.n('turns') ?? 0,
          duration: Duration(milliseconds: p.i('duration') ?? 200),
          child: child0(),
        );
        break;
      case 'animatedslide':
        result = AnimatedSlide(
          offset: _offset(p['offset']) ?? Offset.zero,
          duration: Duration(milliseconds: p.i('duration') ?? 200),
          child: child0(),
        );
        break;
      case 'animatedswitcher':
        result = AnimatedSwitcher(
          duration: Duration(milliseconds: p.i('duration') ?? 200),
          child: children.isEmpty ? null : child0(),
        );
        break;
      case 'animateddefaulttextstyle':
        result = AnimatedDefaultTextStyle(
          duration: Duration(milliseconds: p.i('duration') ?? 200),
          style: Props.toTextStyle(p),
          child: child0(),
        );
        break;
      case 'animatedcrossfade':
        result = AnimatedCrossFade(
          duration: Duration(milliseconds: p.i('duration') ?? 200),
          firstChild: children.isNotEmpty ? children[0] : const SizedBox.shrink(),
          secondChild: children.length > 1 ? children[1] : const SizedBox.shrink(),
          crossFadeState: p.b('showFirst', true) ? CrossFadeState.showFirst : CrossFadeState.showSecond,
        );
        break;

      // ============================================================
      // 复杂控件
      // ============================================================
      case 'pageview':
        result = BridgePageView(
          key: _nodeKey(p, path),
          p: p,
          children: children,
          onChanged: (i) => _emit(p['onChange'], i, fallback: p.map),
        );
        break;
      case 'navigationrail':
        result = NavigationRail(
          selectedIndex: p.i('selectedIndex') ?? p.i('currentIndex') ?? 0,
          extended: p.b('extended'),
          minWidth: p.n('minWidth'),
          minExtendedWidth: p.n('minExtendedWidth'),
          backgroundColor: p.color('backgroundColor') ?? p.color('color'),
          elevation: p.n('elevation'),
          labelType: p.s('labelType')?.toLowerCase() == 'none' ? NavigationRailLabelType.none : NavigationRailLabelType.all,
          groupAlignment: p.n('groupAlignment') ?? -1.0,
          useIndicator: p.b('useIndicator', true),
          onDestinationSelected: (i) => _emit(p['onTap'] ?? p['onChange'], i, fallback: p.map),
          destinations: p.list('items').map((e) {
            final ip = Props.of(e);
            return NavigationRailDestination(
              icon: Icon(Props.toIcon(ip['icon'])),
              selectedIcon: ip['selectedIcon'] != null ? Icon(Props.toIcon(ip['selectedIcon'])) : null,
              label: Text((ip['label'] ?? ip['text'] ?? '').toString()),
            );
          }).toList(),
        );
        break;
      case 'dropdownmenu':
        result = DropdownMenu<String>(
          initialSelection: p.s('initialSelection') ?? p.s('value'),
          label: p['label'] != null ? Text(p['label'].toString()) : null,
          hintText: p.s('hintText') ?? p.s('hint'),
          helperText: p.s('helperText'),
          errorText: p.s('errorText'),
          enabled: p.b('enabled', true),
          requestFocusOnTap: p.b('requestFocusOnTap'),
          width: p.n('width'),
          menuHeight: p.n('menuHeight'),
          textStyle: Props.toTextStyle(p),
          dropdownMenuEntries: p.list('items').map((e) {
            final ip = Props.of(e);
            return DropdownMenuEntry<String>(
              value: (ip['value'] ?? ip['text'] ?? '').toString(),
              label: (ip['label'] ?? ip['text'] ?? '').toString(),
              enabled: ip['enabled'] == null ? true : Props.toBool(ip['enabled']) ?? true,
            );
          }).toList(),
          onSelected: (v) => _emit(p['onChange'], v, fallback: p.map),
        );
        break;
      case 'reorderablelistview':
        final rCount = p.i('itemCount');
        final rTemplate = p['itemTemplate'] ?? p['item'];
        if (rTemplate != null && rCount != null && rCount > 0) {
          final rNeedsSubst = _hasTemplateVar(rTemplate);
          result = ReorderableListView.builder(
            scrollController: p['id'] != null ? FlutterControl.scroll(p['id'].toString()) : null,
            padding: p.inset('padding'),
            physics: Props.toPhysics(p['physics']),
            shrinkWrap: p.b('shrinkWrap'),
            buildDefaultDragHandles: p.b('buildDefaultDragHandles', true),
            itemCount: rCount,
            itemBuilder: (ctx, i) => KeyedSubtree(
              key: ValueKey('$path/ri$i'),
              child: _build(rNeedsSubst ? _subst(rTemplate, i) : rTemplate, '$path/$i') ?? const SizedBox.shrink(),
            ),
            onReorderItem: (a, b) => _emit(p['onReorder'], {'oldIndex': a, 'newIndex': b}, fallback: p.map),
          );
        } else {
          result = ListView(children: children);
        }
        break;
      case 'expansionpanelList':
        final panels = p.list('panels');
        result = ExpansionPanelList(
          elevation: p.n('elevation') ?? 1,
          expansionCallback: (i, isExpanded) => _emit(p['onChange'], {'index': i, 'isExpanded': isExpanded}, fallback: p.map),
          children: panels.map((e) {
            final ep = Props.of(e);
            final expanded = ep.b('expanded') || ep.b('isExpanded');
            final header = ep['header'] ?? ep['title'];
            final body = ep['body'] ?? ep['content'];
            return ExpansionPanel(
              isExpanded: expanded,
              canTapOnHeader: ep.b('canTapOnHeader'),
              headerBuilder: (ctx, isExpanded) => header is Map || header is List
                  ? (_build(header, '$path/header') ?? const SizedBox.shrink())
                  : ListTile(title: Text((header ?? '').toString())),
              body: body is Map || body is List ? (_build(body, '$path/body') ?? const SizedBox.shrink()) : Text((body ?? '').toString()),
            );
          }).toList(),
        );
        break;
      case 'table':
        final tRows = p.list('rows');
        result = Table(
          border: p['border'] != null ? TableBorder.all() : null,
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          columnWidths: null,
          children: tRows.map((row) {
            final cells = Props.toList(row);
            return TableRow(
              children: cells.map((c) => TableCell(child: _dataCell(c, '$path/cell'))).toList(),
            );
          }).toList(),
        );
        break;
      case 'customscrollview':
        result = CustomScrollView(
          controller: p['id'] != null ? FlutterControl.scroll(p['id'].toString()) : null,
          scrollDirection: p.axis('scrollDirection'),
          reverse: p.b('reverse'),
          physics: Props.toPhysics(p['physics']),
          shrinkWrap: p.b('shrinkWrap'),
          slivers: children,
        );
        break;
      case 'slivertoboxadapter':
        result = SliverToBoxAdapter(child: child0());
        break;
      case 'sliverpadding':
        result = SliverPadding(padding: p.inset('padding') ?? EdgeInsets.zero, sliver: children.isNotEmpty ? children[0] : const SliverToBoxAdapter());
        break;
      case 'sliverlist':
        result = SliverList(delegate: SliverChildListDelegate(children));
        break;
      case 'slivergrid':
        result = SliverGrid(
          delegate: SliverChildListDelegate(children),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: p.i('crossAxisCount') ?? p.i('columns') ?? 2,
            mainAxisSpacing: p.n('gap') ?? p.n('mainAxisSpacing') ?? 8,
            crossAxisSpacing: p.n('gap') ?? p.n('crossAxisSpacing') ?? 8,
            childAspectRatio: p.n('childAspectRatio') ?? 1.0,
          ),
        );
        break;
      case 'sliverfillremaining':
        result = SliverFillRemaining(hasScrollBody: p.b('hasScrollBody', true), child: child0());
        break;
      case 'sliverappbar':
        result = SliverAppBar(
          title: _build(p['title'], '$path/title'),
          leading: _build(p['leading'], '$path/leading'),
          actions: _children(p['actions'], '$path/actions'),
          floating: p.b('floating'),
          pinned: p.b('pinned'),
          snap: p.b('snap'),
          expandedHeight: p.n('expandedHeight'),
          toolbarHeight: p.n('toolbarHeight') ?? kToolbarHeight,
          backgroundColor: p.color('backgroundColor') ?? p.color('color'),
          foregroundColor: p.color('foregroundColor'),
          elevation: p.n('elevation'),
          centerTitle: p.b('centerTitle'),
          flexibleSpace: _build(p['flexibleSpace'], '$path/flexible'),
        );
        break;

      // ============================================================
      // 动画
      // ============================================================
      case 'animatedpositioned':
        result = AnimatedPositioned(
          duration: Duration(milliseconds: p.i('duration') ?? 200),
          curve: Props.toCurve(p.s('curve')),
          left: Props.dim(p['left']),
          top: Props.dim(p['top']),
          right: Props.dim(p['right']),
          bottom: Props.dim(p['bottom']),
          width: Props.dim(p['width']),
          height: Props.dim(p['height']),
          child: child0(),
        );
        break;
      case 'animatedsize':
        result = AnimatedSize(
          duration: Duration(milliseconds: p.i('duration') ?? 200),
          curve: Props.toCurve(p.s('curve')),
          alignment: p.align('alignment') ?? Alignment.center,
          child: child0(),
        );
        break;
      case 'animatedtheme':
        result = AnimatedTheme(
          duration: Duration(milliseconds: p.i('duration') ?? 200),
          data: ThemeData(
            colorSchemeSeed: p.color('colorSchemeSeed'),
            brightness: p.s('brightness')?.toLowerCase() == 'dark' ? Brightness.dark : Brightness.light,
          ),
          child: child0(),
        );
        break;

      // ============================================================
      // 弹窗组件（声明式，直接内联在树里渲染）
      // ============================================================
      case 'alertdialog':
        result = AlertDialog(
          icon: _build(p['icon'], '$path/icon'),
          title: _build(p['title'], '$path/title'),
          content: _build(p['content'], '$path/content') ?? (p['text'] != null ? Text(p['text'].toString()) : null),
          actions: _children(p['actions'], '$path/actions'),
          backgroundColor: p.color('backgroundColor') ?? p.color('color'),
          elevation: p.n('elevation'),
          shadowColor: p.color('shadowColor'),
          surfaceTintColor: p.color('surfaceTintColor'),
          insetPadding: p.inset('insetPadding'),
          actionsPadding: p.inset('actionsPadding'),
          shape: Props.toShape(p.s('shape'), p.n('radius')),
          alignment: p.align('alignment'),
          scrollable: p.b('scrollable'),
        );
        break;
      case 'simpledialog':
        result = SimpleDialog(
          title: _build(p['title'], '$path/title'),
          backgroundColor: p.color('backgroundColor') ?? p.color('color'),
          elevation: p.n('elevation'),
          shape: Props.toShape(p.s('shape'), p.n('radius')),
          children: children,
        );
        break;
      case 'dialog':
        result = Dialog(
          backgroundColor: p.color('backgroundColor') ?? p.color('color'),
          elevation: p.n('elevation'),
          insetPadding: p.inset('insetPadding') ?? const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
          shape: Props.toShape(p.s('shape'), p.n('radius')),
          clipBehavior: p.has('clipBehavior') ? Props.toClip(p['clipBehavior']) : Clip.none,
          child: child0(),
        );
        break;
      case 'bottomsheet':
        result = BottomSheet(
          onClosing: () => _emit(p['onClosing'], null, fallback: p.map),
          backgroundColor: p.color('backgroundColor') ?? p.color('color'),
          elevation: p.n('elevation'),
          shape: Props.toShape(p.s('shape'), p.n('radius')),
          enableDrag: p.b('enableDrag', true),
          showDragHandle: p.b('showDragHandle'),
          dragHandleColor: p.color('dragHandleColor'),
          dragHandleSize: _size(p['dragHandleSize']),
          shadowColor: p.color('shadowColor'),
          clipBehavior: p.has('clipBehavior') ? Props.toClip(p['clipBehavior']) : Clip.none,
          builder: (ctx) => child0(),
        );
        break;

      // ============================================================
      // Cupertino / 其它补充
      // ============================================================
      case 'cupertinobutton':
        result = CupertinoButton(
          color: p.color('color'),
          disabledColor: p.color('disabledColor') ?? CupertinoColors.quaternarySystemFill,
          padding: p.inset('padding'),
          borderRadius: Props.toBorderRadius(p['borderRadius'] ?? p['radius']),
          minimumSize: _size(p['minimumSize']) ?? (p.n('minSize') != null ? Size.square(p.n('minSize')!) : null),
          pressedOpacity: p.n('pressedOpacity') ?? 0.1,
          alignment: p.align('alignment') ?? Alignment.center,
          onPressed: p.b('enabled', true) ? _tapHandler(p) : null,
          child: _widgetOrText(p['child'], (p['text'] ?? 'Button').toString(), '$path/child'),
        );
        break;
      case 'cupertinoswitch':
        result = BridgeCupertinoSwitch(key: _nodeKey(p, path), p: p, onChanged: (v) => _change(p, v));
        break;
      case 'cupertinoslider':
        result = BridgeCupertinoSlider(key: _nodeKey(p, path), p: p, onChanged: (v) => _change(p, v));
        break;
      case 'cupertinoalertdialog':
        result = CupertinoAlertDialog(
          title: _build(p['title'], '$path/title'),
          content: _build(p['content'], '$path/content'),
          actions: _children(p['actions'], '$path/actions'),
        );
        break;
      case 'cupertinodatepicker':
        result = BridgeCupertinoDatePicker(
          key: _nodeKey(p, path),
          p: p,
          onChanged: (d) => _emit(p['onChange'], d.toIso8601String(), fallback: p.map),
        );
        break;
      case 'cupertinotimerpicker':
        result = CupertinoTimerPicker(
          mode: p.s('mode')?.toLowerCase() == 'hms' ? CupertinoTimerPickerMode.hms : CupertinoTimerPickerMode.hm,
          initialTimerDuration: Duration(seconds: p.i('initialSeconds') ?? 0),
          alignment: p.align('alignment') ?? Alignment.center,
          onTimerDurationChanged: (d) => _emit(p['onChange'], d.inSeconds, fallback: p.map),
        );
        break;
      case 'cupertinonavigationbar':
        result = CupertinoNavigationBar(
          middle: _slotText(p['title'] ?? p['middle'], '$path/middle'),
          leading: _slotIcon(p['leading'], '$path/leading'),
          trailing: _slotIcon(p['trailing'], '$path/trailing'),
          backgroundColor: p.color('backgroundColor') ?? p.color('color'),
          border: p['border'] != null && _borderSide(p['border']) != null
              ? Border(bottom: _borderSide(p['border'])!)
              : null,
        );
        break;
      case 'navigationdrawer':
        result = NavigationDrawer(
          backgroundColor: p.color('backgroundColor') ?? p.color('color'),
          elevation: p.n('elevation'),
          surfaceTintColor: p.color('surfaceTintColor'),
          selectedIndex: p.i('selectedIndex') ?? p.i('currentIndex'),
          onDestinationSelected: (i) => _emit(p['onTap'] ?? p['onChange'], i, fallback: p.map),
          children: children,
        );
        break;
      case 'materialbanner':
        final bannerActions = _children(p['actions'], '$path/actions');
        result = MaterialBanner(
          content: child0(),
          leading: _build(p['leading'], '$path/leading'),
          backgroundColor: p.color('backgroundColor') ?? p.color('color'),
          elevation: p.n('elevation'),
          // MaterialBanner 要求 actions 非空
          actions: bannerActions.isEmpty
              ? [TextButton(onPressed: _tapHandler(p), child: const Text('OK'))]
              : bannerActions,
        );
        break;
      case 'searchbar':
        final trailing = _children(p['trailing'], '$path/trailing');
        final sbId = p['id']?.toString();
        result = SearchBar(
          controller: sbId != null ? FlutterControl.text(sbId) : null,
          focusNode: sbId != null ? FlutterControl.focusNode(sbId) : null,
          hintText: p.s('hint') ?? p.s('hintText'),
          leading: p['leading'] != null ? Icon(Props.toIcon(p['leading'])) : null,
          trailing: trailing.isEmpty ? null : trailing,
          backgroundColor: p.color('backgroundColor') == null
              ? null
              : WidgetStatePropertyAll<Color?>(p.color('backgroundColor')),
          elevation: p.n('elevation') == null ? null : WidgetStatePropertyAll<double?>(p.n('elevation')),
          onChanged: (v) => _change(p, v),
          onSubmitted: (v) => _emit(p['onSubmitted'], v, fallback: p.map),
        );
        break;
      case 'listwheelscrollview':
        result = ListWheelScrollView(
          itemExtent: p.n('itemExtent') ?? 40,
          diameterRatio: p.n('diameterRatio') ?? 2,
          perspective: p.n('perspective') ?? 0.003,
          offAxisFraction: p.n('offAxisFraction') ?? 0,
          useMagnifier: p.b('useMagnifier'),
          magnification: p.n('magnification') ?? 1,
          squeeze: p.n('squeeze') ?? 1,
          physics: Props.toPhysics(p['physics']),
          children: children,
        );
        break;

      // ---------- 原生 ----------
      default:
        if (children.isNotEmpty) {
          result = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
        } else if (p['text'] != null) {
          result = Text(p['text'].toString());
        } else {
          result = const SizedBox.shrink();
        }
    }

    return _wrapCommon(result, p);
  }

  // ============================================================
  // 列表：ListView.builder（懒加载）
  // ============================================================

  static Widget _listView(Props p, List<Widget> children, String path) {
    final padding = p.inset('padding');
    final physics = Props.toPhysics(p['physics']);
    final shrinkWrap = p.b('shrinkWrap');
    final axis = p.axis('scrollDirection');
    final reverse = p.b('reverse');
    final itemExtent = p.n('itemExtent');
    final cacheExtent = p.n('cacheExtent');
    final ctrl = p['id'] != null ? FlutterControl.scroll(p['id'].toString()) : null;
    final keyboardDismiss = p.s('keyboardDismissBehavior')?.toLowerCase() == 'ondrag'
        ? ScrollViewKeyboardDismissBehavior.onDrag
        : ScrollViewKeyboardDismissBehavior.manual;

    final count = p.i('itemCount');
    final template = p['itemTemplate'] ?? p['item'];
    // 模板式懒加载：给了 item/itemTemplate + itemCount 就按需构建；
    // 模板含 $index/$i 时才逐项替换（否则直接用原引用）。
    final bool lazy = template != null && count != null && count > 0;
    final needsSubst = lazy && _hasTemplateVar(template);
    return ListView.builder(
      controller: ctrl,
      padding: padding,
      physics: physics,
      shrinkWrap: shrinkWrap,
      scrollDirection: axis,
      reverse: reverse,
      itemExtent: itemExtent,
      scrollCacheExtent: cacheExtent != null ? ScrollCacheExtent.pixels(cacheExtent) : null,
      addAutomaticKeepAlives: p.b('addAutomaticKeepAlives', true),
      addRepaintBoundaries: p.b('addRepaintBoundaries', true),
      keyboardDismissBehavior: keyboardDismiss,
      itemCount: lazy ? count : children.length,
      itemBuilder: (ctx, i) => lazy
          ? (_build(needsSubst ? _subst(template, i) : template, '$path/$i') ?? const SizedBox.shrink())
          : children[i],
    );
  }

  /// 深拷贝并把字符串里的 `$index`/`$i` 替换为下标（用于模板式列表）。
  static dynamic _subst(dynamic v, int i) {
    if (v is String) {
      // `$$` 是转义的字面 `$`：先用哨兵占位，替换完再还原
      const sentinel = '\u0000';
      return v
          .replaceAll(r'$$', sentinel)
          .replaceAll(r'$index', '$i')
          .replaceAll(r'$i', '$i')
          .replaceAll(sentinel, r'$');
    }
    if (v is List) return v.map((e) => _subst(e, i)).toList();
    if (v is Map) {
      final m = <String, dynamic>{};
      v.forEach((k, val) => m[k.toString()] = _subst(val, i));
      return m;
    }
    return v;
  }

  /// 模板里是否真的含 `$index`/`$i`。不含时不必逐项深拷贝（长列表是热路径）。
  static bool _hasTemplateVar(dynamic v) {
    if (v is String) return v.contains(r'$index') || v.contains(r'$i');
    if (v is List) return v.any(_hasTemplateVar);
    if (v is Map) return v.values.any(_hasTemplateVar);
    return false;
  }

  // ============================================================
  // 地图 / 图表
  // ============================================================

  static Widget _mapView(Props p) {
    final cp = Props.of(p['center']);
    final lat = cp.n('lat') ?? cp.n('latitude') ?? 39.9042;
    final lng = cp.n('lng') ?? cp.n('longitude') ?? 116.4074;
    final markers = <Marker>[];
    for (final m in p.list('markers')) {
      final mp = Props.of(m);
      markers.add(Marker(
        point: LatLng(mp.n('lat') ?? 0, mp.n('lng') ?? 0),
        width: mp.n('width') ?? 40,
        height: mp.n('height') ?? 40,
        child: Icon(Props.toIcon(mp['icon'] ?? 'location_on'), color: Colors.red, size: 32),
      ));
    }

    final polylines = <Polyline>[];
    for (final pl in p.list('polylines')) {
      final pp = Props.of(pl);
      final pts = _latLngList(pp.list('points'));
      if (pts.length >= 2) {
        polylines.add(Polyline(
          points: pts,
          strokeWidth: pp.n('strokeWidth') ?? 3,
          color: pp.color('color') ?? Colors.blue,
        ));
      }
    }

    final polygons = <Polygon>[];
    for (final pg in p.list('polygons')) {
      final gp = Props.of(pg);
      final pts = _latLngList(gp.list('points'));
      if (pts.length >= 3) {
        final c = gp.color('color') ?? Colors.blue;
        polygons.add(Polygon(
          points: pts,
          color: c.withValues(alpha: gp.n('opacity') ?? 0.3),
          borderColor: gp.color('borderColor') ?? c,
          borderStrokeWidth: gp.n('borderStrokeWidth') ?? 2,
        ));
      }
    }

    final circles = <CircleMarker>[];
    for (final c in p.list('circles')) {
      final cp2 = Props.of(c);
      final cColor = cp2.color('color') ?? Colors.blue;
      circles.add(CircleMarker(
        point: LatLng(cp2.n('lat') ?? cp2.n('latitude') ?? 0, cp2.n('lng') ?? cp2.n('longitude') ?? 0),
        radius: cp2.n('radius') ?? 200,
        color: cColor.withValues(alpha: cp2.n('opacity') ?? 0.2),
        borderColor: cp2.color('borderColor') ?? cColor,
        borderStrokeWidth: cp2.n('borderStrokeWidth') ?? 2,
      ));
    }

    final tile = p.s('tileUrl') ?? 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
    return FlutterMap(
      options: MapOptions(
        initialCenter: LatLng(lat, lng),
        initialZoom: p.n('zoom') ?? 13,
        minZoom: p.n('minZoom'),
        maxZoom: p.n('maxZoom'),
      ),
      children: [
        TileLayer(
          urlTemplate: tile,
          userAgentPackageName: p.s('userAgent') ?? 'com.androlua',
        ),
        if (polygons.isNotEmpty) PolygonLayer(polygons: polygons),
        if (polylines.isNotEmpty) PolylineLayer(polylines: polylines),
        if (circles.isNotEmpty) CircleLayer(circles: circles),
        if (markers.isNotEmpty) MarkerLayer(markers: markers),
      ],
    );
  }

  /// `[ {lat,lng}, ... ]` 或 `[[lat,lng], ...]` -> `List<LatLng>`
  static List<LatLng> _latLngList(List<dynamic> raw) {
    final out = <LatLng>[];
    for (final e in raw) {
      if (e is List && e.length >= 2) {
        out.add(LatLng(Props.toNum(e[0]) ?? 0, Props.toNum(e[1]) ?? 0));
      } else {
        final ep = Props.of(e);
        out.add(LatLng(ep.n('lat') ?? ep.n('latitude') ?? 0, ep.n('lng') ?? ep.n('longitude') ?? 0));
      }
    }
    return out;
  }

  static Widget _chart(Props p) {
    final height = p.n('height');
    final series = p.list('series').map(_Series.of).toList();
    final kind = p.type;

    Widget body;
    switch (kind) {
      case 'barchart':
        // 分组柱：groups = [ { values: [1,2], colors: ['#f00','#0f0'] }, ... ]；
        // 不传 groups 时沿用 series（一个 x 一根柱）。
        final groups = p.list('groups');
        body = BarChart(BarChartData(
          barGroups: groups.isNotEmpty
              ? [
                  for (var i = 0; i < groups.length; i++)
                    BarChartGroupData(x: i, barRods: _barRods(Props.of(groups[i]), series)),
                ]
              : [
                  for (var i = 0; i < series.length; i++)
                    BarChartGroupData(x: i, barRods: [
                      BarChartRodData(
                        toY: series[i].value,
                        color: series[i].color,
                        width: 14,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ]),
                ],
          gridData: const FlGridData(show: true),
          borderData: FlBorderData(show: false),
        ));
        break;
      case 'piechart':
        body = PieChart(PieChartData(
          sections: [
            for (final s in series)
              PieChartSectionData(value: s.value, title: s.name ?? '', color: s.color, radius: 80, titleStyle: const TextStyle(fontSize: 12, color: Colors.white)),
          ],
        ));
        break;
      case 'linechart':
        body = LineChart(LineChartData(
          lineBarsData: [
            for (final s in series)
              LineChartBarData(
                spots: s.spots,
                color: s.color,
                isCurved: true,
                barWidth: 2,
                dotData: const FlDotData(show: false),
              ),
          ],
          gridData: const FlGridData(show: true),
          borderData: FlBorderData(show: false),
        ));
        break;
      default:
        // 将来加 AreaChart/ScatterChart 等时，未知类型明确占位，而不是悄悄渲染成 LineChart
        body = Center(
          child: Text(
            '⚠ 未知图表类型: ${p.type}',
            style: const TextStyle(color: Colors.red, fontSize: 11),
          ),
        );
    }
    // height 未传时不包 SizedBox，交给外层约束（旧实现硬编码 220 会无视外层高度）
    return height == null ? body : SizedBox(height: height, child: body);
  }

  /// 分组柱的一根组：优先读 values/colors，否则按 name 从 series 取值。
  static List<BarChartRodData> _barRods(Props gp, List<_Series> series) {
    final values = gp.list('values');
    final colors = gp.list('colors');
    if (values.isNotEmpty) {
      return [
        for (var j = 0; j < values.length; j++)
          BarChartRodData(
            toY: Props.toNum(values[j]) ?? 0,
            color: Props.toColor(colors.length > j ? colors[j] : null) ?? Colors.blue,
            width: gp.n('barWidth') ?? 12,
            borderRadius: BorderRadius.circular(4),
          ),
      ];
    }
    final names = gp.list('series');
    if (names.isNotEmpty) {
      final rods = <BarChartRodData>[];
      for (final n in names) {
        final idx = series.indexWhere((e) => e.name == n.toString());
        if (idx < 0) {
          // 名字对不上时柱高为 0，很容易被当成“值为 0”，debug 下明确提示
          if (kDebugMode) {
            debugPrint('Renderer: BarChart groups.series 里找不到名为 "$n" 的 series，该柱按 0 处理');
          }
          rods.add(BarChartRodData(
            toY: 0,
            color: Colors.grey,
            width: gp.n('barWidth') ?? 12,
            borderRadius: BorderRadius.circular(4),
          ));
          continue;
        }
        final s = series[idx];
        rods.add(BarChartRodData(
          toY: s.value,
          color: s.color,
          width: gp.n('barWidth') ?? 12,
          borderRadius: BorderRadius.circular(4),
        ));
      }
      return rods;
    }
    return [
      BarChartRodData(
        toY: gp.n('value') ?? 0,
        color: gp.color('color') ?? Colors.blue,
        width: gp.n('barWidth') ?? 12,
        borderRadius: BorderRadius.circular(4),
      ),
    ];
  }

  // ============================================================
  // 通用结构/属性
  // ============================================================

  /// 节点通用包装：visible / opacity / margin / tooltip / weight / width-height。
  /// 自己会处理这些属性的控件列在 _no*Wrap 里，避免重复注入。
  static Widget _wrapCommon(Widget child, Props p) {
    Widget out = child;
    // 水波纹/高亮/hover/focus 与密度这类「主题级」属性：包一层 Theme，
    // 子树里的 InkWell / 按钮 / 列表项 / TabBar 全都跟着变，不用每个控件各接一遍。
    if (_hasThemePatch(p)) {
      out = _InteractTheme(
        noSplash: _noSplash(p),
        splash: p.color('splashColor'),
        highlight: p.color('highlightColor'),
        hover: p.color('hoverColor'),
        focus: p.color('focusColor'),
        density: Props.toVisualDensity(p['visualDensity']),
        tapTarget: Props.toTapTargetSize(p['tapTargetSize'] ?? p['materialTapTargetSize']),
        child: out,
      );
    }
    if (!_noVisibilityWrap.contains(p.type) && p.has('visible')) {
      out = Visibility(visible: p.b('visible', true), child: out);
    }
    if (!_noOpacityWrap.contains(p.type) && p.has('opacity')) {
      final o = (p.n('opacity') ?? 1.0).clamp(0.0, 1.0);
      if (o < 1.0) out = Opacity(opacity: o, child: out);
    }
    if (!_noMarginWrap.contains(p.type) && p.has('margin')) {
      final m = p.inset('margin');
      if (m != null) out = Padding(padding: m, child: out);
    }
    // 通用 padding：控件自己不吃 padding 时，通用层包一层（Row/Column/Text/Wrap… 都能直接写 padding）
    if (!_noPaddingWrap.contains(p.type) && !_noMarginWrap.contains(p.type) && p.has('padding')) {
      final pd = p.inset('padding');
      if (pd != null) out = Padding(padding: pd, child: out);
    }
    if (!_noTooltipWrap.contains(p.type) && p.has('tooltip')) {
      final t = p.s('tooltip');
      if (t != null && t.isNotEmpty) out = Tooltip(message: t, child: out);
    }
    // 通用点击：控件自身不处理 onTap/onClick 时（如 Card / Container / Text / Row），
    // 这里统一包一层 GestureDetector——否则「给卡片写了 onClick 却没反应」很迷惑。
    if (!_noTapWrap.contains(p.type)) {
      final cb = _voidCallback(p['onTap'], fallback: p.map);
      final lp = _voidCallback(p['onLongPress'] ?? p['onLongClick'], fallback: p.map);
      if (cb != null || lp != null) out = GestureDetector(onTap: cb, onLongPress: lp, child: out);
    }
    // 通用交互事件层：写了的才包，不影响现有手势竞争
    if (_hasInteraction(p)) {
      out = _interactionLayerWidget(out, p);
    }
    final w = p['width'];
    final h = p['height'];
    if (w != null || h != null) {
      out = SizedBox(width: Props.dim(w), height: Props.dim(h), child: out);
    }
    // Expanded 必须在外层：SizedBox(child: Expanded) 里父约束不是 Flex，Expanded 会失效
    final weight = p.n('weight');
    if (weight != null) {
      out = Expanded(flex: weight.round(), child: out);
    }
    return out;
  }

  // 下列控件自己会处理对应属性，_wrapCommon 跳过，避免重复包装。
  static const Set<String> _noVisibilityWrap = {'visibility', 'offstage'};
  static const Set<String> _noOpacityWrap = {'opacity', 'animatedopacity', 'animatedcrossfade'};
  static const Set<String> _noMarginWrap = {
    'container', 'card', 'padding', 'animatedcontainer',
    // 以下控件自带边距/占满宽度的语义，重复包 margin 会改变布局
    'listtile', 'switchlisttile', 'checkboxlisttile', 'radiolisttile', 'expansiontile',
    'appbar', 'sliverappbar', 'bottomappbar',
    'bottomnavigationbar', 'navigationbar', 'navigationrail', 'tabbar',
    'divider', 'verticaldivider',
    'dialog', 'alertdialog', 'simpledialog', 'bottomsheet',
  };
  // 自己处理点击的控件（列进来避免包裹后一次点击发两次事件）
  static const Set<String> _noTapWrap = {
    'inkwell', 'gesturedetector',
    'elevatedbutton', 'textbutton', 'filledbutton', 'outlinedbutton', 'materialbutton',
    'cupertinobutton', 'iconbutton', 'floatingactionbutton',
    'listtile', 'switchlisttile', 'checkboxlisttile', 'radiolisttile', 'expansiontile',
    'chip', 'actionchip', 'filterchip', 'choicechip', 'inputchip',
    'dropdownbutton', 'dropdownbuttonformfield',
  };
  /// 自己会处理 padding 的控件：通用层不再重复包一层，避免双重内边距。
  static const Set<String> _noPaddingWrap = {
    'container', 'card', 'padding', 'sliverpadding', 'animatedpadding', 'animatedcontainer',
    'tabbar', 'textfield', 'textformfield',
    'listtile', 'switchlisttile', 'checkboxlisttile', 'radiolisttile',
    'listview', 'gridview', 'listwheelscrollview', 'reorderablelistview', 'singlechildscrollview',
    'chip', 'actionchip', 'filterchip', 'choicechip', 'inputchip',
    'elevatedbutton', 'textbutton', 'filledbutton', 'outlinedbutton', 'materialbutton',
    'iconbutton', 'cupertinobutton', 'segmentedbutton', 'togglebuttons', 'popupmenubutton',
    'badge', 'snackbar',
  };

  /// 要拆水波纹？`noSplash = true`（或 `splash = false` / `splash = "none"`）。
  static bool _noSplash(Props p) {
    if (p.b('noSplash')) return true;
    final s = p['splash'];
    if (s == false) return true;
    final t = s?.toString().toLowerCase();
    return t == 'none' || t == 'off' || t == 'false';
  }

  /// 通用交互事件：写了下面任意一个，就给该节点包一层手势/鼠标/焦点处理。
  static bool _hasInteraction(Props p) =>
      p.has('onTapDown') ||
      p.has('onTapUp') ||
      p.has('onTapCancel') ||
      p.has('onDoubleTap') ||
      p.has('onSecondaryTap') ||
      p.has('onHover') ||
      p.has('onEnter') ||
      p.has('onExit') ||
      p.has('cursor') ||
      p.has('mouseCursor') ||
      p.has('onFocusChange') ||
      p.has('autofocus');

  static MouseCursor? _cursor(dynamic v) {
    switch (v?.toString().toLowerCase()) {
      case 'click':
      case 'pointer':
        return SystemMouseCursors.click;
      case 'basic':
        return SystemMouseCursors.basic;
      case 'text':
        return SystemMouseCursors.text;
      case 'forbidden':
        return SystemMouseCursors.forbidden;
      case 'grab':
        return SystemMouseCursors.grab;
      case 'grabbing':
        return SystemMouseCursors.grabbing;
      case 'help':
        return SystemMouseCursors.help;
      case 'move':
        return SystemMouseCursors.move;
      case 'none':
        return MouseCursor.defer;
    }
    return null;
  }

  /// 通用交互事件层（对任意控件可用）：
  ///  * 手势：`onTapDown/onTapUp/onTapCancel/onDoubleTap/onSecondaryTap`
  ///  * 鼠标：`onHover/onEnter/onExit/cursor`（cursor 取 click/pointer/text/forbidden/grab…）
  ///  * 焦点：`onFocusChange/autofocus`
  /// 事件名是字符串就调同名 Lua 函数；取位置的事件会带上 x/y。
  static Widget _interactionLayerWidget(Widget child, Props p) {
    Widget out = child;
    final down = p['onTapDown'];
    final up = p['onTapUp'];
    final cancel = p['onTapCancel'];
    final dbl = p['onDoubleTap'];
    final sec = p['onSecondaryTap'];
    if (down != null || up != null || cancel != null || dbl != null || sec != null) {
      out = GestureDetector(
        onTapDown: down == null
            ? null
            : (d) => _emit(down, {'x': d.globalPosition.dx, 'y': d.globalPosition.dy}, fallback: p.map, type: 'tapDown'),
        onTapUp: up == null
            ? null
            : (d) => _emit(up, {'x': d.globalPosition.dx, 'y': d.globalPosition.dy}, fallback: p.map, type: 'tapUp'),
        onTapCancel: cancel == null ? null : () => _emit(cancel, null, fallback: p.map, type: 'tapCancel'),
        onDoubleTap: dbl == null ? null : () => _emit(dbl, null, fallback: p.map, type: 'doubleTap'),
        onSecondaryTap: sec == null ? null : () => _emit(sec, null, fallback: p.map, type: 'secondaryTap'),
        child: out,
      );
    }
    final cursor = _cursor(p['cursor'] ?? p['mouseCursor']);
    final onHover = p['onHover'];
    final onEnter = p['onEnter']; 
    final onExit = p['onExit'];
    if (cursor != null || onHover != null || onEnter != null || onExit != null) {
      out = MouseRegion(
        cursor: cursor ?? MouseCursor.defer,
        onHover: onHover == null
            ? null
            : (e) => _emit(onHover, {'x': e.localPosition.dx, 'y': e.localPosition.dy}, fallback: p.map, type: 'hover'),
        onEnter: onEnter == null ? null : (e) => _emit(onEnter, null, fallback: p.map, type: 'enter'),
        onExit: onExit == null ? null : (e) => _emit(onExit, null, fallback: p.map, type: 'exit'),
        child: out,
      );
    }
    final onFocusChange = p['onFocusChange'];
    if (onFocusChange != null || p.has('autofocus')) {
      out = Focus(
        autofocus: p.b('autofocus'),
        onFocusChange: onFocusChange == null
            ? null
            : (has) => _emit(onFocusChange, has, fallback: p.map, type: 'focusChange'),
        child: out,
      );
    }
    return out;
  }

  static bool _hasThemePatch(Props p) =>
      _noSplash(p) ||
      p.has('splashColor') ||
      p.has('highlightColor') ||
      p.has('hoverColor') ||
      p.has('focusColor') ||
      p.has('visualDensity') ||
      p.has('tapTargetSize') ||
      p.has('materialTapTargetSize');

  /// TabBar 的按下/hover 叠加色：noSplash 时全透明（官方文档推荐的组合写法）。
  static WidgetStateProperty<Color?>? _tabOverlay(Props p) {
    final c = p.color('overlayColor');
    if (c != null) return WidgetStatePropertyAll<Color?>(c);
    if (_noSplash(p)) return const WidgetStatePropertyAll<Color?>(Colors.transparent);
    return null;
  }

  /// 自定义下划线指示器：indicator = { color=, weight=, radius=, insets= }
  static Decoration? _tabIndicator(Props p) {
    final raw = p['indicator'];
    if (raw is! Map) return null;
    final ip = Props.of(raw);
    return UnderlineTabIndicator(
      borderSide: BorderSide(
        color: ip.color('color') ?? const Color(0xFFFFFFFF),
        width: ip.n('weight') ?? 2.0,
      ),
      insets: ip.inset('insets'),
      borderRadius: Props.toBorderRadius(raw['radius']),
    );
  }

  static const Set<String> _noTooltipWrap = {    'tooltip', 'iconbutton', 'floatingactionbutton', 'chip',
    'actionchip', 'filterchip', 'choicechip', 'inputchip', 'materialbutton',
    'button', 'elevatedbutton', 'textbutton', 'filledbutton', 'outlinedbutton',
  };

  static Key? _nodeKey(Props p, String path) {
    final id = p['id'] ?? p['key'];
    if (id != null) return ValueKey('id:$id');
    // 结构路径派生的稳定 key：UI 结构不变时，StatefulWidget 的 State 能跨重建保留，
    // 让 Flutter 自身的 reconciliation 生效，避免每次 render 丢失交互状态。
    //
    // 说明：这里的 path 本身就是“父级 key + 序号”的递归形式（子节点为 parent/i，
    // 插槽为 parent/槽名）。Lua 重排 children 时位置型 key 必然改变、State 无法保留——
    // 需要跨重排保状态就给节点写 id（走上面的 id: 分支）。
    return ValueKey('path:$path');
  }

  static List<Widget> _children(dynamic raw, String path) {
    if (raw is List) {
      final out = <Widget>[];
      for (var i = 0; i < raw.length; i++) {
        final w = _build(raw[i], '$path/$i');
        if (w != null) out.add(w);
      }
      return out;
    }
    if (raw is Map) {
      // 单子节点也要延长 path：否则这一层不算嵌套，深度检查会失效（且 key 会和父节点重合）
      final one = _build(raw, '$path/c');
      return one == null ? [] : [one];
    }
    return [];
  }


  static Widget _widgetOrText(dynamic spec, String fallback, String path) {
    if (spec is Map || spec is List) return _build(spec, path) ?? Text(fallback);
    return Text(fallback);
  }

  static Widget? _slotText(dynamic v, String path) {
    if (v == null) return null;
    if (v is Map || v is List) return _build(v, path);
    return Text(v.toString());
  }

  static Widget? _slotIcon(dynamic v, String path) {
    if (v == null) return null;
    if (v is Map || v is List) return _build(v, path);
    return Icon(Props.toIcon(v));
  }

  static String? _decText(Props p, String key) {
    final d = p['decoration'];
    if (d is Map && d[key] != null) return d[key].toString();
    return p.s(key);
  }

  static PreferredSizeWidget? _preferred(Widget? w) {
    if (w == null) return null;
    if (w is PreferredSizeWidget) return w;
    return PreferredSize(preferredSize: const Size.fromHeight(kToolbarHeight), child: w);
  }

  /// 图片占位：url 缺失或加载失败时显示，避免空白。

  /// 图片控件：统一从 src 取源，Dart 自动判定 network / data(base64) / file / asset。
  static Widget _imageWidget(Props p) {
    final src = (p['src'] ?? p['url'] ?? p['asset'] ?? p['file'])?.toString();
    if (src == null || src.isEmpty) return const SizedBox.shrink();
    final w = Props.dim(p['width']);
    final h = Props.dim(p['height']);
    final fit = Props.toBoxFit(p['fit']);
    final alignment = p.align('alignment') ?? Alignment.center;
    final repeat = Props.toImageRepeat(p['repeat']);
    final color = p.color('imageColor');
    final blend = Props.toBlendMode(p['colorBlendMode']);
    final quality = Props.toFilterQuality(p['filterQuality']);
    final label = p.s('semanticLabel');

    // 加载/解码失败就静默不显示（不弹错误占位），避免干扰布局
    Widget make(ImageProvider provider) => Image(
          image: provider,
          width: w,
          height: h,
          fit: fit,
          alignment: alignment,
          repeat: repeat,
          color: color,
          colorBlendMode: blend,
          filterQuality: quality,
          semanticLabel: label,
          errorBuilder: (c, e, s) => const SizedBox.shrink(),
        );

    Widget img;
    if (src.startsWith('http://') || src.startsWith('https://')) {
      img = make(NetworkImage(src));
    } else if (src.startsWith('data:')) {
      final comma = src.indexOf(',');
      if (comma < 0) return const SizedBox.shrink();
      try {
        img = make(MemoryImage(base64Decode(src.substring(comma + 1))));
      } catch (_) {
        return const SizedBox.shrink();
      }
    } else if (src.startsWith('file://') || src.startsWith('/') || src.startsWith('storage/')) {
      final path = src.startsWith('file://') ? Uri.parse(src).toFilePath() : src;
      img = make(FileImage(File(path)));
    } else {
      img = make(AssetImage(src));
    }

    final radius = p.n('radius') ?? p.n('borderRadius');
    if (radius != null) img = ClipRRect(borderRadius: BorderRadius.circular(radius), child: img);
    return img;
  }

  /// 带名字的事件：有 id 时发出指定 type（用于 stepper 等非点击控件）。
  static VoidCallback? _namedEvent(Props p, String type) {
    final id = p['id'];
    if (id == null) return null;
    final sid = id.toString();
    return () => FlutterBridge.instance.emit(sid, {'id': sid, 'type': type});
  }

  /// DataTable 单元格：子节点或纯文本。
  static Widget _dataCell(dynamic v, String path) {
    if (v is Map || v is List) return _build(v, path) ?? const SizedBox.shrink();
    return Text(v?.toString() ?? '');
  }

  /// 日期解析：支持 ISO 字符串或毫秒时间戳。
  static FloatingActionButtonLocation? _fabLocation(String? v) {
    switch (v?.toLowerCase()) {
      case 'centerfloat': return FloatingActionButtonLocation.centerFloat;
      case 'centerdocked': return FloatingActionButtonLocation.centerDocked;
      case 'centertop': return FloatingActionButtonLocation.centerTop;
      case 'endfloat': return FloatingActionButtonLocation.endFloat;
      case 'enddocked': return FloatingActionButtonLocation.endDocked;
      case 'endtop': return FloatingActionButtonLocation.endTop;
      case 'startfloat': return FloatingActionButtonLocation.startFloat;
      case 'startdocked': return FloatingActionButtonLocation.startDocked;
      case 'starttop': return FloatingActionButtonLocation.startTop;
      default: return null;
    }
  }

  /// 颜色 -> `WidgetStateProperty<Color?>`（Switch/Checkbox 的 thumbColor/trackColor/fillColor 等需要）。
  static WidgetStateProperty<Color?>? _colorState(Props p, String key) {
    final c = p.color(key);
    return c == null ? null : WidgetStatePropertyAll<Color?>(c);
  }

  /// InputDecoration 的边框：字符串（outline/underline/none）或 {type, radius, color, width, side}。
  ///
  /// 默认圆角不一致是 Flutter 自己的默认行为，不是笔误：
  /// UnderlineInputBorder 默认只在上方两个角倒 4（topLeft/topRight），
  /// OutlineInputBorder 默认四角都倒 4；传 radius 时两者都按传入值走。
  /// 输入过滤预设：formatter = "digits" / "number" / "phone" / "none"（也接受列表）  /// 嵌套的 { fontSize=, color=, fontWeight= … } 转 TextStyle
  static TextStyle? _textStyleOrNull(dynamic v) =>
      v is Map ? Props.toTextStyle(Props.of(v)) : null;

  static List<TextInputFormatter>? _textFormatters(Props p) {
    final v = p['formatter'] ?? p['inputFormatter'] ?? p['inputFormatters'];
    if (v == null) return null;
    final items = v is List ? v : <dynamic>[v];
    final out = <TextInputFormatter>[];
    for (final f in items) {
      switch (f.toString().toLowerCase()) {
        case 'digits':
        case 'numberonly':
          out.add(FilteringTextInputFormatter.digitsOnly);
          break;
        case 'number':
        case 'decimal':
          out.add(FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')));
          break;
        case 'phone':
          out.add(FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-() ]')));
          break;
      }
    }
    return out.isEmpty ? null : out;
  }

  static InputBorder? _inputBorder(Props p, String key) {
    final v = p[key];
    if (v == null) return null;
    String type = 'outline';
    double? radius;
    BorderSide? side;
    if (v is Map) {
      final m = Props.of(v);
      type = (m.s('type') ?? 'outline').toString().toLowerCase();
      radius = m.n('radius');
      side = _borderSide(m['side'] ?? m['borderSide']);
      if (side == null && (m.has('color') || m.has('width'))) {
        side = BorderSide(color: m.color('color') ?? Colors.black26, width: m.n('width') ?? 1);
      }
    } else {
      type = v.toString().toLowerCase();
    }
    switch (type) {
      case 'none':
        return InputBorder.none;
      case 'underline':
        return UnderlineInputBorder(
          borderRadius: radius != null
              ? BorderRadius.circular(radius)
              : const BorderRadius.only(topLeft: Radius.circular(4), topRight: Radius.circular(4)),
          borderSide: side ?? const BorderSide(),
        );
      default:
        return OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius ?? 4),
          borderSide: side ?? const BorderSide(),
        );
    }
  }

  static FloatingLabelBehavior? _floatingLabel(String? v) {
    switch (v?.toLowerCase()) {
      case 'always': return FloatingLabelBehavior.always;
      case 'never': return FloatingLabelBehavior.never;
      case 'auto': return FloatingLabelBehavior.auto;
      default: return null;
    }
  }

  /// 日期解析：委托给 Props.toDate（通用能力，其他地方也能用）。
  static DateTime? _parseDate(dynamic v) => Props.toDate(v);

  static BoxConstraints _constraints(Props p) => BoxConstraints(
        minWidth: p.nz('minWidth'),
        maxWidth: p.n('maxWidth') ?? double.infinity,
        minHeight: p.nz('minHeight'),
        maxHeight: p.n('maxHeight') ?? double.infinity,
      );

  /// 变换矩阵：接受 16 个数字的列表，或 {translateX/Y/Z, scaleX/Y, rotateZ} 形式的简易描述。
  static Matrix4? _matrix4(dynamic v) {
    if (v is List && v.length == 16) {
      final n = v.map(Props.toNum).whereType<double>().toList();
      if (n.length == 16) return Matrix4.fromList(n);
    }
    if (v is Map) {
      final m = v.cast<String, dynamic>();
      final t = Matrix4.identity();
      final tx = Props.toNum(m['translateX']);
      final ty = Props.toNum(m['translateY']);
      final sx = Props.toNum(m['scaleX']);
      final sy = Props.toNum(m['scaleY']);
      final rz = Props.toNum(m['rotateZ']);
      if (sx != null || sy != null) t.scaleByDouble(sx ?? 1.0, sy ?? 1.0, 1.0, 1.0);
      if (rz != null) t.rotateZ(rz);
      if (tx != null || ty != null) t.translateByDouble(tx ?? 0.0, ty ?? 0.0, 0.0, 1.0);
      return t;
    }
    return null;
  }

  static Offset? _offset(dynamic v) {
    if (v is List && v.length >= 2) {
      return Offset(Props.toNum(v[0]) ?? 0, Props.toNum(v[1]) ?? 0);
    }
    return null;
  }

  // ---------- 回調 ----------

  /// 点击处理：优先显式 onTap；否则若有 id，则按 id 发事件（供 Lua 侧 h.onClick 风格）。
  static VoidCallback? _tapHandler(Props p) {
    final t = p['onTap'];
    if (t != null) return _voidCallback(t, fallback: p.map);
    final id = p['id'];
    if (id != null) {
      final sid = id.toString();
      return () => FlutterBridge.instance.emit(sid, {'id': sid, 'type': 'click'});
    }
    return null;
  }

  /// 变化处理：优先显式 onChange；否则若有 id，则按 id 发 change 事件。
  static void _change(Props p, dynamic value) {
    final c = p['onChange'];
    if (c != null) {
      _emit(c, value, fallback: p.map, type: 'change');
      return;
    }
    final id = p['id'];
    if (id != null) {
      FlutterBridge.instance.emit(id.toString(), {'id': id.toString(), 'type': 'change', 'value': value});
    }
  }

  static VoidCallback? _voidCallback(dynamic onTap, {Map<String, dynamic>? fallback}) {
    if (onTap == null) return null;
    final action = onTap;
    return () {
      if (action is String) {
        // 字符串形式：只发事件，事件名 = 该名字（AndroLua 风格：点击调用同名 Lua 函数）
        FlutterBridge.instance.emit(action, {'action': action, 'type': 'click'});
      } else if (action is Map) {
        final m = action.cast<String, dynamic>();
        final method = (m['call'] ?? m['method'] ?? '').toString();
        final args = m['args'] is Map ? (m['args'] as Map).cast<String, dynamic>() : null;
        dynamic res;
        if (method.isNotEmpty) {
          // 若同名 Dart 方法存在就调用（不存在返回 error，不影响事件名）
          res = FlutterBridge.instance.invoke(method, args);
          if (res is Future) res = null;
        }
        // 事件名默认 = 方法名（而非固定 onTap），可用 event/事件 显式覆盖
        final event = (m['event'] ?? m['emit'] ?? method).toString();
        FlutterBridge.instance.emit(
          event.isEmpty ? 'onTap' : event,
          {'action': method, 'args': args, 'result': res, 'type': 'click'},
        );
      }
    };
  }

  /// 发出事件。type 会放进 data.type（'change' / 'click'），方便接收方统一判断；
  /// 以前只有 id 句柄分支带 type，声明式分支不带，导致 data.type 为 nil。
  static void _emit(dynamic spec, dynamic value, {Map<String, dynamic>? fallback, String? type}) {
    final method = spec is Map ? (spec['call'] ?? spec['method'])?.toString() : null;
    // 事件名：显式 event/emit > 字符串本身 > 方法名 > 'onChange'
    final name = spec is Map
        ? (spec['event'] ?? spec['emit'] ?? method)?.toString()
        : spec?.toString();
    dynamic res;
    if (method != null && method.isNotEmpty) {
      final a = spec is Map ? spec['args'] : null;
      res = FlutterBridge.instance.invoke(method, a is Map ? a.cast<String, dynamic>() : null);
      if (res is Future) res = null;
    }
    FlutterBridge.instance.emit(
      (name == null || name.isEmpty) ? 'onChange' : name,
      {'value': value, 'result': res, 'type': ?type},
    );
  }

  // ---------- 装饰 / 样式 ----------

  static BoxDecoration? _decoration(Props p) {
    final dp = Props.of(p['decoration']);
    final color = dp.color('color') ?? p.color('color') ?? p.color('backgroundColor');
    final gradient = Props.toAnyGradient(dp['gradient'] ?? p['gradient']);
    final radius = dp.n('radius') ?? dp.n('borderRadius') ?? p.n('radius') ?? p.n('borderRadius');
    final border = _decoBorder(dp, p);
    final shadows = Props.toShadows(dp['boxShadow'] ?? dp['shadows'] ?? p['boxShadow'] ?? p['shadows']);
    final shape = dp.s('shape') ?? p.s('shape');
    if (color == null && gradient == null && radius == null && border == null && shadows == null && shape == null) {
      return null;
    }
    final boxShape = Props.toBoxShape(shape ?? 'rectangle');
    return BoxDecoration(
      color: color,
      gradient: gradient,
      shape: boxShape,
      borderRadius: (boxShape == BoxShape.rectangle && radius != null) ? BorderRadius.circular(radius) : null,
      border: border,
      boxShadow: shadows,
    );
  }

  static BoxBorder? _decoBorder(Props dp, Props p) {
    BorderSide side(dynamic s) {
      final sm = s is Map ? s.cast<String, dynamic>() : <String, dynamic>{};
      return BorderSide(color: Props.toColor(sm['color']) ?? Colors.black26, width: Props.toNum(sm['width']) ?? 1);
    }
    final all = dp['border'] ?? dp['all'] ?? p['border'];
    if (all is Map) {
      final a = all.cast<String, dynamic>();
      return Border.all(color: Props.toColor(a['color']) ?? Colors.black26, width: Props.toNum(a['width']) ?? 1);
    }
    final bb = dp['borderBottom'] ?? p['borderBottom'];
    final bt = dp['borderTop'] ?? p['borderTop'];
    if (bb is Map || bt is Map) {
      return Border(
        top: bt is Map ? side(bt) : BorderSide.none,
        bottom: bb is Map ? side(bb) : BorderSide.none,
      );
    }
    final bw = p.n('borderWidth');
    if (bw != null) return Border.all(color: p.color('borderColor') ?? Colors.black26, width: bw);
    return null;
  }

  static ButtonStyle? _buttonStyle(Props p) {
    final sp = Props.of(p['style']);
    final bg = sp.color('backgroundColor') ?? p.color('backgroundColor');
    final fg = sp.color('foregroundColor') ?? p.color('foregroundColor');
    final pad = sp.inset('padding') ?? p.inset('padding');
    final el = sp.n('elevation') ?? p.n('elevation');
    final shadow = sp.color('shadowColor') ?? p.color('shadowColor');
    final overlay = sp.color('overlayColor') ?? p.color('overlayColor');
    final surface = sp.color('surfaceTintColor') ?? p.color('surfaceTintColor');
    final radius = sp.n('radius') ?? sp.n('borderRadius') ?? p.n('radius') ?? p.n('borderRadius');
    final shapeName = sp.s('shape') ?? p.s('shape');
    final shape = Props.toShape(shapeName, radius);
    final side = _borderSide(sp['side'] ?? p['side']);
    final minSize = _size(sp['minimumSize'] ?? p['minimumSize']);
    final fixedSize = _size(sp['fixedSize'] ?? p['fixedSize']);
    final maxSize = _size(sp['maximumSize'] ?? p['maximumSize']);
    final textStyle = (sp['textStyle'] ?? p['textStyle']) != null
        ? Props.toTextStyle(Props.of(sp['textStyle'] ?? p['textStyle']))
        : null;
    final tapTarget = p.has('tapTargetSize')
        ? (p.s('tapTargetSize')?.toLowerCase() == 'shrinkwrap'
            ? MaterialTapTargetSize.shrinkWrap
            : MaterialTapTargetSize.padded)
        : null;
    final density = p.list('visualDensity');
    final visualDensity = density.length == 2
        ? VisualDensity(horizontal: Props.toNum(density[0]) ?? 0, vertical: Props.toNum(density[1]) ?? 0)
        : null;
    if (bg == null && fg == null && pad == null && el == null && shadow == null && overlay == null &&
        surface == null && shape == null && side == null && minSize == null && fixedSize == null &&
        maxSize == null && textStyle == null && tapTarget == null && visualDensity == null && !p.has('animationDuration')) {
      return null;
    }
    return ButtonStyle(
      backgroundColor: bg != null ? WidgetStatePropertyAll<Color>(bg) : null,
      foregroundColor: fg != null ? WidgetStatePropertyAll<Color>(fg) : null,
      overlayColor: overlay != null ? WidgetStatePropertyAll<Color>(overlay) : null,
      shadowColor: shadow != null ? WidgetStatePropertyAll<Color>(shadow) : null,
      surfaceTintColor: surface != null ? WidgetStatePropertyAll<Color>(surface) : null,
      padding: pad != null ? WidgetStatePropertyAll<EdgeInsetsGeometry>(pad) : null,
      elevation: el != null ? WidgetStatePropertyAll<double>(el) : null,
      shape: shape != null ? WidgetStatePropertyAll<OutlinedBorder>(shape) : null,
      side: side != null ? WidgetStatePropertyAll<BorderSide>(side) : null,
      minimumSize: minSize != null ? WidgetStatePropertyAll<Size>(minSize) : null,
      fixedSize: fixedSize != null ? WidgetStatePropertyAll<Size>(fixedSize) : null,
      maximumSize: maxSize != null ? WidgetStatePropertyAll<Size>(maxSize) : null,
      textStyle: textStyle != null ? WidgetStatePropertyAll<TextStyle>(textStyle) : null,
      tapTargetSize: tapTarget,
      visualDensity: visualDensity,
      animationDuration: p.has('animationDuration') ? Props.toDuration(p['animationDuration']) : null,
    );
  }

  /// [宽, 高] -> Size。
  static Size? _size(dynamic v) {
    if (v is List && v.length >= 2) {
      return Size(Props.toNum(v[0]) ?? 0, Props.toNum(v[1]) ?? 0);
    }
    return null;
  }

  /// 边框线：{color, width, style}。
  static BorderSide? _borderSide(dynamic v) {
    if (v is! Map) return null;
    final m = v.cast<String, dynamic>();
    if (m.isEmpty) return null;
    return BorderSide(
      color: Props.toColor(m['color']) ?? Colors.black26,
      width: Props.toNum(m['width']) ?? 1,
      style: Props.toBorderStyle(m['style']),
    );
  }

  static List<DropdownMenuItem<String>> _dropdownItems(dynamic raw) {
    return Props.toList(raw).map((e) {
      final ip = Props.of(e);
      final value = (ip['value'] ?? ip['text'] ?? '').toString();
      return DropdownMenuItem<String>(value: value, child: Text((ip['text'] ?? ip['value'] ?? '').toString()));
    }).toList();
  }
}

/// 图表数据序列。
class _Series {
  _Series(this.name, this.color, this.value, this.spots);

  final String? name;
  final Color color;
  final double value;
  final List<FlSpot> spots;

  static _Series of(dynamic raw) {
    final p = Props.of(raw);
    final points = p.list('points');
    final spots = <FlSpot>[];
    if (points.isNotEmpty) {
      for (var i = 0; i < points.length; i++) {
        final pt = points[i];
        if (pt is Map) {
          final pp = Props.of(pt);
          spots.add(FlSpot(pp.n('x') ?? i.toDouble(), pp.n('y') ?? 0));
        } else {
          spots.add(FlSpot(i.toDouble(), Props.toNum(pt) ?? 0));
        }
      }
    }
    return _Series(
      p.s('name') ?? p.s('label'),
      p.color('color') ?? Colors.blue,
      p.n('value') ?? (spots.isNotEmpty ? spots.last.y : 1),
      spots,
    );
  }
}

// ============================================================
// 有状态交互控件
// ============================================================

class BridgeSwitch extends StatefulWidget {
  const BridgeSwitch({super.key, required this.p, required this.onChanged});
  final Props p;
  final ValueChanged<bool> onChanged;
  @override
  State<BridgeSwitch> createState() => _BridgeSwitchState();
}

class _BridgeSwitchState extends State<BridgeSwitch> {
  late bool _value = widget.p.b('value');
  @override
  void didUpdateWidget(BridgeSwitch old) {
    super.didUpdateWidget(old);
    final next = widget.p.b('value');
    if (next != old.p.b('value')) setState(() => _value = next);
  }
  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    return Switch(
      value: _value,
      activeThumbColor: p.color('activeThumbColor') ?? p.color('activeColor'),
      activeTrackColor: p.color('activeTrackColor'),
      inactiveThumbColor: p.color('inactiveThumbColor'),
      inactiveTrackColor: p.color('inactiveTrackColor'),
      thumbColor: Renderer._colorState(p, 'thumbColor'),
      trackColor: Renderer._colorState(p, 'trackColor'),
      trackOutlineColor: Renderer._colorState(p, 'trackOutlineColor'),
      focusColor: p.color('focusColor'),
      hoverColor: p.color('hoverColor'),
      autofocus: p.b('autofocus'),
      onChanged: p.b('enabled', true)
          ? (v) { setState(() => _value = v); widget.onChanged(v); }
          : null,
    );
  }
}

class BridgeCheckbox extends StatefulWidget {
  const BridgeCheckbox({super.key, required this.p, required this.onChanged});
  final Props p;
  final ValueChanged<bool> onChanged;
  @override
  State<BridgeCheckbox> createState() => _BridgeCheckboxState();
}

class _BridgeCheckboxState extends State<BridgeCheckbox> {
  late bool _value = widget.p.b('value');
  @override
  void didUpdateWidget(BridgeCheckbox old) {
    super.didUpdateWidget(old);
    final next = widget.p.b('value');
    if (next != old.p.b('value')) setState(() => _value = next);
  }
  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    return Checkbox(
      value: _value,
      tristate: p.b('tristate'),
      activeColor: p.color('activeColor'),
      fillColor: Renderer._colorState(p, 'fillColor'),
      checkColor: p.color('checkColor'),
      focusColor: p.color('focusColor'),
      hoverColor: p.color('hoverColor'),
      side: Renderer._borderSide(p['side']),
      shape: Props.toShape(p.s('shape'), p.n('radius')),
      autofocus: p.b('autofocus'),
      isError: p.b('isError'),
      semanticLabel: p.s('semanticLabel'),
      onChanged: p.b('enabled', true)
          ? (v) { setState(() => _value = v == true); widget.onChanged(v == true); }
          : null,
    );
  }
}

class BridgeSwitchListTile extends StatefulWidget {
  const BridgeSwitchListTile({super.key, this.title, this.subtitle, required this.initial, required this.onChanged});
  final String? title;
  final String? subtitle;
  final bool initial;
  final ValueChanged<bool> onChanged;
  @override
  State<BridgeSwitchListTile> createState() => _BridgeSwitchListTileState();
}

class _BridgeSwitchListTileState extends State<BridgeSwitchListTile> {
  late bool _value = widget.initial;
  @override
  void didUpdateWidget(BridgeSwitchListTile old) {
    super.didUpdateWidget(old);
    if (widget.initial != old.initial) setState(() => _value = widget.initial);
  }
  @override
  Widget build(BuildContext context) => SwitchListTile(
        title: widget.title == null ? null : Text(widget.title!),
        subtitle: widget.subtitle == null ? null : Text(widget.subtitle!),
        value: _value,
        onChanged: (v) { setState(() => _value = v); widget.onChanged(v); },
      );
}

class BridgeCheckboxListTile extends StatefulWidget {
  const BridgeCheckboxListTile({super.key, this.title, this.subtitle, required this.initial, required this.onChanged});
  final String? title;
  final String? subtitle;
  final bool initial;
  final ValueChanged<bool> onChanged;
  @override
  State<BridgeCheckboxListTile> createState() => _BridgeCheckboxListTileState();
}

class _BridgeCheckboxListTileState extends State<BridgeCheckboxListTile> {
  late bool _value = widget.initial;
  @override
  void didUpdateWidget(BridgeCheckboxListTile old) {
    super.didUpdateWidget(old);
    if (widget.initial != old.initial) setState(() => _value = widget.initial);
  }
  @override
  Widget build(BuildContext context) => CheckboxListTile(
        title: widget.title == null ? null : Text(widget.title!),
        subtitle: widget.subtitle == null ? null : Text(widget.subtitle!),
        value: _value,
        onChanged: (v) { setState(() => _value = v == true); widget.onChanged(v == true); },
      );
}

class BridgeSlider extends StatefulWidget {
  const BridgeSlider({super.key, required this.p, required this.onChanged});
  final Props p;
  final ValueChanged<double> onChanged;
  @override
  State<BridgeSlider> createState() => _BridgeSliderState();
}

class _BridgeSliderState extends State<BridgeSlider> {
  late double _value = widget.p.n('value') ?? 0;
  @override
  void didUpdateWidget(BridgeSlider old) {
    super.didUpdateWidget(old);
    final next = widget.p.n('value');
    if (next != null && next != old.p.n('value')) setState(() => _value = next);
  }
  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final min = p.n('min') ?? 0;
    final max = p.n('max') ?? 1;
    return Slider(
      value: _value.clamp(min, max <= min ? min + 1 : max),
      min: min,
      max: max <= min ? min + 1 : max,
      divisions: p.i('divisions'),
      label: p.s('label'),
      activeColor: p.color('activeColor'),
      inactiveColor: p.color('inactiveColor'),
      thumbColor: p.color('thumbColor'),
      secondaryActiveColor: p.color('secondaryActiveColor'),
      autofocus: p.b('autofocus'),
      onChanged: p.b('enabled', true)
          ? (v) { setState(() => _value = v); widget.onChanged(v); }
          : null,
    );
  }
}

class BridgeTextField extends StatefulWidget {
  const BridgeTextField({super.key, required this.p, required this.onChanged, this.onSubmitted});
  final Props p;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;
  @override
  State<BridgeTextField> createState() => _BridgeTextFieldState();
}

class _BridgeTextFieldState extends State<BridgeTextField> {
  late final String? _id = widget.p['id']?.toString();
  late final TextEditingController _controller = _id != null
      ? FlutterControl.text(_id!, initial: widget.p.s('text') ?? '')
      : TextEditingController(text: widget.p.s('text') ?? '');

  @override
  void didUpdateWidget(BridgeTextField old) {
    super.didUpdateWidget(old);
    // 受控：Lua 回写 text 且与当前内容不同时更新（避免输入中被打断）。
    final next = widget.p.s('text') ?? '';
    final prev = old.p.s('text') ?? '';
    if (next != prev && _controller.text != next) {
      _controller.text = next;
    }
  }
  @override
  void dispose() { if (_id == null) _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final obscure = p.b('obscure') || p.b('obscureText') || p.b('password');
    return TextField(
      controller: _controller,
      focusNode: _id != null ? FlutterControl.focusNode(_id!) : null,
      decoration: InputDecoration(
        hintText: p.s('hint') ?? p.s('hintText'),
        labelText: p.s('label') ?? p.s('labelText'),
        helperText: p.s('helperText'),
        errorText: p.s('errorText'),
        counterText: p.s('counterText'),
        prefixText: p.s('prefixText'),
        suffixText: p.s('suffixText'),
        prefixIcon: p['prefixIcon'] != null ? Icon(Props.toIcon(p['prefixIcon'])) : null,
        suffixIcon: p['suffixIcon'] != null ? Icon(Props.toIcon(p['suffixIcon'])) : null,
        filled: p.has('filled') ? p.b('filled') : (p.has('fillColor') ? true : null),
        fillColor: p.color('fillColor'),
        contentPadding: p.inset('contentPadding'),
        border: Renderer._inputBorder(p, 'border'),
        enabledBorder: Renderer._inputBorder(p, 'enabledBorder'),
        focusedBorder: Renderer._inputBorder(p, 'focusedBorder'),
        errorBorder: Renderer._inputBorder(p, 'errorBorder'),
        disabledBorder: Renderer._inputBorder(p, 'disabledBorder'),
        focusedErrorBorder: Renderer._inputBorder(p, 'focusedErrorBorder'),
        floatingLabelBehavior: Renderer._floatingLabel(p.s('floatingLabelBehavior')),
        alignLabelWithHint: p.has('alignLabelWithHint') ? p.b('alignLabelWithHint') : null,
        isDense: p.has('isDense') ? p.b('isDense') : null,
        hintMaxLines: p.i('hintMaxLines'),
        errorMaxLines: p.i('errorMaxLines'),
        helperMaxLines: p.i('helperMaxLines'),
      ),
      keyboardType: Props.toKeyboardType(p['keyboardType'] ?? p['inputType']),
      textInputAction: Props.toInputAction(p['textInputAction']),
      textCapitalization: Props.toTextCapitalization(p['textCapitalization']),
      textAlign: Props.toTextAlign(p['textAlign']),
      style: Props.toTextStyle(p),
      cursorColor: p.color('cursorColor'),
      cursorWidth: p.n('cursorWidth') ?? 2.0,
      cursorHeight: p.n('cursorHeight'),
      cursorRadius: p.n('cursorRadius') != null ? Radius.circular(p.n('cursorRadius')!) : null,
      showCursor: p.has('showCursor') ? p.b('showCursor', true) : null,
      autofocus: p.b('autofocus'),
      obscureText: obscure,
      autocorrect: p.b('autocorrect', true),
      enableSuggestions: p.b('enableSuggestions', true),
      maxLines: obscure ? 1 : (p.i('maxLines') ?? 1),
      minLines: p.i('minLines'),
      maxLength: p.i('maxLength'),
      readOnly: p.b('readOnly'),
      enabled: p.b('enabled', true),
      enableInteractiveSelection:
          p.has('enableInteractiveSelection') ? p.b('enableInteractiveSelection', true) : null,
      autofillHints: p.list('autofillHints')?.map((e) => e.toString()).toList(),
      keyboardAppearance: switch (p.s('keyboardAppearance')?.toLowerCase()) {
        'dark' => Brightness.dark,
        'light' => Brightness.light,
        _ => null,
      },
      textAlignVertical: switch (p.s('textAlignVertical')?.toLowerCase()) {
        'top' => TextAlignVertical.top,
        'bottom' => TextAlignVertical.bottom,
        'center' => TextAlignVertical.center,
        _ => null,
      },
      expands: p.has('expands') ? p.b('expands') : null,
      maxLengthEnforcement: switch (p.s('maxLengthEnforcement')?.toLowerCase()) {
        'enforced' => MaxLengthEnforcement.enforced,
        'truncate' || 'truncateaftercompositionends' => MaxLengthEnforcement.truncateAfterCompositionEnds,
        'none' => MaxLengthEnforcement.none,
        _ => null,
      },
      inputFormatters: Renderer._textFormatters(p),
      cursorErrorColor: p.color('cursorErrorColor'),
      scrollPadding: p.inset('scrollPadding'),
      canRequestFocus: p.has('canRequestFocus') ? p.b('canRequestFocus') : null,
      dragStartBehavior: p.s('dragStartBehavior')?.toLowerCase() == 'start' ? DragStartBehavior.start : null,
      clipBehavior: p.has('clipBehavior') ? Props.toClip(p['clipBehavior']) : null,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
    );
  }
}

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

  @override
  void didUpdateWidget(BridgeBottomNav old) {
    super.didUpdateWidget(old);
    if (widget.initialIndex != old.initialIndex) setState(() => _index = widget.initialIndex);
  }

  List<BottomNavigationBarItem> _items() {
    return widget.items.map((e) {
      final ip = Props.of(e);
      return BottomNavigationBarItem(
        icon: Icon(Props.toIcon(ip['icon'])),
        label: (ip['label'] ?? ip['text'])?.toString(),
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
      onTap: (i) { setState(() => _index = i); widget.onTap?.call(i); },
      items: _items(),
    );
  }
}

class BridgeDropdown extends StatefulWidget {
  const BridgeDropdown({super.key, required this.p, required this.onChanged});
  final Props p;
  final ValueChanged<String?> onChanged;
  @override
  State<BridgeDropdown> createState() => _BridgeDropdownState();
}

class _BridgeDropdownState extends State<BridgeDropdown> {
  late String? _value = widget.p.s('value');
  @override
  void didUpdateWidget(BridgeDropdown old) {
    super.didUpdateWidget(old);
    if (widget.p.s('value') != old.p.s('value')) setState(() => _value = widget.p.s('value'));
  }
  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    return DropdownButton<String>(
      value: _value,
      items: Renderer._dropdownItems(p['items']),
      isExpanded: p.b('isExpanded'),
      isDense: p.b('isDense'),
      icon: p['icon'] != null ? Icon(Props.toIcon(p['icon'])) : null,
      iconSize: p.n('iconSize') ?? 24,
      iconDisabledColor: p.color('iconDisabledColor'),
      iconEnabledColor: p.color('iconEnabledColor'),
      elevation: p.i('elevation') ?? 8,
      style: Props.toTextStyle(p),
      alignment: p.align('alignment') ?? AlignmentDirectional.centerStart,
      dropdownColor: p.color('dropdownColor'),
      hint: p['hint'] != null ? Text(p['hint'].toString()) : null,
      focusColor: p.color('focusColor'),
      borderRadius: Props.toBorderRadius(p['borderRadius'] ?? p['radius']),
      itemHeight: p.n('itemHeight'),
      onChanged: p.b('enabled', true)
          ? (v) { setState(() => _value = v); widget.onChanged(v); }
          : null,
    );
  }
}

/// Flutter 视频播放器控制注册表：spec 的 `id` -> 内部状态。
/// Lua 通过 `dartCall('flutterVideo', { id=, action=, ... })` 控制，
/// 事件以 `flutterVideoEvent` 回传（Lua 用 onFlutterEvent 接收）。
class FlutterVideo {
  static final Map<String, _BridgeVideoState> _states = {};

  static void attach(String id, _BridgeVideoState s) => _states[id] = s;

  static void detach(String id, _BridgeVideoState s) {
    if (identical(_states[id], s)) _states.remove(id);
  }

  /// id 不是视频时返回 null（供 FlutterControl 统一分发）。
  static Future<Map<String, dynamic>?> tryCall(Map<String, dynamic> a) async {
    final s = _states[(a['id'] ?? '').toString()];
    if (s == null) return null;
    final action = (a['action'] ?? '').toString();
    if (action.isEmpty) return {'error': 'need action'};
    return s.control(action, a);
  }

  /// 供逻辑层 dartCall('flutterVideo', ...) 直接调用。
  static Future<Map<String, dynamic>> call(Map<String, dynamic>? a) async {
    final args = a ?? const <String, dynamic>{};
    final id = (args['id'] ?? '').toString();
    if (id.isEmpty) return {'error': 'need id'};
    final r = await tryCall(args);
    return r ?? {'error': 'no such video: $id'};
  }

  static void emitEvent(String? id, String type, Map<String, dynamic> data) {
    FlutterBridge.instance.emit('flutterVideoEvent', {'id': id, 'type': type, ...data});
  }

  static void emitState(String? id, _BridgeVideoState s) => emitEvent(id, 'ready', s.stateMap());
}

/// 音频播放器控制注册表（just_audio）。用法与 FlutterVideo 相同：
/// `dartCall('flutterControl', {id=, action=, ...})`，事件名 `flutterAudioEvent`。
class FlutterAudio {
  static final Map<String, _BridgeAudioState> _states = {};

  static void attach(String id, _BridgeAudioState s) => _states[id] = s;

  static void detach(String id, _BridgeAudioState s) {
    if (identical(_states[id], s)) _states.remove(id);
  }

  static Future<Map<String, dynamic>?> tryCall(Map<String, dynamic> a) async {
    final s = _states[(a['id'] ?? '').toString()];
    if (s == null) return null;
    final action = (a['action'] ?? '').toString();
    if (action.isEmpty) return {'error': 'need action'};
    return s.control(action, a);
  }

  static void emitEvent(String? id, String type, Map<String, dynamic> data) {
    FlutterBridge.instance.emit('flutterAudioEvent', {'id': id, 'type': type, ...data});
  }
}

/// Flutter 控件的统一控制中心（命令式）。
///
/// 分工：
///  * **属性**改动：Lua 用 `id.dart.属性 = 值`（原生 patchNode → Dart 定点重建），全控件通用；
///  * **命令**（滚动/翻页/文本框/媒体/抽屉）：改属性做不到，走这里，
///    Lua 调 `dartCall('flutterControl', { id=, action=, ... })`。
///
/// 动作：
///  * 滚动（ListView/GridView/SingleChildScrollView/CustomScrollView）：
///    `scrollTo(offset)` `animatedScrollTo(offset,duration)` `scrollBy(delta)`
///    `scrollToEnd` `scrollToStart` `scrollState`
///  * 翻页（PageView）：`pageTo(index)` `nextPage` `prevPage` `pageState`
///  * 标签页（DefaultTabController，需带 id）：`tabTo(index)` `nextTab` `prevTab` `tabState`
///  * 文本框（TextField/TextFormField）：`setText(text)` `clear` `focus` `unfocus` `textState`
///  * 媒体：VideoPlayer（play/pause/toggle/seek/seekPercent/volume/speed/loop/state）
///    与 AudioPlayer（多一个 stop）；`listenProgress(enabled, interval)` 开启/关闭**持续监听**：
///    每隔 interval 毫秒（默认 500）推一个 `flutterVideoEvent`/`flutterAudioEvent`(type=progress)，
///    带 position/duration/buffered/isPlaying/isBuffering，用于进度条/时间轴。
///  * 下拉刷新（RefreshIndicator）：`refresh`
///  * 抽屉：`openDrawer` `closeDrawer`
///
/// 另外这些“只认初始值”的控件已改成**可运行期改**（改属性即生效）：
///  * DefaultTabController：`tabs.dart.Index = n` 切页（复用同一个 controller 做动画，指示器不再瞬移）
///  * ExpansionTile：`tile.dart.Expanded = true/false` 展开/收起
class FlutterControl {
  static final Map<String, ScrollController> _scrolls = {};
  static final Map<String, TabController> _tabs = {};
  static final Map<String, PageController> _pages = {};
  static final Map<String, TextEditingController> _texts = {};
  static final Map<String, FocusNode> _focusNodes = {};
  static final Map<String, GlobalKey<RefreshIndicatorState>> _refreshKeys = {};

  static GlobalKey<RefreshIndicatorState> refreshKey(String id) =>
      _refreshKeys.putIfAbsent(id, () => GlobalKey<RefreshIndicatorState>());

  static ScrollController scroll(String id) => _scrolls.putIfAbsent(id, () => ScrollController());

  static PageController page(String id, {int initial = 0}) =>
      _pages.putIfAbsent(id, () => PageController(initialPage: initial));

  static TextEditingController text(String id, {String initial = ''}) =>
      _texts.putIfAbsent(id, () => TextEditingController(text: initial));

  static FocusNode focusNode(String id) => _focusNodes.putIfAbsent(id, () => FocusNode());

  /// DefaultTabController 建好控制器后登记进来，供 tabTo/nextTab/prevTab/tabState 使用。
  static void registerTab(String id, TabController controller) => _tabs[id] = controller;

  static TabController? tabOf(String id) => _tabs[id];

  static void unregisterTab(String id) => _tabs.remove(id);

  /// 手动释放某个 id 的全部控制器。一般不用：正常由 _IdNode 的引用计数 +
  /// 整页重建时的 markAlive 自动回收（见下）。
  static void release(String id) => _releaseNow(id);

  // ---------- 生命周期：引用计数 + 整页重建时回收 ----------
  // 这些控制器是「按 id 复用」的（同一 id 重渲染要复用，否则滚动位置/输入内容全丢），
  // 所以不能在控件 dispose 时直接释放（列表回收、切标签页都会 dispose）。
  // 策略：节点挂载 retain、卸载 unmount；整页重建后 markAlive 告知当前布局里还有哪些 id，
  // 只有「引用归零 且 已不在布局里」的才真正释放。
  static final Map<String, int> _refs = {};
  static Set<String> _alive = const {};

  /// 节点挂载（_IdNode 调用）。
  static void retain(String id) => _refs[id] = (_refs[id] ?? 0) + 1;

  /// 节点卸载（_IdNode 调用）。
  static void unmount(String id) {
    final n = (_refs[id] ?? 1) - 1;
    _refs[id] = n < 0 ? 0 : n;
    _sweep();
  }

  /// 整页重建后告知当前 spec 里还有哪些 id。
  static void markAlive(Set<String> ids) {
    _alive = ids;
    _sweep();
  }

  static void _sweep() {
    for (final id in _refs.keys.toList()) {
      if ((_refs[id] ?? 0) <= 0 && !_alive.contains(id)) _releaseNow(id);
    }
  }

  static void _releaseNow(String id) {
    _refs.remove(id);
    _scrolls.remove(id)?.dispose();
    _pages.remove(id)?.dispose();
    _texts.remove(id)?.dispose();
    _focusNodes.remove(id)?.dispose();
    _refreshKeys.remove(id);
    _tabs.remove(id);
  }

  static Future<Map<String, dynamic>> call(Map<String, dynamic>? a) async {
    final args = a ?? const <String, dynamic>{};
    final id = (args['id'] ?? '').toString();
    final action = (args['action'] ?? '').toString();
    if (id.isEmpty || action.isEmpty) return {'error': 'need id and action'};

    // 1) 媒体：视频 → 音频
    final media = await FlutterVideo.tryCall(args);
    if (media != null) return media;
    final audio = await FlutterAudio.tryCall(args);
    if (audio != null) return audio;

    // 2) 滚动
    final sc = _scrolls[id];
    if (sc != null && sc.hasClients) {
      final pos = sc.position;
      double clamp(double v) => v.clamp(pos.minScrollExtent, pos.maxScrollExtent);
      const dur = Duration(milliseconds: 300);
      switch (action) {
        case 'scrollTo':
          sc.jumpTo(clamp((args['offset'] as num?)?.toDouble() ?? 0));
          return {'ok': true, 'offset': sc.offset};
        case 'animatedScrollTo':
          await sc.animateTo(clamp((args['offset'] as num?)?.toDouble() ?? 0),
              duration: Duration(milliseconds: (args['duration'] as num?)?.toInt() ?? 300),
              curve: Curves.easeOut);
          return {'ok': true, 'offset': sc.offset};
        case 'scrollBy':
          sc.jumpTo(clamp(sc.offset + ((args['delta'] as num?)?.toDouble() ?? 0)));
          return {'ok': true, 'offset': sc.offset};
        case 'scrollToEnd':
          await sc.animateTo(pos.maxScrollExtent, duration: dur, curve: Curves.easeOut);
          return {'ok': true, 'offset': sc.offset};
        case 'scrollToStart':
          await sc.animateTo(pos.minScrollExtent, duration: dur, curve: Curves.easeOut);
          return {'ok': true, 'offset': sc.offset};
        case 'scrollState':
          return {'ok': true, 'offset': sc.offset, 'min': pos.minScrollExtent, 'max': pos.maxScrollExtent};
      }
    }

    // 3) 翻页
    final pc = _pages[id];
    if (pc != null && pc.hasClients) {
      const dur = Duration(milliseconds: 300);
      switch (action) {
        case 'pageTo':
          await pc.animateToPage((args['index'] as num?)?.toInt() ?? 0, duration: dur, curve: Curves.easeOut);
          return {'ok': true, 'page': pc.page};
        case 'nextPage':
          await pc.nextPage(duration: dur, curve: Curves.easeOut);
          return {'ok': true, 'page': pc.page};
        case 'prevPage':
          await pc.previousPage(duration: dur, curve: Curves.easeOut);
          return {'ok': true, 'page': pc.page};
        case 'pageState':
          return {'ok': true, 'page': pc.page};
      }
    }

    // 3.5) 标签页
    final tb = _tabs[id];
    if (tb != null) {
      const dur = Duration(milliseconds: 300);
      int clampIndex(int i) => i < 0 ? 0 : (i >= tb.length ? tb.length - 1 : i);
      switch (action) {
        case 'tabTo':
          tb.animateTo(clampIndex((args['index'] as num?)?.toInt() ?? 0), duration: dur, curve: Curves.easeOut);
          return {'ok': true, 'index': tb.index};
        case 'nextTab':
          tb.animateTo(clampIndex(tb.index + 1), duration: dur, curve: Curves.easeOut);
          return {'ok': true, 'index': tb.index};
        case 'prevTab':
          tb.animateTo(clampIndex(tb.index - 1), duration: dur, curve: Curves.easeOut);
          return {'ok': true, 'index': tb.index};
        case 'tabState':
          return {'ok': true, 'index': tb.index, 'length': tb.length};
      }
    }

    // 4) 文本框
    final tc = _texts[id];
    if (tc != null) {
      switch (action) {
        case 'setText':
          tc.text = (args['text'] ?? '').toString();
          tc.selection = TextSelection.collapsed(offset: tc.text.length);
          return {'ok': true, 'text': tc.text};
        case 'clear':
          tc.clear();
          return {'ok': true};
        case 'focus':
          focusNode(id).requestFocus();
          return {'ok': true};
        case 'unfocus':
          focusNode(id).unfocus();
          return {'ok': true};
        case 'textState':
          return {'ok': true, 'text': tc.text, 'length': tc.text.length};
      }
    }

    // 5) 下拉刷新
    if (action == 'refresh') {
      final st = _refreshKeys[id]?.currentState;
      if (st != null) {
        st.show();
        return {'ok': true};
      }
      return {'error': 'no RefreshIndicator for id=$id'};
    }

    // 6) 抽屉
    if (action == 'openDrawer') {
      Renderer.scaffoldKey.currentState?.openDrawer();
      return {'ok': true};
    }
    if (action == 'closeDrawer') {
      Renderer.scaffoldKey.currentState?.closeDrawer();
      return {'ok': true};
    }

    return {'error': 'no controllable widget for id=$id / action=$action'};
  }
}

/// 视频播放器（网络/本地文件/asset）。
class BridgeVideo extends StatefulWidget {
  const BridgeVideo({super.key, required this.url, this.id, this.autoPlay = false, this.loop = false, this.showControls = true});
  final String? id;
  final String url;
  final bool autoPlay;
  final bool loop;
  final bool showControls;
  @override
  State<BridgeVideo> createState() => _BridgeVideoState();
}

class _BridgeVideoState extends State<BridgeVideo> {
  VideoPlayerController? _controller;
  String? _error;
  bool? _lastPlaying;
  bool? _lastBuffering;
  bool _completedSent = false;
  Timer? _progressTimer;

  @override
  void initState() {
    super.initState();
    if (widget.id != null) FlutterVideo.attach(widget.id!, this);
    _init();
  }

  Future<void> _init() async {
    try {
      final u = widget.url;
      final c = u.startsWith('http')
          ? VideoPlayerController.networkUrl(Uri.parse(u))
          : u.startsWith('/')
              ? VideoPlayerController.file(File(u))
              : VideoPlayerController.asset(u);
      await c.initialize();
      await c.setLooping(widget.loop);
      c.addListener(_onControllerChanged);
      if (widget.autoPlay) await c.play();
      if (!mounted) { await c.dispose(); return; }
      setState(() => _controller = c);
      FlutterVideo.emitState(widget.id, this);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
      FlutterVideo.emitEvent(widget.id, 'error', {'error': e.toString()});
    }
  }

  void _onControllerChanged() {
    final c = _controller;
    if (c == null) return;
    final v = c.value;
    final playing = v.isPlaying;
    final buffering = v.isBuffering;
    final needRebuild = playing != _lastPlaying || buffering != _lastBuffering;

    if (playing != _lastPlaying) {
      _lastPlaying = playing;
      FlutterVideo.emitEvent(widget.id, 'state', stateMap());
    }
    if (buffering != _lastBuffering) {
      _lastBuffering = buffering;
      FlutterVideo.emitEvent(widget.id, 'buffering', stateMap());
    }
    if (!_completedSent && v.duration > Duration.zero && v.position >= v.duration && !playing) {
      _completedSent = true;
      FlutterVideo.emitEvent(widget.id, 'completed', stateMap());
    }
    if (v.isPlaying) _completedSent = false;

    // 播放/暂停、缓冲状态变化时需要重绘（否则图标/转圈不刷新）
    if (needRebuild && mounted) setState(() {});
  }

  /// 当前播放状态（位置/时长/是否在播/缓冲等），供 Lua 查询。
  Map<String, dynamic> stateMap() {
    final v = _controller?.value;
    // 注意：该版本 video_player 的 buffered 是 List<DurationRange>（不是 Duration）
    final bufferedMs = (v == null || v.buffered.isEmpty)
        ? 0
        : v.buffered.last.end.inMilliseconds;
    return {
      'position': v?.position.inMilliseconds ?? 0,
      'duration': v?.duration.inMilliseconds ?? 0,
      'isPlaying': v?.isPlaying ?? false,
      'isBuffering': v?.isBuffering ?? false,
      'isInitialized': v?.isInitialized ?? false,
      'isCompleted': v?.isCompleted ?? false,
      'buffered': bufferedMs,
      'volume': v?.volume ?? 1.0,
      'speed': v?.playbackSpeed ?? 1.0,
      'aspectRatio': v?.aspectRatio ?? 1.0,
      'width': v?.size.width ?? 0,
      'height': v?.size.height ?? 0,
      'error': v?.errorDescription,
    };
  }

  /// 执行一条控制命令，返回最新状态。
  Future<Map<String, dynamic>> control(String action, Map<String, dynamic> a) async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return {'error': 'not ready'};
    switch (action) {
      case 'play':
        await c.play();
        break;
      case 'pause':
        await c.pause();
        break;
      case 'toggle':
        if (c.value.isPlaying) {
          await c.pause();
        } else {
          await c.play();
        }
        break;
      case 'seek':
        await c.seekTo(Duration(milliseconds: (a['pos'] as num?)?.toInt() ?? 0));
        break;
      case 'seekPercent':
        final dur = c.value.duration.inMilliseconds;
        final pct = (a['percent'] as num?)?.toDouble() ?? 0;
        await c.seekTo(Duration(milliseconds: (dur * pct / 100).round()));
        break;
      case 'volume':
        await c.setVolume(((a['volume'] as num?) ?? 1).toDouble().clamp(0.0, 1.0));
        break;
      case 'speed':
        await c.setPlaybackSpeed(((a['speed'] as num?) ?? 1).toDouble());
        break;
      case 'loop':
        await c.setLooping(a['loop'] == true);
        break;
      case 'listenProgress':
        // 持续监听：enabled=false 或 interval<=0 则停止
        final enabled = a['enabled'] == null ? true : a['enabled'] == true;
        final ms = (a['interval'] as num?)?.toInt() ?? 500;
        _startProgress(enabled ? ms : 0);
        break;
      case 'state':
        break;
      default:
        return {'error': 'unknown action: $action'};
    }
    return {'ok': true, ...stateMap()};
  }

  /// 开始/停止周期推送 progress 事件（ms<=0 表示停止）。
  void _startProgress(int ms) {
    _progressTimer?.cancel();
    _progressTimer = null;
    if (ms <= 0) return;
    _progressTimer = Timer.periodic(Duration(milliseconds: ms), (_) {
      FlutterVideo.emitEvent(widget.id, 'progress', stateMap());
    });
  }

  @override
  void dispose() {
    if (widget.id != null) FlutterVideo.detach(widget.id!, this);
    _progressTimer?.cancel();
    _controller?.removeListener(_onControllerChanged);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(child: Text('视频加载失败: $_error', style: const TextStyle(color: Colors.red, fontSize: 12)));
    }
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()));
    }
    final v = c.value;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Stack(alignment: Alignment.center, children: [
        AspectRatio(aspectRatio: v.aspectRatio, child: VideoPlayer(c)),
        // 缓冲/卡顿中显示转圈（由 isBuffering 驱动）
        if (v.isBuffering) const CircularProgressIndicator(),
      ]),
      if (widget.showControls)
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(
            icon: Icon(v.isPlaying ? Icons.pause : Icons.play_arrow),
            onPressed: () => setState(() => v.isPlaying ? c.pause() : c.play()),
          ),
        ]),
    ]);
  }
}

/// 音频播放器（网络/本地 URL，含进度条）。
class BridgeAudio extends StatefulWidget {
  const BridgeAudio({super.key, required this.url, this.id, this.title, this.autoPlay = false});
  final String? id;
  final String url;
  final String? title;
  final bool autoPlay;
  @override
  State<BridgeAudio> createState() => _BridgeAudioState();
}

class _BridgeAudioState extends State<BridgeAudio> {
  final AudioPlayer _player = AudioPlayer();
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  String? _error;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<PlayerState>? _stateSub;
  Timer? _progressTimer;

  @override
  void initState() {
    super.initState();
    if (widget.id != null) FlutterAudio.attach(widget.id!, this);
    _init();
  }

  /// 当前状态（供 Lua 查询）。
  Map<String, dynamic> stateMap() => {
        'position': _position.inMilliseconds,
        'duration': _duration.inMilliseconds,
        'isPlaying': _player.playing,
        'volume': _player.volume,
        'speed': _player.speed,
        'error': _error,
      };

  /// 执行控制命令（与视频同构：play/pause/toggle/stop/seek/seekPercent/volume/speed/loop/listenProgress/state）。
  Future<Map<String, dynamic>> control(String action, Map<String, dynamic> a) async {
    switch (action) {
      case 'play':
        await _player.play();
        break;
      case 'pause':
        await _player.pause();
        break;
      case 'toggle':
        if (_player.playing) {
          await _player.pause();
        } else {
          await _player.play();
        }
        break;
      case 'stop':
        await _player.stop();
        break;
      case 'seek':
        await _player.seek(Duration(milliseconds: (a['pos'] as num?)?.toInt() ?? 0));
        break;
      case 'seekPercent':
        final dur = (_player.duration ?? _duration).inMilliseconds;
        final pct = (a['percent'] as num?)?.toDouble() ?? 0;
        await _player.seek(Duration(milliseconds: (dur * pct / 100).round()));
        break;
      case 'volume':
        await _player.setVolume(((a['volume'] as num?) ?? 1).toDouble().clamp(0.0, 1.0));
        break;
      case 'speed':
        await _player.setSpeed(((a['speed'] as num?) ?? 1).toDouble());
        break;
      case 'loop':
        await _player.setLoopMode(a['loop'] == true ? LoopMode.one : LoopMode.off);
        break;
      case 'listenProgress':
        final enabled = a['enabled'] == null ? true : a['enabled'] == true;
        final ms = (a['interval'] as num?)?.toInt() ?? 500;
        _progressTimer?.cancel();
        _progressTimer = null;
        if (enabled && ms > 0) {
          _progressTimer = Timer.periodic(Duration(milliseconds: ms), (_) {
            FlutterAudio.emitEvent(widget.id, 'progress', stateMap());
          });
        }
        break;
      case 'state':
        break;
      default:
        return {'error': 'unknown action: $action'};
    }
    if (mounted) setState(() {});
    return {'ok': true, ...stateMap()};
  }

  @override
  void dispose() {
    if (widget.id != null) FlutterAudio.detach(widget.id!, this);
    _progressTimer?.cancel();
    _posSub?.cancel();
    _stateSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      await _player.setUrl(widget.url);
      _duration = _player.duration ?? Duration.zero;
      _posSub = _player.positionStream.listen((d) { if (mounted) setState(() => _position = d); });
      _stateSub = _player.playerStateStream.listen((_) { if (mounted) setState(() {}); });
      if (widget.autoPlay) await _player.play();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return ListTile(leading: const Icon(Icons.error, color: Colors.red), title: Text('音频加载失败: $_error', style: const TextStyle(fontSize: 12)));
    }
    final total = _duration.inMilliseconds;
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(children: [
          IconButton(
            icon: Icon(_player.playing ? Icons.pause : Icons.play_arrow),
            onPressed: () => _player.playing ? _player.pause() : _player.play(),
          ),
          Expanded(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.title ?? '音频', style: const TextStyle(fontWeight: FontWeight.bold)),
              Slider(
                value: total > 0 ? _position.inMilliseconds.clamp(0, total).toDouble() : 0,
                max: total > 0 ? total.toDouble() : 1,
                onChanged: (v) => _player.seek(Duration(milliseconds: v.round())),
              ),
              Text('${_fmt(_position)} / ${_fmt(_duration)}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// 可按 id 定点重建的节点壳：监听 FlutterBridge 中该 id 的 spec notifier。
/// 命令式 `h.Text="..."`（原生侧改 spec 后下发 patch）或全量 render 更新该节点时，
/// 只有这个子树重建，不牵动整棵树。
class _IdNode extends StatefulWidget {
  const _IdNode({super.key, required this.id, required this.spec, required this.path});
  final String id;
  final dynamic spec;
  final String path;

  @override
  State<_IdNode> createState() => _IdNodeState();
}

class _IdNodeState extends State<_IdNode> {
  late final ValueNotifier<dynamic> _notifier =
      FlutterBridge.instance.nodeNotifier(widget.id, widget.spec);

  @override
  void initState() {
    super.initState();
    _notifier.value = widget.spec;
    FlutterControl.retain(widget.id);
  }

  @override
  void dispose() {
    FlutterControl.unmount(widget.id);
    super.dispose();
  }

  @override
  void didUpdateWidget(_IdNode old) {
    super.didUpdateWidget(old);
    if (!identical(widget.spec, old.spec)) {
      _notifier.value = widget.spec;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<dynamic>(
      valueListenable: _notifier,
      builder: (context, spec, _) =>
          Renderer._buildNodeFor(spec, widget.path) ?? const SizedBox.shrink(),
    );
  }
}

/// 把「水波纹/高亮/hover/focus + 密度」这类主题级属性包成一棵 Theme 子树：
/// InkWell / 按钮 / 列表项 / TabBar 内部都读 Theme.of(context)，包一层就整体生效。
class _InteractTheme extends StatelessWidget {
  const _InteractTheme({
    required this.child,
    this.noSplash = false,
    this.splash,
    this.highlight,
    this.hover,
    this.focus,
    this.density,
    this.tapTarget,
  });

  final Widget child;
  final bool noSplash;
  final Color? splash;
  final Color? highlight;
  final Color? hover;
  final Color? focus;
  final VisualDensity? density;
  final MaterialTapTargetSize? tapTarget;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    return Theme(
      data: base.copyWith(
        splashFactory: noSplash ? NoSplash.splashFactory : null,
        splashColor: splash ?? (noSplash ? Colors.transparent : null),
        highlightColor: highlight ?? (noSplash ? Colors.transparent : null),
        hoverColor: hover ?? (noSplash ? Colors.transparent : null),
        focusColor: focus ?? (noSplash ? Colors.transparent : null),
        visualDensity: density,
        materialTapTargetSize: tapTarget,
      ),
      child: child,
    );
  }
}

/// ExpansionTile 的壳：展开态是声明式的（spec 里 expanded 变了就展开/收起），
/// 不再把状态编进 key——那样「重复赋同一个值」不生效。
class BridgeExpansionTile extends StatefulWidget {
  const BridgeExpansionTile({
    super.key,
    required this.p,
    required this.title,
    required this.children,
    this.subtitle,
    this.leading,
    this.onChanged,
  });
  final Props p;
  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final List<Widget> children;
  final ValueChanged<bool>? onChanged;
  @override
  State<BridgeExpansionTile> createState() => _BridgeExpansionTileState();
}

class _BridgeExpansionTileState extends State<BridgeExpansionTile> {
  final ExpansionTileController _controller = ExpansionTileController();
  late bool _open = widget.p.b('expanded') || widget.p.b('initiallyExpanded');
  bool _inited = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final want = p.b('expanded') || p.b('initiallyExpanded');
    if (_inited && want != _open) {
      _open = want;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (want) {
          _controller.expand();
        } else {
          _controller.collapse();
        }
      });
    }
    _inited = true;
    return ExpansionTile(
      controller: _controller,
      title: widget.title,
      subtitle: widget.subtitle,
      leading: widget.leading,
      initiallyExpanded: _open,
      backgroundColor: p.color('backgroundColor'),
      collapsedBackgroundColor: p.color('collapsedBackgroundColor'),
      iconColor: p.color('iconColor'),
      collapsedIconColor: p.color('collapsedIconColor'),
      textColor: p.color('textColor'),
      collapsedTextColor: p.color('collapsedTextColor'),
      tilePadding: p.inset('tilePadding'),
      childrenPadding: p.inset('childrenPadding'),
      shape: Props.toShape(p.s('shape'), p.n('radius')),
      collapsedShape: Props.toShape(p.s('collapsedShape'), p.n('collapsedRadius')),
      dense: p.has('dense') ? p.b('dense') : null,
      enabled: p.b('enabled', true),
      maintainState: p.b('maintainState'),
      expandedAlignment: p.align('expandedAlignment'),
      expandedCrossAxisAlignment: p.has('expandedCrossAxisAlignment')
          ? Props.toCrossAxis(p['expandedCrossAxisAlignment'])
          : null,
      controlAffinity: switch (p.s('controlAffinity')?.toLowerCase()) {
        'leading' => ListTileControlAffinity.leading,
        'trailing' => ListTileControlAffinity.trailing,
        _ => ListTileControlAffinity.platform,
      },
      onExpansionChanged: (v) {
        _open = v;
        widget.onChanged?.call(v);
      },
      children: widget.children,
    );
  }
}

class BridgeTabs extends StatefulWidget {
  const BridgeTabs({super.key, required this.id, required this.length, required this.index, this.onChanged, required this.child});
  final String? id;
  final int length;
  final int index;
  final ValueChanged<int>? onChanged;
  final Widget child;
  @override
  State<BridgeTabs> createState() => _BridgeTabsState();
}

/// 包一层 DefaultTabController，但切页复用同一个 controller（animateTo → 指示器有过渡动画）。
///
/// index 属性是**声明式**的：spec 里写 index=n，重建后就应该停在第 n 页。
/// 控制器是活对象（用户手滑/点标签都会改它自己），所以每次重建都按属性纠偏——
/// 否则「同一个值再赋一次」在 Dart 侧看不出变化（属性没变、控制器却已经不在那页），
/// 表现为「第二次点跳转没反应」。Lua 侧用 onChange 记住当前页即可。
class _BridgeTabsState extends State<BridgeTabs> {
  BuildContext? _inner;
  TabController? _controller;

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: widget.length,
        initialIndex: widget.index,
        child: Builder(builder: (ctx) {
          _bind(ctx);
          _syncToIndex(widget.index);
          return widget.child;
        }),
      );

  void _bind(BuildContext ctx) {
    _inner = ctx;
    final c = DefaultTabController.maybeOf(ctx);
    if (c == null || identical(c, _controller)) return;
    _controller?.removeListener(_onSettled);
    _controller = c;
    c.addListener(_onSettled);
    final id = widget.id;
    if (id != null) FlutterControl.registerTab(id, c);
  }

  /// 属性说停在哪页就停在哪页（重建时纠偏，动画交给 controller）。
  void _syncToIndex(int index) {
    final c = _controller;
    if (c == null || c.index == index || c.indexIsChanging) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _inner;
      if (!mounted || ctx == null) return;
      final live = DefaultTabController.maybeOf(ctx);
      if (live == null || live.index == index || live.indexIsChanging) return;
      live.animateTo(index);
    });
  }

  /// indexIsChanging 期间是动画中，落地后再通知，避免 Lua 收到一堆中间值。
  void _onSettled() {
    final c = _controller;
    if (c == null || c.indexIsChanging) return;
    widget.onChanged?.call(c.index);
  }

  @override
  void dispose() {
    _controller?.removeListener(_onSettled);
    final id = widget.id;
    // 只清理自己注册的那一个：重建时新状态可能已经注册好了
    if (id != null && identical(FlutterControl.tabOf(id), _controller)) {
      FlutterControl.unregisterTab(id);
    }
    super.dispose();
  }
}

class BridgeRangeSlider extends StatefulWidget {
  const BridgeRangeSlider({super.key, required this.start, required this.end, required this.min, required this.max, required this.onChanged});
  final double start;
  final double end;
  final double min;
  final double max;
  final ValueChanged<List<double>> onChanged;
  @override
  State<BridgeRangeSlider> createState() => _BridgeRangeSliderState();
}

class _BridgeRangeSliderState extends State<BridgeRangeSlider> {
  late RangeValues _r = RangeValues(
    widget.start.clamp(widget.min, widget.max),
    widget.end.clamp(widget.min, widget.max),
  );

  @override
  void didUpdateWidget(BridgeRangeSlider old) {
    super.didUpdateWidget(old);
    if (widget.start != old.start || widget.end != old.end) {
      setState(() => _r = RangeValues(
            widget.start.clamp(widget.min, widget.max),
            widget.end.clamp(widget.min, widget.max),
          ));
    }
  }

  @override
  Widget build(BuildContext context) => RangeSlider(
        values: _r,
        min: widget.min,
        max: widget.max,
        onChanged: (v) {
          setState(() => _r = v);
          widget.onChanged([v.start, v.end]);
        },
      );
}

class BridgeNavigationBar extends StatefulWidget {
  const BridgeNavigationBar({super.key, required this.p, required this.items, this.initialIndex = 0, this.onTap});
  final Props p;
  final List<dynamic> items;
  final int initialIndex;
  final ValueChanged<int>? onTap;
  @override
  State<BridgeNavigationBar> createState() => _BridgeNavigationBarState();
}

class _BridgeNavigationBarState extends State<BridgeNavigationBar> {
  int? _tapped;

  int get _propIndex => widget.items.isEmpty ? 0 : widget.initialIndex.clamp(0, widget.items.length - 1);

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    // 属性是声明式的：spec 写 currentIndex=n 就停在第 n 项；用户点过后重建时按属性纠偏
    final want = _propIndex;
    if (_tapped != null && _tapped != want) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _tapped != null && _tapped != want) setState(() => _tapped = null);
      });
    }
    return NavigationBar(
      selectedIndex: _tapped ?? want,
      onDestinationSelected: (i) {
        setState(() => _tapped = i);
        widget.onTap?.call(i);
      },
      destinations: widget.items.map((e) {
        final ip = Props.of(e);
        return NavigationDestination(
          icon: Icon(Props.toIcon(ip['icon'])),
          label: (ip['label'] ?? ip['text'] ?? '').toString(),
        );
      }).toList(),
      backgroundColor: p.color('backgroundColor') ?? p.color('color'),
      elevation: p.n('elevation'),
      shadowColor: p.color('shadowColor'),
      surfaceTintColor: p.color('surfaceTintColor'),
      indicatorColor: p.color('indicatorColor'),
      indicatorShape: Props.toShape(p.s('indicatorShape'), p.n('indicatorRadius')),
      height: p.n('height'),
      animationDuration: p.has('animationDuration') ? Props.toDuration(p['animationDuration']) : null,
      labelBehavior: switch (p.s('labelBehavior')?.toLowerCase()) {
        'always' || 'alwaysshow' => NavigationDestinationLabelBehavior.alwaysShow,
        'never' || 'hide' || 'alwayshide' => NavigationDestinationLabelBehavior.alwaysHide,
        'selected' || 'onlyshowselected' => NavigationDestinationLabelBehavior.onlyShowSelected,
        _ => null,
      },
      overlayColor: Renderer._colorState(p, 'overlayColor'),
    );
  }
}

class BridgePageView extends StatefulWidget {
  const BridgePageView({super.key, required this.p, required this.children, this.onChanged});
  final Props p;
  final List<Widget> children;
  final ValueChanged<int>? onChanged;
  @override
  State<BridgePageView> createState() => _BridgePageViewState();
}

class _BridgePageViewState extends State<BridgePageView> {
  late final String? _id = widget.p['id']?.toString();
  late final PageController _controller = _id != null
      ? FlutterControl.page(_id!, initial: widget.p.i('initialPage') ?? widget.p.i('page') ?? 0)
      : PageController(initialPage: widget.p.i('initialPage') ?? widget.p.i('page') ?? 0);

  @override
  void dispose() {
    if (_id == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    return PageView(
      controller: _controller,
      scrollDirection: p.axis('scrollDirection'),
      reverse: p.b('reverse'),
      pageSnapping: p.b('pageSnapping', true),
      physics: Props.toPhysics(p['physics']),
      onPageChanged: (i) => widget.onChanged?.call(i),
      children: widget.children,
    );
  }
}

class BridgeCupertinoSwitch extends StatefulWidget {
  const BridgeCupertinoSwitch({super.key, required this.p, required this.onChanged});
  final Props p;
  final ValueChanged<bool> onChanged;
  @override
  State<BridgeCupertinoSwitch> createState() => _BridgeCupertinoSwitchState();
}

class _BridgeCupertinoSwitchState extends State<BridgeCupertinoSwitch> {
  late bool _value = widget.p.b('value');
  @override
  void didUpdateWidget(BridgeCupertinoSwitch old) {
    super.didUpdateWidget(old);
    final next = widget.p.b('value');
    if (next != old.p.b('value')) setState(() => _value = next);
  }
  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    return CupertinoSwitch(
      value: _value,
      activeTrackColor: p.color('activeTrackColor'),
      inactiveTrackColor: p.color('inactiveTrackColor') ?? p.color('trackColor'),
      thumbColor: p.color('thumbColor'),
      applyTheme: p.b('applyTheme'),
      onChanged: p.b('enabled', true)
          ? (v) { setState(() => _value = v); widget.onChanged(v); }
          : null,
    );
  }
}

class BridgeCupertinoSlider extends StatefulWidget {
  const BridgeCupertinoSlider({super.key, required this.p, required this.onChanged});
  final Props p;
  final ValueChanged<double> onChanged;
  @override
  State<BridgeCupertinoSlider> createState() => _BridgeCupertinoSliderState();
}

class _BridgeCupertinoSliderState extends State<BridgeCupertinoSlider> {
  late double _value = widget.p.n('value') ?? 0;
  @override
  void didUpdateWidget(BridgeCupertinoSlider old) {
    super.didUpdateWidget(old);
    final next = widget.p.n('value');
    if (next != null && next != old.p.n('value')) setState(() => _value = next);
  }
  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final min = p.n('min') ?? 0;
    final maxRaw = p.n('max') ?? 1;
    final max = maxRaw <= min ? min + 1 : maxRaw;
    return CupertinoSlider(
      value: _value.clamp(min, max),
      min: min,
      max: max,
      divisions: p.i('divisions'),
      activeColor: p.color('activeColor'),
      thumbColor: p.color('thumbColor') ?? CupertinoColors.white,
      onChanged: p.b('enabled', true)
          ? (v) { setState(() => _value = v); widget.onChanged(v); }
          : null,
    );
  }
}

class BridgeCupertinoDatePicker extends StatefulWidget {
  const BridgeCupertinoDatePicker({super.key, required this.p, this.onChanged});
  final Props p;
  final ValueChanged<DateTime>? onChanged;
  @override
  State<BridgeCupertinoDatePicker> createState() => _BridgeCupertinoDatePickerState();
}

class _BridgeCupertinoDatePickerState extends State<BridgeCupertinoDatePicker> {
  DateTime get _min => Props.toDate(widget.p['minimumDate']) ?? DateTime(2000);
  DateTime get _max => Props.toDate(widget.p['maximumDate']) ?? DateTime(2100);
  late DateTime _value = _initValue();

  DateTime _initValue() {
    final v = Props.toDate(widget.p['value'] ?? widget.p['initialDateTime']) ?? DateTime.now();
    final min = _min;
    final max = _max;
    if (v.isBefore(min)) return min;
    if (v.isAfter(max)) return max;
    return v;
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final mode = p.s('mode')?.toLowerCase();
    return CupertinoDatePicker(
      mode: mode == 'time'
          ? CupertinoDatePickerMode.time
          : (mode == 'dateandtime' ? CupertinoDatePickerMode.dateAndTime : CupertinoDatePickerMode.date),
      initialDateTime: _value,
      minimumDate: _min,
      maximumDate: _max,
      minuteInterval: p.i('minuteInterval') ?? 1,
      use24hFormat: p.b('use24hFormat', true),
      onDateTimeChanged: (d) {
        _value = d;
        widget.onChanged?.call(d);
      },
    );
  }
}
