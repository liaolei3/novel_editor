import 'package:flutter/material.dart';
import 'package:pixelarticons/pixelarticons.dart';
import 'package:provider/provider.dart';

import '../../state/settings_controller.dart';
import '../app_theme.dart';

/// Material 图标 → Pixelarticons 像素图标映射。
final Map<IconData, IconData> _pixelMap = {
  Icons.add: Pixel.plus,
  Icons.folder_outlined: Pixel.folder,
  Icons.edit_note: Pixel.edit,
  Icons.edit_outlined: Pixel.edit,
  Icons.widgets_outlined: Pixel.grid,
  Icons.close: Pixel.close,
  Icons.horizontal_rule: Pixel.minus,
  Icons.crop_square: Pixel.crop,
  Icons.filter_none: Pixel.collapse,
  Icons.file_download_outlined: Pixel.download,
  Icons.file_upload_outlined: Pixel.upload,
  Icons.upload_file: Pixel.upload,
  Icons.post_add: Pixel.noteplus,
  Icons.push_pin: Pixel.pin,
  Icons.delete_outline: Pixel.trash,
  Icons.delete_forever: Pixel.trash,
  Icons.auto_stories_outlined: Pixel.bookopen,
  Icons.history_edu: Pixel.notes,
  Icons.chevron_right: Pixel.chevronright,
  Icons.folder_off_outlined: Pixel.folderx,
  Icons.description: Pixel.filealt,
  Icons.sticky_note_2_outlined: Pixel.note,
  Icons.person_outline: Pixel.user,
  Icons.lock_outline: Pixel.lock,
  Icons.search: Pixel.search,
  Icons.refresh: Pixel.reload,
  Icons.folder_open: Pixel.folder,
  Icons.light_mode: Pixel.sun,
  Icons.dark_mode: Pixel.moonstars,
  Icons.sports_esports: Pixel.gamepad,
};

/// 主题感知图标：像素风主题下自动换用 Pixelarticons，其余主题保持 Material 图标。
class AppIcon extends StatelessWidget {
  const AppIcon(this.icon, {super.key, this.size, this.color});

  final IconData icon;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    var data = icon;
    if (context.watch<SettingsController>().theme == AppTheme.pixel) {
      data = _pixelMap[icon] ?? icon;
    }
    return Icon(data, size: size, color: color);
  }
}
