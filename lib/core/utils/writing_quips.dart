/// 立绘面板的角色台词分档（按今日目标进度 + 摸鱼状态）。
enum WritingQuipTier {
  idle('已经 3 分钟没动笔了，写两句？'),
  notStarted('今天还没动笔，先写两句热热身？'),
  opening('刚开了个头，接着往下写吧！'),
  warming('手感上来了，保持这个节奏！'),
  halfway('已经过半，稳着来！'),
  almost('再写一点就达标了！'),
  completed('今日目标已完成，厉害！');

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