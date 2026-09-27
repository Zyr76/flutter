import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../db.dart';
import '../../models.dart';
import '../../session.dart';
import '../../theme.dart';
import '../../widgets/linkify_text.dart';
import '../../widgets/media_grid.dart';
import '../../widgets/profile_visual.dart';

/// 相册长按“定位到说说”：展示包含某媒体文件的所有说说。
class ShuoLocatePage extends StatefulWidget {
  final String filePath;
  const ShuoLocatePage({Key? key, required this.filePath}) : super(key: key);
  @override
  State<ShuoLocatePage> createState() => _ShuoLocatePageState();
}

class _ShuoLocatePageState extends State<ShuoLocatePage> {
  List<Map>? _items;
  static final _fmt = DateFormat('yyyy-MM-dd HH:mm');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await Db.instance.shuoshuosByMedia(widget.filePath);
    if (mounted) setState(() => _items = data);
  }

  @override
  Widget build(BuildContext context) {
    final items = _items ?? [];
    return Scaffold(
      appBar: AppBar(title: const Text('定位到说说')),
      body: _items == null
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.search_off, size: 56, color: AppTheme.inkSoft),
                    const SizedBox(height: 12),
                    const Text('没有找到对应的说说',
                        style: TextStyle(fontSize: 15)),
                  ]),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(0, 12, 0, 100),
                  children: [
                    for (final it in items) _card(it),
                  ],
                ),
    );
  }

  Widget _card(Map item) {
    final s = item['shuoshuo'] as Shuoshuo;
    final media = item['media'] as List<Media>;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 6, 14, 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.hairline.withOpacity(0.6)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const MeAvatar(size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(Session.instance.user?.nickname ?? '',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(
                      _fmt.format(DateTime.fromMillisecondsSinceEpoch(
                          s.createdAt)),
                      style: TextStyle(fontSize: 11, color: AppTheme.inkSoft)),
                ]),
          ),
        ]),
        if (s.content.isNotEmpty) ...[
          const SizedBox(height: 10),
          LinkifyText(s.content,
              maxLines: 100,
              style: const TextStyle(letterSpacing: 0.2, height: 1.5)),
        ],
        if (s.location.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(children: [
            Icon(Icons.place, size: 14, color: AppTheme.clay),
            const SizedBox(width: 4),
            Text(s.location,
                style: TextStyle(fontSize: 12, color: AppTheme.clayDeep)),
          ]),
        ],
        if (media.isNotEmpty) ...[
          const SizedBox(height: 10),
          MediaGrid(medias: media),
        ],
      ]),
    );
  }
}