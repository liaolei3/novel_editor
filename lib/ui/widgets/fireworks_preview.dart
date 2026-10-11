import 'package:flutter/material.dart';

import 'fireworks.dart';

/// 独立预览入口：flutter run -t lib/ui/widgets/fireworks_preview.dart -d windows
void main() => runApp(const _PreviewApp());

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '烟花特效预览',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF6BA292),
        useMaterial3: true,
      ),
      home: const _PreviewPage(),
    );
  }
}

class _PreviewPage extends StatefulWidget {
  const _PreviewPage();

  @override
  State<_PreviewPage> createState() => _PreviewPageState();
}

class _PreviewPageState extends State<_PreviewPage> {
  FireworksStyle _style = FireworksStyle.starShower;
  bool _dark = true;
  bool _showText = true;
  int _replay = 0;

  @override
  Widget build(BuildContext context) {
    final bg = _dark ? const Color(0xFF10131A) : const Color(0xFFF5F2EC);
    return Scaffold(
      appBar: AppBar(
        title: const Text('烟花特效预览'),
        actions: [
          Row(
            children: [
              const Text('背景'),
              const SizedBox(width: 8),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('深色')),
                  ButtonSegment(value: false, label: Text('浅色')),
                ],
                selected: {_dark},
                onSelectionChanged: (s) => setState(() => _dark = s.first),
              ),
              const SizedBox(width: 12),
              FilterChip(
                label: const Text('祝贺文字'),
                selected: _showText,
                onSelected: (v) => setState(() => _showText = v),
              ),
              const SizedBox(width: 12),
              FilledButton.tonalIcon(
                onPressed: () => setState(() => _replay++),
                icon: const Icon(Icons.replay, size: 18),
                label: const Text('重播'),
              ),
              const SizedBox(width: 16),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final s in FireworksStyle.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(s.label),
                        selected: _style == s,
                        onSelected: (_) => setState(() => _style = s),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  Positioned(
                    left: 12,
                    top: 10,
                    child: Text(
                      _style.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _dark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                  ),
                  FireworksShow(
                    key: ValueKey('${_style.name}-$_replay-$_showText'),
                    style: _style,
                    messages: _showText ? const ['本章目标已达成，太棒了！'] : const [],
                    loop: true,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}