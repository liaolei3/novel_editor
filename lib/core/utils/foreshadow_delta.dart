import 'package:dart_quill_delta/dart_quill_delta.dart';
import 'package:flutter_quill/flutter_quill.dart' show Attribute, AttributeScope;

/// 正文伏笔标注的内联属性键，属性值为片段 id（ForeshadowSegment.id）。
const String kFsidKey = 'fsid';

/// 标注属性对象（value 为片段 id）。
Attribute<String> fsidAttribute(String segId) =>
    Attribute<String>(kFsidKey, AttributeScope.inline, segId);

/// 清除标注的属性对象（value 为 null 时 Delta compose 会移除该属性）。
Attribute<String?> unsetFsidAttribute() =>
    const Attribute<String?>(kFsidKey, AttributeScope.inline, null);

/// [start, end) 文本范围内是否已存在伏笔标注（用于右键入口的叠加拦截）。
bool deltaRangeHasFsid(Delta delta, int start, int end) {
  if (end <= start) return false;
  var pos = 0;
  for (final op in delta.operations) {
    final len = op.length?.toInt() ?? 0;
    final opEnd = pos + len;
    if (opEnd > start &&
        pos < end &&
        op.attributes?[kFsidKey] is String) {
      return true;
    }
    pos = opEnd;
  }
  return false;
}

/// 收集片段 [segId] 标注的文字范围（文档纯文本坐标，闭开区间）。
/// 供跳转定位与属性清除使用；相邻同 id 的 Operation 合并为一个范围。
List<(int, int)> deltaFsidRanges(Delta delta, String segId) {
  final ranges = <(int, int)>[];
  var pos = 0;
  (int, int)? open;
  void closeAt(int end) {
    if (open != null) {
      ranges.add((open!.$1, end));
      open = null;
    }
  }

  for (final op in delta.operations) {
    final len = op.length?.toInt() ?? 0;
    final value = op.attributes?[kFsidKey];
    final hit = value is String && value == segId;
    if (hit) {
      open = open == null ? (pos, pos + len) : (open!.$1, pos + len);
    } else {
      closeAt(pos);
    }
    pos += len;
  }
  closeAt(pos);
  return ranges;
}

/// 返回移除片段 [segId] 标注属性后的新 Delta；原 Delta 不变。
/// 其他属性（内联样式与块属性）全部保留。
Delta removeFsidFromDelta(Delta delta, String segId) {
  final out = Delta();
  for (final op in delta.operations) {
    final attrs = op.attributes;
    if (attrs == null || !attrs.containsKey(kFsidKey)) {
      out.push(op);
      continue;
    }
    final value = attrs[kFsidKey];
    if (value is String && value == segId) {
      final remaining = <String, dynamic>{};
      attrs.forEach((k, v) {
        if (k != kFsidKey) remaining[k] = v;
      });
      out.push(Operation.insert(
        op.data,
        remaining.isEmpty ? null : remaining,
      ));
    } else {
      out.push(op);
    }
  }
  return out;
}

/// 提取文档纯文本坐标 [start, end) 范围内的文本（embed 记 1 字符，用占位符代替）。
String deltaPlainTextInRange(Delta delta, int start, int end) {
  final buf = StringBuffer();
  var pos = 0;
  for (final op in delta.operations) {
    if (pos >= end) break;
    final text = op.data is String ? op.data as String : null;
    final len = text?.length ?? 1;
    final opEnd = pos + len;
    if (opEnd > start) {
      if (text == null) {
        buf.write('\uFFFC');
      } else {
        buf.write(text.substring(
            (start - pos).clamp(0, text.length),
            (end - pos).clamp(0, text.length)));
      }
    }
    pos = opEnd;
  }
  return buf.toString();
}
