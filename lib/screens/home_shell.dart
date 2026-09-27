import 'package:flutter/material.dart';

import '../theme.dart';
import 'capsule/capsule_list.dart';
import 'diary/diary_list.dart';
import 'settings/settings_page.dart';
import 'shuoshuo/home_feed.dart';
import 'space/hub.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({Key? key}) : super(key: key);
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  static final _tabs = [
    _TabData(Icons.auto_awesome, '首页'),
    _TabData(Icons.menu_book_outlined, '日志'),
    _TabData(Icons.timelapse, '胶囊'),
    _TabData(Icons.space_dashboard_outlined, '空间'),
    _TabData(Icons.person_outline, '我的'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: IndexedStack(index: _index, children: _buildPages()),
      bottomNavigationBar: _navBar(),
    );
  }

  List<Widget> _buildPages() => [
        const HomeFeedPage(),
        const DiaryListPage(),
        const CapsuleListPage(),
        const SpaceHub(),
        const SettingsPage(),
      ];

  Widget _navBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.hairline, width: 0.6)),
      ),
      child: SafeArea(
        top: false,
        child: Row(children: [
          for (var i = 0; i < _tabs.length; i++)
            Expanded(
              child: InkWell(
                onTap: () => setState(() => _index = i),
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                      decoration: BoxDecoration(
                        color: i == _index
                            ? AppTheme.clay.withOpacity(0.14)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(
                        i == _index ? _tabs[i].active : _tabs[i].icon,
                        size: 22,
                        color: i == _index ? AppTheme.clay : AppTheme.inkSoft,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _tabs[i].label,
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 0.4,
                        color: i == _index ? AppTheme.clay : AppTheme.inkSoft,
                        fontWeight: i == _index ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ]),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

class _TabData {
  final IconData icon;
  final IconData active;
  final String label;
  _TabData(this.icon, this.label) : active = _activation(icon);
  static IconData _activation(IconData icon) => icon;
}