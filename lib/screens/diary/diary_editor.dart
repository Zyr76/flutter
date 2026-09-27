import 'package:flutter/material.dart';

import '../../db.dart';
import '../../models.dart';
import '../../session.dart';
import '../../theme.dart';
import '../../widgets/diary_icons.dart';
import '../../widgets/location_picker.dart';
import '../../widgets/mood_thermometer.dart';

class DiaryEditorPage extends StatefulWidget {
  final Diary? existing;
  const DiaryEditorPage({Key? key, this.existing}) : super(key: key);
  @override
  State<DiaryEditorPage> createState() => _DiaryEditorPageState();
}

class _DiaryEditorPageState extends State<DiaryEditorPage> {
  late final TextEditingController _title = TextEditingController(text: widget.existing?.title ?? '');
  late final TextEditingController _content = TextEditingController(text: widget.existing?.content ?? '');
  int _moodValue = 5;
  String _weather = '';
  String _location = '';
  bool _busy = false;

  static const weathers = weatherOptions;

  @override
  void initState() {
    super.initState();
    _moodValue = widget.existing?.moodValue ?? 5;
    _weather = widget.existing?.weather ?? '';
    _location = widget.existing?.location ?? '';
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final content = _content.text.trim();
    if (title.isEmpty && content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('写点什么吧')));
      return;
    }
    setState(() => _busy = true);
    final uid = Session.instance.user!.id!;
    final now = DateTime.now().millisecondsSinceEpoch;
    final mark = {
      'title': title, 'content': content,
      'mood': moodLabel(_moodValue), 'mood_value': _moodValue,
      'weather': _weather, 'location': _location,
      'updated_at': now,
    };
    if (widget.existing != null) {
      await Db.instance.updateDiary(widget.existing!.id, mark);
    } else {
      await Db.instance.insertDiary({
        'user_id': uid, ...mark, 'created_at': now,
      });
    }
    if (mounted) Navigator.pop(context, true);
  }

  Widget _weatherChips() =>
      Wrap(spacing: 8, children: weatherOptions.map((o) => ChoiceChip(
        avatar: Icon(weatherIcons[o] ?? Icons.wb_sunny_outlined, size: 18,
            color: _weather == o ? AppTheme.clay : AppTheme.inkSoft),
        label: Text(o), selected: _weather == o,
        onSelected: (_) => setState(() => _weather = o),
      )).toList());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing != null ? '编辑日志' : '写日志'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('保存', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _label('今日情绪'),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppTheme.hairline.withOpacity(0.6)),
            ),
            child: MoodThermometerSlider(
              value: _moodValue,
              onChanged: (v) => setState(() => _moodValue = v),
            ),
          ),
          const SizedBox(height: 20),
          _label('天气'),
          _weatherChips(),
          const SizedBox(height: 24),
          TextField(
            controller: _title,
            decoration: const InputDecoration(hintText: '标题（可留空）'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _content,
            maxLines: 12,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
                hintText: '记录今天…', alignLabelWithHint: true),
          ),
          const SizedBox(height: 14),
          InkWell(
            onTap: () async {
              final r = await pickLocation(context, initial: _location);
              if (r == null) return;
              if (mounted) setState(() => _location = r);
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.sand.withOpacity(0.4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.hairline.withOpacity(0.6)),
              ),
              child: Row(children: [
                Icon(Icons.place_outlined, size: 20,
                    color: _location.isEmpty ? AppTheme.inkSoft : AppTheme.clay),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _location.isEmpty ? '添加位置' : _location,
                    style: TextStyle(
                        fontSize: 14,
                        color: _location.isEmpty ? AppTheme.inkSoft : AppTheme.ink),
                  ),
                ),
                if (_location.isNotEmpty)
                  GestureDetector(
                    onTap: () => setState(() => _location = ''),
                    child: Icon(Icons.close, size: 18, color: AppTheme.inkSoft),
                  ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _label(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(s, style: const TextStyle(fontWeight: FontWeight.w600)),
      );
}