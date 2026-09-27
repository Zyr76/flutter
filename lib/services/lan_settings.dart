import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 局域网空间配置：最高权限开关（私密/开放）+ 各内容类型是否对外可见 +
/// 端口、自启动、保持运行，以及网页外观/自定义 CSS / 自定义页头定制。
class LanSettings extends ChangeNotifier {
  LanSettings._();
  static final LanSettings instance = LanSettings._();

  static const int defaultPort = 8787;

  /// 最高权限开关：true=私密（整个空间对外关闭），false=开放
  bool private = false;

  // 各类型是否对外可见（仅在开放时生效）
  bool showShuoshuo = true;
  bool showDiary = true;
  bool showAlbum = true;
  bool showFile = true;

  // 服务器：端口 / 自启动 / 保持运行
  int port = defaultPort;
  bool autoStart = false;
  bool keepAwake = false;

  // 网页外观与自定义
  String brand = '拾光 · 空间';
  /// #RRGGBB，空表示默认棕色系
  String accentHex = '';
  /// 注入到 <style> 末尾的自定义 CSS
  String customCss = '';
  /// 自定义页头 HTML（显示在顶部 brand 之下），为空则不显示。
  /// 注意：这是“合并后”的完整 HTML（由手动页头 + 组件库生成），供服务器注入。
  String customHtml = '';

  /// 用户手动填写的页头 HTML（不含组件库生成的内容），供编辑页回显。
  String customHeader = '';

  /// 组件块（拖拽编排的网页组件列表）。每个元素为 Map：
  /// {'t': 'heading|text|notice|divider|link|image|quote', 'text':…, 'url':…, 'accent':bool}
  List<Map<String, dynamic>> blocks = [];

  /// 整页主题（深度定制整个网页 UI）：
  ///  - bga/bgb: 背景渐变两个颜色；bgim: 背景图 URL（可空）
  ///  - radius: 卡片圆角(px)；font: sans|song|hei|mono
  ///  - hs: 页头样式 0经典 1横幅 2极简；ts: Tab 样式 0胶囊 1下划线 2分块
  Map<String, dynamic> webTheme = {
    'bga': '#EFE6D6',
    'bgb': '#F7F4EE',
    'bgim': '',
    'radius': 16,
    'font': 'sans',
    'hs': 0,
    'ts': 0,
  };

  /// 网页页脚 HTML（显示在内容区底部）
  String footerHtml = '';

  /// 注入到网页的自定义 JS（整页通用）
  String customJs = '';

  /// 整页源码编辑模式：非空时整页 `<html>` 完全用这段源码替换默认网页，
  /// 可自由编辑整个网页的结构/样式/脚本，实现“编辑整个网页”。
  String fullPageHtml = '';

  /// 自由画布编辑时画布的高度（px）
  int canvasH = 380;

