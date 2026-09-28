import 'dart:async';
import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
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
    if (spec is List) {
      if (spec.isEmpty) return null;
      return _buildInner(<String, dynamic>{'type': Props.typeName(spec.first), 'children': spec.sublist(1)});
    }
    if (spec is! Map) return const SizedBox.shrink();

    final p = Props.of(spec);
    final children = _children(p['children'] ?? p['child']);
    Widget child0() => children.isNotEmpty ? children.first : const SizedBox.shrink();

    final ext = custom[p.type];
    if (ext != null) {
      return _wrapCommon(ext(p.map), p);
    }

    Widget result;
    switch (p.type) {
      // ---------- 布局 ----------
      case 'column':
        result = Column(
          mainAxisAlignment: Props.toMainAxis(p['mainAxisAlignment'] ?? p['gravity']),
          crossAxisAlignment: Props.toCrossAxis(p['crossAxisAlignment']),
          mainAxisSize: Props.toMainAxisSize(p['mainAxisSize']),
          spacing: p.nz('gap'),
          children: children,
        );
        break;
      case 'row':
        result = Row(
          mainAxisAlignment: Props.toMainAxis(p['mainAxisAlignment'] ?? p['gravity']),
          crossAxisAlignment: Props.toCrossAxis(p['crossAxisAlignment']),
          mainAxisSize: Props.toMainAxisSize(p['mainAxisSize']),
          spacing: p.nz('gap'),
          children: children,
        );
        break;
      case 'stack':
        result = Stack(
          alignment: p.align('alignment') ?? AlignmentDirectional.topStart,
          fit: p.s('fit')?.toLowerCase() == 'expand' ? StackFit.expand : StackFit.loose,
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
          decoration: _decoration(p),
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
          scrollDirection: p.axis('scrollDirection'),
          physics: Props.toPhysics(p['physics']),
          padding: p.inset('padding'),
          child: child0(),
        );
        break;
      case 'transform':
        final t = p['translate'];
        final off = t is List && t.length >= 2
            ? Offset((t[0] as num).toDouble(), (t[1] as num).toDouble())
            : Offset.zero;
        result = Transform.translate(offset: off, child: child0());
        break;

      // ---------- 文本 / 图片 / 图标 ----------
      case 'text':
        result = Text(
          (p['text'] ?? p['value'] ?? '').toString(),
          textAlign: Props.toTextAlign(p['textAlign']),
          style: Props.toTextStyle(p),
          maxLines: p.i('maxLines'),
          overflow: p.i('maxLines') != null ? TextOverflow.ellipsis : null,
        );
        break;
      case 'selectabletext':
        result = SelectableText(
          (p['text'] ?? p['value'] ?? '').toString(),
          textAlign: Props.toTextAlign(p['textAlign']),
          style: Props.toTextStyle(p),
        );
        break;
      case 'icon':
        result = Icon(Props.toIcon(p['icon'] ?? p['name']), color: p.color('color'), size: p.n('size'));
        break;
      case 'image':
        final url = p['url'] ?? p['src'] ?? p['asset'];
        if (url == null) {
          result = const SizedBox.shrink();
        } else {
          final u = url.toString();
          result = u.startsWith('http')
              ? Image.network(u, width: Props.dim(p['width']), height: Props.dim(p['height']), fit: BoxFit.cover)
              : Image.asset(u, width: Props.dim(p['width']), height: Props.dim(p['height']), fit: BoxFit.cover);
        }
        break;

      // ---------- 按钮 ----------
      case 'button' || 'elevatedbutton' || 'textbutton' || 'filledbutton' || 'outlinedbutton':
        final label = (p['text'] ?? p['label'] ?? 'Button').toString();
        final onTap = _tapHandler(p);
        final style = _buttonStyle(p);
        final child = _widgetOrText(p['child'], label);
        result = Padding(
          padding: p.inset('padding') ?? EdgeInsets.zero,
          child: p.type == 'textbutton'
              ? TextButton(onPressed: onTap, style: style, child: child)
              : p.type == 'outlinedbutton'
                  ? OutlinedButton(onPressed: onTap, style: style, child: child)
                  : p.type == 'filledbutton'
                      ? FilledButton(onPressed: onTap, style: style, child: child)
                      : ElevatedButton(onPressed: onTap, style: style, child: child),
        );
        break;
      case 'iconbutton':
        result = IconButton(
          icon: Icon(Props.toIcon(p['icon'] ?? p['name']), color: p.color('color')),
          onPressed: _tapHandler(p),
        );
        break;
      case 'floatingactionbutton':
        result = FloatingActionButton(
          onPressed: _tapHandler(p),
          backgroundColor: p.color('color') ?? p.color('backgroundColor'),
          child: Icon(Props.toIcon(p['icon'] ?? p['name'])),
        );
        break;

      // ---------- 容器类 ----------
      case 'card':
        result = Card(
          elevation: p.n('elevation') ?? 1,
          color: p.color('color') ?? _decoration(p)?.color,
          shadowColor: p.color('shadowColor'),
          margin: p.inset('margin') ?? const EdgeInsets.all(4),
          shape: p.n('radius') != null
              ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(p.n('radius')!))
              : null,
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
        result = Chip(label: Text((p['text'] ?? p['label'] ?? '').toString()));
        break;
      case 'listtile':
        result = ListTile(
          leading: _slotIcon(p['leading']),
          title: _slotText(p['title'] ?? p['text']),
          subtitle: _slotText(p['subtitle']),
          trailing: _slotText(p['trailing']),
          onTap: _tapHandler(p),
        );
        break;

      // ---------- 滚动 / 列表 ----------
      case 'listview' || 'list' || 'listviewbuilder':
        result = _listView(p, children);
        break;
      case 'gridview':
        result = GridView.count(
          crossAxisCount: p.i('crossAxisCount') ?? p.i('columns') ?? 2,
          mainAxisSpacing: p.n('gap') ?? p.n('mainAxisGap') ?? 8,
          crossAxisSpacing: p.n('gap') ?? p.n('crossAxisGap') ?? 8,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: children,
        );
        break;
      case 'divider':
        result = Divider(color: p.color('color'), thickness: p.n('thickness'));
        break;
      case 'circularprogressindicator':
        result = Center(child: CircularProgressIndicator(value: p.n('value')));
        break;
      case 'linearprogressindicator':
        result = LinearProgressIndicator(value: p.n('value'));
        break;

      // ---------- 交互 ----------
      case 'checkbox':
        result = BridgeCheckbox(
          key: _nodeKey(p),
          initial: p.b('value'),
          color: p.color('color'),
          onChanged: (v) => _change(p, v),
        );
        break;
      case 'switch':
        result = BridgeSwitch(
          key: _nodeKey(p),
          initial: p.b('value'),
          onChanged: (v) => _change(p, v),
        );
        break;
      case 'slider':
        result = BridgeSlider(
          key: _nodeKey(p),
          initial: p.n('value') ?? 0,
          min: p.n('min') ?? 0,
          max: p.n('max') ?? 1,
          onChanged: (v) => _change(p, v),
        );
        break;
      case 'textfield' || 'edittext':
        result = BridgeTextField(
          key: _nodeKey(p),
          hint: p.s('hint') ?? _decText(p, 'hintText'),
          label: p.s('label') ?? _decText(p, 'labelText'),
          initial: p.s('text'),
          maxLines: p.i('maxLines'),
          onChanged: (v) => _change(p, v),
        );
        break;
      case 'inkwell':
      case 'gesturedetector':
        final onTap = _tapHandler(p);
        result = p.type == 'inkwell' ? InkWell(onTap: onTap, child: child0()) : GestureDetector(onTap: onTap, child: child0());
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
                key: _nodeKey(p),
                initial: p.s('value'),
                items: p.list('items'),
                onChanged: (v) => _emit(p['onChange'], v, fallback: p.map),
              );
        break;

      // ---------- Scaffold 体系 ----------
      case 'scaffold':
        result = Scaffold(
          key: scaffoldKey,
          backgroundColor: p.color('backgroundColor'),
          appBar: _preferred(_build(p['appBar'])),
          drawer: _build(p['drawer']),
          endDrawer: _build(p['endDrawer']),
          body: _build(p['body']) ?? child0(),
          bottomNavigationBar: _build(p['bottomNavigationBar']),
          floatingActionButton: _build(p['floatingActionButton']),
        );
        break;
      case 'appbar':
        result = AppBar(
          title: _build(p['title']),
          leading: _build(p['leading']),
          actions: _children(p['actions']),
          elevation: p.n('elevation'),
          backgroundColor: p.color('backgroundColor') ?? p.color('color'),
          foregroundColor: p.color('foregroundColor'),
          centerTitle: p.b('centerTitle'),
          automaticallyImplyLeading: p.b('automaticallyImplyLeading', true),
        );
        break;
      case 'drawer':
        result = Drawer(backgroundColor: p.color('backgroundColor'), child: child0());
        break;
      case 'useraccountsdrawerheader':
        result = UserAccountsDrawerHeader(
          decoration: _decoration(p),
          accountName: _build(p['accountName']),
          accountEmail: _build(p['accountEmail']),
          currentAccountPicture: _build(p['currentAccountPicture']),
          otherAccountsPictures: _children(p['otherAccountsPictures']),
        );
        break;
      case 'bottomnavigationbar':
        result = BridgeBottomNav(
          key: _nodeKey(p),
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
            return Tab(text: (tp['text'] ?? tp['label'])?.toString());
          }).toList(),
          indicatorColor: p.color('indicatorColor'),
          labelColor: p.color('labelColor'),
          unselectedLabelColor: p.color('unselectedLabelColor'),
        );
        break;
      case 'tabbarview':
        result = TabBarView(children: children);
        break;
      case 'defaulttabcontroller':
        result = DefaultTabController(length: p.i('length') ?? 1, child: child0());
        break;

      // ---------- 二维码 / 地图 / 图表 / 媒体 ----------
      case 'qrcode' || 'qrimage' || 'qr':
        result = QrImageView(
          data: (p['data'] ?? p['text'] ?? '').toString(),
          size: p.n('size'),
          backgroundColor: p.color('background') ?? Colors.white,
          eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: p.color('color') ?? Colors.black),
          dataModuleStyle: QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: p.color('color') ?? Colors.black),
        );
        break;
      case 'map' || 'fluttermap':
        result = _mapView(p);
        break;
      case 'chart' || 'linechart' || 'barchart' || 'piechart':
        result = _chart(p);
        break;
      case 'videoplayer' || 'video':
        result = BridgeVideo(
          url: (p['url'] ?? p['src'] ?? '').toString(),
          autoPlay: p.b('autoPlay'),
          loop: p.b('loop'),
          showControls: p.b('controls', true),
        );
        break;
      case 'audioplayer' || 'audio' || 'music':
        result = BridgeAudio(
          url: (p['url'] ?? p['src'] ?? '').toString(),
          title: p.s('title') ?? p.s('text'),
          autoPlay: p.b('autoPlay'),
        );
        break;

      // ---------- 原生 ----------
      case 'androidview':
      case 'android':
        result = AndroidView(
          viewType: (p['viewType'] ?? p['view'] ?? 'androlua/native').toString(),
          layoutDirection: TextDirection.ltr,
          creationParams: _creationParams(p),
          creationParamsCodec: const StandardMessageCodec(),
        );
        break;

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

  static Widget _listView(Props p, List<Widget> children) {
    final padding = p.inset('padding');
    final physics = Props.toPhysics(p['physics']);
    final shrinkWrap = p.b('shrinkWrap');
    final axis = p.axis('scrollDirection');

    final count = p.i('itemCount');
    final template = p['itemTemplate'] ?? p['item'];
    if (template != null && count != null && count > 0) {
      // 模板式懒加载：按需构建，字符串里的 $index 会替换成当前下标。
      return ListView.builder(
        padding: padding,
        physics: physics,
        shrinkWrap: shrinkWrap,
        scrollDirection: axis,
        itemCount: count,
        itemBuilder: (ctx, i) => _build(_subst(template, i)) ?? const SizedBox.shrink(),
      );
    }
    return ListView.builder(
      padding: padding,
      physics: physics,
      shrinkWrap: shrinkWrap,
      scrollDirection: axis,
      itemCount: children.length,
      itemBuilder: (ctx, i) => children[i],
    );
  }

  /// 深拷贝并把字符串里的 `$index`/`$i` 替换为下标（用于模板式列表）。
  static dynamic _subst(dynamic v, int i) {
    if (v is String) return v.replaceAll(r'$index', '$i').replaceAll(r'$i', '$i');
    if (v is List) return v.map((e) => _subst(e, i)).toList();
    if (v is Map) {
      final m = <String, dynamic>{};
      v.forEach((k, val) => m[k.toString()] = _subst(val, i));
      return m;
    }
    return v;
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
        width: 40,
        height: 40,
        child: Icon(Props.toIcon(mp['icon'] ?? 'location_on'), color: Colors.red, size: 32),
      ));
    }
    final tile = p.s('tileUrl') ?? 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
    return FlutterMap(
      options: MapOptions(
        initialCenter: LatLng(lat, lng),
        initialZoom: p.n('zoom') ?? 13,
      ),
      children: [
        TileLayer(
          urlTemplate: tile,
          userAgentPackageName: p.s('userAgent') ?? 'com.androlua',
        ),
        if (markers.isNotEmpty) MarkerLayer(markers: markers),
      ],
    );
  }

  static Widget _chart(Props p) {
    final height = p.n('height') ?? 220;
    final series = p.list('series').map(_Series.of).toList();
    final kind = p.type == 'chart' ? (p.s('chartType') ?? 'line').toLowerCase() : p.type;

    Widget body;
    switch (kind) {
      case 'bar' || 'barchart':
        body = BarChart(BarChartData(
          barGroups: [
            for (var i = 0; i < series.length; i++)
              BarChartGroupData(x: i, barRods: [
                BarChartRodData(toY: series[i].value, color: series[i].color, width: 14, borderRadius: BorderRadius.circular(4)),
              ]),
          ],
          gridData: const FlGridData(show: true),
          borderData: FlBorderData(show: false),
        ));
        break;
      case 'pie' || 'piechart':
        body = PieChart(PieChartData(
          sections: [
            for (final s in series)
              PieChartSectionData(value: s.value, title: s.name ?? '', color: s.color, radius: 80, titleStyle: const TextStyle(fontSize: 12, color: Colors.white)),
          ],
        ));
        break;
      default:
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
    }
    return SizedBox(height: height, child: body);
  }

  // ============================================================
  // 通用结构/属性
  // ============================================================

  static Widget _wrapCommon(Widget child, Props p) {
    final weight = p.n('weight');
    Widget out = child;
    if (weight != null) {
      out = Expanded(flex: weight.round(), child: out);
    }
    final w = p['width'];
    final h = p['height'];
    if (w != null || h != null) {
      out = SizedBox(width: Props.dim(w), height: Props.dim(h), child: out);
    }
    return out;
  }

  static Key? _nodeKey(Props p) {
    final id = p['id'] ?? p['key'];
    return id == null ? null : ValueKey(id.toString());
  }

  static List<Widget> _children(dynamic raw) {
    if (raw is List) return raw.map((e) => _build(e)).whereType<Widget>().toList();
    if (raw is Map) {
      final one = _build(raw);
      return one == null ? [] : [one];
    }
    return [];
  }


  static Widget _widgetOrText(dynamic spec, String fallback) {
    if (spec is Map || spec is List) return _build(spec) ?? Text(fallback);
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
    return Icon(Props.toIcon(v));
  }

  static dynamic _creationParams(Props p) {
    final params = p['params'];
    if (params is Map) return params.cast<String, dynamic>();
    return <String, dynamic>{
      'text': (p['text'] ?? '原生 AndroidView').toString(),
      'background': p['background']?.toString(),
    };
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
      _emit(c, value, fallback: p.map);
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
        FlutterBridge.instance.emit(action, {'action': action});
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
          {'action': method, 'args': args, 'result': res},
        );
      }
    };
  }

  static void _emit(dynamic spec, dynamic value, {Map<String, dynamic>? fallback}) {
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
      {'value': value, 'result': res},
    );
  }

  // ---------- 装饰 / 样式 ----------

  static BoxDecoration? _decoration(Props p) {
    final dp = Props.of(p['decoration']);
    final color = dp.color('color') ?? p.color('color') ?? p.color('backgroundColor');
    final gradient = Props.toGradient(dp['gradient'] ?? p['gradient']);
    final radius = dp.n('radius') ?? dp.n('borderRadius') ?? p.n('radius');
    final border = _decoBorder(dp, p);
    final shadows = Props.toShadows(dp['boxShadow'] ?? dp['shadows'] ?? p['boxShadow']);
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
    final radius = sp.n('radius') ?? p.n('radius');
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

/// 视频播放器（网络/本地 URL）。
class BridgeVideo extends StatefulWidget {
  const BridgeVideo({super.key, required this.url, this.autoPlay = false, this.loop = false, this.showControls = true});
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

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await c.initialize();
      await c.setLooping(widget.loop);
      if (widget.autoPlay) await c.play();
      if (!mounted) { await c.dispose(); return; }
      setState(() => _controller = c);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
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
    return Column(mainAxisSize: MainAxisSize.min, children: [
      AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c)),
      if (widget.showControls)
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(
            icon: Icon(c.value.isPlaying ? Icons.pause : Icons.play_arrow),
            onPressed: () => setState(() => c.value.isPlaying ? c.pause() : c.play()),
          ),
        ]),
    ]);
  }
}

/// 音频播放器（网络/本地 URL，含进度条）。
class BridgeAudio extends StatefulWidget {
  const BridgeAudio({super.key, required this.url, this.title, this.autoPlay = false});
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

  @override
  void initState() {
    super.initState();
    _init();
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

  @override
  void dispose() {
    _posSub?.cancel();
    _stateSub?.cancel();
    _player.dispose();
    super.dispose();
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
