/// 章节/卷默认标题推导（供书树右键「新建章节」与编辑器「一键分章」共用）：
/// 取「第N章 / 第N卷」标题中的最大编号 + 1，输出中文数字
/// （如卷内已有第一章~第三章，则下一章为「第四章」）。
library;

final _chapterReg = RegExp(r'第\s*([0-9０-９一二三四五六七八九十百千两]+)\s*章');
final _volumeReg = RegExp(r'第\s*([0-9０-９一二三四五六七八九十百千两]+)\s*卷');

/// 推断新章节默认标题。
String suggestChapterTitle(Iterable<String> titles) =>
    _suggest(titles, _chapterReg, '章');

/// 推断新卷默认标题。
String suggestVolumeTitle(Iterable<String> names) =>
    _suggest(names, _volumeReg, '卷');

String _suggest(Iterable<String> titles, RegExp reg, String unit) {
  var max = 0;
  for (final t in titles) {
    final m = reg.firstMatch(t);
    if (m == null) continue;
    final n = parseChineseNumeral(m.group(1)!);
    if (n != null && n > max) max = n;
  }
  return '第${toChineseNumeral(max + 1)}$unit';
}

const _cnDigits = ['零', '一', '二', '三', '四', '五', '六', '七', '八', '九'];

/// 中文/阿拉伯数字 → 整数；无法解析返回 null。
int? parseChineseNumeral(String s) {
  final v = int.tryParse(s);
  if (v != null) return v;
  var total = 0, current = 0;
  for (final ch in s.split('')) {
    const digitIdx = ['一', '二', '三', '四', '五', '六', '七', '八', '九'];
    final i = digitIdx.indexOf(ch);
    if (i >= 0) {
      current = i + 1;
    } else if (ch == '两') {
      current = 2;
    } else if (ch == '十') {
      total += (current == 0 ? 1 : current) * 10;
      current = 0;
    } else if (ch == '百') {
      total += (current == 0 ? 1 : current) * 100;
      current = 0;
    } else if (ch == '千') {
      total += (current == 0 ? 1 : current) * 1000;
      current = 0;
    } else if (ch == '零') {
      continue;
    } else {
      return null;
    }
  }
  return total + current;
}

/// 整数 → 中文数字（1-99，超出退回阿拉伯数字）。
String toChineseNumeral(int n) {
  if (n >= 1 && n <= 10) return n == 10 ? '十' : _cnDigits[n];
  if (n < 20) return '十${_cnDigits[n % 10]}';
  if (n < 100) {
    final ones = n % 10;
    return '${_cnDigits[n ~/ 10]}十${ones == 0 ? '' : _cnDigits[ones]}';
  }
  return '$n';
}
