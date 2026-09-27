import 'package:flutter/material.dart';

import '../../theme.dart';

/// 主题与配色设置：深色模式 + 自定义主色
class ThemeSettingsPage extends StatefulWidget {
  const ThemeSettingsPage({Key? key}) : super(key: key);
  @override
  State<ThemeSettingsPage> createState() => _ThemeSettingsPageState();
}

class _ThemeSettingsPageState extends State<ThemeSettingsPage> {
  static const _presets = [
    Color(0xFFBE7E5A), // 陶土
    Color(0xFF8C5EBE), // 紫
    Color(0xFF4E8B6E), // 绿
    Color(0xFF3E7CB1), // 蓝
    Color(0xFFC25E5E), // 红
    Color(0xFFC2874E), // 琥珀
    Color(0xFF5A6BBE), // 靛
    Color(0xFF6E4E8B), // 深紫
  ];

  Future<void> _pickCustom() async {
    final picked = await showModalBottomSheet<Color>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const _ColorPickerSheet(),
    );
    if (picked != null) {
      await ThemeController.instance.setAccent(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 监听主题控制器，让勾选态 / 开关随选择即时刷新
    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) {
        final tc = ThemeController.instance;
        return Scaffold(
      appBar: AppBar(title: const Text('主题与配色')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 深浅模式：跟随系统 / 浅色 / 深色
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.hairline.withOpacity(0.6)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    color: (tc.dark ? const Color(0xFF1B1815) : const Color(0xFFE9E1CE))
                        .withOpacity(0.9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(tc.dark ? Icons.dark_mode : Icons.light_mode,
                      color: tc.dark ? const Color(0xFFEDE6DA) : const Color(0xFF8A7A5C)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text('显示模式', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ]),
              const SizedBox(height: 14),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'system', label: Text('跟随系统'), icon: Icon(Icons.settings_brightness, size: 16)),
                  ButtonSegment(value: 'light', label: Text('浅色'), icon: Icon(Icons.light_mode, size: 16)),
                  ButtonSegment(value: 'dark', label: Text('深色'), icon: Icon(Icons.dark_mode, size: 16)),
                ],
                selected: {tc.mode},
                showSelectedIcon: false,
                style: ButtonStyle(
                  backgroundColor: WidgetStatePropertyAll(AppTheme.bg),
                  foregroundColor: WidgetStateProperty.resolveWith((s) =>
                      s.contains(WidgetState.selected) ? AppTheme.clay : AppTheme.inkSoft),
                  side: WidgetStatePropertyAll(BorderSide(color: AppTheme.hairline)),
                ),
                onSelectionChanged: (sel) =>
                    ThemeController.instance.setMode(sel.first),
              ),
            ]),
          ),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 10),
            child: Text('主题色', style: TextStyle(fontSize: 13, color: AppTheme.inkSoft, fontWeight: FontWeight.w600)),
          ),
          // 预设色
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.hairline.withOpacity(0.6)),
            ),
            child: Column(children: [
              Wrap(
                spacing: 16, runSpacing: 16,
                children: _presets.map((c) => _swatch(c)).toList(),
              ),
              const SizedBox(height: 16),
              Divider(height: 1, color: AppTheme.hairline),
              const SizedBox(height: 14),
              Row(children: [
                Icon(Icons.palette_outlined, color: AppTheme.clay, size: 20),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('自定义主色', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ),
                TextButton(onPressed: _pickCustom, child: const Text('选择')),
              ]),
            ]),
          ),
          const SizedBox(height: 18),
          Text('主色会应用到按钮、图标、选中态等，深色与浅色模式均可独立适配。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppTheme.inkSoft, height: 1.6)),
        ],
      ),
      );
      },
    );
  }

  Widget _swatch(Color c) {
    final selected = ThemeController.instance.accent.value == c.value;
    return GestureDetector(
      onTap: () => ThemeController.instance.setAccent(c),
      child: Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          color: c,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? AppTheme.ink : AppTheme.hairline,
            width: selected ? 2.5 : 1,
          ),
        ),
        child: selected
            ? const Icon(Icons.check, color: Colors.white, size: 22)
            : null,
      ),
    );
  }
}

/// 自定义主色选择：HSL 调色
class _ColorPickerSheet extends StatefulWidget {
  const _ColorPickerSheet();
  @override
  State<_ColorPickerSheet> createState() => _ColorPickerSheetState();
}

class _ColorPickerSheetState extends State<_ColorPickerSheet> {
  late HSLColor _hsl = HSLColor.fromColor(ThemeController.instance.accent);

  void _confirm() => Navigator.pop(context, _hsl.toColor());

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: _hsl.toColor(),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.hairline),
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(child: Text('选择主色', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
          Text('#${_hsl.toColor().value.toRadixString(16).toUpperCase()}',
              style: TextStyle(color: AppTheme.inkSoft, fontSize: 12, letterSpacing: 0.5)),
        ]),
        const SizedBox(height: 20),
        _slider('色调', _hsl.hue / 360, (v) => setState(() => _hsl = _hsl.withHue(v * 360))),
        _slider('饱和度', _hsl.saturation, (v) => setState(() => _hsl = _hsl.withSaturation(v))),
        _slider('亮度', _hsl.lightness, (v) => setState(() => _hsl = _hsl.withLightness(v))),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _confirm,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.clayDeep,
              side: BorderSide(color: AppTheme.clayDeep, width: 1.2),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('使用这个颜色', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
    );
  }

  Widget _slider(String label, double value, ValueChanged<double> onChanged) {
    return Row(children: [
      SizedBox(width: 52, child: Text(label, style: const TextStyle(fontSize: 13))),
      Expanded(
        child: Slider(
          value: value.clamp(0.0, 1.0),
          activeColor: AppTheme.clay,
          onChanged: onChanged,
        ),
      ),
    ]);
  }
}