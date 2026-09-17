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
