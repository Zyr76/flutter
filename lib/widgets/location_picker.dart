import 'package:flutter/material.dart';

import '../../services/locator.dart';
import '../../theme.dart';

/// 弹出一个位置选择面板，返回选中的地点文本（可空）
Future<String?> pickLocation(BuildContext context, {String? initial}) async {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppTheme.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    isScrollControlled: true,
    builder: (_) => _LocationSheet(initial: initial),
  );
}

class _LocationSheet extends StatefulWidget {
  final String? initial;
  const _LocationSheet({this.initial});
  @override
  State<_LocationSheet> createState() => _LocationSheetState();
}

class _LocationSheetState extends State<_LocationSheet> {
  final _ctrl = TextEditingController();
  bool _locating = false;
  String? _current;

  @override
  void initState() {
    super.initState();
    _ctrl.text = widget.initial ?? '';
  }

  Future<void> _locate() async {
    setState(() => _locating = true);
    final loc = await Locator.ipLocation();
    if (!mounted) return;
    setState(() {
      _locating = false;
      if (loc != null) {
        _current = loc;
        _ctrl.text = _current!;
      }
    });
    if (loc == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法获取当前位置，请检查网络后重试')));
    }
  }

  void _done([String? value]) => Navigator.pop(context, value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('选择地点', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(_current ?? '可输入地点名称或使用定位',
                style: TextStyle(fontSize: 12, color: AppTheme.inkSoft)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  decoration: InputDecoration(
                      hintText: '输入地点名称',
                      prefixIcon: Icon(Icons.place_outlined, color: AppTheme.inkSoft),
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 48,
                width: 48,
                child: OutlinedButton(
                  onPressed: _locating ? null : _locate,
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    side: BorderSide(color: AppTheme.hairline),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _locating
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(Icons.my_location, color: AppTheme.clay, size: 20),
                ),
              ),
            ]),
            const SizedBox(height: 18),
            Row(children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _done(_ctrl.text.trim().isEmpty ? null : _ctrl.text.trim()),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('确定'),
                ),
              ),
              const SizedBox(width: 10),
              TextButton(
                onPressed: () => _done(null),
                child: Text('移除', style: TextStyle(color: AppTheme.inkSoft)),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}