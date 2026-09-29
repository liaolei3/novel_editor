import 'dart:ui';

import '../../data/models.dart';

/// 角色标记色的唯一定义处：角色面板（类型选择器、卡片徽章）、字符悬浮卡、
/// 编辑器正文高亮共用，避免同一套映射在多处各写一遍后口径漂移。

/// 类型默认标记色：也是新建角色写入的默认值。
Color characterTypeColor(CharacterType type) => switch (type) {
      CharacterType.protagonist => const Color(0xFF4A90D9),
      CharacterType.supporting => const Color(0xFF7CB342),
      CharacterType.antagonist => const Color(0xFFE53935),
    };

/// 类型中文名。
String characterTypeLabel(CharacterType type) => switch (type) {
      CharacterType.protagonist => '主角',
      CharacterType.supporting => '配角',
      CharacterType.antagonist => '反派',
    };

/// 标记色 → '#RRGGBB'（入库格式）。
String characterColorToHex(Color color) =>
    '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';

/// 角色卡颜色解析：'#RRGGBB' → Color，非法值返回 null。
Color? parseCharacterColor(String hex) {
  if (hex.isEmpty) return null;
  try {
    return Color(int.parse(hex.replaceFirst('#', '0xFF')));
  } catch (_) {
    return null;
  }
}

/// 角色实际生效的标记色。空色是历史数据（新建不再产生空色），
/// 回退到类型默认色——此前回退主题主色，在自然主题下与正文几乎同色。
Color characterMarkColor(Character character) =>
    parseCharacterColor(character.color) ?? characterTypeColor(character.type);