  static const _kPrivate = 'lan_private';
  static const _kS = 'lan_show_shuoshuo';
  static const _kD = 'lan_show_diary';
  static const _kA = 'lan_show_album';
  static const _kF = 'lan_show_file';
  static const _kPort = 'lan_port';
  static const _kAuto = 'lan_auto_start';
  static const _kAwake = 'lan_keep_awake';
  static const _kBrand = 'lan_brand';
  static const _kAccent = 'lan_accent';
  static const _kCss = 'lan_custom_css';
  static const _kHtml = 'lan_custom_html';
  static const _kHeader = 'lan_custom_header';
  static const _kBlocks = 'lan_blocks';
  static const _kCanvasH = 'lan_canvas_h';
  static const _kTh = 'lan_web_theme';
  static const _kFooter = 'lan_web_footer';
  static const _kJs = 'lan_web_js';
  static const _kFullPage = 'lan_web_fullpage';

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    private = sp.getBool(_kPrivate) ?? false;
    showShuoshuo = sp.getBool(_kS) ?? true;
    showDiary = sp.getBool(_kD) ?? true;
    showAlbum = sp.getBool(_kA) ?? true;
    showFile = sp.getBool(_kF) ?? true;
    port = sp.getInt(_kPort) ?? defaultPort;
    autoStart = sp.getBool(_kAuto) ?? false;
    keepAwake = sp.getBool(_kAwake) ?? false;
    brand = sp.getString(_kBrand) ?? '拾光 · 空间';
    accentHex = sp.getString(_kAccent) ?? '';
    customCss = sp.getString(_kCss) ?? '';
    customHtml = sp.getString(_kHtml) ?? '';
    customHeader = sp.getString(_kHeader) ?? '';
    try {
      final raw = sp.getString(_kBlocks);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          blocks = decoded
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      }
    } catch (_) {
      blocks = [];
    }
    canvasH = sp.getInt(_kCanvasH) ?? 380;
    footerHtml = sp.getString(_kFooter) ?? '';
    customJs = sp.getString(_kJs) ?? '';
    fullPageHtml = sp.getString(_kFullPage) ?? '';
    try {
      final raw = sp.getString(_kTh);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) webTheme = Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _save() async {
    final sp = await SharedPreferences.getInstance();
    sp.setBool(_kPrivate, private);
    sp.setBool(_kS, showShuoshuo);
    sp.setBool(_kD, showDiary);
    sp.setBool(_kA, showAlbum);
    sp.setBool(_kF, showFile);
    sp.setInt(_kPort, port);
    sp.setBool(_kAuto, autoStart);
    sp.setBool(_kAwake, keepAwake);
    sp.setString(_kBrand, brand);
    sp.setString(_kAccent, accentHex);
    sp.setString(_kCss, customCss);
    sp.setString(_kHtml, customHtml);
    sp.setString(_kHeader, customHeader);
    sp.setString(_kBlocks, jsonEncode(blocks));
    sp.setInt(_kCanvasH, canvasH);
    sp.setString(_kTh, jsonEncode(webTheme));
    sp.setString(_kFooter, footerHtml);
    sp.setString(_kJs, customJs);
    sp.setString(_kFullPage, fullPageHtml);
    notifyListeners();
  }

  Future<void> setPrivate(bool v) async {
    private = v;
    await _save();
  }

  Future<void> setShuoshuo(bool v) async {
    showShuoshuo = v;
    await _save();
  }

  Future<void> setDiary(bool v) async {
    showDiary = v;
    await _save();
  }

  Future<void> setAlbum(bool v) async {
    showAlbum = v;
    await _save();
  }

  Future<void> setFile(bool v) async {
    showFile = v;
    await _save();
  }

  Future<void> setPort(int v) async {
    if (v < 1 || v > 65535) v = defaultPort;
    port = v;
    await _save();
  }

  Future<void> setAutoStart(bool v) async {
    autoStart = v;
    await _save();
  }

  Future<void> setKeepAwake(bool v) async {
    keepAwake = v;
    await _save();
  }

  Future<void> setBrand(String v) async {
    brand = v.trim().isEmpty ? '拾光 · 空间' : v.trim();
    await _save();
  }

  Future<void> setAccent(String v) async {
    accentHex = v.trim();
    await _save();
  }

  Future<void> setCustomCss(String v) async {
    customCss = v;
    await _save();
  }

  Future<void> setCustomHtml(String v) async {
    customHtml = v;
    await _save();
  }

  Future<void> setCustomHeader(String v) async {
    customHeader = v;
    await _save();
  }

  Future<void> setBlocks(List<Map<String, dynamic>> v) async {
    blocks = v;
    await _save();
  }

  Future<void> setCanvasH(int v) async {
    canvasH = v < 100 ? 380 : v;
    await _save();
  }

  Future<void> setWebTheme(Map<String, dynamic> v) async {
    webTheme = v;
    await _save();
  }

  Future<void> setFooterHtml(String v) async {
    footerHtml = v;
    await _save();
  }

  Future<void> setCustomJs(String v) async {
    customJs = v;
    await _save();
  }

  Future<void> setFullPageHtml(String v) async {
    fullPageHtml = v;
    await _save();
  }
}