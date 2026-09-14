import 'package:flutter/material.dart';

import '../stats_page.dart';

/// 码字统计面板：工作区右缘图标列弹出，复用统计页内容。
class StatsPanel extends StatelessWidget {
  const StatsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          dense: true,
          title: const Text('码字统计'),
          subtitle: Text(
            '日/周/月曲线、时长、速度、每日目标',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const Expanded(child: StatsView()),
      ],
    );
  }
}
