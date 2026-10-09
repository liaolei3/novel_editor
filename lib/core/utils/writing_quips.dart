/// 立绘面板的角色台词分档（按今日目标进度 + 摸鱼状态）。
///
/// 台词只放在 96px 宽的气泡里，两行封顶：界面缩放 150% 时每行仅容 ~5 字，
/// 故文案控制在 9 字内，保证最大缩放下也不会被省略号截断。
enum WritingQuipTier {
  idle('摸鱼中，写两句？'),
  notStarted('今天还没动笔哦'),
  opening('开头不错，继续！'),
  warming('手感来了，保持住！'),
  halfway('已经过半，稳着来！'),
  almost('再写一点就达标了！'),
  completed('今日目标达成啦！');

  const WritingQuipTier(this.text);

  final String text;
}

/// 摸鱼优先级最高，其余按进度边界 0 / 0.3 / 0.6 / 0.9 / 1 分档。
WritingQuipTier resolveWritingQuipTier(double progress, {bool idle = false}) {
  if (idle) return WritingQuipTier.idle;
  if (progress >= 1) return WritingQuipTier.completed;
  if (progress <= 0) return WritingQuipTier.notStarted;
  if (progress < 0.3) return WritingQuipTier.opening;
  if (progress < 0.6) return WritingQuipTier.warming;
  if (progress < 0.9) return WritingQuipTier.halfway;
  return WritingQuipTier.almost;
}