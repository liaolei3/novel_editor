import 'package:flutter/services.dart' show TextSelection;
import 'package:flutter_quill/flutter_quill.dart';

/// 全角成对符号自动补全表（开符 → 闭符）。
///
/// 供编辑器两条路径共用：
/// - 输入法提交开符时补全闭符（fork 的 QuillEditorConfig.autoPairSymbols）；
/// - 一对空符号中间退格一并删除（[handlePairBackspace]）。
const Map<String, String> fullWidthPairSymbols = {
  '“': '”',
  '‘': '’',
  '《': '》',
  '【': '】',
  '（': '）',
  '「': '」',
  '『': '』',
};

/// 对话（台词）引号表（开符 → 闭符）。取各类引号：全角单双引号 “” ‘’、
/// 半角直双引号 "、直角引号「」『』；不含半角单引号（'，英文撇号易误判）、
/// 书名号与括号。
/// 半角 " 的开/闭同字符，故配对按「开关式」处理（见 [findDialogueRanges]）。
const Map<String, String> dialoguePairSymbols = {
  '“': '”',
  '‘': '’',
  '"': '"',
  '「': '」',
  '『': '』',
};

/// 扫描单段文本里的对话区间（引号内文字，不含引号本身），按起点升序返回。
///
/// - 开关式配对：命中栈顶闭符即闭合，否则遇开符入栈；只有成对闭合才收录，
///   孤立/未闭合的引号忽略（半角 " 的同字符开闭即依赖此顺序）；
/// - 支持嵌套（如「他说：“你好”」），嵌套区间与父区间合并为同一段，
///   因为渲染时统一用同一底色；
/// - 空引号对（“”/"")不产出区间。
List<(int, int)> findDialogueRanges(String text) {
  final raw = <(int, int)>[];
  final opens = <(String close, int start)>[];
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (opens.isNotEmpty && opens.last.$1 == ch) {
      final open = opens.removeLast();
      if (i > open.$2 + 1) raw.add((open.$2 + 1, i));
      continue;
    }
    final close = dialoguePairSymbols[ch];
    if (close != null) opens.add((close, i));
  }
  raw.sort((a, b) => a.$1.compareTo(b.$1));
  final merged = <(int, int)>[];
  for (final r in raw) {
    if (merged.isNotEmpty && r.$1 <= merged.last.$2) {
      if (r.$2 > merged.last.$2) {
        merged[merged.length - 1] = (merged.last.$1, r.$2);
      }
    } else {
      merged.add(r);
    }
  }
  return merged;
}

/// offset 之前同族开符多于闭符，视为有未闭合开符。
bool hasUnclosedOpenBefore(String text, int offset, String open, String close) {
  var opens = 0, closes = 0;
  for (var i = 0; i < offset && i < text.length; i++) {
    if (text[i] == open) {
      opens++;
    } else if (text[i] == close) {
      closes++;
    }
  }
  return opens > closes;
}

/// 光标停在一对空成对符号中间（前一字符为开符且后一字符为其闭符）时，
/// 退格一并删除两个符号；单次 replaceText，撤销一并回退。
/// 未命中时返回 false，交给调用方的默认退格逻辑。
bool handlePairBackspace(QuillController controller) {
  final sel = controller.selection;
  if (!sel.isCollapsed) return false;
  final offset = sel.start;
  if (offset == 0) return false;
  final text = controller.document.toPlainText();
  if (offset >= text.length) return false;
  final closer = fullWidthPairSymbols[text[offset - 1]];
  if (closer == null || text[offset] != closer) return false;
  controller.replaceText(
    offset - 1,
    2,
    '',
    TextSelection.collapsed(offset: offset - 1),
  );
  return true;
}
