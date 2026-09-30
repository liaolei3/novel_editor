import 'package:flutter_test/flutter_test.dart';
import 'package:novel_editor/core/utils/writing_quips.dart';

void main() {
  group('resolveWritingQuipTier 进度分档', () {
    test('0 及以下为未动笔', () {
      expect(resolveWritingQuipTier(0), WritingQuipTier.notStarted);
      expect(resolveWritingQuipTier(-0.5), WritingQuipTier.notStarted);
    });

    test('0 < p < 0.3 为起步', () {
      expect(resolveWritingQuipTier(0.01), WritingQuipTier.opening);
      expect(resolveWritingQuipTier(0.29), WritingQuipTier.opening);
    });

    test('0.3 <= p < 0.6 为进入状态', () {
      expect(resolveWritingQuipTier(0.3), WritingQuipTier.warming);
      expect(resolveWritingQuipTier(0.59), WritingQuipTier.warming);
    });

    test('0.6 <= p < 0.9 为过半', () {
      expect(resolveWritingQuipTier(0.6), WritingQuipTier.halfway);
      expect(resolveWritingQuipTier(0.89), WritingQuipTier.halfway);
    });

    test('0.9 <= p < 1 为接近达标', () {
      expect(resolveWritingQuipTier(0.9), WritingQuipTier.almost);
      expect(resolveWritingQuipTier(0.99), WritingQuipTier.almost);
    });

    test('p >= 1 为已达标（含超出）', () {
      expect(resolveWritingQuipTier(1), WritingQuipTier.completed);
      expect(resolveWritingQuipTier(1.5), WritingQuipTier.completed);
    });
  });

  test('摸鱼状态优先级最高，覆盖任意进度', () {
    for (final p in [0.0, 0.3, 0.6, 0.9, 1.0, 2.0]) {
      expect(resolveWritingQuipTier(p, idle: true), WritingQuipTier.idle);
    }
  });

  test('每档台词非空', () {
    for (final tier in WritingQuipTier.values) {
      expect(tier.text.trim(), isNotEmpty);
    }
  });
}